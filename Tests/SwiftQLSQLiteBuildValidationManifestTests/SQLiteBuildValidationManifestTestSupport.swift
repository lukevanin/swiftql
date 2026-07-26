import Foundation
import SwiftQLCore
@testable import SwiftQLSQLiteBuildValidationManifest


/// Shared fixture construction for the #292 manifest test suite.
enum SQLiteBuildValidationManifestTestSupport {

    static func schemaSnapshot(
        identifier: String = "northwind-fixture",
        databaseSHA256: String = String(repeating: "a", count: 64),
        databaseByteCount: Int = 602112,
        schemaRowCount: Int = 37,
        schemaFingerprint: String = String(repeating: "b", count: 16)
    ) -> SQLiteBuildValidationSchemaSnapshot {
        SQLiteBuildValidationSchemaSnapshot(
            identifier: identifier,
            databaseSHA256: databaseSHA256,
            databaseByteCount: databaseByteCount,
            schemaRowCount: schemaRowCount,
            schemaFingerprint: schemaFingerprint
        )
    }

    static func manifest(
        conformanceInventoryVersion: String = "190.1.0",
        combinatorialManifestVersion: String = "c191-v2",
        schemaSnapshot: SQLiteBuildValidationSchemaSnapshot? = nil,
        queries: [SQLiteBuildValidationQueryEntry]
    ) -> SQLiteBuildValidationManifest {
        SQLiteBuildValidationManifest(
            conformanceInventoryVersion: conformanceInventoryVersion,
            combinatorialManifestVersion: combinatorialManifestVersion,
            schemaSnapshot: schemaSnapshot ?? Self.schemaSnapshot(),
            queries: queries
        )
    }

    static func query(
        id: String = "query.id",
        sql: String = "SELECT 1",
        conformanceFeatureIDs: [String] = [],
        conformanceCaseIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        parameters: [SQLiteBuildValidationParameterEntry] = [],
        results: [SQLiteBuildValidationResultEntry] = [],
        requiredCapabilities: [String] = []
    ) -> SQLiteBuildValidationQueryEntry {
        SQLiteBuildValidationQueryEntry(
            id: id,
            definitionIdentity: "tests/\(id)@1",
            descriptorIdentity: "swiftql-query-v1-deadbeef",
            conformanceFeatureIDs: conformanceFeatureIDs,
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            sql: sql,
            dialectIdentifier: XLSQLiteDialect.identity.rawValue,
            cardinality: XLQueryCardinality.exactlyOne.rawValue,
            parameters: parameters,
            results: results.isEmpty ? [Self.result()] : results,
            requiredCapabilities: requiredCapabilities
        )
    }

    static func parameter(
        logicalIndex: Int = 0,
        physicalIndex: Int = 1,
        identity: String = "parameter/first",
        keyKind: SQLiteBuildValidationParameterEntry.KeyKind = .named,
        keyName: String? = "first",
        keyIndex: Int? = nil,
        codec: SQLiteBuildValidationCodecReference? = nil
    ) -> SQLiteBuildValidationParameterEntry {
        SQLiteBuildValidationParameterEntry(
            logicalIndex: logicalIndex,
            physicalIndex: physicalIndex,
            identity: identity,
            keyKind: keyKind,
            keyName: keyName,
            keyIndex: keyIndex,
            valueTypeIdentifier: "swift.int",
            valueTypeName: "Swift.Int",
            nullability: "required",
            codec: codec,
            storageIdentifier: "integer"
        )
    }

    static func result(
        index: Int = 0,
        identity: String = "result/first",
        declaredAlias: String? = "first",
        codec: SQLiteBuildValidationCodecReference? = nil
    ) -> SQLiteBuildValidationResultEntry {
        SQLiteBuildValidationResultEntry(
            index: index,
            identity: identity,
            declaredAlias: declaredAlias,
            valueTypeIdentifier: "swift.int",
            valueTypeName: "Swift.Int",
            nullability: "required",
            codec: codec,
            storageIdentifier: "integer"
        )
    }

    static func codec(
        keyID: String = "tests.codec",
        keyVersion: UInt = 1,
        valueTypeIdentifier: String = "tests.token",
        dialectIdentifier: String = XLSQLiteDialect.identity.rawValue,
        storageIdentifier: String = "text"
    ) -> SQLiteBuildValidationCodecReference {
        SQLiteBuildValidationCodecReference(
            keyID: keyID,
            keyVersion: keyVersion,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: dialectIdentifier,
            storageIdentifier: storageIdentifier
        )
    }

    static func descriptorCodec() -> XLValueCodecIdentity {
        XLValueCodecIdentity(
            key: XLValueCodecKey(id: "tests.codec.token", version: 7),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.token"),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text")
        )
    }

    /// A descriptor mixing an indexed and a named parameter, matching the SQL
    /// physical placeholder ordering exercised by the #132 research prototype.
    static func mixedBindingDescriptor(
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
                path: ["tests", "build-validation", "manifest-projection"],
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
                    nullability: .required,
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
