import Foundation
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteCombinatorialSupport
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLiteBuildValidatorIntegrationTests: XCTestCase {
    typealias Support = SQLiteBuildValidationTestSupport

    func testRepresentativeIssue191CasesAndFeatureReferencesPass() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let named = try manifestCase(
            "c191.v1.select.j-inner.w-named-binding",
            in: manifest
        )
        let cte = try manifestCase(
            "c191.v1.northwind.cte-order-subtotals",
            in: manifest
        )
        let floor = try manifestCase(
            "c191.v1.expression.numeric-floor",
            in: manifest
        )

        XCTAssertEqual(named.inventoryFeatureIDs, [
            "binding.named",
            "syntax.expression.current-operators",
            "syntax.join.current-inner-left-cross",
            "syntax.select.core",
        ])
        XCTAssertEqual(
            named.northwindAnchorCaseIDs,
            ["northwind.join.customer-order-employee-product"]
        )
        XCTAssertEqual(cte.inventoryFeatureIDs, [
            "syntax.cte.recursive",
            "syntax.expression.aggregate-functions",
            "syntax.select.core",
        ])
        XCTAssertEqual(
            cte.northwindAnchorCaseIDs,
            ["northwind.cte.order-subtotals"]
        )
        XCTAssertEqual(
            floor.inventoryFeatureIDs,
            ["syntax.expression.numeric-comparable-functions"]
        )
        XCTAssertEqual(floor.requiredCapabilities, ["function:FLOOR"])

        let queries = [
            Support.query(
                id: named.id,
                conformanceCaseIDs: [named.id],
                inventoryFeatureIDs: named.inventoryFeatureIDs,
                northwindAnchorCaseIDs: named.northwindAnchorCaseIDs ?? [],
                sql: named.renderedSQL,
                cardinality: XLQueryCardinality.many.rawValue,
                parameters: [Support.parameter(
                    identity: "parameter/minimum-order-id",
                    keyName: "minimum_order_id"
                )],
                results: [Support.result(
                    identity: "result/order-id",
                    expectedAlias: nil
                )],
                requiredCapabilities: named.requiredCapabilities
            ),
            Support.query(
                id: cte.id,
                conformanceCaseIDs: [cte.id],
                inventoryFeatureIDs: cte.inventoryFeatureIDs,
                northwindAnchorCaseIDs: cte.northwindAnchorCaseIDs ?? [],
                sql: cte.renderedSQL,
                cardinality: XLQueryCardinality.many.rawValue,
                results: [
                    Support.result(
                        index: 0,
                        identity: "result/order-id",
                        expectedAlias: "orderID"
                    ),
                    Support.result(
                        index: 1,
                        identity: "result/subtotal",
                        expectedAlias: "subtotal",
                        valueTypeIdentifier: "swift.double",
                        valueTypeName: "Swift.Double",
                        storageIdentifier: "real"
                    ),
                ],
                requiredCapabilities: cte.requiredCapabilities
            ),
            Support.query(
                id: floor.id,
                conformanceCaseIDs: [floor.id],
                inventoryFeatureIDs: floor.inventoryFeatureIDs,
                northwindAnchorCaseIDs: floor.northwindAnchorCaseIDs ?? [],
                sql: floor.renderedSQL,
                parameters: [Support.parameter(
                    identity: "parameter/real-value",
                    keyName: "real_value",
                    valueTypeIdentifier: "swift.double",
                    valueTypeName: "Swift.Double",
                    storageIdentifier: "real"
                )],
                results: [Support.result(
                    identity: "result/floor",
                    expectedAlias: nil,
                    valueTypeIdentifier: "swift.double",
                    valueTypeName: "Swift.Double",
                    storageIdentifier: "real"
                )],
                requiredCapabilities: floor.requiredCapabilities
            ),
        ]
        let plan = Support.plan(
            inventoryVersion: manifest.inventoryVersion,
            queries: queries
        )

        let report = try validateOnOwnedNorthwindURL(plan: plan)
        XCTAssertEqual(report.overallVerdict, .passed)
        XCTAssertEqual(report.diagnostics, [])
        XCTAssertEqual(
            report.outcomes.map(\.queryID),
            queries.map(\.id).sorted()
        )
        XCTAssertTrue(report.outcomes.allSatisfy { outcome in
            outcome.verdict == .passed && outcome.diagnostics.isEmpty
        })
        for query in queries {
            let outcome = try XCTUnwrap(
                report.outcomes.first { $0.queryID == query.id }
            )
            XCTAssertEqual(outcome.conformanceCaseIDs, query.conformanceCaseIDs)
            XCTAssertEqual(outcome.inventoryFeatureIDs, query.inventoryFeatureIDs)
            XCTAssertEqual(
                outcome.northwindAnchorCaseIDs,
                query.northwindAnchorCaseIDs
            )
            XCTAssertNotNil(outcome.preparedShape)
        }
    }

    func testSyntaxMissingTableAndMissingColumnFailWithStableDescriptorAndFeatureReferences() throws {
        let queries = [
            Support.query(
                id: "invalid.syntax",
                inventoryFeatureIDs: ["syntax.select.core"],
                sql: "SELECT FROM"
            ),
            Support.query(
                id: "invalid.table",
                inventoryFeatureIDs: ["syntax.select.core"],
                sql: "SELECT * FROM definitely_missing_table"
            ),
            Support.query(
                id: "invalid.column",
                inventoryFeatureIDs: ["syntax.select.core"],
                sql: "SELECT definitely_missing_column FROM Customers"
            ),
        ]

        let report = try validateOnOwnedNorthwindURL(
            plan: Support.plan(queries: queries)
        )
        XCTAssertEqual(report.overallVerdict, .failed)
        XCTAssertEqual(report.outcomes.count, 3)
        for query in queries {
            let outcome = try XCTUnwrap(
                report.outcomes.first { $0.queryID == query.id }
            )
            XCTAssertEqual(outcome.verdict, .failed)
            XCTAssertNil(outcome.preparedShape)
            let diagnostic = try XCTUnwrap(
                outcome.diagnostics.first { $0.code == "sqlite.prepare.failed" }
            )
            XCTAssertEqual(diagnostic.queryID, query.id)
            XCTAssertEqual(
                diagnostic.definitionIdentity,
                query.definitionIdentity
            )
            XCTAssertEqual(
                diagnostic.descriptorIdentity,
                query.descriptorIdentity
            )
            XCTAssertEqual(
                diagnostic.conformanceCaseIDs,
                query.conformanceCaseIDs
            )
            XCTAssertEqual(
                diagnostic.inventoryFeatureIDs,
                query.inventoryFeatureIDs
            )
            XCTAssertNotNil(diagnostic.sqliteResultCode)
            XCTAssertNotNil(diagnostic.sqliteExtendedResultCode)
            XCTAssertFalse(diagnostic.message.isEmpty)
        }
    }

    func testIndexedGapPassesCollisionFailsAndAnonymousIsExplicitlyUnsupported() throws {
        let indexedGap = Support.query(
            id: "binding.indexed-gap",
            sql: "SELECT ?3 AS value",
            parameters: [Support.parameter(
                physicalIndex: 3,
                keyKind: .indexed,
                keyName: nil,
                keyIndex: 2
            )]
        )
        let collision = Support.query(
            id: "binding.collision",
            sql: "SELECT :first AS first, ?1 AS duplicate",
            parameters: [Support.parameter(
                identity: "parameter/first",
                keyName: "first"
            )],
            results: [
                Support.result(identity: "result/first", expectedAlias: "first"),
                Support.result(
                    index: 1,
                    identity: "result/duplicate",
                    expectedAlias: "duplicate"
                ),
            ]
        )
        let anonymous = Support.query(
            id: "binding.anonymous",
            sql: "SELECT ? AS value",
            parameters: [Support.parameter(
                keyKind: .indexed,
                keyName: nil,
                keyIndex: 0
            )]
        )

        let report = try validateOnOwnedNorthwindURL(
            plan: Support.plan(queries: [anonymous, collision, indexedGap])
        )
        XCTAssertEqual(report.overallVerdict, .failed)
        XCTAssertEqual(
            try outcome("binding.indexed-gap", in: report).verdict,
            .passed
        )
        XCTAssertTrue(
            try outcome("binding.collision", in: report).diagnostics.contains {
                $0.code == "parameter.key" && $0.verdict == .failed
            }
        )
        let anonymousOutcome = try outcome("binding.anonymous", in: report)
        XCTAssertEqual(anonymousOutcome.verdict, .unsupported)
        XCTAssertTrue(anonymousOutcome.diagnostics.contains {
            $0.code == "parameter.syntax" && $0.verdict == .unsupported
        })
        XCTAssertFalse(anonymousOutcome.diagnostics.contains {
            $0.stage == .parameter && $0.verdict == .failed
        })
    }

    func testResultCountAndExplicitAliasMismatchesFail() throws {
        let count = Support.query(
            id: "result.count-mismatch",
            results: [
                Support.result(index: 0),
                Support.result(index: 1, identity: "result/extra", expectedAlias: "extra"),
            ]
        )
        let alias = Support.query(
            id: "result.alias-mismatch",
            results: [Support.result(expectedAlias: "not_value")]
        )

        let report = try validateOnOwnedNorthwindURL(
            plan: Support.plan(queries: [count, alias])
        )
        XCTAssertEqual(report.overallVerdict, .failed)
        XCTAssertTrue(
            try outcome(count.id, in: report).diagnostics.contains {
                $0.code == "result.count"
            }
        )
        XCTAssertTrue(
            try outcome(alias.id, in: report).diagnostics.contains {
                $0.code == "result.name"
            }
        )
    }

    func testMissingCodecAndExtensionCapabilityAreUnsupportedAndExplicitInputsPass() throws {
        let codec = Support.codec()
        let query = Support.query(
            id: "requirements.codec-extension",
            sql: "SELECT :value AS value",
            parameters: [Support.parameter(
                valueTypeIdentifier: codec.valueTypeIdentifier,
                valueTypeName: "Tests.Token",
                codec: codec,
                storageIdentifier: codec.storageIdentifier
            )],
            results: [Support.result(
                valueTypeIdentifier: codec.valueTypeIdentifier,
                valueTypeName: "Tests.Token",
                codec: codec,
                storageIdentifier: codec.storageIdentifier
            )],
            requiredCapabilities: ["extension:tests-required-extension"]
        )
        let plan = Support.plan(queries: [query])

        let missing = try validateOnOwnedNorthwindURL(plan: plan)
        XCTAssertEqual(missing.overallVerdict, .unsupported)
        let missingOutcome = try XCTUnwrap(missing.outcomes.first)
        XCTAssertEqual(missingOutcome.verdict, .unsupported)
        XCTAssertEqual(
            Set(missingOutcome.diagnostics.map(\.code)),
            ["codec.missing", "capability.extension"]
        )
        XCTAssertTrue(missingOutcome.diagnostics.allSatisfy {
            $0.verdict == .unsupported
        })

        let supplied = try validateOnOwnedNorthwindURL(
            plan: plan,
            environment: SQLiteBuildValidationEnvironment(
                codecIdentities: [codec],
                extensionNames: ["tests-required-extension"]
            )
        )
        XCTAssertEqual(supplied.overallVerdict, .passed)
        XCTAssertEqual(try XCTUnwrap(supplied.outcomes.first).diagnostics, [])
    }

    func testSchemaSHAByteCountAndFNVDisagreementsFailClosed() throws {
        let cases: [(SQLiteBuildValidationSchemaInput, String)] = [
            (
                Support.schema(
                    databaseSHA256: String(repeating: "0", count: 64)
                ),
                "schema.snapshot-sha"
            ),
            (
                Support.schema(
                    databaseByteCount: Support.northwindSchemaByteCount + 1
                ),
                "schema.byte-count"
            ),
            (
                Support.schema(
                    schemaFNV1A64: String(repeating: "0", count: 16)
                ),
                "schema.fingerprint"
            ),
        ]

        try Support.withValidatorOwnedNorthwindURL { url in
            for (schema, code) in cases {
                let report = try SQLiteBuildValidator.validate(
                    plan: Support.plan(schema: schema),
                    againstDatabaseAt: url
                )
                XCTAssertEqual(report.overallVerdict, .failed)
                let diagnostic = try XCTUnwrap(
                    report.diagnostics.first { $0.code == code }
                )
                XCTAssertEqual(diagnostic.stage, .schema)
                XCTAssertEqual(diagnostic.verdict, .failed)
            }
        }
    }

    func testRuntimeMetadataMatchesIssue191CollectorOnSameConnection() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            let extensionNames = ["tests.extension.z", "tests.extension.a"]
            let prototype = try SQLiteBuildValidationRuntime.capture(
                from: database,
                extensionNames: extensionNames
            )
            let issue191 = try SQLiteRuntimeMetadata.capture(
                from: database,
                extensionNames: extensionNames
            )

            XCTAssertEqual(prototype.sqliteVersion, issue191.sqliteVersion)
            XCTAssertEqual(prototype.sqliteSourceID, issue191.sqliteSourceID)
            XCTAssertEqual(prototype.compileOptions, issue191.compileOptions)
            XCTAssertEqual(prototype.collations, issue191.collations)
            XCTAssertEqual(prototype.moduleNames, issue191.moduleNames)
            XCTAssertEqual(prototype.extensionNames, issue191.extensionNames)
            XCTAssertEqual(prototype.schemaRowCount, issue191.schemaRowCount)
            XCTAssertEqual(prototype.schemaFNV1A64, issue191.schemaFNV1A64)
            XCTAssertEqual(prototype.schemaRowCount, Support.northwindSchemaRowCount)
            XCTAssertEqual(prototype.schemaFNV1A64, Support.northwindSchemaFNV1A64)
            XCTAssertEqual(
                prototype.functions.map(prototypeFunctionSignature),
                issue191.functions.map(issue191FunctionSignature)
            )
        }
    }

    func testDifferentCopiedPathsProduceByteIdenticalCanonicalReports() throws {
        let plan = Support.plan(queries: [
            Support.query(id: "z-query"),
            Support.query(id: "a-query"),
        ])

        let first = try canonicalReportFromFreshCopy(plan: plan)
        let second = try canonicalReportFromFreshCopy(plan: plan)

        XCTAssertNotEqual(first.path, second.path)
        XCTAssertEqual(first.data, second.data)
        XCTAssertEqual(first.data.last, 0x0A)
        XCTAssertNotEqual(first.data.dropLast().last, 0x0A)
        let decoded = try JSONDecoder().decode(
            SQLiteBuildValidationReport.self,
            from: first.data
        )
        XCTAssertEqual(decoded.overallVerdict, .passed)
        XCTAssertEqual(decoded.outcomes.map(\.queryID), ["a-query", "z-query"])
        XCTAssertEqual(
            decoded.observedDatabaseSHA256,
            Support.northwindSchemaSHA256
        )
    }

    func testURLOverloadRejectsOpenFixtureSidecars() throws {
        try Support.withNorthwindURL { url in
            XCTAssertThrowsError(
                try SQLiteBuildValidator.validate(
                    plan: Support.plan(),
                    againstDatabaseAt: url
                )
            ) { error in
                guard case .databaseHasSidecar(let path) =
                    error as? SQLiteBuildValidationValidatorError else {
                    return XCTFail("Expected database sidecar rejection, received \(error)")
                }
                XCTAssertTrue(path.hasSuffix("-wal") || path.hasSuffix("-shm"))
            }
        }
    }

    func testURLOverloadRejectsSidecarAdjacentToSymlinkTarget() throws {
        try Support.withValidatorOwnedNorthwindURL { databaseURL in
            let databaseAliasURL = databaseURL.deletingLastPathComponent()
                .appendingPathComponent("database-alias.sqlite")
            try FileManager.default.createSymbolicLink(
                at: databaseAliasURL,
                withDestinationURL: databaseURL
            )
            let journalURL = URL(fileURLWithPath: databaseURL.path + "-journal")
            XCTAssertTrue(FileManager.default.createFile(
                atPath: journalURL.path,
                contents: Data("audit".utf8)
            ))

            XCTAssertThrowsError(
                try SQLiteBuildValidator.validate(
                    plan: Support.plan(),
                    againstDatabaseAt: databaseAliasURL
                )
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationValidatorError,
                    .databaseHasSidecar(journalURL.path)
                )
            }
        }
    }

    private func validateOnOwnedNorthwindURL(
        plan: SQLiteBuildValidationPlan,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        try Support.withValidatorOwnedNorthwindURL { url in
            try SQLiteBuildValidator.validate(
                plan: plan,
                againstDatabaseAt: url,
                environment: environment
            )
        }
    }

    private func canonicalReportFromFreshCopy(
        plan: SQLiteBuildValidationPlan
    ) throws -> (path: String, data: Data) {
        try Support.withValidatorOwnedNorthwindURL { url in
            let report = try SQLiteBuildValidator.validate(
                plan: plan,
                againstDatabaseAt: url
            )
            return (url.path, try report.canonicalJSONData())
        }
    }

    private func outcome(
        _ queryID: String,
        in report: SQLiteBuildValidationReport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SQLiteBuildValidationQueryOutcome {
        try XCTUnwrap(
            report.outcomes.first { $0.queryID == queryID },
            "Missing outcome for \(queryID)",
            file: file,
            line: line
        )
    }

    private func manifestCase(
        _ id: String,
        in manifest: SQLiteCombinatorialManifest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SQLiteCombinatorialCase {
        try XCTUnwrap(
            manifest.cases.first { $0.id == id },
            "Missing #191 case \(id)",
            file: file,
            line: line
        )
    }

    private func prototypeFunctionSignature(
        _ function: SQLiteBuildValidationRuntimeFunction
    ) -> String {
        [
            function.name,
            function.isBuiltIn ? "1" : "0",
            function.kind,
            function.encoding,
            String(function.argumentCount),
            String(function.flags),
        ].joined(separator: "|")
    }

    private func issue191FunctionSignature(
        _ function: SQLiteRuntimeFunction
    ) -> String {
        [
            function.name,
            function.isBuiltIn ? "1" : "0",
            function.kind,
            function.encoding,
            String(function.argumentCount),
            String(function.flags),
        ].joined(separator: "|")
    }
}
