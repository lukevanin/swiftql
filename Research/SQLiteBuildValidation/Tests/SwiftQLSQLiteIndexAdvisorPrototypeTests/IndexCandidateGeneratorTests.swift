import XCTest
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype
@testable import SwiftQLSQLiteIndexAdvisorPrototype


final class IndexCandidateGeneratorTests: XCTestCase {
    // MARK: - Precedence rule

    func testPrecedenceEqualityAndJoinThenRangeThenOrderBy() {
        let sql = #"""
            SELECT "t0"."x" FROM "T" AS "t0"
            JOIN "U" AS "u" ON ("t0"."joinCol" == "u"."id")
            WHERE (("t0"."eq" == 1) AND ("t0"."rangeA" > 2) AND ("t0"."rangeB" < 3))
            ORDER BY "t0"."sortCol" ASC
            """#
        XCTAssertEqual(
            IndexCandidateGenerator.candidateColumns(for: "t0", in: sql),
            ["eq", "joinCol", "rangeA", "sortCol"],
            "join keys share the equality tier (both before any range column); "
                + "only the FIRST range column is included since the second (rangeB) narrows no further"
        )
    }

    /// Real, confirmed evidence for the precedence rule, not an assumption:
    /// `Categories LEFT JOIN Products ON p.CategoryID = c.CategoryID WHERE
    /// p.UnitPrice > 20 OR p.ProductID IS NULL` puts `Products` on the
    /// looked-up side of the join, with both a join key (`CategoryID`) and a
    /// range predicate (`UnitPrice`) on it and no existing index to compete
    /// with. `CREATE INDEX ON Products(CategoryID, UnitPrice)` (join key
    /// first) is the index SQLite actually uses, replacing its own
    /// automatic covering index; `CREATE INDEX ON Products(UnitPrice,
    /// CategoryID)` (range first) is silently ignored — SQLite falls back
    /// to the same automatic covering index as if the candidate didn't
    /// exist. See `IndexCandidateVerifierTests` for the same result
    /// verified end to end via a real scratch-copy re-plan.
    func testJoinKeyMustPrecedeRangeColumnForSQLiteToUseTheIndex() {
        // This is the precedence-logic unit test; IndexCandidateVerifierTests
        // proves the same ordering against real SQLite via a scratch-copy
        // re-plan, using an `OR`-qualified WHERE clause there to keep the
        // LEFT JOIN from being flattened by the planner (this extractor
        // deliberately doesn't parse `OR` clauses at all, so this simpler
        // form is what exercises `candidateColumns` directly).
        let sql = #"""
            SELECT p.ProductID FROM Categories AS c
            LEFT JOIN Products AS p ON p.CategoryID = c.CategoryID
            WHERE p.UnitPrice > 20
            """#
        XCTAssertEqual(
            IndexCandidateGenerator.candidateColumns(for: "p", in: sql),
            ["CategoryID", "UnitPrice"]
        )
    }

    func testColumnAlreadyIncludedAtHigherPrecedenceIsNotDuplicated() {
        // The same column appears as both an equality predicate and the
        // ORDER BY term — it must appear once, at its equality position.
        let sql = #"""
            SELECT "t0"."x" FROM "T" AS "t0"
            WHERE ("t0"."col" == 1)
            ORDER BY "t0"."col" ASC
            """#
        XCTAssertEqual(IndexCandidateGenerator.candidateColumns(for: "t0", in: sql), ["col"])
    }

    func testNoSignalYieldsEmptyColumnList() {
        let sql = #"SELECT "t0"."x" FROM "T" AS "t0""#
        XCTAssertEqual(IndexCandidateGenerator.candidateColumns(for: "t0", in: sql), [])
    }

    // MARK: - Deduplication

    private func candidate(
        table: String,
        columns: [String],
        statementIDs: [String] = ["s1"]
    ) -> IndexCandidate {
        IndexCandidate(
            table: table,
            columns: columns,
            sourceStatementIDs: statementIDs,
            representativeStatementID: statementIDs[0],
            representativeAlias: "t0"
        )
    }

    func testDeduplicateMergesIdenticalCandidatesRecordingAllSources() {
        let remediables = [
            RemediableCandidate(table: "Orders", columns: ["CustomerID"], statementID: "s1", alias: "t0"),
            RemediableCandidate(table: "Orders", columns: ["CustomerID"], statementID: "s2", alias: "o"),
        ]
        let deduped = IndexCandidateGenerator.deduplicate(remediables)
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].sourceStatementIDs, ["s1", "s2"])
        XCTAssertEqual(deduped[0].representativeStatementID, "s1", "keeps the FIRST occurrence as the verification target")
    }

    func testDeduplicateDropsExactPrefixInFavorOfWiderIndex() {
        let remediables = [
            RemediableCandidate(table: "Orders", columns: ["CustomerID"], statementID: "s1", alias: "t0"),
            RemediableCandidate(table: "Orders", columns: ["CustomerID", "OrderDate"], statementID: "s2", alias: "t0"),
        ]
        let deduped = IndexCandidateGenerator.deduplicate(remediables)
        XCTAssertEqual(deduped.map(\.columns), [["CustomerID", "OrderDate"]])
    }

    /// A dropped prefix candidate's provenance must not be lost: `s1`
    /// contributed only `(CustomerID)`, which never survives on its own,
    /// but `s1` is still attributed to the wider `(CustomerID, OrderDate)`
    /// index that now serves it.
    func testDeduplicatePreservesPrefixCandidateSourceStatementIDs() {
        let remediables = [
            RemediableCandidate(table: "Orders", columns: ["CustomerID"], statementID: "s1", alias: "t0"),
            RemediableCandidate(table: "Orders", columns: ["CustomerID", "OrderDate"], statementID: "s2", alias: "t0"),
        ]
        let deduped = IndexCandidateGenerator.deduplicate(remediables)
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].sourceStatementIDs, ["s1", "s2"])
    }

    func testDeduplicateKeepsNonPrefixCandidatesOnTheSameTable() {
        let remediables = [
            RemediableCandidate(table: "Orders", columns: ["CustomerID"], statementID: "s1", alias: "t0"),
            RemediableCandidate(table: "Orders", columns: ["EmployeeID"], statementID: "s2", alias: "t0"),
        ]
        let deduped = IndexCandidateGenerator.deduplicate(remediables)
        XCTAssertEqual(Set(deduped.map(\.columns)), [["CustomerID"], ["EmployeeID"]])
    }

    func testDDLRendersQuotedTableAndColumns() {
        let candidate = candidate(table: "Order Details", columns: ["OrderID", "ProductID"])
        XCTAssertEqual(
            candidate.ddl,
            #"CREATE INDEX "ix_advisor_order_details_orderid_productid" ON "Order Details" ("OrderID", "ProductID")"#
        )
    }

    // MARK: - Finding remediable statements

    /// The improvement rule accepts `automatic_covering_index` as a
    /// remediable "before" shape (see `IndexCandidateVerifierTests`), but
    /// that's only reachable end to end if `remediableCandidates` actually
    /// looks for that root shape too, not only `full_table_scan`. These are
    /// the same three real EQP rows from the Products/Categories scratch-copy
    /// finding, hand-built here so this is a pure unit test of the
    /// generator's root-shape scan, independent of a live database.
    ///
    /// `Categories AS c` (the driving side of the `LEFT JOIN`, a genuine
    /// `full_table_scan` root) also yields a candidate here, same as the
    /// driving-side false positive in
    /// `IndexCandidateVerifierTests.testRealFalsePositiveFromDrivingSideJoinKeyIsRejected`
    /// — `remediableCandidates` surfaces every remediable root regardless of
    /// whether verification will later confirm it as an improvement.
    func testRemediableCandidatesIncludesAutomaticCoveringIndexRoots() {
        let rows = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SCAN c"),
            EQPRow(id: 2, parent: 0, notused: 0, detail: "BLOOM FILTER ON p (CategoryID=?)"),
            EQPRow(
                id: 3,
                parent: 0,
                notused: 0,
                detail: "SEARCH p USING AUTOMATIC COVERING INDEX (CategoryID=?) LEFT-JOIN"
            ),
        ]
        let statement = EQPVarianceStatement(
            id: "test.remediable.automatic-covering-index",
            source: .northwindAnchor,
            renderedSQL: """
                SELECT p.ProductID FROM Categories AS c
                LEFT JOIN Products AS p ON p.CategoryID = c.CategoryID
                WHERE p.UnitPrice > 20
                """,
            northwindAnchorCaseIDs: [],
            bindings: []
        )
        let plan = EQPPlanShapeClassifier.classify(rows: rows, statementID: statement.id)
        let candidates = IndexCandidateGenerator.remediableCandidates(for: statement, plan: plan)
        XCTAssertEqual(candidates.map(\.table), ["Categories", "Products"])
        XCTAssertEqual(candidates.map(\.columns), [["CategoryID"], ["CategoryID", "UnitPrice"]])
    }

    // MARK: - Real corpus, real #390/#391 evidence

    func testRealCorpusCandidatesMatchCheckedInEvidence() throws {
        let candidates = try realGeneratedCandidates()
        let pinned = try loadCandidates("candidates.json")
        XCTAssertEqual(codable(candidates), pinned, "candidates.json is stale relative to a fresh generate run")
    }

    func testCandidateGenerationIsDeterministicAcrossRepeatedRuns() throws {
        let first = try realGeneratedCandidates()
        let second = try realGeneratedCandidates()
        XCTAssertEqual(codable(first), codable(second))
    }

    /// Reconciles with real evidence: the driving/outer table of a join
    /// (e.g. `Employees AS e` in the self left-join, or `Orders AS t0` in a
    /// join with no `WHERE` filter) legitimately produces a candidate from
    /// its join key, but that candidate provides no improvement — see
    /// `IndexCandidateVerifierTests`. This test only pins that the real
    /// corpus does produce exactly the 6 deduplicated candidates evidenced
    /// in `candidates.json`, not that all 6 are good advice.
    func testRealCorpusProducesExactlySixDeduplicatedCandidates() throws {
        let candidates = try realGeneratedCandidates()
        XCTAssertEqual(candidates.count, 6)
    }

    private func realGeneratedCandidates() throws -> [IndexCandidate] {
        let corpus = try EQPVarianceCorpus.assemble()
        let corpusByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
        let run = try loadCapture("capture_apple-system-3.51.0.json")

        var remediables: [RemediableCandidate] = []
        for capture in run.statements {
            guard let statement = corpusByID[capture.statementID] else {
                continue
            }
            let plan = EQPPlanShapeClassifier.classify(rows: capture.rows, statementID: statement.id)
            remediables.append(contentsOf: IndexCandidateGenerator.remediableCandidates(for: statement, plan: plan))
        }
        return IndexCandidateGenerator.deduplicate(remediables)
    }
}


// MARK: - Shared fixture loading (also used by IndexCandidateVerifierTests)

struct CodableIndexCandidateFixture: Codable, Equatable {
    let table: String
    let columns: [String]
    let sourceStatementIDs: [String]
    let representativeStatementID: String
    let representativeAlias: String

    private enum CodingKeys: String, CodingKey {
        case table
        case columns
        case sourceStatementIDs = "source_statement_ids"
        case representativeStatementID = "representative_statement_id"
        case representativeAlias = "representative_alias"
    }
}


func codable(_ candidates: [IndexCandidate]) -> [CodableIndexCandidateFixture] {
    candidates.map {
        CodableIndexCandidateFixture(
            table: $0.table,
            columns: $0.columns,
            sourceStatementIDs: $0.sourceStatementIDs,
            representativeStatementID: $0.representativeStatementID,
            representativeAlias: $0.representativeAlias
        )
    }
}


func pinnedEvidenceURL(named name: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Evidence") else {
        throw IndexAdvisorFixtureError.missingResource(name)
    }
    return url
}


func loadCapture(_ name: String) throws -> EQPCaptureRun {
    try JSONDecoder().decode(EQPCaptureRun.self, from: Data(contentsOf: pinnedEvidenceURL(named: name)))
}


func loadCandidates(_ name: String) throws -> [CodableIndexCandidateFixture] {
    try JSONDecoder().decode([CodableIndexCandidateFixture].self, from: Data(contentsOf: pinnedEvidenceURL(named: name)))
}


enum IndexAdvisorFixtureError: Error {
    case missingResource(String)
}
