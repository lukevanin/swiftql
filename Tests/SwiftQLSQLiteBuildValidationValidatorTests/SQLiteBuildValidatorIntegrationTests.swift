import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidatorIntegrationTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    // MARK: - Passing path against the real pinned Northwind snapshot

    func testValidQueriesPassAgainstPinnedNorthwindSnapshot() throws {
        let trivial = Support.query(id: "trivial", sql: "SELECT 1 AS value")
        let namedBinding = Support.query(
            id: "customer-company-name",
            sql: "SELECT CompanyName AS company_name FROM Customers WHERE CustomerID = :customer_id",
            parameters: [
                Support.parameter(
                    logicalIndex: 0,
                    physicalIndex: 1,
                    identity: "parameter/customer_id",
                    keyName: "customer_id",
                    valueTypeIdentifier: "swift.string",
                    valueTypeName: "Swift.String",
                    storageIdentifier: "text"
                ),
            ],
            results: [
                Support.result(
                    identity: "result/company_name",
                    declaredAlias: "company_name",
                    valueTypeIdentifier: "swift.string",
                    valueTypeName: "Swift.String",
                    storageIdentifier: "text"
                ),
            ]
        )
        let manifest = Support.manifest(queries: [trivial, namedBinding])

        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .passed)
            XCTAssertTrue(report.diagnostics.isEmpty)
            XCTAssertEqual(report.outcomes.count, 2)
            for outcome in report.outcomes {
                XCTAssertEqual(outcome.verdict, .passed, outcome.queryID)
                XCTAssertTrue(outcome.diagnostics.isEmpty, outcome.queryID)
                XCTAssertNotNil(outcome.preparedShape, outcome.queryID)
            }
        }
    }

    // MARK: - Fail-closed: statement/schema-resolution failures

    func testMissingTableFailsClosed() throws {
        let manifest = Support.manifest(queries: [
            Support.query(sql: "SELECT * FROM tests_totally_missing_table"),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .failed)
            let outcome = try XCTUnwrap(report.outcomes.first)
            let diagnostic = try XCTUnwrap(
                outcome.diagnostics.first { $0.code == "sqlite.prepare.failed" }
            )
            XCTAssertEqual(diagnostic.verdict, .failed)
            XCTAssertNotEqual(diagnostic.sqliteResultCode, 0)
            XCTAssertFalse(diagnostic.message.isEmpty)
        }
    }

    func testEmptyStatementFailsClosed() throws {
        // Nonempty but non-preparable: passes #292's structural "sql must not
        // be empty" check, but SQLite prepares no statement from it.
        let manifest = Support.manifest(queries: [
            Support.query(sql: "-- just a comment, nothing to prepare"),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .failed)
            let outcome = try XCTUnwrap(report.outcomes.first)
            XCTAssertTrue(outcome.diagnostics.contains { $0.code == "statement.empty" })
        }
    }

    func testResultCountAndAliasMismatchesFailClosed() throws {
        let extraResult = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                results: [Support.result(), Support.result(index: 1, identity: "result/extra")]
            ),
        ])
        let wrongAlias = Support.manifest(queries: [
            Support.query(sql: "SELECT 1 AS value", results: [
                Support.result(declaredAlias: "not_value"),
            ]),
        ])

        try Support.withValidatorOwnedNorthwindURL { url in
            let extraReport = try SQLiteBuildValidator.validate(
                manifest: extraResult,
                againstDatabaseAt: url
            )
            XCTAssertEqual(extraReport.overallVerdict, .failed)
            XCTAssertTrue(
                try XCTUnwrap(extraReport.outcomes.first).diagnostics
                    .contains { $0.code == "result.count" }
            )
        }

        try Support.withValidatorOwnedNorthwindURL { url in
            let aliasReport = try SQLiteBuildValidator.validate(
                manifest: wrongAlias,
                againstDatabaseAt: url
            )
            XCTAssertEqual(aliasReport.overallVerdict, .failed)
            XCTAssertTrue(
                try XCTUnwrap(aliasReport.outcomes.first).diagnostics
                    .contains { $0.code == "result.name" }
            )
        }
    }

    // MARK: - Fail-closed: capabilities and codecs never silently pass

    func testMissingFunctionCapabilityIsUnsupportedAndCannotBeSpoofed() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                requiredCapabilities: ["function:definitely_missing_function"]
            ),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            // Even explicitly claiming the capability via environment does not
            // satisfy an *observable* capability the connection doesn't have —
            // only genuinely opaque (non-observable) capability IDs can be
            // supplied that way.
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url,
                environment: SQLiteBuildValidationEnvironment(
                    capabilityIDs: ["function:definitely_missing_function"]
                )
            )
            XCTAssertEqual(report.overallVerdict, .unsupported)
            let outcome = try XCTUnwrap(report.outcomes.first)
            XCTAssertTrue(outcome.diagnostics.contains {
                $0.code == "capability.function" && $0.verdict == .unsupported
            })
            // Preparation is skipped entirely when a capability prerequisite
            // is unavailable — never a confusing prepare failure instead.
            XCTAssertNil(outcome.preparedShape)
        }
    }

    /// `capability.compile-option` must gate preparation exactly like every
    /// other capability code — a query missing a required compile option
    /// must never reach `sqlite3_prepare_v3` at all.
    func testMissingCompileOptionCapabilitySkipsPreparation() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                requiredCapabilities: ["compile-option:DEFINITELY_MISSING_OPTION"]
            ),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .unsupported)
            let outcome = try XCTUnwrap(report.outcomes.first)
            XCTAssertTrue(outcome.diagnostics.contains {
                $0.code == "capability.compile-option" && $0.verdict == .unsupported
            })
            XCTAssertNil(outcome.preparedShape)
        }
    }

    /// Capability-ID prefix classification folds case before comparing
    /// (`isOpaqueCapability`/`capabilityDiagnosticCode`), so resolution
    /// against captured runtime evidence must too — a mixed-case id like
    /// "Function:ABS" must still resolve against the real `ABS` builtin
    /// instead of silently falling through to "unavailable".
    func testCapabilityMatchingIsCaseInsensitive() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                requiredCapabilities: ["Function:ABS"]
            ),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .passed)
            XCTAssertTrue(try XCTUnwrap(report.outcomes.first).diagnostics.isEmpty)
        }
    }

    /// The fixed-literal capability switch (named-bindings, transactions,
    /// sqlite-json-functions, ...) must fold case exactly like the prefixed
    /// (function:/collation:/...) capabilities do.
    func testFixedLiteralCapabilityMatchingIsCaseInsensitive() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                requiredCapabilities: ["Transactions", "SQLite-JSON-Functions"]
            ),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(report.overallVerdict, .passed)
            XCTAssertTrue(try XCTUnwrap(report.outcomes.first).diagnostics.isEmpty)
        }
    }

    /// `hasExtension`/`hasModule`/`hasCompileOption` must ASCII-fold like
    /// `hasFunction`/`hasCollation` already do — a caller-supplied extension
    /// name in different case than the required capability id must still
    /// resolve.
    func testExtensionCapabilityMatchingIsCaseInsensitive() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                requiredCapabilities: ["Extension:MyExt"]
            ),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url,
                environment: SQLiteBuildValidationEnvironment(
                    extensionNames: ["myext"]
                )
            )
            XCTAssertEqual(report.overallVerdict, .passed)
            XCTAssertTrue(try XCTUnwrap(report.outcomes.first).diagnostics.isEmpty)
        }
    }

    /// `SQLiteBuildValidationEnvironment` claims semantically equivalent
    /// invocations produce byte-identical canonical reports. Since extension
    /// matching is ASCII case-insensitive, "MyExt" and "myext" are the same
    /// requirement and must fold to one canonical entry, not two.
    func testEnvironmentNormalizesExtensionNameCaseForDeterminism() {
        let mixedCase = SQLiteBuildValidationEnvironment(extensionNames: ["MyExt", "myext"])
        let lowercaseOnly = SQLiteBuildValidationEnvironment(extensionNames: ["myext"])
        XCTAssertEqual(mixedCase.extensionNames, ["myext"])
        XCTAssertEqual(mixedCase, lowercaseOnly)
    }

    func testMissingCodecIsUnsupportedUntilSuppliedInEnvironment() throws {
        let codec = SQLiteBuildValidationCodecReference(
            keyID: "tests.codec.value",
            keyVersion: 1,
            valueTypeIdentifier: "swift.int",
            dialectIdentifier: XLSQLiteDialect.identity.rawValue,
            storageIdentifier: "integer"
        )
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT 1 AS value",
                results: [Support.result(codec: codec)]
            ),
        ])

        try Support.withValidatorOwnedNorthwindURL { url in
            let unsupportedReport = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            XCTAssertEqual(unsupportedReport.overallVerdict, .unsupported)
            XCTAssertTrue(
                try XCTUnwrap(unsupportedReport.outcomes.first).diagnostics
                    .contains { $0.code == "codec.missing" }
            )
        }

        try Support.withValidatorOwnedNorthwindURL { url in
            let passedReport = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url,
                environment: SQLiteBuildValidationEnvironment(
                    codecIdentities: [codec]
                )
            )
            XCTAssertEqual(passedReport.overallVerdict, .passed)
        }
    }

    // MARK: - Fail-closed: schema snapshot identity

    func testSnapshotMismatchesFailClosed() throws {
        let wrongSHA = Support.manifest(
            schemaSnapshot: Support.schemaSnapshot(
                databaseSHA256: String(repeating: "0", count: 64)
            )
        )
        let wrongByteCount = Support.manifest(
            schemaSnapshot: Support.schemaSnapshot(databaseByteCount: 1)
        )
        let wrongRowCount = Support.manifest(
            schemaSnapshot: Support.schemaSnapshot(schemaRowCount: 999)
        )
        let wrongFingerprint = Support.manifest(
            schemaSnapshot: Support.schemaSnapshot(
                schemaFingerprint: String(repeating: "a", count: 16)
            )
        )

        for (manifest, expectedCode) in [
            (wrongSHA, "schema.snapshot-sha"),
            (wrongByteCount, "schema.byte-count"),
            (wrongRowCount, "schema.row-count"),
            (wrongFingerprint, "schema.fingerprint"),
        ] {
            try Support.withValidatorOwnedNorthwindURL { url in
                let report = try SQLiteBuildValidator.validate(
                    manifest: manifest,
                    againstDatabaseAt: url
                )
                XCTAssertEqual(report.overallVerdict, .failed, expectedCode)
                XCTAssertTrue(
                    report.diagnostics.contains { $0.code == expectedCode },
                    expectedCode
                )
            }
        }
    }

    func testValidatorRejectsDatabaseWithAdjacentSidecar() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let journalPath = url.path + "-journal"
            FileManager.default.createFile(atPath: journalPath, contents: Data())
            defer { try? FileManager.default.removeItem(atPath: journalPath) }

            XCTAssertThrowsError(
                try SQLiteBuildValidator.validate(
                    manifest: Support.manifest(),
                    againstDatabaseAt: url
                )
            ) { error in
                guard case .databaseHasSidecar = error as? SQLiteBuildValidationValidatorError else {
                    return XCTFail("Expected databaseHasSidecar, received \(error)")
                }
            }
        }
    }

    // MARK: - Determinism

    func testRepeatedValidationsProduceByteIdenticalCanonicalReports() throws {
        let manifest = Support.manifest(queries: [
            Support.query(id: "trivial", sql: "SELECT 1 AS value"),
        ])
        try Support.withValidatorOwnedNorthwindURL { url in
            let first = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            let second = try SQLiteBuildValidator.validate(
                manifest: manifest,
                againstDatabaseAt: url
            )
            let firstData = try first.canonicalJSONData()
            let secondData = try second.canonicalJSONData()
            XCTAssertEqual(first, second)
            XCTAssertEqual(firstData, secondData)
            XCTAssertEqual(firstData.last, 0x0A)
            XCTAssertNotEqual(firstData.dropLast().last, 0x0A)
        }
    }

    // MARK: - Caller-owned-connection seam: missing evidence is unsupported, not passed

    func testCallerOwnedSeamTreatsMissingSnapshotEvidenceAsUnsupported() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            let report = try SQLiteBuildValidator.validate(
                manifest: Support.manifest(),
                in: database
            )
            XCTAssertEqual(report.overallVerdict, .unsupported)
            XCTAssertTrue(report.diagnostics.contains {
                $0.code == "schema.snapshot-sha" && $0.verdict == .unsupported
            })
            XCTAssertTrue(report.diagnostics.contains {
                $0.code == "schema.byte-count" && $0.verdict == .unsupported
            })
        }
    }
}
