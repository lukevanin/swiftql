import Foundation
import XCTest
@testable import SwiftQLBenchmarks

final class BenchmarkRunnerTests: XCTestCase {
    func testSmokeRunCoversEveryCaseAndPhaseWithoutLatencyGates() throws {
        let report = try SwiftQLBenchmarkRunner().run(
            configuration: .smoke,
            packageRoot: repositoryRoot()
        )

        XCTAssertEqual(report.formatVersion, 2)
        XCTAssertEqual(
            report.cases.map(\.identifier),
            [
                "simple_parameterized_lookup",
                "simple_lookup_inline_literals",
                "representative_multi_join_read",
                "representative_multi_join_read_inline_literals",
                "bounded_write",
                "bounded_write_inline_literals",
                "deterministic_row_decode",
                "deterministic_row_decode_inline_literals",
                "contextual_value_codec",
            ]
        )
        // 9 cases x 12 phases. Six read cases measure 11 phases, two write
        // cases measure 8, and the contextual-codec case measures 2.
        XCTAssertEqual(report.cases.flatMap(\.phases).count, 108)
        XCTAssertEqual(report.measurementCount, 84)
        XCTAssertEqual(
            report.cases.flatMap(\.phases).filter { $0.applicability == .notApplicable }.count,
            24
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
        XCTAssertEqual(report.environment.buildConfiguration, "debug")
        XCTAssertEqual(report.fixture.personCount, 512)

        let contextualCodec = try XCTUnwrap(
            report.cases.first { $0.identifier == "contextual_value_codec" }
        )
        XCTAssertEqual(
            contextualCodec.phases
                .filter { $0.applicability == .measured }
                .map(\.phase),
            [.statementResetAndBinding, .rowDecoding]
        )

        // Every SQL case measures SwiftQL's own production path phase by phase:
        // render, bind, execute, materialize (reads), decode (reads), and the
        // public end-to-end call.
        let readCases = [
            "simple_parameterized_lookup",
            "simple_lookup_inline_literals",
            "representative_multi_join_read",
            "representative_multi_join_read_inline_literals",
            "deterministic_row_decode",
            "deterministic_row_decode_inline_literals",
        ]
        for identifier in readCases {
            let benchmarkCase = try XCTUnwrap(report.cases.first { $0.identifier == identifier })
            XCTAssertEqual(
                benchmarkCase.phases.filter { $0.applicability == .measured }.map(\.phase),
                [
                    .swiftQLConstructionAndRendering,
                    .coldStatementPreparation,
                    .cachedStatementLookup,
                    .statementResetAndBinding,
                    .execution,
                    .rowDecoding,
                    .swiftQLBinding,
                    .swiftQLExecution,
                    .swiftQLRowMaterialization,
                    .swiftQLRowDecoding,
                    .swiftQLFetchAll,
                ],
                identifier
            )
        }
        for identifier in ["bounded_write", "bounded_write_inline_literals"] {
            let benchmarkCase = try XCTUnwrap(report.cases.first { $0.identifier == identifier })
            XCTAssertEqual(
                benchmarkCase.phases.filter { $0.applicability == .measured }.map(\.phase),
                [
                    .swiftQLConstructionAndRendering,
                    .coldStatementPreparation,
                    .cachedStatementLookup,
                    .statementResetAndBinding,
                    .execution,
                    .swiftQLBinding,
                    .swiftQLExecution,
                    .swiftQLExecute,
                ],
                identifier
            )
        }

        // Each plain-value variant sits next to its named-binding variant and
        // renders its values inline, so it has no parameter to bind.
        for (named, inline) in [
            ("simple_parameterized_lookup", "simple_lookup_inline_literals"),
            ("representative_multi_join_read", "representative_multi_join_read_inline_literals"),
            ("bounded_write", "bounded_write_inline_literals"),
            ("deterministic_row_decode", "deterministic_row_decode_inline_literals"),
        ] {
            let namedCase = try XCTUnwrap(report.cases.first { $0.identifier == named })
            let inlineCase = try XCTUnwrap(report.cases.first { $0.identifier == inline })
            XCTAssertTrue(namedCase.sql.contains(":"), named)
            XCTAssertFalse(namedCase.parameters.isEmpty, named)
            XCTAssertFalse(inlineCase.sql.contains(":"), inline)
            XCTAssertTrue(inlineCase.parameters.isEmpty, inline)
            XCTAssertEqual(inlineCase.expectedResultRowCount, namedCase.expectedResultRowCount)
            XCTAssertEqual(inlineCase.expectedAffectedRowCount, namedCase.expectedAffectedRowCount)
        }
        XCTAssertTrue(
            try XCTUnwrap(
                contextualCodec.phases.first { $0.phase == .statementResetAndBinding }?.measurement
            ).notes.contains { $0.contains("XLInvocationBindings construction") }
        )
        XCTAssertTrue(
            try XCTUnwrap(
                contextualCodec.phases.first { $0.phase == .statementResetAndBinding }?.measurement
            ).notes.contains { $0.contains("StatementArguments construction") }
        )
        XCTAssertEqual(
            contextualCodec.phases.first { $0.phase == .execution }?.applicability,
            .notApplicable
        )
        XCTAssertTrue(
            try XCTUnwrap(
                contextualCodec.phases.first { $0.phase == .execution }?.reason
            ).contains("decodes its scalar result")
        )
        XCTAssertTrue(
            try XCTUnwrap(
                contextualCodec.phases.first { $0.phase == .rowDecoding }?.measurement
            ).notes.contains { $0.contains("normalization to XLSQLiteValue") }
        )

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
        XCTAssertEqual(object["formatVersion"] as? Int, 2)
        XCTAssertEqual(object["sampleUnit"] as? String, "nanoseconds_per_operation")
        let environment = try XCTUnwrap(object["environment"] as? [String: Any])
        XCTAssertEqual(environment["buildConfiguration"] as? String, "debug")
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

    func testCheckedInBaselinesDecodeAndValidate() throws {
        let baselineDirectory = sourceRepositoryRoot()
            .appendingPathComponent("Benchmarks/Baselines", isDirectory: true)
        var reports: [BenchmarkReport] = []

        for run in 1 ... 3 {
            let url = baselineDirectory.appendingPathComponent(
                "2026-07-17-mac16-8-run-\(run).json"
            )
            let data = try Data(contentsOf: url)
            let report = try JSONDecoder().decode(BenchmarkReport.self, from: data)
            try report.validate()
            reports.append(report)
        }

        XCTAssertEqual(Set(reports.map(\.environment.repositoryRevision)).count, 1)
        XCTAssertEqual(Set(reports.map(\.environment.repositoryState)), ["clean"])
        XCTAssertEqual(Set(reports.map(\.environment.buildConfiguration)), ["release"])
        XCTAssertTrue(reports.allSatisfy { $0.configuration == .standard })
        XCTAssertTrue(reports.allSatisfy { $0.measurementCount == 23 })
        XCTAssertTrue(reports.allSatisfy { $0.formatVersion == 1 })
    }

    func testFormatVersion2RequiresTheSwiftQLProductionPhases() throws {
        let url = sourceRepositoryRoot()
            .appendingPathComponent("Benchmarks/Baselines/2026-07-17-mac16-8-run-1.json")
        let version1 = try JSONDecoder().decode(
            BenchmarkReport.self,
            from: Data(contentsOf: url)
        )
        XCTAssertNoThrow(try version1.validate())

        // The same six-phase cases labelled as version 2 are incomplete.
        let relabelled = BenchmarkReport(
            formatVersion: 2,
            generatedAt: version1.generatedAt,
            monotonicClock: version1.monotonicClock,
            sampleUnit: version1.sampleUnit,
            configuration: version1.configuration,
            environment: version1.environment,
            database: version1.database,
            fixture: version1.fixture,
            schemaSQL: version1.schemaSQL,
            cases: version1.cases
        )
        XCTAssertThrowsError(try relabelled.validate())
        XCTAssertNil(BenchmarkPhase.phases(forFormatVersion: 3))
        XCTAssertEqual(
            BenchmarkPhase.phases(forFormatVersion: 1)?.map(\.rawValue),
            [
                "swiftql_construction_and_rendering",
                "cold_statement_preparation",
                "cached_statement_lookup",
                "statement_reset_and_binding",
                "execution",
                "row_decoding",
            ]
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private func sourceRepositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
