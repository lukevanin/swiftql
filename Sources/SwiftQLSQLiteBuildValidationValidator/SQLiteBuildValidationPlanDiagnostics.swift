import Foundation


/// The severity a plan diagnostic can carry.
///
/// One case, and that is the point. `advisory` is deliberately a separate
/// type from ``SQLiteBuildValidationVerdict`` rather than a fourth case on
/// it: a verdict decides the validator's exit status, and no arrangement of
/// this type can reach that decision. Adding `advisory` to the verdict enum
/// would have put "never affects exit status" behind a convention that every
/// future `switch` over verdicts has to keep. Here it is behind the type
/// system.
public enum SQLiteBuildValidationPlanDiagnosticSeverity:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case advisory
}


/// The plan shapes this validator will diagnose.
///
/// Each case names a shape the #390/#391 evidence measured as stable across
/// SQLite builds, and each maps to exactly one classified
/// ``SQLiteBuildValidationPlanShape``. A diagnostic is keyed on that shape,
/// never on the raw detail wording that produced it — wording is the
/// classifier's input, not this layer's.
public enum SQLiteBuildValidationPlanDiagnosticCode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case fullTableScan = "plan.full-table-scan"
    case tempBTreeForOrderBy = "plan.temp-b-tree-order-by"
    case tempBTreeForGroupBy = "plan.temp-b-tree-group-by"
    case correlatedScalarSubquery = "plan.correlated-scalar-subquery"

    /// The plan shape this code fires on.
    public var shape: SQLiteBuildValidationPlanShape {
        switch self {
        case .fullTableScan:
            return .fullTableScan
        case .tempBTreeForOrderBy:
            return .tempBTreeForOrderBy
        case .tempBTreeForGroupBy:
            return .tempBTreeForGroupBy
        case .correlatedScalarSubquery:
            return .correlatedScalarSubquery
        }
    }
}


/// One advisory finding about one statement's plan.
public struct SQLiteBuildValidationPlanDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    public let severity: SQLiteBuildValidationPlanDiagnosticSeverity
    public let code: SQLiteBuildValidationPlanDiagnosticCode
    public let queryID: String
    public let definitionIdentity: String
    public let descriptorIdentity: String
    /// The real table, when the statement's `FROM`/`JOIN` clauses resolve the
    /// plan node's spelling to one. `nil` when they do not — an unresolvable
    /// alias is reported as unresolved rather than guessed at.
    public let table: String?
    /// The spelling `EXPLAIN QUERY PLAN` used for the table: an alias when
    /// the statement declared one, otherwise the table name.
    public let alias: String?
    /// Rows in ``table`` at capture time, for the diagnostics whose rule reads
    /// it.
    public let tableRowCount: Int?
    /// The classified shape of the node that produced this diagnostic.
    public let planNodeShape: SQLiteBuildValidationPlanShape
    /// That node's raw `EXPLAIN QUERY PLAN` text, so the finding can be
    /// audited back to what SQLite actually said.
    public let planNodeDetail: String
    public let message: String

    public init(
        severity: SQLiteBuildValidationPlanDiagnosticSeverity = .advisory,
        code: SQLiteBuildValidationPlanDiagnosticCode,
        queryID: String,
        definitionIdentity: String,
        descriptorIdentity: String,
        table: String?,
        alias: String?,
        tableRowCount: Int?,
        planNodeShape: SQLiteBuildValidationPlanShape,
        planNodeDetail: String,
        message: String
    ) {
        precondition(
            planNodeShape != .unclassified,
            "A diagnostic must never fire on an unclassified plan shape."
        )
        self.severity = severity
        self.code = code
        self.queryID = queryID
        self.definitionIdentity = definitionIdentity
        self.descriptorIdentity = descriptorIdentity
        self.table = table
        self.alias = alias
        self.tableRowCount = tableRowCount
        self.planNodeShape = planNodeShape
        self.planNodeDetail = planNodeDetail
        self.message = message
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        let lhsKey = [
            lhs.queryID,
            lhs.code.rawValue,
            lhs.table ?? "",
            lhs.alias ?? "",
            lhs.planNodeDetail,
        ]
        let rhsKey = [
            rhs.queryID,
            rhs.code.rawValue,
            rhs.table ?? "",
            rhs.alias ?? "",
            rhs.planNodeDetail,
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey)
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case code
        case queryID = "query_id"
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case table
        case alias
        case tableRowCount = "table_row_count"
        case planNodeShape = "plan_node_shape"
        case planNodeDetail = "plan_node_detail"
        case message
    }
}


/// A diagnostic that a checked-in suppression silenced, kept in the report
/// rather than dropped.
///
/// Silencing a finding is a decision, and a decision that leaves no trace is
/// indistinguishable from a finding that never happened. The sidecar records
/// what was silenced and the reason the repository gave for it.
public struct SQLiteBuildValidationSuppressedPlanDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    public let diagnostic: SQLiteBuildValidationPlanDiagnostic
    public let reason: String

    public init(
        diagnostic: SQLiteBuildValidationPlanDiagnostic,
        reason: String
    ) {
        self.diagnostic = diagnostic
        self.reason = reason
    }
}


/// One checked-in suppression rule.
///
/// A rule must name a code and at least one of a query or a table, and must
/// state a reason. A blanket "silence everything" rule is not expressible,
/// and neither is a silent one.
public struct SQLiteBuildValidationPlanSuppression:
    Codable,
    Equatable,
    Sendable
{
    public let code: SQLiteBuildValidationPlanDiagnosticCode
    public let queryID: String?
    public let table: String?
    public let reason: String

    public init(
        code: SQLiteBuildValidationPlanDiagnosticCode,
        queryID: String? = nil,
        table: String? = nil,
        reason: String
    ) {
        self.code = code
        self.queryID = queryID
        self.table = table
        self.reason = reason
    }

    /// Whether this rule silences `diagnostic`.
    ///
    /// Every field a rule states must match. A rule naming both a query and a
    /// table is therefore narrower than either alone, never broader.
    public func silences(_ diagnostic: SQLiteBuildValidationPlanDiagnostic) -> Bool {
        guard code == diagnostic.code else {
            return false
        }
        if let queryID, queryID != diagnostic.queryID {
            return false
        }
        if let table, table != diagnostic.table {
            return false
        }
        return true
    }

    func validated() throws -> Self {
        guard queryID != nil || table != nil else {
            throw SQLiteBuildValidationPlanSuppressionError.rulesEverything(
                code: code.rawValue
            )
        }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SQLiteBuildValidationPlanSuppressionError.missingReason(
                code: code.rawValue
            )
        }
        return self
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        [lhs.code.rawValue, lhs.queryID ?? "", lhs.table ?? "", lhs.reason]
            .lexicographicallyPrecedes(
                [rhs.code.rawValue, rhs.queryID ?? "", rhs.table ?? "", rhs.reason]
            )
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case queryID = "query_id"
        case table
        case reason
    }
}


public enum SQLiteBuildValidationPlanSuppressionError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case unsupportedFormatVersion(Int)
    case rulesEverything(code: String)
    case missingReason(code: String)

    public var description: String {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "Unsupported plan-suppression format version \(version); this validator reads version \(SQLiteBuildValidationPlanSuppressions.currentFormatVersion)."
        case .rulesEverything(let code):
            return "A plan suppression for '\(code)' must name a query_id, a table, or both; a rule that silences every occurrence is not expressible."
        case .missingReason(let code):
            return "A plan suppression for '\(code)' must state a nonempty reason."
        }
    }
}


/// The checked-in suppression file.
///
/// Deliberately a file in the repository rather than an inference or a
/// command-line flag: an intentional scan of a small table should be silenced
/// once, in a place a reviewer reads, with the reason attached.
public struct SQLiteBuildValidationPlanSuppressions:
    Codable,
    Equatable,
    Sendable
{
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let suppressions: [SQLiteBuildValidationPlanSuppression]

    public init(
        formatVersion: Int = SQLiteBuildValidationPlanSuppressions.currentFormatVersion,
        suppressions: [SQLiteBuildValidationPlanSuppression]
    ) {
        self.formatVersion = formatVersion
        self.suppressions = suppressions.sorted(
            by: SQLiteBuildValidationPlanSuppression.canonicalOrder
        )
    }

    public static let none = SQLiteBuildValidationPlanSuppressions(suppressions: [])

    public func validating() throws -> Self {
        guard formatVersion == Self.currentFormatVersion else {
            throw SQLiteBuildValidationPlanSuppressionError
                .unsupportedFormatVersion(formatVersion)
        }
        return Self(
            formatVersion: formatVersion,
            suppressions: try suppressions.map { try $0.validated() }
        )
    }

    public static func decode(contentsOf url: URL) throws -> Self {
        try JSONDecoder()
            .decode(Self.self, from: try Data(contentsOf: url))
            .validating()
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case suppressions
    }
}


/// The thresholds and rules one run diagnosed under, recorded in the sidecar
/// so a finding can be read without also having to know how the run was
/// invoked.
public struct SQLiteBuildValidationPlanDiagnosticSettings:
    Codable,
    Equatable,
    Sendable
{
    /// A full table scan is diagnosed only above this many rows.
    ///
    /// Below a few hundred rows a full scan is typically a handful of page
    /// reads, and advice about it is noise that trains a reader to ignore the
    /// findings that matter.
    public static let defaultFullTableScanRowThreshold = 500

    public let fullTableScanRowThreshold: Int
    public let suppressions: [SQLiteBuildValidationPlanSuppression]
    /// The stated bounds on index-candidate generation (#396).
    public let candidateLimits: SQLiteBuildValidationIndexCandidateLimits

    public init(
        fullTableScanRowThreshold: Int = SQLiteBuildValidationPlanDiagnosticSettings
            .defaultFullTableScanRowThreshold,
        suppressions: [SQLiteBuildValidationPlanSuppression] = [],
        candidateLimits: SQLiteBuildValidationIndexCandidateLimits = .init()
    ) {
        self.fullTableScanRowThreshold = fullTableScanRowThreshold
        self.suppressions = suppressions.sorted(
            by: SQLiteBuildValidationPlanSuppression.canonicalOrder
        )
        self.candidateLimits = candidateLimits
    }

    private enum CodingKeys: String, CodingKey {
        case fullTableScanRowThreshold = "full_table_scan_row_threshold"
        case suppressions
        case candidateLimits = "candidate_limits"
    }
}
