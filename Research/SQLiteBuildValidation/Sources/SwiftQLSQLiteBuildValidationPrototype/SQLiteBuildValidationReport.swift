import Foundation


/// Explicit caller-supplied evidence used during one validation run.
///
/// The encoded form is deliberately limited to stable identifiers: it does
/// not retain paths, timestamps, process identity, or host identity. Every
/// list is sorted and deduplicated so semantically equivalent invocations
/// produce byte-identical canonical reports.
package struct SQLiteBuildValidationEnvironment:
    Codable,
    Equatable,
    Sendable
{
    package let codecIdentifiers: [String]
    package let extensionNames: [String]
    package let capabilityIDs: [String]

    package init(
        codecIdentifiers: [String] = [],
        extensionNames: [String] = [],
        capabilityIDs: [String] = []
    ) {
        self.codecIdentifiers = Self.sortedUnique(codecIdentifiers)
        self.extensionNames = Self.sortedUnique(extensionNames)
        self.capabilityIDs = Self.sortedUnique(capabilityIDs)
    }

    package init(
        codecIdentities: [SQLiteBuildValidationCodec],
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


package struct SQLiteBuildValidationDiagnostic: Codable, Equatable, Sendable {
    package enum Stage: String, Codable, CaseIterable, Sendable {
        case schema
        case runtime
        case codec
        case capability
        case prepare
        case parameter
        case result
    }

    package let verdict: SQLiteBuildValidationVerdict
    package let stage: Stage
    package let code: String
    package let message: String
    package let queryID: String?
    package let definitionIdentity: String?
    package let descriptorIdentity: String?
    package let conformanceCaseIDs: [String]
    package let northwindAnchorCaseIDs: [String]
    package let inventoryFeatureIDs: [String]
    package let sqliteResultCode: Int32?
    package let sqliteExtendedResultCode: Int32?

    package init(
        verdict: SQLiteBuildValidationVerdict,
        stage: Stage,
        code: String,
        message: String,
        query: SQLiteBuildValidationQuery? = nil,
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
        self.conformanceCaseIDs = query?.conformanceCaseIDs ?? []
        self.northwindAnchorCaseIDs = query?.northwindAnchorCaseIDs ?? []
        self.inventoryFeatureIDs = query?.inventoryFeatureIDs ?? []
        self.sqliteResultCode = sqliteResultCode
        self.sqliteExtendedResultCode = sqliteExtendedResultCode
    }

    fileprivate static func canonicalOrder(
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
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case inventoryFeatureIDs = "inventory_feature_ids"
        case sqliteResultCode = "sqlite_result_code"
        case sqliteExtendedResultCode = "sqlite_extended_result_code"
    }
}


package struct SQLiteBuildValidationQueryOutcome:
    Codable,
    Equatable,
    Sendable
{
    package let queryID: String
    package let definitionIdentity: String
    package let descriptorIdentity: String
    package let conformanceCaseIDs: [String]
    package let northwindAnchorCaseIDs: [String]
    package let inventoryFeatureIDs: [String]
    package let verdict: SQLiteBuildValidationVerdict
    package let placeholderAnalysis: SQLiteBuildValidationPlaceholderAnalysis
    package let preparedShape: SQLitePreparedStatementShape?
    package let diagnostics: [SQLiteBuildValidationDiagnostic]

    package init(
        query: SQLiteBuildValidationQuery,
        placeholderAnalysis: SQLiteBuildValidationPlaceholderAnalysis,
        preparedShape: SQLitePreparedStatementShape?,
        diagnostics: [SQLiteBuildValidationDiagnostic]
    ) {
        let diagnostics = diagnostics.sorted(
            by: SQLiteBuildValidationDiagnostic.canonicalOrder
        )
        self.queryID = query.id
        self.definitionIdentity = query.definitionIdentity
        self.descriptorIdentity = query.descriptorIdentity
        self.conformanceCaseIDs = query.conformanceCaseIDs
        self.northwindAnchorCaseIDs = query.northwindAnchorCaseIDs
        self.inventoryFeatureIDs = query.inventoryFeatureIDs
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
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case inventoryFeatureIDs = "inventory_feature_ids"
        case verdict
        case placeholderAnalysis = "placeholder_analysis"
        case preparedShape = "prepared_shape"
        case diagnostics
    }
}


package struct SQLiteBuildValidationReport: Codable, Equatable, Sendable {
    package let formatVersion: Int
    package let planSchemaVersion: Int
    package let inventoryVersion: String
    package let schema: SQLiteBuildValidationSchemaInput
    package let observedDatabaseByteCount: Int?
    package let observedDatabaseSHA256: String?
    package let runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    package let environmentEvidence: SQLiteBuildValidationEnvironment
    package let delegatedChecks: [String]
    package let overallVerdict: SQLiteBuildValidationVerdict
    package let diagnostics: [SQLiteBuildValidationDiagnostic]
    package let outcomes: [SQLiteBuildValidationQueryOutcome]

    package init(
        plan: SQLiteBuildValidationPlan,
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
        self.planSchemaVersion = plan.schemaVersion
        self.inventoryVersion = plan.inventoryVersion
        self.schema = plan.schema
        self.observedDatabaseByteCount = observedDatabaseByteCount
        self.observedDatabaseSHA256 = observedDatabaseSHA256?.lowercased()
        self.runtimeMetadata = runtimeMetadata
        self.environmentEvidence = environmentEvidence
        self.delegatedChecks = [
            "#214 catalog membership and table-reference binding",
            "#214 correlated and nested reference scopes",
            "#214 DML target roles",
            "#214 nullability views",
            "#214 same-scope alias uniqueness",
            "SQLite declared types do not prove dynamic expression storage or codec compatibility",
        ].sorted()
        self.overallVerdict = Self.overallVerdict(
            diagnostics: diagnostics,
            outcomes: outcomes
        )
        self.diagnostics = diagnostics
        self.outcomes = outcomes
    }

    package func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationCanonicalJSON.encode(self)
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
        case planSchemaVersion = "plan_schema_version"
        case inventoryVersion = "inventory_version"
        case schema
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
