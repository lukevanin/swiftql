import Foundation
import XCTest

import SwiftQLCore


final class SQLStaticQueryDescriptorTests: XCTestCase {

    func testCanonicalIdentityIsStableAcrossUnorderedInputAndInvocationValues() throws {
        let forward = try makeDescriptor(
            entities: ["zeta", "alpha"],
            parametersReversed: false
        )
        let reversed = try makeDescriptor(
            entities: ["alpha", "zeta"],
            parametersReversed: true
        )

        XCTAssertEqual(forward.identity, reversed.identity)
        XCTAssertEqual(forward.canonicalIdentityMaterial, reversed.canonicalIdentityMaterial)
        requireSendable(forward)
        requireSendable(forward.identity)
        XCTAssertEqual(
            forward.parameters.map(\.slot.index),
            [XLLogicalParameterIndex(0), XLLogicalParameterIndex(1)]
        )

        let firstPacket = try XLInvocationBindings<XLSQLiteValue>(
            layout: forward.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(forward.parameterLayout.slot(at: .init(0))),
                    value: .integer(1)
                ),
                try XLInvocationBinding(
                    slot: try XCTUnwrap(forward.parameterLayout.slot(at: .init(1))),
                    value: .text("first")
                ),
            ]
        )
        let secondPacket = try XLInvocationBindings<XLSQLiteValue>(
            layout: forward.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(forward.parameterLayout.slot(at: .init(0))),
                    value: .integer(99)
                ),
                try XLInvocationBinding(
                    slot: try XCTUnwrap(forward.parameterLayout.slot(at: .init(1))),
                    value: .text("second")
                ),
            ]
        )

        XCTAssertNotEqual(firstPacket, secondPacket)
        XCTAssertEqual(forward.identity, reversed.identity)
    }

    func testSameContractCodecAndDiagnosticChangesDoNotChangeIdentity() throws {
        let first = try makeContextualDescriptor(
            codecKey: XLValueCodecKey(id: "tests.token.first", version: 1),
            valueTypeName: "OriginalModule.Token",
            codingPath: ["original", "token"],
            storage: "integer"
        )
        let second = try makeContextualDescriptor(
            codecKey: XLValueCodecKey(id: "tests.token.second", version: 99),
            valueTypeName: "RenamedModule.Token",
            codingPath: ["renamed", "value"],
            storage: "integer"
        )

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(
            first.parameters[0].slot.codecIdentity,
            second.parameters[0].slot.codecIdentity
        )
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertNoThrow(
            try first.identity.validateDefinitionCompatibility(with: second.identity)
        )
    }

    func testStorageSQLCapabilityLayoutAndCardinalityChangesAffectIdentity() throws {
        let baseline = try makeContextualDescriptor(storage: "integer")
        let storage = try makeContextualDescriptor(storage: "text")
        let sql = try makeContextualDescriptor(
            sql: "SELECT CAST(:token AS TEXT)"
        )
        let capabilities = try makeContextualDescriptor(
            capabilities: [.namedBindings, .indexedBindings]
        )
        let nullable = try makeContextualDescriptor(nullability: .nullable)
        let many = try makeContextualDescriptor(cardinality: .many)

        XCTAssertNotEqual(baseline.identity, storage.identity)
        XCTAssertNotEqual(baseline.identity, sql.identity)
        XCTAssertNotEqual(baseline.identity, capabilities.identity)
        XCTAssertNotEqual(baseline.identity, nullable.identity)
        XCTAssertNotEqual(baseline.identity, many.identity)
    }

    func testEveryDialectRequirementComponentAffectsIdentity() throws {
        let baseline = try makeCommandDescriptor(
            dialect: "example.custom",
            minimumVersion: nil,
            capabilities: []
        )
        let dialect = try makeCommandDescriptor(
            dialect: "example.other",
            minimumVersion: nil,
            capabilities: []
        )
        let version = try makeCommandDescriptor(
            dialect: "example.custom",
            minimumVersion: XLDialectVersion(2, 1, 0),
            capabilities: []
        )
        let capabilities = try makeCommandDescriptor(
            dialect: "example.custom",
            minimumVersion: nil,
            capabilities: [.indexedBindings]
        )

        XCTAssertNotEqual(baseline.identity, dialect.identity)
        XCTAssertNotEqual(baseline.identity, version.identity)
        XCTAssertNotEqual(baseline.identity, capabilities.identity)
    }

    func testDefinitionCollisionFailsClosedAndVersionBumpIsDistinct() throws {
        let first = try makeContextualDescriptor(sql: "SELECT :token")
        let collision = try makeContextualDescriptor(sql: "SELECT +:token")

        XCTAssertThrowsError(
            try first.identity.validateDefinitionCompatibility(
                with: collision.identity
            )
        ) { error in
            guard case .definitionIdentityCollision(
                let definition,
                let existing,
                let incoming
            ) = error as? XLStaticQueryError else {
                return XCTFail("Expected definition collision, received \(error)")
            }
            XCTAssertEqual(definition, first.definitionIdentity)
            XCTAssertEqual(existing, first.identity)
            XCTAssertEqual(incoming, collision.identity)
        }

        let nextVersion = try makeContextualDescriptor(
            definitionVersion: first.definitionIdentity.version + 1,
            sql: collision.sql
        )
        XCTAssertNotEqual(first.identity, nextVersion.identity)
        XCTAssertNoThrow(
            try first.identity.validateDefinitionCompatibility(
                with: nextVersion.identity
            )
        )
    }

    func testIdentityUsesNFCMetadataExactSQLAndFrozenV1Material() throws {
        let descriptor = try makeGoldenDescriptor()

        XCTAssertEqual(descriptor.identity.formatVersion, .v1)
        XCTAssertEqual(
            descriptor.identity.canonicalHex,
            "5377696674514c2e53746174696351756572794964656e7469747900000100000000000000010000000000000001710000000000000001000000000000000153000000000000000164000000000000000001000000000000000100000000000000010000000000000001700000000000000000000000000000000001780000000000000001740000000000000000016901000000000000000100000000000000010000000000000001720000000000000000000000000000000174000000000000000001690000000000000001000000000000000165"
        )

        let composed = try XLQueryDefinitionIdentity(
            path: ["caf\u{00e9}"],
            version: 1
        )
        let decomposed = try XLQueryDefinitionIdentity(
            path: ["cafe\u{0301}"],
            version: 1
        )
        XCTAssertEqual(composed, decomposed)

        let composedSlot = try XLQuerySlotIdentity(path: ["caf\u{00e9}"])
        let decomposedSlot = try XLQuerySlotIdentity(path: ["cafe\u{0301}"])
        XCTAssertEqual(composedSlot, decomposedSlot)

        func metadataDescriptor(
            definition: XLQueryDefinitionIdentity,
            slotIdentity: XLQuerySlotIdentity,
            suffix: String
        ) throws -> XLStaticQueryDescriptor {
            let valueType = XLValueTypeIdentifier(rawValue: "value-\(suffix)")
            let storage = XLValueStorageIdentifier(rawValue: "storage-\(suffix)")
            let parameter = XLParameterSlot(
                index: XLLogicalParameterIndex(0),
                key: .named("key-\(suffix)"),
                valueTypeIdentifier: valueType,
                valueTypeName: "Diagnostic.Value",
                nullability: .required,
                codecIdentity: nil,
                codingContext: XLValueCodingContext(
                    site: .parameter,
                    path: XLValueCodingPath("ignored")
                )
            )
            return try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: XLStaticStatementDefinition(
                    sql: "SELECT :value",
                    dialectRequirement: XLDialectRequirement(
                        identity: XLDialectIdentifier(rawValue: "dialect-\(suffix)"),
                        capabilities: [.namedBindings]
                    ),
                    entities: ["entity-\(suffix)"],
                    parameterLayout: try XLParameterLayout(slots: [parameter])
                ),
                parameters: [
                    XLStaticQueryParameterMetadata(
                        identity: slotIdentity,
                        slot: parameter,
                        storageIdentifier: storage
                    ),
                ],
                results: try XLStaticQueryResultMetadata(
                    slots: [
                        XLStaticQueryResultSlot(
                            index: XLLogicalResultIndex(0),
                            identity: slotIdentity,
                            valueTypeIdentifier: valueType,
                            valueTypeName: "Diagnostic.Value",
                            nullability: .required,
                            codecIdentity: nil,
                            storageIdentifier: storage,
                            codingContext: XLValueCodingContext(
                                site: .result,
                                path: XLValueCodingPath("ignored")
                            )
                        ),
                    ]
                ),
                cardinality: .exactlyOne
            )
        }

        let first = try metadataDescriptor(
            definition: composed,
            slotIdentity: composedSlot,
            suffix: "caf\u{00e9}"
        )
        let second = try metadataDescriptor(
            definition: decomposed,
            slotIdentity: decomposedSlot,
            suffix: "cafe\u{0301}"
        )

        XCTAssertEqual(first.identity.canonicalBytes, second.identity.canonicalBytes)
        XCTAssertEqual(first.identity, second.identity)

        let sqlDefinition = try XLQueryDefinitionIdentity(
            path: ["tests", "exact-sql"],
            version: 1
        )
        func sqlDescriptor(_ sql: String) throws -> XLStaticQueryDescriptor {
            try XLStaticQueryDescriptor(
                definitionIdentity: sqlDefinition,
                statement: XLStaticStatementDefinition(
                    sql: sql,
                    dialectRequirement: XLDialectRequirement(
                        identity: XLDialectIdentifier(rawValue: "d")
                    )
                ),
                parameters: [],
                results: .empty,
                cardinality: .command
            )
        }
        let composedSQL = try sqlDescriptor("SELECT 'caf\u{00e9}'")
        let decomposedSQL = try sqlDescriptor("SELECT 'cafe\u{0301}'")

        XCTAssertNotEqual(composedSQL.statement, decomposedSQL.statement)
        XCTAssertNotEqual(composedSQL.identity.canonicalBytes, decomposedSQL.identity.canonicalBytes)
        XCTAssertNotEqual(composedSQL.identity, decomposedSQL.identity)
    }

    func testResultMetadataRejectsDuplicateAndNoncontiguousSlots() throws {
        let slot = try resultSlot(index: 0, identity: ["result", "value"])

        XCTAssertThrowsError(
            try XLStaticQueryResultMetadata(slots: [slot, slot])
        ) { error in
            guard case .conflictingResultIndex(
                let index,
                let existing,
                let incoming
            ) =
                error as? XLStaticQueryError else {
                return XCTFail("Expected duplicate result index, received \(error)")
            }
            XCTAssertEqual(index, slot.index)
            XCTAssertEqual(existing, slot)
            XCTAssertEqual(incoming, slot)
        }

        let gap = try resultSlot(index: 1, identity: ["result", "gap"])
        XCTAssertThrowsError(
            try XLStaticQueryResultMetadata(slots: [gap])
        ) { error in
            guard case .noncontiguousResultIndex(let actual, let expected) =
                error as? XLStaticQueryError else {
                return XCTFail("Expected result index gap, received \(error)")
            }
            XCTAssertEqual(actual, gap)
            XCTAssertEqual(expected, XLLogicalResultIndex(0))
        }
    }

    func testDescriptorValidationRejectsIncompleteOrIncompatibleMetadata() throws {
        let slot = intrinsicSlot(
            index: 0,
            key: .named("value"),
            type: "swift.int"
        )
        let statement = XLStaticStatementDefinition(
            sql: "SELECT :value",
            dialectRequirement: XLDialectRequirement(
                identity: XLSQLiteDialect.identity,
                capabilities: [.namedBindings]
            ),
            parameterLayout: try XLParameterLayout(slots: [slot])
        )
        let definition = try XLQueryDefinitionIdentity(
            path: ["tests", "invalid"],
            version: 1
        )

        XCTAssertThrowsError(
            try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: statement,
                parameters: [],
                results: try XLStaticQueryResultMetadata(
                    slots: [resultSlot(index: 0)]
                ),
                cardinality: .exactlyOne
            )
        ) { error in
            XCTAssertEqual(
                error as? XLStaticQueryError,
                .parameterMetadataCountMismatch(expected: 1, actual: 0)
            )
        }

        let parameterMetadata = XLStaticQueryParameterMetadata(
            identity: try XLQuerySlotIdentity(path: ["parameter", "value"]),
            slot: slot,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "integer")
        )

        let invalidSiteSlot = intrinsicSlot(
            index: 0,
            key: .named("value"),
            type: "swift.int",
            codingSite: .property
        )
        let invalidSiteParameter = XLStaticQueryParameterMetadata(
            identity: parameterMetadata.identity,
            slot: invalidSiteSlot,
            storageIdentifier: parameterMetadata.storageIdentifier
        )
        XCTAssertThrowsError(
            try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: XLStaticStatementDefinition(
                    sql: statement.sql,
                    dialectRequirement: statement.dialectRequirement,
                    parameterLayout: try XLParameterLayout(
                        slots: [invalidSiteSlot]
                    )
                ),
                parameters: [invalidSiteParameter],
                results: try XLStaticQueryResultMetadata(
                    slots: [resultSlot(index: 0)]
                ),
                cardinality: .exactlyOne
            )
        ) { error in
            XCTAssertEqual(
                error as? XLStaticQueryError,
                .invalidParameterCodingSite(
                    parameter: invalidSiteParameter,
                    actual: .property
                )
            )
        }

        let propertyResult = try resultSlot(
            index: 0,
            codingSite: .property
        )
        XCTAssertNoThrow(
            try XLStaticQueryResultMetadata(slots: [propertyResult])
        )
        for invalidSite in [XLValueCodingSite.parameter, .configuration] {
            let invalidResult = try resultSlot(
                index: 0,
                codingSite: invalidSite
            )
            XCTAssertThrowsError(
                try XLStaticQueryResultMetadata(slots: [invalidResult])
            ) { error in
                XCTAssertEqual(
                    error as? XLStaticQueryError,
                    .invalidResultCodingSite(
                        result: invalidResult,
                        actual: invalidSite
                    )
                )
            }
        }

        XCTAssertThrowsError(
            try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: XLStaticStatementDefinition(
                    sql: statement.sql,
                    dialectRequirement: XLDialectRequirement(
                        identity: XLSQLiteDialect.identity
                    ),
                    parameterLayout: statement.parameterLayout
                ),
                parameters: [parameterMetadata],
                results: try XLStaticQueryResultMetadata(
                    slots: [resultSlot(index: 0)]
                ),
                cardinality: .exactlyOne
            )
        ) { error in
            guard case .parameterCapabilityMissing(
                let actual,
                let capability
            ) = error as? XLStaticQueryError else {
                return XCTFail("Expected missing capability, received \(error)")
            }
            XCTAssertEqual(actual, parameterMetadata)
            XCTAssertEqual(capability, .namedBindings)
        }

        XCTAssertThrowsError(
            try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: statement,
                parameters: [
                    parameterMetadata,
                ],
                results: .empty,
                cardinality: .many
            )
        ) { error in
            XCTAssertEqual(
                error as? XLStaticQueryError,
                .rowQueryHasNoResults(cardinality: .many)
            )
        }

        XCTAssertThrowsError(
            try XLStaticQueryDescriptor(
                definitionIdentity: definition,
                statement: XLStaticStatementDefinition(
                    sql: "SELECT 1",
                    dialectRequirement: XLDialectRequirement(
                        identity: XLSQLiteDialect.identity
                    )
                ),
                parameters: [],
                results: .empty,
                cardinality: .command,
                identityFormatVersion: .init(rawValue: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? XLStaticQueryError,
                .unsupportedIdentityFormatVersion(.init(rawValue: 2))
            )
        }
    }
}


private extension SQLStaticQueryDescriptorTests {

    func makeDescriptor(
        entities: Set<String>,
        parametersReversed: Bool
    ) throws -> XLStaticQueryDescriptor {
        let first = intrinsicSlot(
            index: 0,
            key: .named("number"),
            type: "swift.int"
        )
        let second = intrinsicSlot(
            index: 1,
            key: .named("text"),
            type: "swift.string",
            codingPath: ["parameter", "text"]
        )
        let layout = try XLParameterLayout(slots: [second, first])
        let firstMetadata = XLStaticQueryParameterMetadata(
            identity: try XLQuerySlotIdentity(path: ["parameter", "number"]),
            slot: first,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "integer")
        )
        let secondMetadata = XLStaticQueryParameterMetadata(
            identity: try XLQuerySlotIdentity(path: ["parameter", "text"]),
            slot: second,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text")
        )
        let parameters = parametersReversed
            ? [secondMetadata, firstMetadata]
            : [firstMetadata, secondMetadata]
        return try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "canonical"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "SELECT :number, :text",
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    capabilities: [.namedBindings]
                ),
                entities: entities,
                parameterLayout: layout
            ),
            parameters: parameters,
            results: try XLStaticQueryResultMetadata(
                slots: [resultSlot(index: 0)]
            ),
            cardinality: .many
        )
    }

    func makeContextualDescriptor(
        definitionVersion: UInt64 = 1,
        codecKey: XLValueCodecKey = XLValueCodecKey(
            id: "tests.token",
            version: 1
        ),
        valueTypeName: String = "Tests.Token",
        codingPath: [String] = ["query", "token"],
        storage: String = "integer",
        sql: String = "SELECT :token",
        capabilities: XLDialectCapabilities = [.namedBindings],
        nullability: XLParameterNullability = .required,
        cardinality: XLQueryCardinality = .exactlyOne
    ) throws -> XLStaticQueryDescriptor {
        let valueType = XLValueTypeIdentifier(rawValue: "tests.token")
        let storageIdentifier = XLValueStorageIdentifier(rawValue: storage)
        let codec = XLValueCodecIdentity(
            key: codecKey,
            valueTypeIdentifier: valueType,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storageIdentifier
        )
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(codingPath)
        )
        let parameterSlot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("token"),
            valueTypeIdentifier: valueType,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codec,
            codingContext: context
        )
        let result = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(0),
            identity: try XLQuerySlotIdentity(path: ["result", "token"]),
            valueTypeIdentifier: valueType,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codec,
            storageIdentifier: storageIdentifier,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath(codingPath)
            )
        )
        return try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "contextual"],
                version: definitionVersion
            ),
            statement: XLStaticStatementDefinition(
                sql: sql,
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    capabilities: capabilities
                ),
                parameterLayout: try XLParameterLayout(slots: [parameterSlot])
            ),
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: try XLQuerySlotIdentity(path: ["parameter", "token"]),
                    slot: parameterSlot,
                    storageIdentifier: storageIdentifier
                ),
            ],
            results: try XLStaticQueryResultMetadata(slots: [result]),
            cardinality: cardinality
        )
    }

    func makeGoldenDescriptor() throws -> XLStaticQueryDescriptor {
        let parameter = intrinsicSlot(
            index: 0,
            key: .named("x"),
            type: "t",
            codingPath: ["p"]
        )
        return try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["q"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "S",
                dialectRequirement: XLDialectRequirement(
                    identity: XLDialectIdentifier(rawValue: "d"),
                    capabilities: [.namedBindings]
                ),
                entities: ["e"],
                parameterLayout: try XLParameterLayout(slots: [parameter])
            ),
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: try XLQuerySlotIdentity(path: ["p"]),
                    slot: parameter,
                    storageIdentifier: XLValueStorageIdentifier(rawValue: "i")
                ),
            ],
            results: try XLStaticQueryResultMetadata(
                slots: [
                    XLStaticQueryResultSlot(
                        index: XLLogicalResultIndex(0),
                        identity: try XLQuerySlotIdentity(path: ["r"]),
                        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "t"),
                        valueTypeName: "Diagnostic.T",
                        nullability: .required,
                        codecIdentity: nil,
                        storageIdentifier: XLValueStorageIdentifier(rawValue: "i"),
                        codingContext: XLValueCodingContext(
                            site: .result,
                            path: XLValueCodingPath("ignored")
                        )
                    ),
                ]
            ),
            cardinality: .exactlyOne
        )
    }

    func makeCommandDescriptor(
        dialect: String,
        minimumVersion: XLDialectVersion?,
        capabilities: XLDialectCapabilities
    ) throws -> XLStaticQueryDescriptor {
        try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "dialect-contract"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "COMMAND",
                dialectRequirement: XLDialectRequirement(
                    identity: XLDialectIdentifier(rawValue: dialect),
                    minimumVersion: minimumVersion,
                    capabilities: capabilities
                )
            ),
            parameters: [],
            results: .empty,
            cardinality: .command
        )
    }

    func intrinsicSlot(
        index: Int,
        key: XLBindingKey,
        type: String,
        nullability: XLParameterNullability = .required,
        codingPath: [String] = ["parameter", "number"],
        codingSite: XLValueCodingSite = .parameter
    ) -> XLParameterSlot {
        XLParameterSlot(
            index: XLLogicalParameterIndex(index),
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: type),
            valueTypeName: "Diagnostic.\(type)",
            nullability: nullability,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: codingSite,
                path: XLValueCodingPath(codingPath)
            )
        )
    }

    func resultSlot(
        index: Int,
        identity: [String] = ["result", "value"],
        codingSite: XLValueCodingSite = .result
    ) throws -> XLStaticQueryResultSlot {
        XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(index),
            identity: try XLQuerySlotIdentity(path: identity),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: "Swift.Int",
            nullability: .required,
            codecIdentity: nil,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
            codingContext: XLValueCodingContext(
                site: codingSite,
                path: XLValueCodingPath(identity)
            )
        )
    }
}


private func requireSendable<Value: Sendable>(_ value: Value) {
    _ = value
}
