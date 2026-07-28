import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
@testable import SwiftQLSQLiteBuildValidationValidator


enum SQLiteBuildValidationValidatorTestSupport {
    static let northwindSchemaSHA256 =
        "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8"
    static let northwindSchemaByteCount = 602_112
    static let northwindSchemaRowCount = 37
    static let northwindSchemaFingerprint = "e2c8fadbd38c2313"

    static func schemaSnapshot(
        databaseSHA256: String = northwindSchemaSHA256,
        databaseByteCount: Int = northwindSchemaByteCount,
        schemaRowCount: Int = northwindSchemaRowCount,
        schemaFingerprint: String = northwindSchemaFingerprint
    ) -> SQLiteBuildValidationSchemaSnapshot {
        SQLiteBuildValidationSchemaSnapshot(
            identifier: "northwind.issue-254",
            databaseSHA256: databaseSHA256,
            databaseByteCount: databaseByteCount,
            schemaRowCount: schemaRowCount,
            schemaFingerprint: schemaFingerprint
        )
    }

    static func query(
        id: String = "tests.query",
        sql: String = "SELECT 1 AS value",
        cardinality: UInt8 = XLQueryCardinality.exactlyOne.rawValue,
        parameters: [SQLiteBuildValidationParameterEntry] = [],
        results: [SQLiteBuildValidationResultEntry] = [result()],
        requiredCapabilities: [String] = []
    ) -> SQLiteBuildValidationQueryEntry {
        SQLiteBuildValidationQueryEntry(
            id: id,
            definitionIdentity: "tests/\(id)@1",
            descriptorIdentity: "swiftql-query-v1-\(id)",
            sql: sql,
            dialectIdentifier: XLSQLiteDialect.identity.rawValue,
            cardinality: cardinality,
            parameters: parameters,
            results: results,
            requiredCapabilities: requiredCapabilities
        )
    }

    static func parameter(
        logicalIndex: Int = 0,
        physicalIndex: Int = 1,
        identity: String = "parameter/value",
        keyKind: SQLiteBuildValidationParameterEntry.KeyKind = .named,
        keyName: String? = "value",
        keyIndex: Int? = nil,
        valueTypeIdentifier: String = "swift.int",
        valueTypeName: String = "Swift.Int",
        nullability: String = "required",
        codec: SQLiteBuildValidationCodecReference? = nil,
        storageIdentifier: String = "integer"
    ) -> SQLiteBuildValidationParameterEntry {
        SQLiteBuildValidationParameterEntry(
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
        declaredAlias: String? = "value",
        valueTypeIdentifier: String = "swift.int",
        valueTypeName: String = "Swift.Int",
        nullability: String = "required",
        codec: SQLiteBuildValidationCodecReference? = nil,
        storageIdentifier: String = "integer"
    ) -> SQLiteBuildValidationResultEntry {
        SQLiteBuildValidationResultEntry(
            index: index,
            identity: identity,
            declaredAlias: declaredAlias,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codec: codec,
            storageIdentifier: storageIdentifier
        )
    }

    static func manifest(
        schemaSnapshot: SQLiteBuildValidationSchemaSnapshot = schemaSnapshot(),
        queries: [SQLiteBuildValidationQueryEntry] = [query()]
    ) -> SQLiteBuildValidationManifest {
        SQLiteBuildValidationManifest(
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: schemaSnapshot,
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
            configuration.label = "SwiftQLSQLiteBuildValidationValidatorTests.raw-probe"
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
