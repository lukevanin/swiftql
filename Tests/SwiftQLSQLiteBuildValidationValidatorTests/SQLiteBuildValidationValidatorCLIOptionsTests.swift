//
//  SQLiteBuildValidationValidatorCLIOptionsTests.swift
//
//  Argument parsing and output-safety preflight for the validator CLI.
//
//  The preflight coverage here was ported from the research prototype's
//  `SQLiteBuildValidationCLIOptionsTests` when `Research/SQLiteBuildValidation`
//  was retired (issue #565). The shipped validator implements the same
//  identity-based safety check the prototype did -- resolving symlinks,
//  comparing device/inode of existing files, and protecting SQLite's
//  `-journal`/`-shm`/`-wal` sidecars -- but only the aliasing-by-same-path case
//  was covered on this side. Overwriting the database being validated, or one
//  of its sidecars, corrupts the input the build is checking against.
//

import Foundation
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationValidatorCLIOptionsTests: XCTestCase {

    // MARK: - Parsing

    /// Repeatable options are canonicalized -- deduplicated and sorted -- so a
    /// report is a function of which codecs, extensions, and capabilities were
    /// declared, not of the order they appeared on the command line. Relative
    /// paths resolve against the working directory; absolute ones are taken as
    /// they are.
    func testParsesRequiredPathsAndCanonicalizesRepeatableValues() throws {
        let currentDirectory = URL(
            fileURLWithPath: "/tmp/swiftql-build-validation-options",
            isDirectory: true
        )
        let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
            arguments: [
                "--database", "fixtures/northwind.db",
                "--manifest", "input/manifest.json",
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
            options.manifestURL,
            currentDirectory
                .appendingPathComponent("input/manifest.json")
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

    func testRejectsMissingDuplicateRequiredAndUnknownOptions() throws {
        assertParseError(
            arguments: ["--database"],
            expected: .missingValue("--database")
        )
        assertParseError(
            arguments: [
                "--database", "first.db",
                "--database", "second.db",
                "--manifest", "manifest.json",
                "--output", "report.json",
            ],
            expected: .duplicateOption("--database")
        )
        assertParseError(
            arguments: [],
            expected: .requiredOption("--database")
        )
        assertParseError(
            arguments: ["--unknown"],
            expected: .unknownOption("--unknown")
        )
    }

    // MARK: - Output-safety preflight

    /// Path spelling alone does not make an output distinct from an input: two
    /// different spellings that standardize to one path are the same file.
    func testPreflightRejectsStandardizedDatabaseAndManifestEquality() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [([String], SQLiteBuildValidationValidatorCLIError)] = [
            (
                [
                    "--database", "inputs/../database.sqlite",
                    "--manifest", "manifest.json",
                    "--output", "./database.sqlite",
                ],
                .outputConflictsWithInput("--database")
            ),
            (
                [
                    "--database", "database.sqlite",
                    "--manifest", "inputs/../manifest.json",
                    "--output", "./manifest.json",
                ],
                .outputConflictsWithInput("--manifest")
            ),
        ]

        for (arguments, expected) in cases {
            let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
                arguments: arguments,
                currentDirectory: directory
            )
            assertPreflightError(options: options, expected: expected)
        }
    }

    /// A symlink to an input, and a path reached through a symlinked parent
    /// directory, are both the input. Comparing spelled paths would miss both.
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
        let manifestURL = realDirectory.appendingPathComponent("manifest.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("manifest".utf8).write(to: manifestURL)

        let databaseAliasURL = directory.appendingPathComponent("database-alias")
        try fileManager.createSymbolicLink(
            at: databaseAliasURL,
            withDestinationURL: databaseURL
        )
        assertPreflightError(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: databaseAliasURL,
            expected: .outputConflictsWithInput("--database")
        )

        let parentAliasURL = directory.appendingPathComponent("parent-alias")
        try fileManager.createSymbolicLink(
            at: parentAliasURL,
            withDestinationURL: realDirectory
        )
        assertPreflightError(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: parentAliasURL.appendingPathComponent("database.sqlite"),
            expected: .outputConflictsWithInput("--database")
        )
    }

    /// A hard link shares no path with its input and resolves no symlinks, so
    /// only device and inode identify it. Writing the report through one would
    /// overwrite the database in place.
    func testPreflightRejectsExistingHardLinkIdentity() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("database.sqlite")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let outputURL = directory.appendingPathComponent("report.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("manifest".utf8).write(to: manifestURL)
        try fileManager.linkItem(at: databaseURL, to: outputURL)

        assertPreflightError(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL,
            expected: .outputConflictsWithInput("--database")
        )
    }

    /// SQLite's rollback journal, shared-memory, and write-ahead log files are
    /// derived from the database's own path. They are not the database, so the
    /// identity checks above never see them -- they are protected by name, for
    /// the spelled path and for the symlink-resolved one alike.
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
        let manifestURL = realDirectory.appendingPathComponent("manifest.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("manifest".utf8).write(to: manifestURL)

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
                assertPreflightError(
                    databaseURL: inputURL,
                    manifestURL: manifestURL,
                    outputURL: outputURL,
                    expected: .outputConflictsWithDatabaseSidecar,
                    message: "Expected \(outputURL.path) to be protected for \(inputURL.path)"
                )
            }
        }
    }

    /// The counterpart to every rejection above: writing a new report into the
    /// same directory as the inputs is the ordinary case and stays allowed.
    func testPreflightAllowsNewOutputBesideInputs() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("database.sqlite")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let outputURL = directory.appendingPathComponent("report.json")
        try Data("database".utf8).write(to: databaseURL)
        try Data("manifest".utf8).write(to: manifestURL)

        XCTAssertNoThrow(
            try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                manifestURL: manifestURL,
                outputURL: outputURL
            )
        )
    }

    // MARK: - Helpers

    private func assertParseError(
        arguments: [String],
        expected: SQLiteBuildValidationValidatorCLIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SQLiteBuildValidationValidatorCLIOptions.parse(arguments: arguments),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationValidatorCLIError,
                expected,
                file: file,
                line: line
            )
            XCTAssertFalse(expected.description.isEmpty, file: file, line: line)
        }
    }

    private func assertPreflightError(
        options: SQLiteBuildValidationValidatorCLIOptions,
        expected: SQLiteBuildValidationValidatorCLIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            let databaseURL = options.databaseURL,
            let manifestURL = options.manifestURL,
            let outputURL = options.outputURL
        else {
            return XCTFail("Expected operational URLs", file: file, line: line)
        }
        assertPreflightError(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL,
            expected: expected,
            file: file,
            line: line
        )
    }

    private func assertPreflightError(
        databaseURL: URL,
        manifestURL: URL,
        outputURL: URL,
        expected: SQLiteBuildValidationValidatorCLIError,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
                databaseURL: databaseURL,
                manifestURL: manifestURL,
                outputURL: outputURL
            ),
            message,
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationValidatorCLIError,
                expected,
                message,
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
