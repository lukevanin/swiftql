import XCTest
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype
@testable import SwiftQLSQLiteIndexAdvisorPrototype


final class IndexCandidateVerifierTests: XCTestCase {
    // MARK: - Real evidence: one genuine improvement, several honest false positives

    /// `Orders(CustomerID, EmployeeID)` for
    /// `c191.v1.select.j-left.w-injection-binding` — a real `WHERE
    /// t0.customerID == :customer_input` equality filter on the driving
    /// table of a `LEFT JOIN`. This is the one real improvement in the
    /// checked-in evidence: the plan genuinely changes from a full table
    /// scan to an index search constrained by `CustomerID`.
    func testRealImprovingCandidateIsConfirmed() throws {
        let evidence = try verify(candidateWithColumns: ["customerID", "employeeID"], table: "Orders")
        XCTAssertTrue(evidence.isImprovement)
        XCTAssertTrue(evidence.improvementReason.contains("CustomerID"))
    }

    /// `Orders(OrderID)` — derived from an `ORDER BY orderID` term with no
    /// `WHERE` filter at all. `OrderID` is already the table's
    /// `INTEGER PRIMARY KEY`/rowid, so a full scan already visits rows in
    /// that order for free; the candidate index is never chosen. A false
    /// positive this prototype's own verification catches, not one it
    /// asserts around.
    func testRealFalsePositiveOnPrimaryKeyColumnIsRejected() throws {
        let evidence = try verify(candidateWithColumns: ["orderID"], table: "Orders")
        XCTAssertFalse(evidence.isImprovement)
        XCTAssertEqual(evidence.beforePlan, evidence.afterPlan, "the redundant index changes nothing about the chosen plan")
    }

    /// `Employees(ReportsTo, EmployeeID)` — derived from the self left-join
    /// anchor. `ReportsTo` is a join key, but for the *driving* side of the
    /// join (`Employees AS e`), not a `WHERE` filter on it; SQLite must scan
    /// every row of `e` regardless of any index on `ReportsTo`. Same false-
    /// positive class as the join-key-only `Orders` candidates.
    func testRealFalsePositiveFromDrivingSideJoinKeyIsRejected() throws {
        let evidence = try verify(candidateWithColumns: ["ReportsTo", "EmployeeID"], table: "Employees")
        XCTAssertFalse(evidence.isImprovement)
    }

    /// Settles the #396 candidate-column precedence question (join key vs.
    /// range column) with a real scratch-copy re-plan, not just the unit
    /// test in `IndexCandidateGeneratorTests`. `Products` is the looked-up
    /// side of a `LEFT JOIN` on `CategoryID`, filtered by `UnitPrice > 20`,
    /// with no existing index on either column — SQLite's baseline plan is
    /// its own ephemeral `automatic_covering_index` on `CategoryID` alone
    /// (verified below). `CREATE INDEX ON Products(CategoryID, UnitPrice)`
    /// (join key first) is the index SQLite actually adopts, replacing that
    /// ephemeral index; `CREATE INDEX ON Products(UnitPrice, CategoryID)`
    /// (range first) is completely ignored — the after-plan is byte-for-byte
    /// identical to the before-plan, as if the candidate didn't exist.
    func testJoinKeyPrecedesRangeColumnConfirmedByRealScratchCopyReplan() throws {
        let statement = EQPVarianceStatement(
            id: "test.precedence.products-category-unitprice",
            source: .northwindAnchor,
            renderedSQL: """
                SELECT p.ProductID FROM Categories AS c
                LEFT JOIN Products AS p ON p.CategoryID = c.CategoryID
                WHERE p.UnitPrice > 20 OR p.ProductID IS NULL
                """,
            northwindAnchorCaseIDs: [],
            bindings: []
        )

        let joinKeyFirst = IndexCandidate(
            table: "Products",
            columns: ["CategoryID", "UnitPrice"],
            sourceStatementIDs: [statement.id],
            representativeStatementID: statement.id,
            representativeAlias: "p"
        )
        let rangeFirst = IndexCandidate(
            table: "Products",
            columns: ["UnitPrice", "CategoryID"],
            sourceStatementIDs: [statement.id],
            representativeStatementID: statement.id,
            representativeAlias: "p"
        )

        let joinKeyFirstEvidence = try IndexCandidateVerifier.verify(candidate: joinKeyFirst, statement: statement)
        XCTAssertTrue(joinKeyFirstEvidence.isImprovement, joinKeyFirstEvidence.improvementReason)
        XCTAssertTrue(joinKeyFirstEvidence.improvementReason.contains("automatic_covering_index"))
        XCTAssertTrue(joinKeyFirstEvidence.improvementReason.contains("CategoryID"))

        let rangeFirstEvidence = try IndexCandidateVerifier.verify(candidate: rangeFirst, statement: statement)
        XCTAssertFalse(rangeFirstEvidence.isImprovement)
        XCTAssertEqual(
            rangeFirstEvidence.beforePlan,
            rangeFirstEvidence.afterPlan,
            "the wrongly-ordered index is completely ignored by SQLite; the plan is unchanged"
        )
    }

    /// Copilot review: `findNode(forTable:in:)` did a plain per-root
    /// depth-first search, tried root by root in array order — so a nested
    /// match under an *earlier* root could be returned before a *later*
    /// root's own direct match was ever considered. Modeled on a real shape
    /// from the corpus (`c390.northwind.subquery.products-above-average`
    /// has a root `SCAN Products` and a sibling `SCALAR SUBQUERY 1` root
    /// whose own child is a second, nested `SCAN Products`), but with the
    /// non-matching root placed *first* — the real capture's root order
    /// happens to already put the matching root first, so it wouldn't have
    /// exercised the bug; this ordering reliably does. Pre-fix this would
    /// return the nested node (found while recursing into the first root);
    /// post-fix it returns the second root's own direct match.
    func testFindNodePrefersRootLevelMatchOverEarlierNestedMatch() {
        let nestedMatch = EQPPlanNode(
            detail: "SCAN Products (nested, under the subquery)",
            shape: .fullTableScan,
            attributes: EQPPlanShapeAttributes(table: "Products"),
            children: []
        )
        let subqueryRoot = EQPPlanNode(
            detail: "SCALAR SUBQUERY 1",
            shape: .scalarSubquery,
            attributes: .none,
            children: [nestedMatch]
        )
        let rootMatch = EQPPlanNode(
            detail: "SCAN Products (root, the intended node)",
            shape: .fullTableScan,
            attributes: EQPPlanShapeAttributes(table: "Products"),
            children: []
        )
        let plan = EQPPlan(statementID: "test.find-node.root-preferred", roots: [subqueryRoot, rootMatch])

        XCTAssertEqual(IndexCandidateVerifier.findNode(forTable: "Products", in: plan), rootMatch)
    }

    func testVerificationNeverMutatesThePinnedNorthwindSnapshot() throws {
        let before = try NorthwindFixture.validateCanonical()
        _ = try verify(candidateWithColumns: ["customerID", "employeeID"], table: "Orders")
        let after = try NorthwindFixture.validateCanonical()
        XCTAssertEqual(before.databaseSHA256, after.databaseSHA256)
    }

    /// Guards the checked-in verification evidence against silent drift.
    /// Neither `EQPPlan` nor `IndexCandidateEvidence` embeds an SQLite
    /// version field, so this assertion is unconditional rather than
    /// runtime-gated like #390's equivalent check — but that is *not* a
    /// proof these specific index-search/full-scan decisions are stable
    /// across every SQLite build, only that #390 observed them stable
    /// between the two real builds it measured (3.51.0/3.53.2). EQP choices
    /// remain SQLite-version-dependent in principle (#390's own premise); a
    /// future SQLite could in principle plan even these simple cases
    /// differently. If this test ever fails on a host whose SQLite the
    /// pinned evidence was never verified against, the failure message
    /// prints that host's `sqlite_version()`/`sqlite_source_id()` so the
    /// difference is diagnosable rather than a bare JSON diff.
    func testCheckedInVerificationEvidenceMatchesFreshRun() throws {
        let pinnedCandidates = try loadCandidates("candidates.json")
        let pinnedEvidence = try loadEvidence("verification.json")
        let corpus = try EQPVarianceCorpus.assemble()
        let corpusByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })

        var fresh: [IndexCandidateEvidence] = []
        for candidate in pinnedCandidates {
            let statement = try XCTUnwrap(corpusByID[candidate.representativeStatementID])
            fresh.append(try IndexCandidateVerifier.verify(
                candidate: candidate.asIndexCandidate,
                statement: statement
            ))
        }

        let runtime = try currentSQLiteRuntimeDescription()
        XCTAssertEqual(fresh, pinnedEvidence, "mismatch on \(runtime); if this host's SQLite build genuinely plans one of these statements differently, that's real evidence for this write-up, not just a broken test")
    }

    // MARK: - Helpers

    private func verify(candidateWithColumns columns: [String], table: String) throws -> IndexCandidateEvidence {
        let pinnedCandidates = try loadCandidates("candidates.json")
        let candidate = try XCTUnwrap(pinnedCandidates.first { $0.table == table && $0.columns == columns })
        let corpus = try EQPVarianceCorpus.assemble()
        let statement = try XCTUnwrap(corpus.first { $0.id == candidate.representativeStatementID })
        return try IndexCandidateVerifier.verify(candidate: candidate.asIndexCandidate, statement: statement)
    }

    /// `validateCanonical()` reads the canonical snapshot through a
    /// read-only pool — no scratch copy needed just to read
    /// `sqlite_version()`/`sqlite_source_id()`, unlike `withTemporaryCopy`.
    private func currentSQLiteRuntimeDescription() throws -> String {
        let validation = try NorthwindFixture.validateCanonical()
        return "sqlite_version=\(validation.sqliteVersion) sqlite_source_id=\(validation.sqliteSourceID)"
    }
}


private extension CodableIndexCandidateFixture {
    var asIndexCandidate: IndexCandidate {
        IndexCandidate(
            table: table,
            columns: columns,
            sourceStatementIDs: sourceStatementIDs,
            representativeStatementID: representativeStatementID,
            representativeAlias: representativeAlias
        )
    }
}


private func loadEvidence(_ name: String) throws -> [IndexCandidateEvidence] {
    try JSONDecoder().decode([IndexCandidateEvidence].self, from: Data(contentsOf: pinnedEvidenceURL(named: name)))
}
