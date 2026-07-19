import Foundation
import GRDB
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLiteBuildValidationCapabilityAuditTests: XCTestCase {
    private typealias Support = SQLiteBuildValidationTestSupport

    func testObservableFunctionCapabilityCannotBeSpoofedByGenericEvidence() throws {
        let capabilityID = "function:definitely_missing"
        let report = try validate(
            query: Support.query(
                id: "capability.function-spoof",
                requiredCapabilities: [capabilityID]
            ),
            environment: SQLiteBuildValidationEnvironment(
                capabilityIDs: [capabilityID]
            )
        )

        let outcome = try XCTUnwrap(report.outcomes.first)
        XCTAssertEqual(report.overallVerdict, .unsupported)
        XCTAssertEqual(outcome.verdict, .unsupported)
        XCTAssertNil(outcome.preparedShape)
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "capability.function" && $0.verdict == .unsupported
        })
    }

    func testOpaqueCustomCapabilityCanBeSuppliedExplicitly() throws {
        let capabilityID = "custom:opaque-audit-capability"
        let report = try validate(
            query: Support.query(
                id: "capability.opaque-explicit",
                requiredCapabilities: [capabilityID]
            ),
            environment: SQLiteBuildValidationEnvironment(
                capabilityIDs: [capabilityID]
            )
        )

        let outcome = try XCTUnwrap(report.outcomes.first)
        XCTAssertEqual(report.overallVerdict, .passed)
        XCTAssertEqual(outcome.verdict, .passed)
        XCTAssertNotNil(outcome.preparedShape)
        XCTAssertEqual(outcome.diagnostics, [])
    }

    func testCanonicalReportIncludesNormalizedExplicitEnvironmentEvidence() throws {
        let plan = Support.plan()
        let environment = SQLiteBuildValidationEnvironment(
            codecIdentifiers: ["codec:z", "codec:a", "codec:z"],
            extensionNames: ["extension:z", "extension:a", "extension:z"],
            capabilityIDs: ["custom:z", "custom:a", "custom:z"]
        )
        let reorderedEnvironment = SQLiteBuildValidationEnvironment(
            codecIdentifiers: ["codec:a", "codec:z"],
            extensionNames: ["extension:a", "extension:z"],
            capabilityIDs: ["custom:a", "custom:z"]
        )

        try Support.withReadOnlyNorthwindDatabase { database in
            let report = try validate(
                plan: plan,
                in: database,
                environment: environment
            )
            let canonicalData = try report.canonicalJSONData()
            let reorderedData = try validate(
                plan: plan,
                in: database,
                environment: reorderedEnvironment
            ).canonicalJSONData()

            XCTAssertEqual(
                report.environmentEvidence.codecIdentifiers,
                ["codec:a", "codec:z"]
            )
            XCTAssertEqual(
                report.environmentEvidence.extensionNames,
                ["extension:a", "extension:z"]
            )
            XCTAssertEqual(
                report.environmentEvidence.capabilityIDs,
                ["custom:a", "custom:z"]
            )
            XCTAssertEqual(canonicalData, reorderedData)

            let changedCodecData = try validate(
                plan: plan,
                in: database,
                environment: SQLiteBuildValidationEnvironment(
                    codecIdentifiers: ["codec:different"],
                    extensionNames: environment.extensionNames,
                    capabilityIDs: environment.capabilityIDs
                )
            ).canonicalJSONData()
            let changedExtensionData = try validate(
                plan: plan,
                in: database,
                environment: SQLiteBuildValidationEnvironment(
                    codecIdentifiers: environment.codecIdentifiers,
                    extensionNames: ["extension:different"],
                    capabilityIDs: environment.capabilityIDs
                )
            ).canonicalJSONData()
            let changedCapabilityData = try validate(
                plan: plan,
                in: database,
                environment: SQLiteBuildValidationEnvironment(
                    codecIdentifiers: environment.codecIdentifiers,
                    extensionNames: environment.extensionNames,
                    capabilityIDs: ["custom:different"]
                )
            ).canonicalJSONData()

            XCTAssertNotEqual(canonicalData, changedCodecData)
            XCTAssertNotEqual(canonicalData, changedExtensionData)
            XCTAssertNotEqual(canonicalData, changedCapabilityData)
        }
    }

    func testInvokedMissingFunctionRemainsUnsupportedWithoutPreparationFailure() throws {
        let report = try validate(query: Support.query(
            id: "capability.invoked-missing-function",
            sql: "SELECT definitely_missing() AS value",
            requiredCapabilities: ["function:definitely_missing"]
        ))

        let outcome = try XCTUnwrap(report.outcomes.first)
        XCTAssertEqual(report.overallVerdict, .unsupported)
        XCTAssertEqual(outcome.verdict, .unsupported)
        XCTAssertNil(outcome.preparedShape)
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "capability.function" && $0.verdict == .unsupported
        })
        XCTAssertFalse(outcome.diagnostics.contains {
            $0.code == "sqlite.prepare.failed" || $0.stage == .prepare
        })
    }

    func testMissingCodecDoesNotMaskIndependentMissingTableFailure() throws {
        let codec = Support.codec()
        let report = try validate(query: Support.query(
            id: "codec.missing-with-missing-table",
            sql: "SELECT value FROM definitely_missing_table",
            results: [Support.result(
                valueTypeIdentifier: codec.valueTypeIdentifier,
                valueTypeName: "Tests.Token",
                codec: codec,
                storageIdentifier: codec.storageIdentifier
            )]
        ))

        let outcome = try XCTUnwrap(report.outcomes.first)
        XCTAssertEqual(report.overallVerdict, .failed)
        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertNil(outcome.preparedShape)
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "codec.missing" && $0.verdict == .unsupported
        })
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "sqlite.prepare.failed" && $0.verdict == .failed
        })
    }

    func testMissingOpaqueCapabilityDoesNotMaskIndependentSyntaxFailure() throws {
        let report = try validate(query: Support.query(
            id: "capability.missing-opaque-with-invalid-sql",
            sql: "SELEC 1 AS value",
            requiredCapabilities: ["custom:missing-audit-capability"]
        ))

        let outcome = try XCTUnwrap(report.outcomes.first)
        XCTAssertEqual(report.overallVerdict, .failed)
        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertNil(outcome.preparedShape)
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "capability.missing" && $0.verdict == .unsupported
        })
        XCTAssertTrue(outcome.diagnostics.contains {
            $0.code == "sqlite.prepare.failed" && $0.verdict == .failed
        })
    }

    func testUnsupportedPlaceholderSyntaxDoesNotProduceDerivedParameterFailures() throws {
        let queries = [
            Support.query(id: "placeholder.anonymous", sql: "SELECT ? AS value"),
            Support.query(id: "placeholder.at", sql: "SELECT @value AS value"),
            Support.query(id: "placeholder.dollar", sql: "SELECT $value AS value"),
        ]
        let report = try validate(plan: Support.plan(queries: queries))

        XCTAssertEqual(report.overallVerdict, .unsupported)
        for outcome in report.outcomes {
            XCTAssertEqual(outcome.verdict, .unsupported, outcome.queryID)
            XCTAssertNotNil(outcome.preparedShape, outcome.queryID)
            XCTAssertTrue(outcome.diagnostics.contains {
                $0.code == "parameter.syntax" && $0.verdict == .unsupported
            }, outcome.queryID)
            XCTAssertFalse(outcome.diagnostics.contains {
                $0.stage == .parameter && $0.verdict == .failed
            }, outcome.queryID)
        }
    }

    func testURLValidationRejectsAdjacentRollbackJournal() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let journalURL = URL(fileURLWithPath: databaseURL.path + "-journal")
            XCTAssertTrue(FileManager.default.createFile(
                atPath: journalURL.path,
                contents: Data("audit".utf8)
            ))

            XCTAssertThrowsError(
                try SQLiteBuildValidator.validate(
                    plan: Support.plan(),
                    againstDatabaseAt: databaseURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorError,
                    .databaseHasSidecar(journalURL.path)
                )
            }
        }
    }

    private func validate(
        query: SQLiteBuildValidationQuery,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        try validate(
            plan: Support.plan(queries: [query]),
            environment: environment
        )
    }

    private func validate(
        plan: SQLiteBuildValidationPlan,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        try Support.withReadOnlyNorthwindDatabase { database in
            try validate(
                plan: plan,
                in: database,
                environment: environment
            )
        }
    }

    private func validate(
        plan: SQLiteBuildValidationPlan,
        in database: Database,
        environment: SQLiteBuildValidationEnvironment
    ) throws -> SQLiteBuildValidationReport {
        try SQLiteBuildValidator.validate(
            plan: plan,
            in: database,
            observedDatabaseByteCount: Support.northwindSchemaByteCount,
            observedDatabaseSHA256: Support.northwindSchemaSHA256,
            environment: environment
        )
    }
}
