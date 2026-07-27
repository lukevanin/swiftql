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

    func testVerificationNeverMutatesThePinnedNorthwindSnapshot() throws {
        let before = try NorthwindFixture.validateCanonical()
        _ = try verify(candidateWithColumns: ["customerID", "employeeID"], table: "Orders")
        let after = try NorthwindFixture.validateCanonical()
        XCTAssertEqual(before.databaseSHA256, after.databaseSHA256)
    }

    /// Guards the checked-in verification evidence against silent drift.
    /// Unlike #390's runtime-provenance-embedding evidence, `EQPPlan` (and
    /// therefore `IndexCandidateEvidence`) carries no SQLite version field,
    /// so this comparison has no version-skew caveat — a fresh verify run
    /// against this same pinned snapshot must reproduce the checked-in
    /// evidence exactly, on any host.
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
        XCTAssertEqual(fresh, pinnedEvidence)
    }

    // MARK: - Helpers

    private func verify(candidateWithColumns columns: [String], table: String) throws -> IndexCandidateEvidence {
        let pinnedCandidates = try loadCandidates("candidates.json")
        let candidate = try XCTUnwrap(pinnedCandidates.first { $0.table == table && $0.columns == columns })
        let corpus = try EQPVarianceCorpus.assemble()
        let statement = try XCTUnwrap(corpus.first { $0.id == candidate.representativeStatementID })
        return try IndexCandidateVerifier.verify(candidate: candidate.asIndexCandidate, statement: statement)
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
