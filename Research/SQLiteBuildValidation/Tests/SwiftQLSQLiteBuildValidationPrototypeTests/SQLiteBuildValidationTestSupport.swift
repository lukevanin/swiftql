import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures

@testable import SwiftQLSQLiteBuildValidationPrototype


enum SQLiteBuildValidationTestSupport {
    static let northwindSchemaSHA256 =
        "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8"
    static let northwindSchemaByteCount = 602_112
    static let northwindSchemaRowCount = 37
    static let northwindSchemaFNV1A64 = "e2c8fadbd38c2313"

    static func schema(
        databaseSHA256: String = northwindSchemaSHA256,
        databaseByteCount: Int = northwindSchemaByteCount,
        schemaRowCount: Int = northwindSchemaRowCount,
        schemaFNV1A64: String = northwindSchemaFNV1A64
    ) -> SQLiteBuildValidationSchemaInput {
        SQLiteBuildValidationSchemaInput(
            identifier: "northwind.issue-254",
            databaseSHA256: databaseSHA256,
            databaseByteCount: databaseByteCount,
            schemaRowCount: schemaRowCount,
            schemaFNV1A64: schemaFNV1A64
        )
    }

    static func codec(
        keyID: String = "tests.codec.token",
        keyVersion: UInt64 = 7,
        valueTypeIdentifier: String = "tests.token",
        dialectIdentifier: String = XLSQLiteDialect.identity.rawValue,
        storageIdentifier: String = "text"
    ) -> SQLiteBuildValidationCodec {
        SQLiteBuildValidationCodec(
            keyID: keyID,
            keyVersion: keyVersion,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: dialectIdentifier,
            storageIdentifier: storageIdentifier
        )
    }

    static func parameter(
        logicalIndex: Int = 0,
        physicalIndex: Int = 1,
        identity: String = "parameter/value",
        keyKind: SQLiteBuildValidationParameter.KeyKind = .named,
        keyName: String? = "value",
        keyIndex: Int? = nil,
        valueTypeIdentifier: String = "swift.int",
        valueTypeName: String = "Swift.Int",
        nullability: String = "required",
        codec: SQLiteBuildValidationCodec? = nil,
        storageIdentifier: String = "integer"
    ) -> SQLiteBuildValidationParameter {
        SQLiteBuildValidationParameter(
            logicalIndex: logicalIndex,
            physicalIndex: physicalIndex,
            identity: identity,
            keyKind: keyKind,
            keyName: keyName,
            keyIndex: keyIndex,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codec: codec,
            storageIdentifier: storageIdentifier
        )
    }

    static func result(
        index: Int = 0,
        identity: String = "result/value",
        expectedAlias: String? = "value",
        valueTypeIdentifier: String = "swift.int",
        valueTypeName: String = "Swift.Int",
        nullability: String = "required",
        codec: SQLiteBuildValidationCodec? = nil,
        storageIdentifier: String = "integer"
    ) -> SQLiteBuildValidationResult {
        SQLiteBuildValidationResult(
            index: index,
            identity: identity,
            expectedAlias: expectedAlias,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codec: codec,
            storageIdentifier: storageIdentifier
        )
    }

    static func query(
        id: String = "tests.query",
        definitionIdentity: String? = nil,
        descriptorIdentity: String? = nil,
        conformanceCaseIDs: [String] = [],
        inventoryFeatureIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        sql: String = "SELECT 1 AS value",
        cardinality: UInt8 = XLQueryCardinality.exactlyOne.rawValue,
        parameters: [SQLiteBuildValidationParameter] = [],
        results: [SQLiteBuildValidationResult] = [result()],
        requiredCapabilities: [String] = []
    ) -> SQLiteBuildValidationQuery {
        SQLiteBuildValidationQuery(
            id: id,
            definitionIdentity: definitionIdentity ?? "tests/\(id)@1",
            descriptorIdentity: descriptorIdentity ?? "swiftql-query-v1-\(id)",
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            inventoryFeatureIDs: inventoryFeatureIDs,
            sql: sql,
            cardinality: cardinality,
            parameters: parameters,
            results: results,
            requiredCapabilities: requiredCapabilities.map {
                SQLiteBuildValidationCapabilityRequirement(id: $0)
            }
        )
    }

    static func plan(
        schema: SQLiteBuildValidationSchemaInput = schema(),
        inventoryVersion: String = "1.3.0",
        queries: [SQLiteBuildValidationQuery] = [query()]
    ) -> SQLiteBuildValidationPlan {
        SQLiteBuildValidationPlan(
            inventoryVersion: inventoryVersion,
            schema: schema,
            queries: queries
        )
    }

    static func withNorthwindURL<Result>(
        _ body: (URL) throws -> Result
    ) throws -> Result {
        try NorthwindFixture.withTemporaryCopy { copy in
            try body(copy.url)
        }
    }

    /// Places an untouched canonical snapshot at a second unique path inside
    /// the fixture's temporary directory. The fixture pool never opens this
    /// path, so the validator owns its complete connection lifecycle and no
    /// WAL/SHM sidecars exist before validation begins.
    static func withValidatorOwnedNorthwindURL<Result>(
        _ body: (URL) throws -> Result
    ) throws -> Result {
        try NorthwindFixture.withTemporaryCopy { copy in
            let canonicalPool = try NorthwindFixture.validatedReadOnlyPool()
            defer { try? canonicalPool.close() }

            let sourceURL = URL(fileURLWithPath: canonicalPool.path)
            let validatorURL = copy.url.deletingLastPathComponent()
                .appendingPathComponent("validator-owned-northwind.db")
            try FileManager.default.copyItem(at: sourceURL, to: validatorURL)
            return try body(validatorURL)
        }
    }

    static func withReadOnlyNorthwindDatabase<Result>(
        _ body: (Database) throws -> Result
    ) throws -> Result {
        try withNorthwindURL { url in
            var configuration = Configuration()
            configuration.label = "SwiftQLSQLiteBuildValidationPrototypeTests.raw-probe"
            configuration.readonly = true
            configuration.prepareDatabase { database in
                try database.execute(sql: "PRAGMA query_only = ON")
            }
            let queue = try DatabaseQueue(
                path: url.path,
                configuration: configuration
            )
            defer { try? queue.close() }
            return try queue.read(body)
        }
    }
}
