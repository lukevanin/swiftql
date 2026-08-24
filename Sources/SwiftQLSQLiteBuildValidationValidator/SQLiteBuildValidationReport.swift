import Foundation
import SwiftQLSQLiteBuildValidationManifest


/// A single query's or run's overall pass/fail/unsupported classification.
///
/// Only `passed` is success. `failed` and `unsupported` both fail the
/// validation gate — an absent or unavailable capability must never report
/// as `passed`.
public enum SQLiteBuildValidationVerdict: String, Codable, CaseIterable, Sendable {
    case passed
    case failed
    case unsupported
}


/// Explicit caller-supplied evidence used during one validation run.
///
/// The encoded form is deliberately limited to stable identifiers: it does
/// not retain paths, timestamps, process identity, or host identity. Every
/// list is sorted and deduplicated so semantically equivalent invocations
/// produce byte-identical canonical reports.
public struct SQLiteBuildValidationEnvironment:
    Codable,
    Equatable,
    Sendable
{
    public let codecIdentifiers: [String]
    public let extensionNames: [String]
    public let capabilityIDs: [String]

    public init(
        codecIdentifiers: [String] = [],
        extensionNames: [String] = [],
        capabilityIDs: [String] = []
    ) {
        self.codecIdentifiers = Self.sortedUnique(codecIdentifiers)
        // Fold before deduping: extension-name matching is ASCII
        // case-insensitive (SQLiteBuildValidationRuntimeMetadata.hasExtension),
        // so "MyExt" and "myext" are the same semantic requirement and must
        // not survive as two distinct entries in the canonical report.
        self.extensionNames = Self.sortedUnique(extensionNames.map(sqliteASCIIFolded))
        self.capabilityIDs = Self.sortedUnique(capabilityIDs)
    }

    public init(
        codecIdentities: [SQLiteBuildValidationCodecReference],
        extensionNames: [String] = [],
        capabilityIDs: [String] = []
    ) {
        self.init(
            codecIdentifiers: codecIdentities.map(\.stableIdentifier),
            extensionNames: extensionNames,
            capabilityIDs: capabilityIDs
        )
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case codecIdentifiers = "codec_identifiers"
        case extensionNames = "extension_names"
        case capabilityIDs = "capability_ids"
    }
}


public struct SQLiteBuildValidationDiagnostic: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, CaseIterable, Sendable {
        case schema
        case runtime
        case codec
        case capability
        case prepare
        case parameter
        case result
    }

    public let verdict: SQLiteBuildValidationVerdict
    public let stage: Stage
    public let code: String
    public let message: String
    public let queryID: String?
    public let definitionIdentity: String?
    public let descriptorIdentity: String?
    public let conformanceFeatureIDs: [String]
    public let conformanceCaseIDs: [String]
    public let northwindAnchorCaseIDs: [String]
    public let sqliteResultCode: Int32?
    public let sqliteExtendedResultCode: Int32?

    public init(
        verdict: SQLiteBuildValidationVerdict,
        stage: Stage,
        code: String,
        message: String,
        query: SQLiteBuildValidationQueryEntry? = nil,
        sqliteResultCode: Int32? = nil,
        sqliteExtendedResultCode: Int32? = nil
    ) {
        precondition(verdict != .passed, "A diagnostic cannot carry a passed verdict.")
        self.verdict = verdict
        self.stage = stage
        self.code = code
        self.message = message
        self.queryID = query?.id
        self.definitionIdentity = query?.definitionIdentity
        self.descriptorIdentity = query?.descriptorIdentity
        self.conformanceFeatureIDs = query?.conformanceFeatureIDs ?? []
        self.conformanceCaseIDs = query?.conformanceCaseIDs ?? []
        self.northwindAnchorCaseIDs = query?.northwindAnchorCaseIDs ?? []
        self.sqliteResultCode = sqliteResultCode
        self.sqliteExtendedResultCode = sqliteExtendedResultCode
    }

    static func canonicalOrder(
        _ lhs: Self,
        _ rhs: Self
    ) -> Bool {
        let lhsKey = [
            lhs.queryID ?? "",
            lhs.code,
            lhs.stage.rawValue,
            String(lhs.sqliteResultCode ?? 0),
            String(lhs.sqliteExtendedResultCode ?? 0),
            lhs.message,
        ]
        let rhsKey = [
            rhs.queryID ?? "",
            rhs.code,
            rhs.stage.rawValue,
            String(rhs.sqliteResultCode ?? 0),
            String(rhs.sqliteExtendedResultCode ?? 0),
            rhs.message,
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey)
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case stage
        case code
        case message
        case queryID = "query_id"
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case conformanceFeatureIDs = "conformance_feature_ids"
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case sqliteResultCode = "sqlite_result_code"
        case sqliteExtendedResultCode = "sqlite_extended_result_code"
    }
}


public struct SQLiteBuildValidationQueryOutcome:
    Codable,
    Equatable,
    Sendable
{
    public let queryID: String
    public let definitionIdentity: String
    public let descriptorIdentity: String
    public let conformanceFeatureIDs: [String]
    public let conformanceCaseIDs: [String]
    public let northwindAnchorCaseIDs: [String]
    public let verdict: SQLiteBuildValidationVerdict
    public let placeholderAnalysis: SQLiteBuildValidationValidatorPlaceholderAnalysis
    public let preparedShape: SQLitePreparedStatementShape?
    public let diagnostics: [SQLiteBuildValidationDiagnostic]

    public init(
        query: SQLiteBuildValidationQueryEntry,
        placeholderAnalysis: SQLiteBuildValidationValidatorPlaceholderAnalysis,
        preparedShape: SQLitePreparedStatementShape?,
        diagnostics: [SQLiteBuildValidationDiagnostic]
    ) {
        let diagnostics = diagnostics.sorted(
            by: SQLiteBuildValidationDiagnostic.canonicalOrder
        )
        self.queryID = query.id
        self.definitionIdentity = query.definitionIdentity
        self.descriptorIdentity = query.descriptorIdentity
        self.conformanceFeatureIDs = query.conformanceFeatureIDs
        self.conformanceCaseIDs = query.conformanceCaseIDs
        self.northwindAnchorCaseIDs = query.northwindAnchorCaseIDs
        self.verdict = Self.verdict(for: diagnostics)
        self.placeholderAnalysis = placeholderAnalysis
        self.preparedShape = preparedShape
        self.diagnostics = diagnostics
    }

    private static func verdict(
        for diagnostics: [SQLiteBuildValidationDiagnostic]
    ) -> SQLiteBuildValidationVerdict {
        if diagnostics.contains(where: { $0.verdict == .failed }) {
            return .failed
        }
        if diagnostics.contains(where: { $0.verdict == .unsupported }) {
            return .unsupported
        }
        return .passed
    }

    private enum CodingKeys: String, CodingKey {
        case queryID = "query_id"
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case conformanceFeatureIDs = "conformance_feature_ids"
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case verdict
        case placeholderAnalysis = "placeholder_analysis"
        case preparedShape = "prepared_shape"
        case diagnostics
    }
}


public struct SQLiteBuildValidationReport: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let manifestFormatVersion: Int
    public let conformanceInventoryVersion: String
    public let combinatorialManifestVersion: String
    public let schemaSnapshot: SQLiteBuildValidationSchemaSnapshot
    public let observedDatabaseByteCount: Int?
    public let observedDatabaseSHA256: String?
    public let runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    public let environmentEvidence: SQLiteBuildValidationEnvironment
    /// Checks this validator deliberately does not make, named in every report
    /// so a reader can tell "not checked" from "checked and passed".
    ///
    /// A constant, not rebuilt per report: it is the same list every time, and
    /// the report's bytes are a determinism gate.
    static let delegatedChecks: [String] = [
        "#214 catalog membership and table-reference binding",
        "#214 correlated and nested reference scopes",
        "#214 DML target roles",
        "#214 nullability views",
        "#214 same-scope alias uniqueness",
        "SQLite declared types do not prove dynamic expression storage or codec compatibility",
    ].sorted()

    public let delegatedChecks: [String]
    public let overallVerdict: SQLiteBuildValidationVerdict
    public let diagnostics: [SQLiteBuildValidationDiagnostic]
    public let outcomes: [SQLiteBuildValidationQueryOutcome]

    public init(
        manifest: SQLiteBuildValidationManifest,
        observedDatabaseByteCount: Int?,
        observedDatabaseSHA256: String?,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        environmentEvidence: SQLiteBuildValidationEnvironment,
        diagnostics: [SQLiteBuildValidationDiagnostic],
        outcomes: [SQLiteBuildValidationQueryOutcome]
    ) {
        let diagnostics = diagnostics.sorted(
            by: SQLiteBuildValidationDiagnostic.canonicalOrder
        )
        let outcomes = outcomes.sorted { $0.queryID < $1.queryID }
        self.formatVersion = 1
        self.manifestFormatVersion = manifest.formatVersion.rawValue
        self.conformanceInventoryVersion = manifest.conformanceInventoryVersion
        self.combinatorialManifestVersion = manifest.combinatorialManifestVersion
        self.schemaSnapshot = manifest.schemaSnapshot
        self.observedDatabaseByteCount = observedDatabaseByteCount
        self.observedDatabaseSHA256 = observedDatabaseSHA256?.lowercased()
        self.runtimeMetadata = runtimeMetadata
        self.environmentEvidence = environmentEvidence
        self.delegatedChecks = Self.delegatedChecks
        self.overallVerdict = Self.overallVerdict(
            diagnostics: diagnostics,
            outcomes: outcomes
        )
        self.diagnostics = diagnostics
        self.outcomes = outcomes
    }

    public func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationValidatorCanonicalJSON.encode(self)
    }

    private static func overallVerdict(
        diagnostics: [SQLiteBuildValidationDiagnostic],
        outcomes: [SQLiteBuildValidationQueryOutcome]
    ) -> SQLiteBuildValidationVerdict {
        if diagnostics.contains(where: { $0.verdict == .failed })
            || outcomes.contains(where: { $0.verdict == .failed }) {
            return .failed
        }
        if diagnostics.contains(where: { $0.verdict == .unsupported })
            || outcomes.contains(where: { $0.verdict == .unsupported }) {
            return .unsupported
        }
        return .passed
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case manifestFormatVersion = "manifest_format_version"
        case conformanceInventoryVersion = "conformance_inventory_version"
        case combinatorialManifestVersion = "combinatorial_manifest_version"
        case schemaSnapshot = "schema_snapshot"
        case observedDatabaseByteCount = "observed_database_byte_count"
        case observedDatabaseSHA256 = "observed_database_sha256"
        case runtimeMetadata = "runtime_metadata"
        case environmentEvidence = "environment_evidence"
        case delegatedChecks = "delegated_checks"
        case overallVerdict = "overall_verdict"
        case diagnostics
        case outcomes
    }
}


enum SQLiteBuildValidationValidatorCanonicalJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        while data.last == 0x0A {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }
}
