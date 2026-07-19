import Foundation
import GRDB
import SwiftQLSQLiteCombinatorialSupport
import XCTest


#if swift(>=6.0)
#error("SwiftQL 1.x compatibility lanes must compile in Swift 5 language mode")
#endif


final class SQLiteCombinatorialManifestRuntimeTests: XCTestCase {

    func testCanonicalManifestEncodingAndMarkdownAreRepeatable() throws {
        let manifest = sampleManifest(cases: [sampleCase(id: "case.z"), sampleCase(id: "case.a")])

        let firstJSON = try manifest.canonicalJSONData()
        let secondJSON = try manifest.canonicalJSONData()
        XCTAssertEqual(firstJSON, secondJSON)
        XCTAssertEqual(firstJSON.last, 0x0A)
        XCTAssertFalse(firstJSON.dropLast().last == 0x0A)

        let json = try XCTUnwrap(String(data: firstJSON, encoding: .utf8))
        XCTAssertLessThan(
            try XCTUnwrap(json.range(of: "\"cases\"")) .lowerBound,
            try XCTUnwrap(json.range(of: "\"constraints\"")) .lowerBound
        )
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("hostname"))

        let decoded = try JSONDecoder().decode(SQLiteCombinatorialManifest.self, from: firstJSON)
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.cases.map(\.id), ["case.a", "case.z"])

        let firstMarkdown = try manifest.markdownSummary()
        let secondMarkdown = try manifest.markdownSummary()
        XCTAssertEqual(firstMarkdown, secondMarkdown)
        XCTAssertTrue(firstMarkdown.hasSuffix("\n"))
        XCTAssertTrue(firstMarkdown.contains("| case.a | select-customer |"))
        XCTAssertLessThan(
            try XCTUnwrap(firstMarkdown.range(of: "| case.a |")) .lowerBound,
            try XCTUnwrap(firstMarkdown.range(of: "| case.z |")) .lowerBound
        )
    }

    func testCanonicalModelsNormalizeOnlyUnorderedCollections() throws {
        let firstCase = sampleCase(
            id: "case.order-insensitive",
            constraintIDs: ["constraint.semantic", "constraint.semantic"],
            inventoryFeatureIDs: ["syntax.where", "syntax.select"],
            northwindAnchorCaseIDs: ["case.254.b", "case.254.a", "case.254.b"],
            requiredCapabilities: ["window-functions", "cte", "cte"],
            bindings: [indexedBinding(), namedBinding()]
        )
        let secondCase = sampleCase(
            id: "case.order-insensitive",
            constraintIDs: ["constraint.semantic"],
            inventoryFeatureIDs: ["syntax.select", "syntax.where"],
            northwindAnchorCaseIDs: ["case.254.a", "case.254.b"],
            requiredCapabilities: ["cte", "window-functions"],
            bindings: [namedBinding(), indexedBinding()]
        )

        XCTAssertEqual(firstCase, secondCase)
        XCTAssertEqual(firstCase.inventoryFeatureIDs, ["syntax.select", "syntax.where"])
        XCTAssertEqual(firstCase.bindings.map(\.logicalIndex), [0, 1])

        let firstRuntime = sampleRuntimeMetadata(
            compileOptions: ["THREADSAFE=2", "ENABLE_FTS5", "THREADSAFE=2"],
            collations: ["RTRIM", "BINARY", "NOCASE"],
            modules: ["rtree", "fts5", "fts5"],
            extensions: ["z-extension", "a-extension"]
        )
        let secondRuntime = sampleRuntimeMetadata(
            compileOptions: ["ENABLE_FTS5", "THREADSAFE=2"],
            collations: ["BINARY", "NOCASE", "RTRIM"],
            modules: ["fts5", "rtree"],
            extensions: ["a-extension", "z-extension"]
        )
        XCTAssertEqual(firstRuntime, secondRuntime)

        // Dimension vectors are semantic ordered tuples and are not normalized.
        let reversedVector = Array(firstCase.dimensionVector.reversed())
        let changed = sampleCase(id: firstCase.id, dimensionVector: reversedVector)
        XCTAssertNotEqual(firstCase.dimensionVector, changed.dimensionVector)
    }

    func testSchemaFingerprintIsRepeatableAndChangesWithSchema() throws {
        let queue = try DatabaseQueue()
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE beta(id INTEGER PRIMARY KEY, note TEXT)")
            try database.execute(sql: "CREATE TABLE alpha(id INTEGER PRIMARY KEY)")
            try database.execute(sql: "CREATE INDEX beta_note ON beta(note)")
        }

        let first = try queue.read { try SQLiteRuntimeMetadata.capture(from: $0) }
        let second = try queue.read { try SQLiteRuntimeMetadata.capture(from: $0) }
        XCTAssertEqual(first.schemaRowCount, 3)
        XCTAssertEqual(first.schemaFNV1A64, second.schemaFNV1A64)
        XCTAssertEqual(first.schemaFNV1A64.count, 16)

        try queue.write { database in
            try database.execute(sql: "CREATE VIEW beta_notes AS SELECT note FROM beta")
        }
        let changed = try queue.read { try SQLiteRuntimeMetadata.capture(from: $0) }
        XCTAssertEqual(changed.schemaRowCount, 4)
        XCTAssertNotEqual(changed.schemaFNV1A64, first.schemaFNV1A64)
    }

    func testRuntimeCollectorSortsEveryDiscoverableList() throws {
        let queue = try DatabaseQueue()
        let runtime = try queue.read {
            try SQLiteRuntimeMetadata.capture(
                from: $0,
                extensionNames: ["z-test-extension", "a-test-extension", "z-test-extension"]
            )
        }

        XCTAssertFalse(runtime.sqliteVersion.isEmpty)
        XCTAssertFalse(runtime.sqliteSourceID.isEmpty)
        XCTAssertEqual(runtime.compileOptions, Array(Set(runtime.compileOptions)).sorted())
        XCTAssertEqual(runtime.collations, Array(Set(runtime.collations)).sorted())
        XCTAssertEqual(runtime.moduleNames, Array(Set(runtime.moduleNames)).sorted())
        XCTAssertEqual(runtime.extensionNames, ["a-test-extension", "z-test-extension"])
        XCTAssertEqual(runtime.functions, runtime.functions.sorted(by: runtimeFunctionOrder))
        XCTAssertFalse(runtime.functions.isEmpty)
    }

    func testFailureRecordSerializationRetainsCompleteReplayEvidence() throws {
        let testCase = sampleCase(id: "case.failure")
        let failure = SQLiteCombinatorialFailureRecord(
            testCase: testCase,
            originalSQL: testCase.renderedSQL,
            failingSQL: testCase.renderedSQL,
            bindings: testCase.bindings,
            stage: .oracle,
            failureSignature: SQLiteCombinatorialFailureSignature(
                errorType: "RowMismatch",
                code: "rows-differ",
                message: "expected one row; observed zero"
            ),
            runtimeMetadata: sampleRuntimeMetadata(),
            reducedFromCaseID: nil,
            reductionAttemptCount: 0,
            reducedDimensions: [],
            reproductionCommand: "swift test --filter SQLiteCombinatorialGeneratedTests/case.failure"
        )

        let data = try failure.canonicalJSONData()
        let decoded = try JSONDecoder().decode(SQLiteCombinatorialFailureRecord.self, from: data)
        XCTAssertEqual(decoded, failure)

        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for requiredKey in [
            "\"case\"",
            "\"original_sql\"",
            "\"failing_sql\"",
            "\"bindings\"",
            "\"stage\"",
            "\"failure_signature\"",
            "\"runtime_metadata\"",
            "\"reduction_attempt_count\"",
            "\"reduced_dimensions\"",
            "\"reproduction_command\"",
        ] {
            XCTAssertTrue(json.contains(requiredKey), "missing \(requiredKey)")
        }
        XCTAssertTrue(json.contains("\"sqlite_source_id\""))
        XCTAssertTrue(json.contains("\"schema_fnv1a_64\""))
        XCTAssertFalse(json.contains("\"reduced_from_case_id\""))
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("hostname"))
        XCTAssertEqual(decoded.testCase.id, "case.failure")
        XCTAssertEqual(decoded.testCase.renderedSQL, decoded.failingSQL)
        XCTAssertEqual(decoded.originalSQL, decoded.failingSQL)
        XCTAssertEqual(decoded.testCase.bindings, decoded.bindings)
        XCTAssertNil(decoded.reducedFromCaseID)
        XCTAssertEqual(decoded.reductionAttemptCount, 0)
        XCTAssertTrue(decoded.reducedDimensions.isEmpty)

        let report = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: String(repeating: "ab", count: 32),
            manifestCaseCount: 1,
            hardBounds: sampleBounds(),
            maximumRuntimeMilliseconds: 120_000,
            totalElapsedMilliseconds: 1_234.5,
            runtimeMetadata: failure.runtimeMetadata,
            outcomes: [
                SQLiteCombinatorialCaseOutcome(
                    caseID: testCase.id,
                    stage: failure.stage,
                    verdict: .failed,
                    elapsedMilliseconds: 12.5,
                    failure: failure
                ),
            ]
        )
        let reportData = try report.canonicalJSONData()
        let decodedReport = try JSONDecoder().decode(
            SQLiteCombinatorialRuntimeReport.self,
            from: reportData
        )
        XCTAssertEqual(decodedReport, report)
        XCTAssertEqual(decodedReport.maximumRuntimeMilliseconds, 120_000)
        XCTAssertGreaterThan(decodedReport.maximumRuntimeMilliseconds, 0)
        XCTAssertEqual(decodedReport.totalElapsedMilliseconds, 1_234.5)
        XCTAssertTrue(decodedReport.satisfiesRuntimeBound)
        let reportJSON = try XCTUnwrap(String(data: reportData, encoding: .utf8))
        XCTAssertTrue(reportJSON.contains("\"maximum_runtime_ms\""))
        XCTAssertTrue(reportJSON.contains("\"total_elapsed_ms\""))

        let invalidBound = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: report.manifestSHA256,
            manifestCaseCount: report.manifestCaseCount,
            hardBounds: report.hardBounds,
            maximumRuntimeMilliseconds: 0,
            totalElapsedMilliseconds: 0,
            runtimeMetadata: report.runtimeMetadata,
            outcomes: report.outcomes
        )
        XCTAssertFalse(invalidBound.satisfiesRuntimeBound)
    }

    private func sampleManifest(cases: [SQLiteCombinatorialCase]) -> SQLiteCombinatorialManifest {
        SQLiteCombinatorialManifest(
            schemaVersion: 1,
            generatorVersion: "1.3.0",
            issue: 191,
            inventoryVersion: "2026-07-19",
            hardBounds: sampleBounds(),
            dimensions: [
                SQLiteCombinatorialManifestDimension(
                    id: "predicate",
                    title: "Predicate form",
                    values: [
                        SQLiteCombinatorialManifestDimensionValue(
                            id: "named-equality",
                            label: "named equality"
                        ),
                        SQLiteCombinatorialManifestDimensionValue(
                            id: "indexed-equality",
                            label: "indexed equality"
                        ),
                    ]
                ),
                SQLiteCombinatorialManifestDimension(
                    id: "source",
                    title: "Fixture source",
                    values: [
                        SQLiteCombinatorialManifestDimensionValue(
                            id: "northwind-customers",
                            label: "Northwind Customers"
                        ),
                    ]
                ),
            ],
            constraints: [
                SQLiteCombinatorialManifestConstraint(
                    id: "constraint.semantic",
                    dimensionIDs: ["predicate", "source"],
                    description: "semantic cases require a real fixture source"
                ),
            ],
            exclusions: [
                SQLiteCombinatorialManifestExclusion(
                    id: "exclusion.prepare-source",
                    constraintID: "constraint.semantic",
                    reason: "prepare-only coverage does not require Northwind",
                    dimensionVector: [
                        SQLiteCombinatorialCaseDimensionSelection(
                            dimensionID: "source",
                            valueID: "northwind-customers"
                        ),
                    ]
                ),
            ],
            coverage: [
                SQLiteCombinatorialManifestCoverage(
                    strength: 2,
                    dimensionIDs: ["predicate", "source"],
                    requiredTupleCount: 2,
                    coveredTupleCount: 2,
                    excludedTupleCount: 0
                ),
            ],
            cases: cases
        )
    }

    private func sampleCase(
        id: String,
        dimensionVector: [SQLiteCombinatorialCaseDimensionSelection]? = nil,
        constraintIDs: [String] = ["constraint.semantic"],
        inventoryFeatureIDs: [String] = ["syntax.select"],
        northwindAnchorCaseIDs: [String]? = ["case.254.customer-page"],
        requiredCapabilities: [String] = ["named-bindings"],
        bindings: [SQLiteCombinatorialBinding]? = nil
    ) -> SQLiteCombinatorialCase {
        SQLiteCombinatorialCase(
            id: id,
            template: "select-customer",
            strength: "pairwise",
            dimensionVector: dimensionVector ?? [
                SQLiteCombinatorialCaseDimensionSelection(
                    dimensionID: "predicate",
                    valueID: "named-equality"
                ),
                SQLiteCombinatorialCaseDimensionSelection(
                    dimensionID: "source",
                    valueID: "northwind-customers"
                ),
            ],
            constraintIDs: constraintIDs,
            inventoryFeatureIDs: inventoryFeatureIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            requiredCapabilities: requiredCapabilities,
            renderedSQL: "SELECT \"CustomerID\" FROM \"Customers\" WHERE \"CustomerID\" = :token",
            bindings: bindings ?? [namedBinding()],
            mode: .semantic,
            oracle: SQLiteCombinatorialOracle(
                id: "oracle.customer-id",
                kind: .fixedValue
            ),
            reproductionCommand: "swift test --filter SQLiteCombinatorialGeneratedTests/\(id)"
        )
    }

    private func namedBinding() -> SQLiteCombinatorialBinding {
        SQLiteCombinatorialBinding(
            logicalIndex: 0,
            keyKind: .named,
            keyName: "token",
            keyIndex: nil,
            storage: .text,
            taggedValue: .text("ALFKI"),
            repeatCount: 2
        )
    }

    private func indexedBinding() -> SQLiteCombinatorialBinding {
        SQLiteCombinatorialBinding(
            logicalIndex: 1,
            keyKind: .indexed,
            keyName: nil,
            keyIndex: 1,
            storage: .blob,
            taggedValue: .blob(Data([0x00, 0x7F, 0xFF])),
            repeatCount: 1
        )
    }

    private func sampleBounds() -> SQLiteCombinatorialHardBounds {
        SQLiteCombinatorialHardBounds(
            maximumCaseCount: 64,
            maximumDimensionsPerCase: 8,
            maximumBindingsPerCase: 16,
            maximumRenderedSQLBytes: 16_384,
            maximumReproductionCommandBytes: 2_048,
            maximumReductionAttempts: 32
        )
    }

    private func sampleRuntimeMetadata(
        compileOptions: [String] = ["ENABLE_FTS5", "THREADSAFE=2"],
        collations: [String] = ["BINARY", "NOCASE", "RTRIM"],
        modules: [String] = ["fts5", "rtree"],
        extensions: [String] = []
    ) -> SQLiteRuntimeMetadata {
        SQLiteRuntimeMetadata(
            sqliteVersion: "3.51.0",
            sqliteSourceID: "source-id",
            compileOptions: compileOptions,
            functions: [
                SQLiteRuntimeFunction(
                    name: "sum",
                    isBuiltIn: true,
                    kind: "w",
                    encoding: "utf8",
                    argumentCount: 1,
                    flags: 2_097_152
                ),
                SQLiteRuntimeFunction(
                    name: "abs",
                    isBuiltIn: true,
                    kind: "s",
                    encoding: "utf8",
                    argumentCount: 1,
                    flags: 2_097_152
                ),
            ],
            collations: collations,
            moduleNames: modules,
            extensionNames: extensions,
            schemaRowCount: 3,
            schemaFNV1A64: "0123456789abcdef"
        )
    }

    private func runtimeFunctionOrder(
        _ lhs: SQLiteRuntimeFunction,
        _ rhs: SQLiteRuntimeFunction
    ) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        if lhs.isBuiltIn != rhs.isBuiltIn {
            return !lhs.isBuiltIn && rhs.isBuiltIn
        }
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        if lhs.encoding != rhs.encoding {
            return lhs.encoding < rhs.encoding
        }
        if lhs.argumentCount != rhs.argumentCount {
            return lhs.argumentCount < rhs.argumentCount
        }
        return lhs.flags < rhs.flags
    }
}
