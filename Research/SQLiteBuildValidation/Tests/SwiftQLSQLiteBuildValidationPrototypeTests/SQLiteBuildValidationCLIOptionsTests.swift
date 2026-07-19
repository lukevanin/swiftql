import Foundation
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLiteBuildValidationCLIOptionsTests: XCTestCase {
    func testParsesRequiredPathsAndCanonicalizesRepeatableValues() throws {
        let currentDirectory = URL(
            fileURLWithPath: "/tmp/swiftql-build-validation-options",
            isDirectory: true
        )
        let options = try SQLiteBuildValidationCLIOptions.parse(
            arguments: [
                "--database", "fixtures/northwind.db",
                "--plan", "input/plan.json",
                "--output", "/tmp/report.json",
                "--codec", "z-codec",
                "--codec", "a-codec",
                "--codec", "z-codec",
                "--extension", "json1",
                "--extension", "json1",
                "--capability", "custom:z",
                "--capability", "custom:a",
            ],
            currentDirectory: currentDirectory
        )

        XCTAssertEqual(
            options.databaseURL,
            currentDirectory
                .appendingPathComponent("fixtures/northwind.db")
                .standardizedFileURL
        )
        XCTAssertEqual(
            options.planURL,
            currentDirectory
                .appendingPathComponent("input/plan.json")
                .standardizedFileURL
        )
        XCTAssertEqual(
            options.outputURL,
            URL(fileURLWithPath: "/tmp/report.json").standardizedFileURL
        )
        XCTAssertEqual(options.codecIdentifiers, ["a-codec", "z-codec"])
        XCTAssertEqual(options.extensionNames, ["json1"])
        XCTAssertEqual(options.capabilityIDs, ["custom:a", "custom:z"])
        XCTAssertFalse(options.showsHelp)
    }

    func testHelpDoesNotRequireOperationalArguments() throws {
        for argument in ["--help", "-h"] {
            let options = try SQLiteBuildValidationCLIOptions.parse(
                arguments: [argument]
            )
            XCTAssertTrue(options.showsHelp)
            XCTAssertNil(options.databaseURL)
            XCTAssertNil(options.planURL)
            XCTAssertNil(options.outputURL)
        }
        XCTAssertTrue(SQLiteBuildValidationCLIOptions.usage.contains("--database"))
        XCTAssertTrue(SQLiteBuildValidationCLIOptions.usage.contains("--codec"))
    }

    func testRejectsMissingDuplicateRequiredAndUnknownOptions() throws {
        assertCLIError(
            arguments: ["--database"],
            expected: .missingValue("--database")
        )
        assertCLIError(
            arguments: [
                "--database", "first.db",
                "--database", "second.db",
                "--plan", "plan.json",
                "--output", "report.json",
            ],
            expected: .duplicateOption("--database")
        )
        assertCLIError(
            arguments: [],
            expected: .requiredOption("--database")
        )
        assertCLIError(
            arguments: ["--unknown"],
            expected: .unknownOption("--unknown")
        )
    }

    func testPreflightRejectsStandardizedDatabaseAndPlanEquality() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [([String], SQLiteBuildValidationCLIError)] = [
            (
                [
                    "--database", "inputs/../database.sqlite",
                    "--plan", "plan.json",
                    "--output", "./database.sqlite",
                ],
                .outputConflictsWithInput("--database")
            ),
            (
                [
                    "--database", "database.sqlite",
                    "--plan", "inputs/../plan.json",
                    "--output", "./plan.json",
                ],
                .outputConflictsWithInput("--plan")
            ),
        ]

        for (arguments, expected) in cases {
            let options = try SQLiteBuildValidationCLIOptions.parse(
                arguments: arguments,
                currentDirectory: directory
            )
            assertOutputPreflightError(options: options, expected: expected)
        }
    }

    func testPreflightRejectsSymlinkAliasesAndSymlinkedParents() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let realDirectory = directory.appendingPathComponent(
            "real",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        let databaseURL = realDirectory.appendingPathComponent("database.sqlite")
        let planURL = realDirectory.appendingPathComponent("plan.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("plan".utf8).write(to: planURL)

        let databaseAliasURL = directory.appendingPathComponent("database-alias")
        try fileManager.createSymbolicLink(
            at: databaseAliasURL,
            withDestinationURL: databaseURL
        )
        XCTAssertThrowsError(
            try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: databaseAliasURL
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationCLIError,
                .outputConflictsWithInput("--database")
            )
        }

        let parentAliasURL = directory.appendingPathComponent("parent-alias")
        try fileManager.createSymbolicLink(
            at: parentAliasURL,
            withDestinationURL: realDirectory
        )
        XCTAssertThrowsError(
            try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: parentAliasURL.appendingPathComponent("database.sqlite")
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationCLIError,
                .outputConflictsWithInput("--database")
            )
        }
    }

    func testPreflightRejectsExistingHardLinkIdentity() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("database.sqlite")
        let planURL = directory.appendingPathComponent("plan.json")
        let outputURL = directory.appendingPathComponent("report.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("plan".utf8).write(to: planURL)
        try fileManager.linkItem(at: databaseURL, to: outputURL)

        XCTAssertThrowsError(
            try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationCLIError,
                .outputConflictsWithInput("--database")
            )
        }
    }

    func testPreflightRejectsDatabaseSidecarOutputPaths() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let realDirectory = directory.appendingPathComponent(
            "real",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        let databaseURL = realDirectory.appendingPathComponent("database.sqlite")
        let planURL = realDirectory.appendingPathComponent("plan.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("plan".utf8).write(to: planURL)

        let parentAliasURL = directory.appendingPathComponent("parent-alias")
        try fileManager.createSymbolicLink(
            at: parentAliasURL,
            withDestinationURL: realDirectory
        )
        let databaseAliasURL = directory.appendingPathComponent("database-alias")
        try fileManager.createSymbolicLink(
            at: databaseAliasURL,
            withDestinationURL: databaseURL
        )
        for suffix in ["-journal", "-shm", "-wal"] {
            let cases = [
                (
                    databaseURL,
                    parentAliasURL.appendingPathComponent(
                        "database.sqlite\(suffix)"
                    )
                ),
                (
                    databaseAliasURL,
                    URL(fileURLWithPath: databaseAliasURL.path + suffix)
                ),
            ]
            for (inputURL, outputURL) in cases {
                XCTAssertThrowsError(
                    try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                        databaseURL: inputURL,
                        planURL: planURL,
                        outputURL: outputURL
                    ),
                    "Expected \(outputURL.path) to be protected for \(inputURL.path)"
                ) { error in
                    XCTAssertEqual(
                        error as? SQLiteBuildValidationCLIError,
                        .outputConflictsWithDatabaseSidecar
                    )
                }
            }
        }
    }

    func testPreflightAllowsNewOutputBesideInputs() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("database.sqlite")
        let planURL = directory.appendingPathComponent("plan.json")
        let outputURL = directory.appendingPathComponent("report.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("plan".utf8).write(to: planURL)

        XCTAssertNoThrow(
            try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: outputURL
            )
        )
    }

    private func assertCLIError(
        arguments: [String],
        expected: SQLiteBuildValidationCLIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SQLiteBuildValidationCLIOptions.parse(arguments: arguments),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationCLIError,
                expected,
                file: file,
                line: line
            )
            XCTAssertFalse(expected.description.isEmpty, file: file, line: line)
        }
    }

    private func assertOutputPreflightError(
        options: SQLiteBuildValidationCLIOptions,
        expected: SQLiteBuildValidationCLIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let databaseURL = options.databaseURL,
              let planURL = options.planURL,
              let outputURL = options.outputURL else {
            return XCTFail("Expected operational URLs", file: file, line: line)
        }

        XCTAssertThrowsError(
            try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                planURL: planURL,
                outputURL: outputURL
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationCLIError,
                expected,
                file: file,
                line: line
            )
            XCTAssertFalse(expected.description.isEmpty, file: file, line: line)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
