import Foundation
import SwiftQLCore
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLiteBuildValidationModelTests: XCTestCase {
    typealias Support = SQLiteBuildValidationTestSupport

    func testPlanCanonicalizesOrderingRoundTripsAndEndsWithOneNewline() throws {
        let later = Support.query(
            id: "z-later",
            conformanceCaseIDs: [
                "c191.v1.select.j-inner.w-named-binding",
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ],
            inventoryFeatureIDs: [
                "syntax.select.core",
                "binding.named",
                "syntax.select.core",
            ],
            requiredCapabilities: [
                "function:FLOOR",
                "function:ABS",
                "function:FLOOR",
            ]
        )
        let earlier = Support.query(id: "a-earlier")
        let plan = Support.plan(queries: [later, earlier])

        let validated = try plan.validating()
        XCTAssertEqual(validated.queries.map(\.id), ["a-earlier", "z-later"])
        XCTAssertEqual(
            validated.queries[1].conformanceCaseIDs,
            [
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ]
        )
        XCTAssertEqual(
            validated.queries[1].inventoryFeatureIDs,
            ["binding.named", "syntax.select.core"]
        )
        XCTAssertEqual(
            validated.queries[1].requiredCapabilities.map(\.id),
            ["function:ABS", "function:FLOOR"]
        )

        let data = try validated.canonicalJSONData()
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertNotEqual(data.dropLast().last, 0x0A)
        XCTAssertEqual(try SQLiteBuildValidationPlan.decode(data), validated)
        XCTAssertEqual(
            try SQLiteBuildValidationPlan.decode(data).canonicalJSONData(),
            data
        )

        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let earlierRange = try XCTUnwrap(json.range(of: "a-earlier"))
        let laterRange = try XCTUnwrap(json.range(of: "z-later"))
        XCTAssertLessThan(earlierRange.lowerBound, laterRange.lowerBound)
        XCTAssertTrue(json.contains("\"schema_version\" : 1"))
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("hostname"))
    }

    func testPlanRejectsInvalidSchemaVersionIdentityAndDuplicateQueryIDs() throws {
        XCTAssertThrowsError(
            try SQLiteBuildValidationPlan(
                schemaVersion: 2,
                inventoryVersion: "1.3.0",
                schema: Support.schema(),
                queries: []
            ).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationModelError,
                .unsupportedSchemaVersion(2)
            )
        }

        XCTAssertThrowsError(
            try Support.plan(
                schema: Support.schema(databaseSHA256: String(repeating: "g", count: 64))
            ).validating()
        ) { error in
            guard case .invalidPlan(let reason) =
                error as? SQLiteBuildValidationModelError else {
                return XCTFail("Expected invalid plan, received \(error)")
            }
            XCTAssertTrue(reason.contains("SHA-256"))
        }

        let duplicate = Support.query(id: "duplicate")
        XCTAssertThrowsError(
            try Support.plan(queries: [duplicate, duplicate]).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationModelError,
                .duplicateQueryID("duplicate")
            )
        }
    }

    func testPlanRejectsParameterGapsPhysicalCollisionsAndMalformedKeys() throws {
        let logicalGap = Support.parameter(logicalIndex: 1)
        assertInvalidQuery(
            Support.query(parameters: [logicalGap]),
            contains: "contiguous"
        )

        let first = Support.parameter(
            logicalIndex: 0,
            physicalIndex: 1,
            identity: "parameter/first",
            keyName: "first"
        )
        let collision = Support.parameter(
            logicalIndex: 1,
            physicalIndex: 1,
            identity: "parameter/second",
            keyName: "second"
        )
        assertInvalidQuery(
            Support.query(parameters: [first, collision]),
            contains: "must not share"
        )

        let malformedIndexed = Support.parameter(
            logicalIndex: 0,
            physicalIndex: 3,
            keyKind: .indexed,
            keyName: nil,
            keyIndex: 0
        )
        assertInvalidQuery(
            Support.query(parameters: [malformedIndexed]),
            contains: "matching physical_index"
        )

        let malformedNamed = Support.parameter(
            keyKind: .named,
            keyName: nil,
            keyIndex: 0
        )
        assertInvalidQuery(
            Support.query(parameters: [malformedNamed]),
            contains: "named parameters"
        )
    }

    func testPlanRejectsResultGapsEmptyAliasesAndIncompleteCodecs() throws {
        assertInvalidQuery(
            Support.query(results: [Support.result(index: 1)]),
            contains: "result metadata"
        )
        assertInvalidQuery(
            Support.query(results: [Support.result(expectedAlias: "")]),
            contains: "result metadata"
        )

        let incompleteCodec = Support.codec(keyID: "")
        assertInvalidQuery(
            Support.query(results: [Support.result(codec: incompleteCodec)]),
            contains: "codec metadata"
        )
    }

    func testDescriptorProjectionPreservesStableIdentityPhysicalSlotsAndCodec() throws {
        let descriptorCodec = makeDescriptorCodec()
        let descriptor = try makeMixedDescriptor(codec: descriptorCodec)

        let projected = try SQLiteBuildValidationQuery(
            id: "projection.mixed-bindings",
            descriptor: descriptor,
            resultAliases: ["indexed_value", "token"],
            conformanceCaseIDs: [
                "c191.v1.select.j-inner.w-named-binding",
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ],
            inventoryFeatureIDs: ["binding.named", "binding.indexed"],
            requiredCapabilities: ["function:JSON_VALID", "function:ABS"]
        )
        let repeated = try SQLiteBuildValidationQuery(
            id: "projection.mixed-bindings",
            descriptor: descriptor,
            resultAliases: ["indexed_value", "token"],
            conformanceCaseIDs: [
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ],
            inventoryFeatureIDs: ["binding.indexed", "binding.named"],
            requiredCapabilities: ["function:ABS", "function:JSON_VALID"]
        )

        XCTAssertEqual(projected, repeated)
        XCTAssertEqual(
            projected.definitionIdentity,
            "tests/build-validation/projection@1"
        )
        XCTAssertEqual(projected.descriptorIdentity, descriptor.identity.description)
        XCTAssertEqual(projected.sql, "SELECT ?5 AS indexed_value, :token AS token")
        XCTAssertEqual(projected.parameters.map(\.logicalIndex), [0, 1])
        XCTAssertEqual(projected.parameters.map(\.physicalIndex), [5, 6])
        XCTAssertEqual(projected.expectedPhysicalParameterCount, 6)
        XCTAssertEqual(projected.parameters[0].expectedSQLiteName, "?5")
        XCTAssertEqual(projected.parameters[1].expectedSQLiteName, ":token")
        XCTAssertNil(projected.parameters[0].codec)
        XCTAssertEqual(
            projected.parameters[1].codec,
            SQLiteBuildValidationCodec(descriptorCodec)
        )
        XCTAssertEqual(projected.results.map(\.expectedAlias), ["indexed_value", "token"])
        XCTAssertEqual(
            projected.results[1].codec,
            SQLiteBuildValidationCodec(descriptorCodec)
        )
        XCTAssertEqual(
            projected.requiredCodecIdentifiers,
            [SQLiteBuildValidationCodec(descriptorCodec).stableIdentifier]
        )
        XCTAssertEqual(projected.conformanceCaseIDs, [
            "c191.v1.northwind.cte-order-subtotals",
            "c191.v1.select.j-inner.w-named-binding",
        ])
        XCTAssertEqual(
            projected.requiredCapabilities.map(\.id),
            ["function:ABS", "function:JSON_VALID"]
        )
    }

    func testDescriptorProjectionRejectsAliasCountMismatch() throws {
        let descriptor = try makeMixedDescriptor(codec: makeDescriptorCodec())
        XCTAssertThrowsError(
            try SQLiteBuildValidationQuery(
                id: "projection.alias-mismatch",
                descriptor: descriptor,
                resultAliases: ["only-one"]
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationModelError,
                .resultAliasCountMismatch(
                    queryID: "projection.alias-mismatch",
                    expected: 2,
                    actual: 1
                )
            )
        }
    }

    func testDescriptorProjectionUsesSQLTokenOrderForNamedPhysicalSlots() throws {
        let descriptor = try makeMixedDescriptor(
            codec: makeDescriptorCodec(),
            sql: "SELECT :token AS indexed_value, ?5 AS token"
        )

        let projected = try SQLiteBuildValidationQuery(
            id: "projection.sql-token-order",
            descriptor: descriptor
        )

        XCTAssertEqual(projected.parameters.map(\.logicalIndex), [0, 1])
        XCTAssertEqual(projected.parameters.map(\.physicalIndex), [5, 1])
        XCTAssertEqual(projected.parameters.map(\.expectedSQLiteName), ["?5", ":token"])
        XCTAssertEqual(projected.expectedPhysicalParameterCount, 5)
    }

    func testDescriptorProjectionRejectsNamedParameterAbsentFromSQL() throws {
        let descriptor = try makeMixedDescriptor(
            codec: makeDescriptorCodec(),
            sql: "SELECT ?5 AS indexed_value, 1 AS token"
        )

        XCTAssertThrowsError(
            try SQLiteBuildValidationQuery(
                id: "projection.missing-named-parameter",
                descriptor: descriptor
            )
        ) { error in
            guard case .invalidQuery(let queryID, let reason) =
                    error as? SQLiteBuildValidationModelError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertEqual(queryID, "projection.missing-named-parameter")
            XCTAssertTrue(reason.contains(":token"))
        }
    }

    private func assertInvalidQuery(
        _ query: SQLiteBuildValidationQuery,
        contains expectedReason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try Support.plan(queries: [query]).validating(),
            file: file,
            line: line
        ) { error in
            guard case .invalidQuery(_, let reason) =
                error as? SQLiteBuildValidationModelError else {
                return XCTFail(
                    "Expected invalid query, received \(error)",
                    file: file,
                    line: line
                )
            }
            XCTAssertTrue(
                reason.contains(expectedReason),
                "Expected '\(reason)' to contain '\(expectedReason)'",
                file: file,
                line: line
            )
        }
    }

    private func makeDescriptorCodec() -> XLValueCodecIdentity {
        XLValueCodecIdentity(
            key: XLValueCodecKey(id: "tests.codec.token", version: 7),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.token"),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text")
        )
    }

    private func makeMixedDescriptor(
        codec: XLValueCodecIdentity,
        sql: String = "SELECT ?5 AS indexed_value, :token AS token"
    ) throws -> XLStaticQueryDescriptor {
        let indexed = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .indexed(4),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: "Swift.Int",
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath(["parameter", "indexed"])
            )
        )
        let named = XLParameterSlot(
            index: XLLogicalParameterIndex(1),
            key: .named("token"),
            valueTypeIdentifier: codec.valueTypeIdentifier,
            valueTypeName: "Tests.Token",
            nullability: .nullable,
            codecIdentity: codec,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath(["parameter", "token"])
            )
        )
        let integerStorage = XLValueStorageIdentifier(rawValue: "integer")
        let textStorage = XLValueStorageIdentifier(rawValue: "text")

        return try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "build-validation", "projection"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: sql,
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    minimumVersion: XLDialectVersion(3, 38, 0),
                    capabilities: [.namedBindings, .indexedBindings]
                ),
                parameterLayout: try XLParameterLayout(slots: [named, indexed])
            ),
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: try XLQuerySlotIdentity(path: ["parameter", "token"]),
                    slot: named,
                    storageIdentifier: textStorage
                ),
                XLStaticQueryParameterMetadata(
                    identity: try XLQuerySlotIdentity(path: ["parameter", "indexed"]),
                    slot: indexed,
                    storageIdentifier: integerStorage
                ),
            ],
            results: try XLStaticQueryResultMetadata(slots: [
                XLStaticQueryResultSlot(
                    index: XLLogicalResultIndex(0),
                    identity: try XLQuerySlotIdentity(path: ["result", "indexed"]),
                    valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
                    valueTypeName: "Swift.Int",
                    nullability: .required,
                    codecIdentity: nil,
                    storageIdentifier: integerStorage,
                    codingContext: XLValueCodingContext(
                        site: .result,
                        path: XLValueCodingPath(["result", "indexed"])
                    )
                ),
                XLStaticQueryResultSlot(
                    index: XLLogicalResultIndex(1),
                    identity: try XLQuerySlotIdentity(path: ["result", "token"]),
                    valueTypeIdentifier: codec.valueTypeIdentifier,
                    valueTypeName: "Tests.Token",
                    nullability: .nullable,
                    codecIdentity: codec,
                    storageIdentifier: textStorage,
                    codingContext: XLValueCodingContext(
                        site: .result,
                        path: XLValueCodingPath(["result", "token"])
                    )
                ),
            ]),
            cardinality: .exactlyOne
        )
    }
}
