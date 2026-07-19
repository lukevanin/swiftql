import Foundation
import GRDB


/// Stable process, connection-capability, and schema identity for one build
/// validation run.
///
/// Every encoded list is sorted and deduplicated. No timestamp, hostname,
/// process identifier, or database path is retained.
package struct SQLiteBuildValidationRuntimeMetadata:
    Codable,
    Equatable,
    Sendable
{
    package let sqliteVersion: String
    package let sqliteSourceID: String
    package let compileOptions: [String]
    package let functions: [SQLiteBuildValidationRuntimeFunction]
    package let collations: [String]
    package let moduleNames: [String]
    package let extensionNames: [String]
    package let schemaRowCount: Int
    package let schemaFNV1A64: String

    package init(
        sqliteVersion: String,
        sqliteSourceID: String,
        compileOptions: [String],
        functions: [SQLiteBuildValidationRuntimeFunction],
        collations: [String],
        moduleNames: [String],
        extensionNames: [String],
        schemaRowCount: Int,
        schemaFNV1A64: String
    ) {
        self.sqliteVersion = sqliteVersion
        self.sqliteSourceID = sqliteSourceID
        self.compileOptions = sortedUniqueRuntimeStrings(compileOptions)
        self.functions = Array(Set(functions)).sorted(
            by: SQLiteBuildValidationRuntimeFunction.canonicalOrder
        )
        self.collations = sortedUniqueRuntimeStrings(collations)
        self.moduleNames = sortedUniqueRuntimeStrings(moduleNames)
        self.extensionNames = sortedUniqueRuntimeStrings(extensionNames)
        self.schemaRowCount = schemaRowCount
        self.schemaFNV1A64 = schemaFNV1A64.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case sqliteVersion = "sqlite_version"
        case sqliteSourceID = "sqlite_source_id"
        case compileOptions = "compile_options"
        case functions
        case collations
        case moduleNames = "module_names"
        case extensionNames = "extension_names"
        case schemaRowCount = "schema_row_count"
        case schemaFNV1A64 = "schema_fnv1a_64"
    }

    /// Computed sets are for capability lookup only and are not serialized.
    package var compileOptionCapabilities: Set<String> {
        Set(compileOptions)
    }

    package var functionCapabilities: Set<SQLiteBuildValidationRuntimeFunction> {
        Set(functions)
    }

    package var collationCapabilities: Set<String> {
        Set(collations)
    }

    package var moduleCapabilities: Set<String> {
        Set(moduleNames)
    }

    package var extensionCapabilities: Set<String> {
        Set(extensionNames)
    }

    package func hasFunction(
        named name: String,
        argumentCount: Int? = nil
    ) -> Bool {
        let requiredName = sqliteASCIIFolded(name)
        return functions.contains { function in
            guard sqliteASCIIFolded(function.name) == requiredName else {
                return false
            }
            guard let argumentCount else {
                return true
            }
            return function.argumentCount == argumentCount
                || function.argumentCount == -1
        }
    }

    package func hasCollation(named name: String) -> Bool {
        let requiredName = sqliteASCIIFolded(name)
        return collations.contains {
            sqliteASCIIFolded($0) == requiredName
        }
    }

    package func hasModule(named name: String) -> Bool {
        moduleCapabilities.contains(name)
    }

    package func hasCompileOption(_ option: String) -> Bool {
        compileOptionCapabilities.contains(option)
    }

    package func hasExtension(named name: String) -> Bool {
        extensionCapabilities.contains(name)
    }
}


package struct SQLiteBuildValidationRuntimeFunction:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    package let name: String
    package let isBuiltIn: Bool
    package let kind: String
    package let encoding: String
    package let argumentCount: Int
    package let flags: Int64

    package init(
        name: String,
        isBuiltIn: Bool,
        kind: String,
        encoding: String,
        argumentCount: Int,
        flags: Int64
    ) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.kind = kind
        self.encoding = encoding
        self.argumentCount = argumentCount
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case isBuiltIn = "is_built_in"
        case kind
        case encoding
        case argumentCount = "argument_count"
        case flags
    }

    fileprivate static func canonicalOrder(
        _ lhs: SQLiteBuildValidationRuntimeFunction,
        _ rhs: SQLiteBuildValidationRuntimeFunction
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


package enum SQLiteBuildValidationRuntimeError: Error, Equatable, Sendable {
    case missingSQLiteIdentity
}


package enum SQLiteBuildValidationRuntime {
    /// Captures capabilities from the same validator-owned connection used by
    /// raw preparation. SQLite can enumerate registered functions, collations,
    /// and virtual-table modules, but not arbitrary loaded-extension library
    /// names. Callers must therefore supply stable extension names explicitly.
    package static func capture(
        from database: Database,
        extensionNames: [String] = []
    ) throws -> SQLiteBuildValidationRuntimeMetadata {
        guard let identity = try Row.fetchOne(
            database,
            sql: """
                SELECT
                    sqlite_version() AS sqlite_version,
                    sqlite_source_id() AS sqlite_source_id
                """
        ) else {
            throw SQLiteBuildValidationRuntimeError.missingSQLiteIdentity
        }

        let sqliteVersion: String = identity["sqlite_version"]
        let sqliteSourceID: String = identity["sqlite_source_id"]
        guard !sqliteVersion.isEmpty, !sqliteSourceID.isEmpty else {
            throw SQLiteBuildValidationRuntimeError.missingSQLiteIdentity
        }

        let compileOptions = try firstColumnStrings(
            database,
            pragma: "compile_options"
        )
        let functions = try Row.fetchAll(
            database,
            sql: "PRAGMA function_list"
        ).map { row in
            let name: String = row["name"]
            let builtIn: Int = row["builtin"]
            let kind: String = row["type"]
            let encoding: String = row["enc"]
            let argumentCount: Int = row["narg"]
            let flags: Int64 = row["flags"]
            return SQLiteBuildValidationRuntimeFunction(
                name: name,
                isBuiltIn: builtIn != 0,
                kind: kind,
                encoding: encoding,
                argumentCount: argumentCount,
                flags: flags
            )
        }
        let collations = try namedPragmaEntries(
            database,
            pragma: "collation_list"
        )
        let moduleNames = try namedPragmaEntries(
            database,
            pragma: "module_list"
        )
        let schemaRows = try SQLiteBuildValidationSchemaRow.fetchAll(
            from: database
        )

        return SQLiteBuildValidationRuntimeMetadata(
            sqliteVersion: sqliteVersion,
            sqliteSourceID: sqliteSourceID,
            compileOptions: compileOptions,
            functions: functions,
            collations: collations,
            moduleNames: moduleNames,
            extensionNames: extensionNames,
            schemaRowCount: schemaRows.count,
            schemaFNV1A64: schemaFingerprint(rows: schemaRows)
        )
    }

    private static func firstColumnStrings(
        _ database: Database,
        pragma: String
    ) throws -> [String] {
        try Row.fetchAll(
            database,
            sql: "PRAGMA \(pragma)"
        ).map { row in
            let value: String = row[0]
            return value
        }
    }

    private static func namedPragmaEntries(
        _ database: Database,
        pragma: String
    ) throws -> [String] {
        try Row.fetchAll(
            database,
            sql: "PRAGMA \(pragma)"
        ).map { row in
            let value: String = row["name"]
            return value
        }
    }

    private static func schemaFingerprint(
        rows: [SQLiteBuildValidationSchemaRow]
    ) -> String {
        let rows = rows.sorted(
            by: SQLiteBuildValidationSchemaRow.canonicalOrder
        )
        var hash = SQLiteBuildValidationFNV1A64.offsetBasis
        for row in rows {
            for field in row.canonicalFields {
                SQLiteBuildValidationFNV1A64.update(
                    &hash,
                    withLengthPrefixed: field
                )
            }
        }
        let unpadded = String(hash, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - unpadded.count) + unpadded
    }
}


private struct SQLiteBuildValidationSchemaRow: Equatable {
    let type: String
    let name: String
    let tableName: String
    let rootPage: Int64
    let sql: String

    var canonicalFields: [String] {
        [type, name, tableName, String(rootPage), sql]
    }

    static func fetchAll(from database: Database) throws -> [Self] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT
                    type,
                    name,
                    tbl_name,
                    rootpage,
                    COALESCE(sql, '') AS sql
                FROM sqlite_schema
                ORDER BY
                    type COLLATE BINARY,
                    name COLLATE BINARY,
                    tbl_name COLLATE BINARY,
                    rootpage,
                    sql COLLATE BINARY
                """
        ).map { row in
            let type: String = row["type"]
            let name: String = row["name"]
            let tableName: String = row["tbl_name"]
            let rootPage: Int64 = row["rootpage"]
            let sql: String = row["sql"]
            return Self(
                type: type,
                name: name,
                tableName: tableName,
                rootPage: rootPage,
                sql: sql
            )
        }
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.type != rhs.type {
            return lhs.type < rhs.type
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        if lhs.tableName != rhs.tableName {
            return lhs.tableName < rhs.tableName
        }
        if lhs.rootPage != rhs.rootPage {
            return lhs.rootPage < rhs.rootPage
        }
        return lhs.sql < rhs.sql
    }
}


private enum SQLiteBuildValidationFNV1A64 {
    static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    static let prime: UInt64 = 1_099_511_628_211

    static func update(
        _ hash: inout UInt64,
        withLengthPrefixed field: String
    ) {
        let bytes = Array(field.utf8)
        update(&hash, bytes: Array(String(bytes.count).utf8))
        update(&hash, bytes: [0x3A])
        update(&hash, bytes: bytes)
        update(&hash, bytes: [0x0A])
    }

    private static func update(_ hash: inout UInt64, bytes: [UInt8]) {
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= prime
        }
    }
}


private func sortedUniqueRuntimeStrings(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}


/// SQLite compares function and collation names with ASCII case folding.
private func sqliteASCIIFolded(_ value: String) -> String {
    String(decoding: value.utf8.map { byte in
        if byte >= 0x41, byte <= 0x5A {
            return byte + 0x20
        }
        return byte
    }, as: UTF8.self)
}
