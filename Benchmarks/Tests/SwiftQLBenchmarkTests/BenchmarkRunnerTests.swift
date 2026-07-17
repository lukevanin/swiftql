import Foundation
import XCTest
@testable import SwiftQLBenchmarks

final class BenchmarkRunnerTests: XCTestCase {
    func testSmokeRunCoversEveryCaseAndPhaseWithoutLatencyGates() throws {
        let report = try SwiftQLBenchmarkRunner().run(
            configuration: .smoke,
            packageRoot: repositoryRoot()
        )

        XCTAssertEqual(
            report.cases.map(\.identifier),
            [
                "simple_parameterized_lookup",
                "representative_multi_join_read",
                "bounded_write",
                "deterministic_row_decode",
            ]
        )
        XCTAssertEqual(report.cases.flatMap(\.phases).count, 24)
        XCTAssertEqual(report.measurementCount, 23)
        XCTAssertEqual(
            report.cases.flatMap(\.phases).filter { $0.applicability == .notApplicable }.count,
            1
        )
        XCTAssertEqual(
            Set(report.cases.flatMap(\.phases).map(\.phase)),
            Set(BenchmarkPhase.allCases)
        )
        XCTAssertFalse(report.database.sqliteVersion.isEmpty)
        XCTAssertFalse(report.database.sqliteSourceID.isEmpty)
        XCTAssertFalse(report.database.compileOptions.isEmpty)
        XCTAssertFalse(report.environment.swiftVersion.isEmpty)
        XCTAssertFalse(report.environment.grdbVersion.isEmpty)
        XCTAssertEqual(report.fixture.personCount, 512)

        // Structural checks only: CI machines are intentionally not held to latency thresholds.
        for measurement in report.cases.flatMap(\.phases).compactMap(\.measurement) {
            XCTAssertEqual(measurement.samplesNanoseconds.count, 1)
        }
    }

    func testJSONRoundTripAndStableSchemaKeys() throws {
        let report = try SwiftQLBenchmarkRunner().run(
            configuration: .smoke,
            packageRoot: repositoryRoot()
        )
        let data = try report.encodedJSON()
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        XCTAssertEqual(decoded, report)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["sampleUnit"] as? String, "nanoseconds_per_operation")
        let cases = try XCTUnwrap(object["cases"] as? [[String: Any]])
        let phases = try XCTUnwrap(cases.first?["phases"] as? [[String: Any]])
        let measurement = try XCTUnwrap(phases.first?["measurement"] as? [String: Any])
        XCTAssertNotNil(measurement["samplesNanoseconds"] as? [Int])
    }

    func testReportValidationRejectsIncompletePhaseMatrix() throws {
        let report = try SwiftQLBenchmarkRunner().run(
            configuration: .smoke,
            packageRoot: repositoryRoot()
        )
        let first = report.cases[0]
        let incompleteCase = BenchmarkCaseReport(
            identifier: first.identifier,
            purpose: first.purpose,
            sql: first.sql,
            parameters: first.parameters,
            queryPlan: first.queryPlan,
            expectedResultRowCount: first.expectedResultRowCount,
            expectedAffectedRowCount: first.expectedAffectedRowCount,
            phases: Array(first.phases.dropLast())
        )
        let invalid = BenchmarkReport(
            formatVersion: report.formatVersion,
            generatedAt: report.generatedAt,
            monotonicClock: report.monotonicClock,
            sampleUnit: report.sampleUnit,
            configuration: report.configuration,
            environment: report.environment,
            database: report.database,
            fixture: report.fixture,
            schemaSQL: report.schemaSQL,
            cases: [incompleteCase] + report.cases.dropFirst()
        )

        XCTAssertThrowsError(try invalid.validate())
    }

    func testHumanSummaryComesFromSameReport() throws {
        let report = try SwiftQLBenchmarkRunner().run(
            configuration: .smoke,
            packageRoot: repositoryRoot()
        )
        let summary = report.humanReadableSummary()
        XCTAssertTrue(summary.contains("SwiftQL performance baseline"))
        XCTAssertTrue(summary.contains("simple_parameterized_lookup"))
        XCTAssertTrue(summary.contains("not applicable"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
