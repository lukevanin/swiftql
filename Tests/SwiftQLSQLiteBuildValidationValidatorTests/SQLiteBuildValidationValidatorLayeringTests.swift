//
//  SQLiteBuildValidationValidatorLayeringTests.swift
//
//  The seams issue #566 introduced: capability classification in one place,
//  diagnostic codes as a type rather than as literals at both ends, settled
//  CLI options, and the report's own human-readable rendering.
//

import Foundation
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class CapabilityKindTests: XCTestCase {

    func testPrefixedCapabilitiesAreClassifiedWithTheirName() {
        let cases: [(String, CapabilityKind, String?)] = [
            ("function:JSON_VALID", .function, "JSON_VALID"),
            ("collation:NOCASE", .collation, "NOCASE"),
            ("compile-option:ENABLE_FTS5", .compileOption, "ENABLE_FTS5"),
            ("module:fts5", .module, "fts5"),
            ("extension:spellfix", .loadedExtension, "spellfix"),
        ]
        for (id, expectedKind, expectedName) in cases {
            let (kind, name) = CapabilityKind.classify(id)
            XCTAssertEqual(kind, expectedKind, id)
            XCTAssertEqual(name, expectedName, id)
        }
    }

    /// Case folding has to be uniform. Classifying `Function:JSON_VALID`
    /// differently from `function:JSON_VALID` is how a recognized capability
    /// silently becomes unavailable -- the name after the prefix is preserved
    /// as written, because SQLite's own matching folds it later.
    func testClassificationFoldsTheSigilButPreservesTheName() {
        let (kind, name) = CapabilityKind.classify("Function:JSON_Valid")

        XCTAssertEqual(kind, .function)
        XCTAssertEqual(name, "JSON_Valid")
    }

    /// A bare prefix keeps its kind -- and so its diagnostic code -- but names
    /// nothing, so nothing can resolve it.
    func testABarePrefixKeepsItsKindWithNoName() {
        let (kind, name) = CapabilityKind.classify("function:")

        XCTAssertEqual(kind, .function)
        XCTAssertNil(name)
        XCTAssertEqual(kind.diagnosticCode, .capabilityFunction)
        XCTAssertTrue(kind.isObservable)
    }

    func testJSONFunctionsAndIntrinsicsAreClassifiedWithoutAPrefix() {
        XCTAssertEqual(CapabilityKind.classify("sqlite-json-functions").kind, .sqliteJSONFunctions)
        XCTAssertEqual(CapabilityKind.classify("SQLite-JSON-Functions").kind, .sqliteJSONFunctions)
        XCTAssertEqual(CapabilityKind.classify("transactions").kind, .intrinsic)
        XCTAssertEqual(CapabilityKind.classify("recursive-cte").kind, .intrinsic)
    }

    func testAnUnrecognizedIdentifierIsOpaque() {
        let (kind, name) = CapabilityKind.classify("acme:whatever")

        XCTAssertEqual(kind, .opaque)
        XCTAssertNil(name)
        XCTAssertEqual(kind.diagnosticCode, .capabilityMissing)
    }

    /// The distinction the explicit-declaration seam turns on: an observable
    /// capability can never be declared into existence, an unobservable one
    /// can. Intrinsics are unobservable -- they name SwiftQL's own guarantees,
    /// not features a connection reports.
    func testOnlyConnectionVisibleKindsAreObservable() {
        for kind in CapabilityKind.allCases {
            switch kind {
            case .intrinsic, .opaque:
                XCTAssertFalse(kind.isObservable, "\(kind)")
            default:
                XCTAssertTrue(kind.isObservable, "\(kind)")
            }
        }
    }
}


final class SQLiteBuildValidationDiagnosticCodeTests: XCTestCase {

    /// The set that decides whether preparation is skipped is derived from
    /// `CapabilityKind`, so a new capability kind joins it by existing. Listing
    /// it by hand is how the research prototype shipped for months without
    /// `capability.compile-option` in it.
    func testPreparationBlockingCoversEveryObservableCapabilityKind() {
        for kind in CapabilityKind.allCases where kind.isObservable {
            XCTAssertTrue(
                SQLiteBuildValidationDiagnosticCode
                    .preparationBlocking.contains(kind.diagnosticCode),
                "\(kind)"
            )
        }
        XCTAssertEqual(
            SQLiteBuildValidationDiagnosticCode.preparationBlocking,
            [
                .capabilityCollation,
                .capabilityCompileOption,
                .capabilityDialect,
                .capabilityDialectFlags,
                .capabilityExtension,
                .capabilityFunction,
                .capabilityModule,
                .capabilitySQLiteJSONFunctions,
                .capabilitySQLiteVersion,
            ]
        )
    }

    /// A capability the validator cannot see is not a reason to skip
    /// preparation: the caller may legitimately own it, and preparing the query
    /// is the only way to find out whether it matters.
    func testAnUnobservableCapabilityDoesNotBlockPreparation() {
        XCTAssertFalse(
            SQLiteBuildValidationDiagnosticCode
                .preparationBlocking.contains(.capabilityMissing)
        )
    }

    func testSchemaIdentityMismatchCoversTheFourIdentityChecks() {
        XCTAssertEqual(
            SQLiteBuildValidationDiagnosticCode.schemaIdentityMismatch,
            [.schemaByteCount, .schemaSnapshotSHA, .schemaRowCount, .schemaFingerprint]
        )
    }

    /// The raw values are the report's on-disk codes and a byte-determinism
    /// gate, so they cannot drift.
    func testRawValuesAreTheOnDiskCodes() {
        XCTAssertEqual(SQLiteBuildValidationDiagnosticCode.schemaByteCount.rawValue, "schema.byte-count")
        XCTAssertEqual(SQLiteBuildValidationDiagnosticCode.capabilityCompileOption.rawValue, "capability.compile-option")
        XCTAssertEqual(SQLiteBuildValidationDiagnosticCode.sqliteFinalizeFailed.rawValue, "sqlite.finalize.failed")
    }

    func testCodesAreUnique() {
        let raw = SQLiteBuildValidationDiagnosticCode.allCases.map(\.rawValue)

        XCTAssertEqual(Set(raw).count, raw.count)
    }

    /// A typed diagnostic encodes exactly the code it names, and reads back as
    /// that code.
    func testATypedDiagnosticRoundTripsThroughItsStringCode() {
        let diagnostic = SQLiteBuildValidationDiagnostic(
            verdict: .failed,
            stage: .result,
            code: .resultName,
            message: "tests"
        )

        XCTAssertEqual(diagnostic.code, "result.name")
        XCTAssertEqual(diagnostic.diagnosticCode, .resultName)
    }

    /// A report written by a newer validator can carry a code this build does
    /// not know. It survives decoding; it just is not one of ours.
    func testAnUnknownCodeDecodesWithoutATypedCounterpart() {
        let diagnostic = SQLiteBuildValidationDiagnostic(
            verdict: .failed,
            stage: .result,
            code: "result.from-the-future",
            message: "tests"
        )

        XCTAssertEqual(diagnostic.code, "result.from-the-future")
        XCTAssertNil(diagnostic.diagnosticCode)
    }
}


final class SQLiteBuildValidationValidatorCLIResolutionTests: XCTestCase {

    func testHelpResolvesToHelpWithoutRequiringPaths() throws {
        let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
            arguments: ["--help"]
        )

        XCTAssertEqual(try options.resolved(), .help)
    }

    func testAFullInvocationResolvesToARunCarryingItsEnvironment() throws {
        let directory = URL(fileURLWithPath: "/tmp/swiftql-resolve", isDirectory: true)
        let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
            arguments: [
                "--database", "snapshot.sqlite",
                "--manifest", "manifest.json",
                "--output", "report.json",
                "--codec", "z-codec",
                "--codec", "a-codec",
                "--capability", "function:JSON_VALID",
            ],
            currentDirectory: directory
        )

        guard case .run(let resolved) = try options.resolved() else {
            return XCTFail("Expected a run invocation")
        }
        XCTAssertEqual(
            resolved.databaseURL,
            directory.appendingPathComponent("snapshot.sqlite").standardizedFileURL
        )
        XCTAssertEqual(
            resolved.outputURL,
            directory.appendingPathComponent("report.json").standardizedFileURL
        )
        XCTAssertEqual(resolved.environment.codecIdentifiers, ["a-codec", "z-codec"])
        XCTAssertEqual(resolved.environment.capabilityIDs, ["function:JSON_VALID"])
    }

    /// Parsing already refuses a run missing a required path, so this is only
    /// reachable for options a caller assembled by hand -- which is the point
    /// of the check living here rather than in the runner, where it could never
    /// fire.
    func testHandBuiltOptionsMissingAPathAreRefusedOnResolution() {
        let options = SQLiteBuildValidationValidatorCLIOptions(
            databaseURL: URL(fileURLWithPath: "/tmp/a.sqlite"),
            manifestURL: nil,
            outputURL: URL(fileURLWithPath: "/tmp/report.json"),
            codecIdentifiers: [],
            extensionNames: [],
            capabilityIDs: [],
            showsHelp: false
        )

        XCTAssertThrowsError(try options.resolved()) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationValidatorCLIError,
                .requiredOption("--manifest")
            )
        }
    }
}


final class SQLiteBuildValidationReportSummaryTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    /// A passing build prints nothing.
    func testAPassingReportSummarisesToNothing() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: Support.manifest(queries: [
                    Support.query(id: "trivial", sql: "SELECT 1 AS value"),
                ]),
                againstDatabaseAt: url
            )

            XCTAssertEqual(report.overallVerdict, .passed)
            XCTAssertEqual(report.humanReadableSummary(), "")
        }
    }

    /// A failing build prints the verdict and every diagnostic behind it,
    /// per-query ones labelled with the query they belong to.
    func testAFailingReportSummarisesItsVerdictAndEveryDiagnostic() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: Support.manifest(queries: [
                    Support.query(
                        id: "missing-table",
                        sql: "SELECT * FROM tests_totally_missing_table"
                    ),
                ]),
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .failed)

            let summary = report.humanReadableSummary()
            let lines = summary.split(separator: "\n").map(String.init)

            XCTAssertEqual(
                lines.first,
                "swiftql-build-validate: overall verdict failed"
            )
            XCTAssertTrue(
                lines.dropFirst().allSatisfy { $0.hasPrefix("  ") },
                summary
            )
            XCTAssertTrue(
                summary.contains("missing-table: [failed] prepare.sqlite.prepare.failed:"),
                summary
            )
            XCTAssertTrue(summary.contains("tests_totally_missing_table"), summary)
        }
    }
}
