//
//  SQLiteIndexAdvisorTests.swift
//
//  Issue #399: the fixit-equivalent. One explicit invocation turns reviewed,
//  verified advice into a checked-in artifact; a build never does it.
//

import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator
import XCTest
@testable import SwiftQLSQLiteIndexAdvisor


final class SQLiteIndexAdvisorTests: XCTestCase {

    // MARK: - A real, verified sidecar to work from

    private static let northwindSchemaSHA256 =
        "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8"

    /// A statement whose plan is a full scan and whose predicates give SQLite
    /// something to seek on.
    private static let remediableSQL =
        "SELECT o.ShipCity AS ship_city FROM Orders AS o WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5"

    private static func manifest() -> SQLiteBuildValidationManifest {
        SQLiteBuildValidationManifest(
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: SQLiteBuildValidationSchemaSnapshot(
                identifier: "northwind.issue-254",
                databaseSHA256: northwindSchemaSHA256,
                databaseByteCount: 602_112,
                schemaRowCount: 37,
                schemaFingerprint: "e2c8fadbd38c2313"
            ),
            queries: [
                SQLiteBuildValidationQueryEntry(
                    id: "advisor.orders-by-customer-and-employee",
                    definitionIdentity: "advisor/orders@1",
                    descriptorIdentity: "swiftql-query-v1-advisor-orders",
                    sql: remediableSQL,
                    dialectIdentifier: XLSQLiteDialect.identity.rawValue,
                    cardinality: XLQueryCardinality.many.rawValue,
                    results: [
                        SQLiteBuildValidationResultEntry(
                            index: 0,
                            identity: "result/ship_city",
                            declaredAlias: "ship_city",
                            valueTypeIdentifier: "swift.string",
                            valueTypeName: "Swift.String",
                            nullability: "nullable",
                            codec: nil,
                            storageIdentifier: "text"
                        ),
                    ]
                ),
            ]
        )
    }

    /// Runs the real validator over the pinned snapshot, with plan analysis
    /// and verification, and hands back the sidecar it wrote.
    private func withVerifiedSidecar<Result>(
        _ body: (URL, SQLiteBuildValidationPlanReport) throws -> Result
    ) throws -> Result {
        try NorthwindFixture.withTemporaryCopy { copy in
            let workingDirectory = copy.url.deletingLastPathComponent()
            let snapshotURL = workingDirectory.appendingPathComponent("snapshot.sqlite")
            let canonicalPool = try NorthwindFixture.validatedReadOnlyPool()
            defer { try? canonicalPool.close() }
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: canonicalPool.path),
                to: snapshotURL
            )

            let manifest = Self.manifest()
            let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
            try manifest.canonicalJSONData().write(to: manifestURL)
            let reportURL = workingDirectory.appendingPathComponent("report.json")
            let planURL = workingDirectory.appendingPathComponent("plans.json")

            _ = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", snapshotURL.path,
                    "--manifest", manifestURL.path,
                    "--output", reportURL.path,
                    "--plan-output", planURL.path,
                    "--verify-index-candidates",
                ])
            )
            return try body(
                planURL,
                try SQLiteBuildValidationPlanReport.decode(contentsOf: planURL)
            )
        }
    }

    // MARK: - Report mode

    func testReportModePrintsRecommendationsWithEvidenceAndWritesNothing() throws {
        try withVerifiedSidecar { planURL, planReport in
            let workingDirectory = planURL.deletingLastPathComponent()
            let before = try FileManager.default.contentsOfDirectory(
                atPath: workingDirectory.path
            ).sorted()

            let result = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(planReportURL: planURL)
            )

            XCTAssertEqual(result.outcome, .reported)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(result.standardOutput.contains("1 verified recommendation(s)"))
            XCTAssertTrue(result.standardOutput.contains("CREATE INDEX IF NOT EXISTS"))
            XCTAssertTrue(result.standardOutput.contains("Before:"))
            XCTAssertTrue(result.standardOutput.contains("After:"))
            XCTAssertTrue(result.standardOutput.contains("Cost:"))
            XCTAssertTrue(
                result.standardOutput.contains("Report mode changed nothing")
            )
            XCTAssertEqual(
                planReport.indexRecommendations?.recommendations.count,
                1
            )

            // The tree is untouched.
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(
                    atPath: workingDirectory.path
                ).sorted(),
                before
            )
        }
    }

    // MARK: - Apply mode

    func testApplyWritesTheExpectedArtifactAndASecondRunIsANoOp() throws {
        try withVerifiedSidecar { planURL, _ in
            let outputURL = planURL.deletingLastPathComponent()
                .appendingPathComponent("Generated/AdvisedIndices.sql")

            let first = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(
                    planReportURL: planURL,
                    outputURL: outputURL,
                    applies: true
                )
            )
            XCTAssertEqual(first.outcome, .written)

            let contents = try String(contentsOf: outputURL, encoding: .utf8)
            XCTAssertTrue(contents.contains(SQLiteIndexAdvisorArtifact.generatedHeaderMarker))
            XCTAssertTrue(
                contents.contains(
                    "CREATE INDEX IF NOT EXISTS \"ix_advisor_orders_customerid_employeeid\" ON \"Orders\" (\"CustomerID\", \"EmployeeID\");"
                ),
                contents
            )
            XCTAssertTrue(contents.contains("-- Motivated by: advisor.orders-by-customer-and-employee"))
            XCTAssertTrue(contents.contains("swiftql-index-improvement-rule-v1"))

            let writtenData = try Data(contentsOf: outputURL)
            let modifiedBefore = try FileManager.default
                .attributesOfItem(atPath: outputURL.path)[.modificationDate] as? Date

            let second = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(
                    planReportURL: planURL,
                    outputURL: outputURL,
                    applies: true
                )
            )
            XCTAssertEqual(second.outcome, .unchanged)
            XCTAssertEqual(try Data(contentsOf: outputURL), writtenData)
            // Not even the mtime moves, so nothing downstream rebuilds.
            XCTAssertEqual(
                try FileManager.default
                    .attributesOfItem(atPath: outputURL.path)[.modificationDate] as? Date,
                modifiedBefore
            )
        }
    }

    /// The whole point of apply mode being a separate flag.
    func testApplyingRequiresBothTheFlagAndAnOutputPath() throws {
        XCTAssertThrowsError(
            try SQLiteIndexAdvisorOptions.parse(arguments: [
                "--plan-report", "/tmp/plans.json",
                "--apply",
            ])
        ) { error in
            XCTAssertEqual(
                error as? SQLiteIndexAdvisorError,
                .applyRequiresOutput
            )
        }

        // Naming an output without --apply still writes nothing.
        try withVerifiedSidecar { planURL, _ in
            let outputURL = planURL.deletingLastPathComponent()
                .appendingPathComponent("NotWritten.sql")
            let result = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(
                    planReportURL: planURL,
                    outputURL: outputURL
                )
            )

            XCTAssertEqual(result.outcome, .reported)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    // MARK: - Refusals

    func testASidecarWithoutVerificationIsRefusedWithAClearMessage() throws {
        try NorthwindFixture.withTemporaryCopy { copy in
            let workingDirectory = copy.url.deletingLastPathComponent()
            let planURL = workingDirectory.appendingPathComponent("unverified-plans.json")
            // A sidecar from a run that captured plans but never verified.
            try SQLiteBuildValidationPlanReport(
                manifest: Self.manifest(),
                observedDatabaseByteCount: nil,
                observedDatabaseSHA256: nil,
                records: []
            ).canonicalJSONData().write(to: planURL)

            XCTAssertThrowsError(
                try SQLiteIndexAdvisorRunner.run(
                    options: SQLiteIndexAdvisorOptions(
                        planReportURL: planURL,
                        outputURL: workingDirectory.appendingPathComponent("out.sql"),
                        applies: true
                    )
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteIndexAdvisorError,
                    .noVerificationInSidecar
                )
                XCTAssertTrue(
                    String(describing: error).contains("--verify-index-candidates"),
                    String(describing: error)
                )
            }
        }
    }

    /// Verification that ran and accepted nothing is an answer, not a
    /// failure — but it still writes nothing.
    func testVerificationThatAcceptedNothingWritesNothingAndSaysSo() throws {
        try NorthwindFixture.withTemporaryCopy { copy in
            let workingDirectory = copy.url.deletingLastPathComponent()
            let planURL = workingDirectory.appendingPathComponent("empty-plans.json")
            let outputURL = workingDirectory.appendingPathComponent("out.sql")
            try SQLiteBuildValidationPlanReport(
                manifest: Self.manifest(),
                observedDatabaseByteCount: nil,
                observedDatabaseSHA256: nil,
                records: []
            )
            .withIndexRecommendations(SQLiteBuildValidationIndexRecommendationSet())
            .canonicalJSONData()
            .write(to: planURL)

            let result = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(
                    planReportURL: planURL,
                    outputURL: outputURL,
                    applies: true
                )
            )

            XCTAssertEqual(result.outcome, .nothingToApply)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testAnUnreadableSidecarIsRefusedWithItsPath() throws {
        try NorthwindFixture.withTemporaryCopy { copy in
            let planURL = copy.url.deletingLastPathComponent()
                .appendingPathComponent("not-json.json")
            try Data("this is not a plan sidecar".utf8).write(to: planURL)

            XCTAssertThrowsError(
                try SQLiteIndexAdvisorRunner.run(
                    options: SQLiteIndexAdvisorOptions(planReportURL: planURL)
                )
            ) { error in
                guard case .unreadableSidecar(let path, _) =
                    error as? SQLiteIndexAdvisorError else {
                    return XCTFail("expected an unreadable-sidecar refusal, got \(error)")
                }
                XCTAssertEqual(path, planURL.path)
            }
        }
    }

    // MARK: - The advice actually resolves the diagnosed shape

    /// Applying the generated SQL to a database and re-running plan analysis
    /// must show the diagnosed shape gone. Without this, the whole pipeline
    /// could be internally consistent and still useless.
    func testApplyingTheArtifactResolvesTheDiagnosedShape() throws {
        try withVerifiedSidecar { planURL, planReport in
            let workingDirectory = planURL.deletingLastPathComponent()
            let outputURL = workingDirectory.appendingPathComponent("AdvisedIndices.sql")
            _ = try SQLiteIndexAdvisorRunner.run(
                options: SQLiteIndexAdvisorOptions(
                    planReportURL: planURL,
                    outputURL: outputURL,
                    applies: true
                )
            )

            // Before: the scan is diagnosed.
            XCTAssertEqual(
                planReport.diagnostics.map(\.code.rawValue),
                ["plan.full-table-scan"]
            )

            let appliedURL = workingDirectory.appendingPathComponent("applied.sqlite")
            try FileManager.default.copyItem(
                at: workingDirectory.appendingPathComponent("snapshot.sqlite"),
                to: appliedURL
            )
            let queue = try DatabaseQueue(path: appliedURL.path)
            defer { try? queue.close() }
            let generatedSQL = try String(contentsOf: outputURL, encoding: .utf8)
            try queue.write { database in
                try database.execute(sql: generatedSQL)
            }

            let manifest = Self.manifest()
            let afterReport = try queue.read { database -> SQLiteBuildValidationPlanReport in
                SQLiteBuildValidationPlanCapture.capture(
                    manifest: manifest,
                    in: database,
                    runtimeMetadata: try SQLiteBuildValidationRuntime.capture(from: database),
                    observedDatabaseByteCount: nil,
                    observedDatabaseSHA256: nil
                )
            }

            XCTAssertTrue(
                afterReport.diagnostics.isEmpty,
                "expected the diagnosed shape to be resolved, still have: \(afterReport.diagnostics.map(\.code.rawValue))"
            )
            let roots = try XCTUnwrap(afterReport.records.first?.outcome.capturedRoots)
            XCTAssertTrue(
                roots.contains { $0.shape == .indexSearch },
                "expected an index search, got \(roots.map(\.detail))"
            )
        }
    }

    // MARK: - Determinism

    func testTheGeneratedArtifactIsAPureFunctionOfTheRecommendations() throws {
        try withVerifiedSidecar { planURL, planReport in
            let recommendations = try XCTUnwrap(planReport.indexRecommendations)
            let first = SQLiteIndexAdvisorArtifact.sql(
                for: recommendations,
                sourceDescription: "plans.json"
            )
            let second = SQLiteIndexAdvisorArtifact.sql(
                for: recommendations,
                sourceDescription: "plans.json"
            )

            XCTAssertEqual(first, second)
            XCTAssertFalse(first.isEmpty)
        }
    }
}
