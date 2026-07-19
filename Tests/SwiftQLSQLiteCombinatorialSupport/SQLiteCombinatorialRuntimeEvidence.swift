import Foundation
import GRDB


/// Stable SQLite process and schema identity captured from the replay database.
///
/// Lists are sorted and deduplicated on initialization. No timestamp, hostname,
/// process identifier, or temporary database path is retained.
public struct SQLiteRuntimeMetadata: Codable, Equatable, Sendable {
    public let sqliteVersion: String
    public let sqliteSourceID: String
    public let compileOptions: [String]
    public let functions: [SQLiteRuntimeFunction]
    public let collations: [String]
    public let moduleNames: [String]
    public let extensionNames: [String]
    public let schemaRowCount: Int
    public let schemaFNV1A64: String

    public init(
        sqliteVersion: String,
        sqliteSourceID: String,
        compileOptions: [String],
        functions: [SQLiteRuntimeFunction],
        collations: [String],
        moduleNames: [String],
        extensionNames: [String],
        schemaRowCount: Int,
        schemaFNV1A64: String
    ) {
        self.sqliteVersion = sqliteVersion
        self.sqliteSourceID = sqliteSourceID
        self.compileOptions = sortedUniqueRuntimeStrings(compileOptions)
        self.functions = Array(Set(functions)).sorted(by: SQLiteRuntimeFunction.canonicalOrder)
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

    /// Captures deterministic metadata from a concrete GRDB connection.
    ///
    /// SQLite exposes registered virtual-table modules, functions, and
    /// collations, but has no portable registry of arbitrary loaded-extension
    /// library names. Callers that own extension registration can provide those
    /// stable names explicitly; they are normalized with the discovered lists.
    public static func capture(
        from database: Database,
        extensionNames: [String] = []
    ) throws -> Self {
        try SQLiteRuntimeMetadataCollector.capture(
            from: database,
            extensionNames: extensionNames
        )
    }
}


public struct SQLiteRuntimeFunction: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let isBuiltIn: Bool
    public let kind: String
    public let encoding: String
    public let argumentCount: Int
    public let flags: Int64

    public init(
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


public enum SQLiteRuntimeMetadataCollector {
    public static func capture(
        from database: Database,
        extensionNames: [String] = []
    ) throws -> SQLiteRuntimeMetadata {
        guard let identity = try Row.fetchOne(
            database,
            sql: """
                SELECT
                    sqlite_version() AS sqlite_version,
                    sqlite_source_id() AS sqlite_source_id
                """
        ) else {
            throw SQLiteRuntimeMetadataError.missingSQLiteIdentity
        }

        let sqliteVersion: String = identity["sqlite_version"]
        let sqliteSourceID: String = identity["sqlite_source_id"]
        guard !sqliteVersion.isEmpty, !sqliteSourceID.isEmpty else {
            throw SQLiteRuntimeMetadataError.missingSQLiteIdentity
        }

        let compileOptions = try firstColumnStrings(database, pragma: "compile_options")
        let functions = try Row.fetchAll(database, sql: "PRAGMA function_list").map { row in
            let name: String = row["name"]
            let builtIn: Int = row["builtin"]
            let kind: String = row["type"]
            let encoding: String = row["enc"]
            let argumentCount: Int = row["narg"]
            let flags: Int64 = row["flags"]
            return SQLiteRuntimeFunction(
                name: name,
                isBuiltIn: builtIn != 0,
                kind: kind,
                encoding: encoding,
                argumentCount: argumentCount,
                flags: flags
            )
        }
        let collations = try namedPragmaEntries(database, pragma: "collation_list")
        let moduleNames = try namedPragmaEntries(database, pragma: "module_list")
        let schemaRows = try SQLiteSchemaFingerprintRow.fetchAll(from: database)

        return SQLiteRuntimeMetadata(
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
        try Row.fetchAll(database, sql: "PRAGMA \(pragma)").map { row in
            let value: String = row[0]
            return value
        }
    }

    private static func namedPragmaEntries(
        _ database: Database,
        pragma: String
    ) throws -> [String] {
        try Row.fetchAll(database, sql: "PRAGMA \(pragma)").map { row in
            let value: String = row["name"]
            return value
        }
    }

    fileprivate static func schemaFingerprint(
        rows: [SQLiteSchemaFingerprintRow]
    ) -> String {
        let rows = rows.sorted(by: SQLiteSchemaFingerprintRow.canonicalOrder)
        var hash = FNV1A64.offsetBasis
        for row in rows {
            for field in row.canonicalFields {
                FNV1A64.update(&hash, withLengthPrefixed: field)
            }
        }
        let unpadded = String(hash, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - unpadded.count) + unpadded
    }
}


public enum SQLiteRuntimeMetadataError: Error, Equatable, Sendable {
    case missingSQLiteIdentity
}


public enum SQLiteCombinatorialFailureStage: String, Codable, CaseIterable, Sendable {
    case prepare
    case execution
    case oracle
}


public struct SQLiteCombinatorialFailureSignature: Codable, Equatable, Sendable {
    public let errorType: String
    public let code: String?
    public let message: String

    public init(errorType: String, code: String?, message: String) {
        self.errorType = errorType
        self.code = code
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case code
        case message
    }
}


/// A self-contained failure artifact suitable for deterministic replay.
public struct SQLiteCombinatorialFailureRecord: Codable, Equatable, Sendable {
    public let testCase: SQLiteCombinatorialCase
    public let originalSQL: String
    public let failingSQL: String
    public let bindings: [SQLiteCombinatorialBinding]
    public let stage: SQLiteCombinatorialFailureStage
    public let failureSignature: SQLiteCombinatorialFailureSignature
    public let runtimeMetadata: SQLiteRuntimeMetadata
    public let reducedFromCaseID: String?
    public let reductionAttemptCount: Int
    public let reducedDimensions: [SQLiteCombinatorialCaseDimensionSelection]
    public let reproductionCommand: String

    public init(
        testCase: SQLiteCombinatorialCase,
        originalSQL: String,
        failingSQL: String,
        bindings: [SQLiteCombinatorialBinding],
        stage: SQLiteCombinatorialFailureStage,
        failureSignature: SQLiteCombinatorialFailureSignature,
        runtimeMetadata: SQLiteRuntimeMetadata,
        reducedFromCaseID: String?,
        reductionAttemptCount: Int,
        reducedDimensions: [SQLiteCombinatorialCaseDimensionSelection],
        reproductionCommand: String
    ) {
        self.testCase = testCase
        self.originalSQL = originalSQL
        self.failingSQL = failingSQL
        self.bindings = bindings.sorted(by: SQLiteCombinatorialBinding.canonicalOrder)
        self.stage = stage
        self.failureSignature = failureSignature
        self.runtimeMetadata = runtimeMetadata
        self.reducedFromCaseID = reducedFromCaseID
        self.reductionAttemptCount = reductionAttemptCount
        self.reducedDimensions = reducedDimensions
        self.reproductionCommand = reproductionCommand
    }

    private enum CodingKeys: String, CodingKey {
        case testCase = "case"
        case originalSQL = "original_sql"
        case failingSQL = "failing_sql"
        case bindings
        case stage
        case failureSignature = "failure_signature"
        case runtimeMetadata = "runtime_metadata"
        case reducedFromCaseID = "reduced_from_case_id"
        case reductionAttemptCount = "reduction_attempt_count"
        case reducedDimensions = "reduced_dimensions"
        case reproductionCommand = "reproduction_command"
    }

    public func canonicalJSONData() throws -> Data {
        try SQLiteCombinatorialCanonicalJSON.encode(self)
    }
}


public enum SQLiteCombinatorialCaseVerdict: String, Codable, CaseIterable, Sendable {
    case passed
    case failed
    case skipped
}


/// One measured runtime outcome. It is intentionally separate from the manifest.
public struct SQLiteCombinatorialCaseOutcome: Codable, Equatable, Sendable {
    public let caseID: String
    public let stage: SQLiteCombinatorialFailureStage
    public let verdict: SQLiteCombinatorialCaseVerdict
    public let elapsedMilliseconds: Double
    public let failure: SQLiteCombinatorialFailureRecord?

    public init(
        caseID: String,
        stage: SQLiteCombinatorialFailureStage,
        verdict: SQLiteCombinatorialCaseVerdict,
        elapsedMilliseconds: Double,
        failure: SQLiteCombinatorialFailureRecord?
    ) {
        self.caseID = caseID
        self.stage = stage
        self.verdict = verdict
        self.elapsedMilliseconds = elapsedMilliseconds
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case caseID = "case_id"
        case stage
        case verdict
        case elapsedMilliseconds = "elapsed_ms"
        case failure
    }
}


/// Runtime evidence tied back to the exact canonical manifest bytes.
public struct SQLiteCombinatorialRuntimeReport: Codable, Equatable, Sendable {
    public let manifestSHA256: String
    public let manifestCaseCount: Int
    public let hardBounds: SQLiteCombinatorialHardBounds
    public let maximumRuntimeMilliseconds: Int
    public let totalElapsedMilliseconds: Double
    public let runtimeMetadata: SQLiteRuntimeMetadata
    public let outcomes: [SQLiteCombinatorialCaseOutcome]

    public init(
        manifestSHA256: String,
        manifestCaseCount: Int,
        hardBounds: SQLiteCombinatorialHardBounds,
        maximumRuntimeMilliseconds: Int,
        totalElapsedMilliseconds: Double,
        runtimeMetadata: SQLiteRuntimeMetadata,
        outcomes: [SQLiteCombinatorialCaseOutcome]
    ) {
        self.manifestSHA256 = manifestSHA256.lowercased()
        self.manifestCaseCount = manifestCaseCount
        self.hardBounds = hardBounds
        self.maximumRuntimeMilliseconds = maximumRuntimeMilliseconds
        self.totalElapsedMilliseconds = totalElapsedMilliseconds
        self.runtimeMetadata = runtimeMetadata
        self.outcomes = outcomes.sorted {
            if $0.caseID != $1.caseID {
                return $0.caseID < $1.caseID
            }
            return $0.stage.rawValue < $1.stage.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case manifestSHA256 = "manifest_sha256"
        case manifestCaseCount = "manifest_case_count"
        case hardBounds = "hard_bounds"
        case maximumRuntimeMilliseconds = "maximum_runtime_ms"
        case totalElapsedMilliseconds = "total_elapsed_ms"
        case runtimeMetadata = "runtime_metadata"
        case outcomes
    }

    public var satisfiesRuntimeBound: Bool {
        maximumRuntimeMilliseconds > 0
            && totalElapsedMilliseconds >= 0
            && totalElapsedMilliseconds <= Double(maximumRuntimeMilliseconds)
    }

    public func canonicalJSONData() throws -> Data {
        try SQLiteCombinatorialCanonicalJSON.encode(self)
    }
}


private struct SQLiteSchemaFingerprintRow: Equatable {
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


private enum FNV1A64 {
    static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    static let prime: UInt64 = 1_099_511_628_211

    static func update(_ hash: inout UInt64, withLengthPrefixed field: String) {
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
