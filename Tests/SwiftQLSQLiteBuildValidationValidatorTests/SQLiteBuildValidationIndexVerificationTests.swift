//
//  SQLiteBuildValidationIndexVerificationTests.swift
//
//  Issue #397: a recommendation that carries its own proof — a before-plan,
//  the DDL, and an after-plan — produced on a disposable copy that never
//  touches the pinned snapshot.
//

import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationScratchSnapshotTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    func testTheCopyIsRemovedOnASuccessfulRun() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            var observedCopy: URL?
            try SQLiteBuildValidationScratchSnapshot.withCopy(of: url) { copyURL in
                observedCopy = copyURL
                XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))
            }
            let copyURL = try XCTUnwrap(observedCopy)
            XCTAssertFalse(FileManager.default.fileExists(atPath: copyURL.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: copyURL.deletingLastPathComponent().path
                )
            )
        }
    }

    /// The interruption case: work stops part-way, and no scratch state and no
    /// change to the snapshot may survive it.
    func testAnInterruptedRunLeavesNoScratchStateAndAnUnchangedSnapshot() throws {
        struct Interruption: Error {}

        try Support.withValidatorOwnedNorthwindURL { url in
            let before = try Data(contentsOf: url)
            var observedCopy: URL?

            XCTAssertThrowsError(
                try SQLiteBuildValidationScratchSnapshot.withCopy(of: url) { copyURL in
                    observedCopy = copyURL
                    // Write to the copy first, so the test proves the cleanup
                    // removes real state rather than an empty directory.
                    let queue = try DatabaseQueue(path: copyURL.path)
                    try queue.write { database in
                        try database.execute(
                            sql: "CREATE INDEX ix_scratch_probe ON Orders (CustomerID)"
                        )
                    }
                    try queue.close()
                    throw Interruption()
                }
            ) { error in
                XCTAssertTrue(error is Interruption)
            }

            let copyURL = try XCTUnwrap(observedCopy)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: copyURL.deletingLastPathComponent().path
                )
            )
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testAScratchDirectoryBesideTheSnapshotIsRefused() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            XCTAssertThrowsError(
                try SQLiteBuildValidationScratchSnapshot.withCopy(
                    of: url,
                    in: url.deletingLastPathComponent()
                ) { _ in }
            ) { error in
                guard case .scratchInsideSnapshotDirectory =
                    error as? SQLiteBuildValidationScratchError else {
                    return XCTFail("expected a snapshot-directory refusal, got \(error)")
                }
            }
        }
    }

    func testAScratchDirectoryInsideTheWorkingDirectoryIsRefused() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let workingDirectory = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            XCTAssertThrowsError(
                try SQLiteBuildValidationScratchSnapshot.withCopy(
                    of: url,
                    in: workingDirectory
                ) { _ in }
            ) { error in
                guard case .scratchInsideWorkingDirectory =
                    error as? SQLiteBuildValidationScratchError else {
                    return XCTFail("expected a working-directory refusal, got \(error)")
                }
            }
        }
    }
}


final class SQLiteBuildValidationIndexVerificationTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport
    typealias Verifier = SQLiteBuildValidationIndexCandidateVerifier

    private static func query(
        _ id: String,
        _ sql: String
    ) -> SQLiteBuildValidationQueryEntry {
        Support.query(
            id: id,
            sql: sql,
            results: [
                Support.result(
                    identity: "result/value",
                    declaredAlias: "value",
                    valueTypeIdentifier: "swift.string",
                    valueTypeName: "Swift.String",
                    nullability: "nullable",
                    storageIdentifier: "text"
                ),
            ]
        )
    }

    /// A statement whose plan is a full scan and whose predicates give SQLite
    /// something to seek on.
    private static let remediable = query(
        "orders.by-customer-and-employee",
        "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5"
    )

    private func verifiedSet(
        queries: [SQLiteBuildValidationQueryEntry]
    ) throws -> SQLiteBuildValidationIndexRecommendationSet {
        try Support.withValidatorOwnedNorthwindURL { url in
            let manifest = Support.manifest(queries: queries)
            let planReport = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )
            return try Verifier.verify(
                candidates: planReport.indexCandidates.candidates,
                queries: manifest.queries,
                snapshotURL: url
            )
        }
    }

    // MARK: - A recommendation carries its own proof

    func testARemediableStatementYieldsAVerifiedRecommendationWithEvidence() throws {
        let set = try verifiedSet(queries: [Self.remediable])

        XCTAssertEqual(set.improvementRuleVersion, Verifier.improvementRuleVersion)
        XCTAssertEqual(set.recommendations.count, 1)
        XCTAssertTrue(set.unverified.isEmpty)

        let recommendation = try XCTUnwrap(set.recommendations.first)
        XCTAssertEqual(recommendation.candidate.table, "Orders")
        XCTAssertEqual(
            recommendation.candidate.columns.map(\.name),
            ["CustomerID", "EmployeeID"]
        )
        XCTAssertEqual(recommendation.statementID, Self.remediable.id)
        XCTAssertEqual(
            recommendation.descriptorIdentity,
            Self.remediable.descriptorIdentity
        )
        XCTAssertEqual(
            recommendation.improvementRuleVersion,
            Verifier.improvementRuleVersion
        )

        // The evidence triple: a scan before, this candidate's index after.
        XCTAssertTrue(
            recommendation.beforePlan.contains { $0.shape == .fullTableScan },
            "before: \(recommendation.beforePlan.map(\.detail))"
        )
        let afterNode = try XCTUnwrap(
            Verifier.node(
                forTable: recommendation.candidate.representativeAlias,
                in: recommendation.afterPlan
            )
        )
        XCTAssertEqual(afterNode.shape, .indexSearch)
        XCTAssertEqual(afterNode.attributes.indexName, recommendation.candidate.indexName)

        // Advice is not presented as free.
        XCTAssertTrue(recommendation.writeCostNote.contains("Orders"))
        XCTAssertTrue(recommendation.writeCostNote.contains("830 rows"))
    }

    /// A candidate SQLite declines to use is rejected, with the reason kept.
    func testAPlausibleButUselessCandidateIsRejectedWithItsReason() throws {
        let candidate = SQLiteBuildValidationIndexCandidate(
            table: "Orders",
            // The rowid seek this statement already gets cannot be improved
            // on, so a plausible-looking index on another column is ignored.
            columns: [SQLiteBuildValidationIndexCandidateColumn(name: "ShipCity")],
            sourceQueryIDs: ["seek"],
            sourceDescriptorIdentities: ["d"],
            representativeQueryID: "seek",
            representativeAlias: "o"
        )
        let seek = Self.query(
            "seek",
            "SELECT o.ShipCity AS value FROM Orders o WHERE o.OrderID = 10248"
        )

        try Support.withValidatorOwnedNorthwindURL { url in
            let set = try Verifier.verify(
                candidates: [candidate],
                queries: [seek],
                snapshotURL: url
            )

            XCTAssertTrue(set.recommendations.isEmpty)
            XCTAssertEqual(set.unverified.count, 1)
            let rejection = try XCTUnwrap(set.unverified.first)
            XCTAssertTrue(
                rejection.reason.contains("not a full table scan"),
                rejection.reason
            )
            // A rejection that reached the rule keeps its plans, so the reader
            // can see what actually happened.
            XCTAssertNotNil(rejection.beforePlan)
            XCTAssertNotNil(rejection.afterPlan)
        }
    }

    /// A candidate whose statement is not in the manifest cannot be verified,
    /// so it is reported unverified rather than recommended.
    func testACandidateThatCannotBeVerifiedIsReportedUnverified() throws {
        let orphan = SQLiteBuildValidationIndexCandidate(
            table: "Orders",
            columns: [SQLiteBuildValidationIndexCandidateColumn(name: "CustomerID")],
            sourceQueryIDs: ["missing"],
            sourceDescriptorIdentities: ["d"],
            representativeQueryID: "missing",
            representativeAlias: "o"
        )

        try Support.withValidatorOwnedNorthwindURL { url in
            let set = try Verifier.verify(
                candidates: [orphan],
                queries: [],
                snapshotURL: url
            )

            XCTAssertTrue(set.recommendations.isEmpty)
            XCTAssertEqual(set.unverified.count, 1)
            XCTAssertTrue(
                try XCTUnwrap(set.unverified.first).reason.contains("not in the manifest")
            )
        }
    }

    // MARK: - The improvement rule

    /// The rule must credit an improvement only to the index that produced it.
    func testTheRuleRefusesToCreditAnImprovementToADifferentIndex() {
        let candidate = SQLiteBuildValidationIndexCandidate(
            table: "Orders",
            columns: [SQLiteBuildValidationIndexCandidateColumn(name: "CustomerID")],
            sourceQueryIDs: ["q"],
            sourceDescriptorIdentities: ["d"],
            representativeQueryID: "q",
            representativeAlias: "o"
        )
        let before = [
            SQLiteBuildValidationPlanNode(
                detail: "SCAN o",
                shape: .fullTableScan,
                attributes: SQLiteBuildValidationPlanAttributes(table: "o"),
                children: []
            ),
        ]
        let after = [
            SQLiteBuildValidationPlanNode(
                detail: "SEARCH o USING INDEX some_other_index (CustomerID=?)",
                shape: .indexSearch,
                attributes: SQLiteBuildValidationPlanAttributes(
                    table: "o",
                    indexName: "some_other_index",
                    constrainedColumns: ["CustomerID"]
                ),
                children: []
            ),
        ]

        let outcome = Verifier.applyImprovementRule(
            candidate: candidate,
            before: before,
            after: after
        )
        XCTAssertFalse(outcome.isImprovement)
        XCTAssertTrue(outcome.reason.contains("some_other_index"), outcome.reason)
    }

    /// An index SQLite creates but never narrows the scan with is not an
    /// improvement.
    func testAnIndexThatNarrowsNothingIsNotAnImprovement() {
        let candidate = SQLiteBuildValidationIndexCandidate(
            table: "Orders",
            columns: [SQLiteBuildValidationIndexCandidateColumn(name: "CustomerID")],
            sourceQueryIDs: ["q"],
            sourceDescriptorIdentities: ["d"],
            representativeQueryID: "q",
            representativeAlias: "o"
        )
        let outcome = Verifier.applyImprovementRule(
            candidate: candidate,
            before: [
                SQLiteBuildValidationPlanNode(
                    detail: "SCAN o",
                    shape: .fullTableScan,
                    attributes: SQLiteBuildValidationPlanAttributes(table: "o"),
                    children: []
                ),
            ],
            after: [
                SQLiteBuildValidationPlanNode(
                    detail: "SCAN o USING COVERING INDEX \(candidate.indexName)",
                    shape: .coveringIndexScan,
                    attributes: SQLiteBuildValidationPlanAttributes(
                        table: "o",
                        indexName: candidate.indexName,
                        isCovering: true
                    ),
                    children: []
                ),
            ]
        )

        XCTAssertFalse(outcome.isImprovement)
        XCTAssertTrue(outcome.reason.contains("not narrowing"), outcome.reason)
    }

    // MARK: - The pinned snapshot, and determinism

    func testVerificationLeavesTheSnapshotByteIdentical() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let before = try Data(contentsOf: url)
            let manifest = Support.manifest(queries: [Self.remediable])
            let planReport = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )
            _ = try Verifier.verify(
                candidates: planReport.indexCandidates.candidates,
                queries: manifest.queries,
                snapshotURL: url
            )

            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testRepeatedVerificationsProduceIdenticalRecommendations() throws {
        let first = try verifiedSet(queries: [Self.remediable])
        let second = try verifiedSet(queries: [Self.remediable])

        XCTAssertEqual(
            try JSONEncoder.canonical.encode(first),
            try JSONEncoder.canonical.encode(second)
        )
    }

    // MARK: - Through the CLI

    func testVerificationIsOptInAndNeverChangesTheExitStatus() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let workingDirectory = databaseURL.deletingLastPathComponent()
            let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
            try Support.manifest(queries: [Self.remediable])
                .canonicalJSONData()
                .write(to: manifestURL)

            func run(_ extraArguments: [String], suffix: String) throws
                -> SQLiteBuildValidationValidatorCLIRunResult {
                try SQLiteBuildValidationValidatorCLIRunner.run(
                    options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                        "--database", databaseURL.path,
                        "--manifest", manifestURL.path,
                        "--output", workingDirectory.appendingPathComponent("r\(suffix).json").path,
                        "--plan-output", workingDirectory.appendingPathComponent("p\(suffix).json").path,
                    ] + extraArguments)
                )
            }

            let unverified = try run([], suffix: "1")
            // Not requested is not the same answer as "nothing survived".
            XCTAssertNil(unverified.planReport?.indexRecommendations)

            let verified = try run(["--verify-index-candidates"], suffix: "2")
            let recommendations = try XCTUnwrap(verified.planReport?.indexRecommendations)
            XCTAssertEqual(recommendations.recommendations.count, 1)
            XCTAssertEqual(verified.exitCode, 0)
            XCTAssertEqual(verified.report.overallVerdict, .passed)

            // The advisory summary carries the copy-pasteable DDL.
            let summary = try XCTUnwrap(verified.planReport).humanReadableSummary()
            XCTAssertTrue(summary.contains("CREATE INDEX"), summary)
        }
    }
}
