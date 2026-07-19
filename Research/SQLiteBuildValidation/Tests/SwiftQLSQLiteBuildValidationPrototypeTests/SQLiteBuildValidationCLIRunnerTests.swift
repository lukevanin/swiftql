import Foundation
import SwiftQLCore
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLiteBuildValidationCLIRunnerTests: XCTestCase {
    private typealias Support = SQLiteBuildValidationTestSupport

    func testRunnerWritesByteIdenticalPassingReportsAndReturnsZero() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let directory = databaseURL.deletingLastPathComponent()
            let planURL = directory.appendingPathComponent("plan.json")
            let firstOutputURL = directory.appendingPathComponent("report-1.json")
            let secondOutputURL = directory.appendingPathComponent("report-2.json")
            let plan = Support.plan(queries: [Support.query(
                id: "cli.northwind.customer-count",
                inventoryFeatureIDs: ["syntax.select.core"],
                sql: "SELECT COUNT(*) AS value FROM Customers",
                cardinality: XLQueryCardinality.exactlyOne.rawValue
            )])
            try plan.canonicalJSONData().write(to: planURL)

            let first = try SQLiteBuildValidationCLIRunner.run(options: options(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: firstOutputURL
            ))
            let second = try SQLiteBuildValidationCLIRunner.run(options: options(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: secondOutputURL
            ))

            XCTAssertEqual(first.exitCode, 0)
            XCTAssertEqual(second.exitCode, 0)
            XCTAssertEqual(first.report.overallVerdict, .passed)
            XCTAssertEqual(second.report, first.report)
            XCTAssertEqual(
                try Data(contentsOf: firstOutputURL),
                try Data(contentsOf: secondOutputURL)
            )
            XCTAssertEqual(
                try Data(contentsOf: firstOutputURL),
                try first.report.canonicalJSONData()
            )
        }
    }

    func testRunnerWritesFailedReportAndReturnsOne() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let directory = databaseURL.deletingLastPathComponent()
            let planURL = directory.appendingPathComponent("invalid-plan.json")
            let outputURL = directory.appendingPathComponent("failed-report.json")
            let plan = Support.plan(queries: [Support.query(
                id: "cli.invalid.missing-table",
                inventoryFeatureIDs: ["syntax.select.core"],
                sql: "SELECT value FROM definitely_missing_table"
            )])
            try plan.canonicalJSONData().write(to: planURL)

            let result = try SQLiteBuildValidationCLIRunner.run(options: options(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: outputURL
            ))

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertEqual(result.report.overallVerdict, .failed)
            XCTAssertTrue(result.report.outcomes[0].diagnostics.contains {
                $0.code == "sqlite.prepare.failed" && $0.verdict == .failed
            })
            XCTAssertEqual(
                try Data(contentsOf: outputURL),
                try result.report.canonicalJSONData()
            )
        }
    }

    private func options(
        databaseURL: URL,
        planURL: URL,
        outputURL: URL
    ) throws -> SQLiteBuildValidationCLIOptions {
        try SQLiteBuildValidationCLIOptions.parse(arguments: [
            "--database", databaseURL.path,
            "--plan", planURL.path,
            "--output", outputURL.path,
        ])
    }
}
