import Foundation
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationValidatorCLIRunnerTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    func testRunnerExitsZeroOnPassAndOneOnFailAndWritesCanonicalReport() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let workingDirectory = databaseURL.deletingLastPathComponent()

            let passingManifestURL = workingDirectory.appendingPathComponent("passing.json")
            try Support.manifest(queries: [
                Support.query(id: "trivial", sql: "SELECT 1 AS value"),
            ]).canonicalJSONData().write(to: passingManifestURL)
            let passingOutputURL = workingDirectory.appendingPathComponent("passing-report.json")

            let passingResult = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", passingManifestURL.path,
                    "--output", passingOutputURL.path,
                ])
            )
            XCTAssertEqual(passingResult.exitCode, 0)
            XCTAssertEqual(
                try Data(contentsOf: passingOutputURL),
                try passingResult.report.canonicalJSONData()
            )

            let failingManifestURL = workingDirectory.appendingPathComponent("failing.json")
            try Support.manifest(queries: [
                Support.query(sql: "SELECT * FROM tests_totally_missing_table"),
            ]).canonicalJSONData().write(to: failingManifestURL)
            let failingOutputURL = workingDirectory.appendingPathComponent("failing-report.json")

            let failingResult = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", failingManifestURL.path,
                    "--output", failingOutputURL.path,
                ])
            )
            XCTAssertEqual(failingResult.exitCode, 1)
            XCTAssertEqual(failingResult.report.overallVerdict, .failed)
        }
    }

    /// `--plan-output` is the whole opt-in: without it the run captures no
    /// plans and writes no sidecar, and with it the sidecar is a second file
    /// beside the report rather than a change to it.
    func testPlanOutputIsOptInAndWritesASecondArtifact() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let workingDirectory = databaseURL.deletingLastPathComponent()
            let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
            try Support.manifest(queries: [
                Support.query(id: "trivial", sql: "SELECT 1 AS value"),
            ]).canonicalJSONData().write(to: manifestURL)

            let reportOnlyURL = workingDirectory.appendingPathComponent("report-only.json")
            let withoutPlans = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", manifestURL.path,
                    "--output", reportOnlyURL.path,
                ])
            )
            XCTAssertNil(withoutPlans.planReport)

            let reportURL = workingDirectory.appendingPathComponent("report.json")
            let planURL = workingDirectory.appendingPathComponent("plans.json")
            let withPlans = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", manifestURL.path,
                    "--output", reportURL.path,
                    "--plan-output", planURL.path,
                ])
            )
            let planReport = try XCTUnwrap(withPlans.planReport)

            XCTAssertEqual(withPlans.exitCode, 0)
            XCTAssertEqual(
                try Data(contentsOf: planURL),
                try planReport.canonicalJSONData()
            )
            // The correctness artifact is unchanged by the presence of plans.
            XCTAssertEqual(
                try Data(contentsOf: reportURL),
                try Data(contentsOf: reportOnlyURL)
            )
            XCTAssertEqual(planReport.records.count, 1)
        }
    }

    /// Two artifacts, two files. One path for both would silently keep only
    /// whichever was written last.
    func testPlanOutputMayNotAliasTheReportOrTheInputs() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let workingDirectory = databaseURL.deletingLastPathComponent()
            let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
            try Support.manifest().canonicalJSONData().write(to: manifestURL)
            let reportURL = workingDirectory.appendingPathComponent("report.json")

            XCTAssertThrowsError(
                try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                    databaseURL: databaseURL,
                    manifestURL: manifestURL,
                    outputURL: reportURL,
                    planOutputURL: reportURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorCLIError,
                    .planOutputConflictsWithReportOutput
                )
            }

            XCTAssertThrowsError(
                try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                    databaseURL: databaseURL,
                    manifestURL: manifestURL,
                    outputURL: reportURL,
                    planOutputURL: manifestURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorCLIError,
                    .planOutputConflictsWithInput("--manifest")
                )
            }

            XCTAssertThrowsError(
                try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                    databaseURL: databaseURL,
                    manifestURL: manifestURL,
                    outputURL: reportURL,
                    planOutputURL: URL(fileURLWithPath: databaseURL.path + "-wal")
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorCLIError,
                    .planOutputConflictsWithDatabaseSidecar
                )
            }
        }
    }

    /// The advisory options are read from the command line and the
    /// checked-in file, and neither can reach the exit code.
    func testPlanDiagnosticOptionsAreReadFromTheCommandLineAndTheSuppressionFile() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let workingDirectory = databaseURL.deletingLastPathComponent()
            let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
            try Support.manifest(queries: [
                Support.query(
                    id: "scan-orders",
                    sql: "SELECT ShipCity AS ship_city FROM Orders",
                    results: [
                        Support.result(
                            identity: "result/ship_city",
                            declaredAlias: "ship_city",
                            valueTypeIdentifier: "swift.string",
                            valueTypeName: "Swift.String",
                            nullability: "nullable",
                            storageIdentifier: "text"
                        ),
                    ]
                ),
            ]).canonicalJSONData().write(to: manifestURL)

            let suppressionsURL = workingDirectory.appendingPathComponent("suppressions.json")
            try JSONEncoder().encode(
                SQLiteBuildValidationPlanSuppressions(suppressions: [
                    SQLiteBuildValidationPlanSuppression(
                        code: .fullTableScan,
                        table: "Orders",
                        reason: "The reporting query reads the whole table by design."
                    ),
                ])
            ).write(to: suppressionsURL)

            let unsuppressed = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", manifestURL.path,
                    "--output", workingDirectory.appendingPathComponent("r1.json").path,
                    "--plan-output", workingDirectory.appendingPathComponent("p1.json").path,
                ])
            )
            XCTAssertEqual(unsuppressed.planReport?.diagnostics.map(\.code), [.fullTableScan])
            XCTAssertEqual(unsuppressed.exitCode, 0)

            let suppressed = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", manifestURL.path,
                    "--output", workingDirectory.appendingPathComponent("r2.json").path,
                    "--plan-output", workingDirectory.appendingPathComponent("p2.json").path,
                    "--plan-suppressions", suppressionsURL.path,
                ])
            )
            XCTAssertTrue(try XCTUnwrap(suppressed.planReport).diagnostics.isEmpty)
            XCTAssertEqual(suppressed.planReport?.suppressedDiagnostics.count, 1)

            let lenient = try SQLiteBuildValidationValidatorCLIRunner.run(
                options: try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                    "--database", databaseURL.path,
                    "--manifest", manifestURL.path,
                    "--output", workingDirectory.appendingPathComponent("r3.json").path,
                    "--plan-output", workingDirectory.appendingPathComponent("p3.json").path,
                    "--plan-scan-row-threshold", "100000",
                ])
            )
            XCTAssertTrue(try XCTUnwrap(lenient.planReport).diagnostics.isEmpty)
            XCTAssertEqual(
                try XCTUnwrap(lenient.planReport).settings.fullTableScanRowThreshold,
                100_000
            )
        }
    }

    func testANonNumericScanThresholdIsRejected() {
        XCTAssertThrowsError(
            try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                "--database", "/tmp/a.sqlite",
                "--manifest", "/tmp/m.json",
                "--output", "/tmp/r.json",
                "--plan-scan-row-threshold", "lots",
            ])
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationValidatorCLIError,
                .invalidValue("--plan-scan-row-threshold", "lots")
            )
        }
    }

    func testOptionsParsingRequiresDatabaseManifestAndOutput() {
        XCTAssertThrowsError(
            try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: [
                "--database", "/tmp/a.sqlite",
            ])
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationValidatorCLIError,
                .requiredOption("--manifest")
            )
        }
    }

    func testHelpBypassesRequiredOptionChecks() throws {
        let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
            arguments: ["--help"]
        )
        XCTAssertTrue(options.showsHelp)
    }

    func testPreflightRejectsOutputAliasingInputs() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let manifestURL = databaseURL.deletingLastPathComponent()
                .appendingPathComponent("manifest.json")
            try Data().write(to: manifestURL)

            XCTAssertThrowsError(
                try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                    databaseURL: databaseURL,
                    manifestURL: manifestURL,
                    outputURL: databaseURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorCLIError,
                    .outputConflictsWithInput("--database")
                )
            }
        }
    }
}
