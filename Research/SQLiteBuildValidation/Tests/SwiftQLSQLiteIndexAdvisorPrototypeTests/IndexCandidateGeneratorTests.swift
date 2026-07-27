import XCTest
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype
@testable import SwiftQLSQLiteIndexAdvisorPrototype


final class IndexCandidateGeneratorTests: XCTestCase {
    // MARK: - Precedence rule

    func testPrecedenceEqualityThenRangeThenJoinThenOrderBy() {
        let sql = #"""
            SELECT "t0"."x" FROM "T" AS "t0"
            JOIN "U" AS "u" ON ("t0"."joinCol" == "u"."id")
            WHERE (("t0"."eq" == 1) AND ("t0"."rangeA" > 2) AND ("t0"."rangeB" < 3))
            ORDER BY "t0"."sortCol" ASC
            """#
        XCTAssertEqual(
            IndexCandidateGenerator.candidateColumns(for: "t0", in: sql),
            ["eq", "rangeA", "joinCol", "sortCol"],
            "only the FIRST range column is included; the second range column (rangeB) narrows no further"
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
