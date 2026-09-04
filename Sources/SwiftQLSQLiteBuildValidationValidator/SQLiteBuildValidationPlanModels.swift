import Foundation
import SwiftQLSQLiteBuildValidationManifest


/// A named `EXPLAIN QUERY PLAN` node shape.
///
/// Deliberately granular: the #390 variance corpus's real captures contain
/// compound-query, co-routine, and recursive-CTE structural nodes that are
/// none of the scan/search/sort shapes the advisory diagnostics care about,
/// and folding them into one another would be exactly the coercion the #391
/// classifier forbids. Every distinct pattern is named precisely, and
/// ``unclassified`` is reserved for genuinely unrecognized detail text so a
/// gap is visible rather than guessed at.
public enum SQLiteBuildValidationPlanShape:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case fullTableScan = "full_table_scan"
    case coveringIndexScan = "covering_index_scan"
    case indexSearch = "index_search"
    case automaticCoveringIndex = "automatic_covering_index"
    case tempBTreeForOrderBy = "temp_b_tree_for_order_by"
    case tempBTreeForGroupBy = "temp_b_tree_for_group_by"
    case tempBTreeForDistinctAggregate = "temp_b_tree_for_distinct_aggregate"
    case tempBTreeForCompoundOperation = "temp_b_tree_for_compound_operation"
    case scalarSubquery = "scalar_subquery"
    case correlatedScalarSubquery = "correlated_scalar_subquery"
    case listSubquery = "list_subquery"
    case coRoutineSubqueryOrCTE = "co_routine_subquery_or_cte"
    case materializedSubqueryOrCTE = "materialized_subquery_or_cte"
    case compoundQueryStrategy = "compound_query_strategy"
    case recursiveCTEStep = "recursive_cte_step"
    case constantRowScan = "constant_row_scan"
    case bloomFilter = "bloom_filter"
    case unclassified
}


/// Structured detail extracted from a node's raw text, populated only where
/// the shape carries it.
///
/// Every field is optional or empty rather than defaulted to a placeholder,
/// so absence stays visible in the encoded evidence.
public struct SQLiteBuildValidationPlanAttributes:
    Codable,
    Equatable,
    Sendable
{
    /// The table or alias SQLite names in the node. `EXPLAIN QUERY PLAN`
    /// reports whichever spelling the statement used, so this is an alias
    /// whenever the statement declared one.
    public let table: String?
    public let indexName: String?
    public let constrainedColumns: [String]
    public let isCovering: Bool
    public let isAutomatic: Bool

    public init(
        table: String? = nil,
        indexName: String? = nil,
        constrainedColumns: [String] = [],
        isCovering: Bool = false,
        isAutomatic: Bool = false
    ) {
        self.table = table
        self.indexName = indexName
        self.constrainedColumns = constrainedColumns
        self.isCovering = isCovering
        self.isAutomatic = isAutomatic
    }

    public static let none = SQLiteBuildValidationPlanAttributes()

    private enum CodingKeys: String, CodingKey {
        case table
        case indexName = "index_name"
        case constrainedColumns = "constrained_columns"
        case isCovering = "is_covering"
        case isAutomatic = "is_automatic"
    }
}


/// One classified node in the normalised plan tree.
///
/// The raw `detail` string is always retained alongside its classification,
/// so a misclassification is auditable rather than silent. SQLite's own `id`
/// and `parent` row numbers are deliberately absent: #390 measured them as
/// the one cross-build unstable field, and the tree structure they encode is
/// already carried by ``children``.
public struct SQLiteBuildValidationPlanNode: Codable, Equatable, Sendable {
    public let detail: String
    public let shape: SQLiteBuildValidationPlanShape
    public let attributes: SQLiteBuildValidationPlanAttributes
    public let children: [SQLiteBuildValidationPlanNode]

    public init(
        detail: String,
        shape: SQLiteBuildValidationPlanShape,
        attributes: SQLiteBuildValidationPlanAttributes,
        children: [SQLiteBuildValidationPlanNode]
    ) {
        self.detail = detail
        self.shape = shape
        self.attributes = attributes
        self.children = children
    }
}


/// The SQLite build that produced one plan, pinned into the plan record
/// itself so a record lifted out of its report is still provenance-complete.
///
/// `compileOptions` is filtered to the options that can change a query plan
/// (see ``SQLiteBuildValidationPlanProvenance/isPlanRelevant(_:)``) rather
/// than carrying the connection's full option list, which the correctness
/// report already records in full.
public struct SQLiteBuildValidationPlanProvenance:
    Codable,
    Equatable,
    Sendable
{
    public let sqliteVersion: String
    public let sqliteSourceID: String
    public let compileOptions: [String]

    public init(
        sqliteVersion: String,
        sqliteSourceID: String,
        compileOptions: [String]
    ) {
        self.sqliteVersion = sqliteVersion
        self.sqliteSourceID = sqliteSourceID
        self.compileOptions = sqliteBuildValidationSortedUnique(compileOptions)
    }

    /// Projects the run's full runtime metadata down to plan provenance.
    public init(_ metadata: SQLiteBuildValidationRuntimeMetadata) {
        self.init(
            sqliteVersion: metadata.sqliteVersion,
            sqliteSourceID: metadata.sqliteSourceID,
            compileOptions: metadata.compileOptions.filter(Self.isPlanRelevant)
        )
    }

    /// Compile options that can change which plan SQLite chooses.
    ///
    /// An allowlist of prefixes, not a guess: each one names a planner input
    /// (index availability, statistics, the automatic-index and LIKE
    /// optimizations, or a virtual-table module that owns its own plan). An
    /// option outside this list can still change results or performance, but
    /// it does not change the plan tree this record normalises, and carrying
    /// every option in every record would bury the ones that matter.
    static let planRelevantCompileOptionPrefixes: [String] = [
        "DEFAULT_AUTOMATIC_INDEX",
        "ENABLE_FTS",
        "ENABLE_GEOPOLY",
        "ENABLE_QPSG",
        "ENABLE_RTREE",
        "ENABLE_STAT",
        "LIKE_DOESNT_MATCH_BLOBS",
        "MAX_ATTACHED",
        "OMIT_AUTOMATIC_INDEX",
        "OMIT_LIKE_OPTIMIZATION",
        "OMIT_OR_OPTIMIZATION",
        "OMIT_SUBQUERY",
        "QUERY_PLANNER",
    ]

    static func isPlanRelevant(_ option: String) -> Bool {
        let folded = sqliteASCIIFolded(option)
        return planRelevantCompileOptionPrefixes.contains { prefix in
            folded.hasPrefix(sqliteASCIIFolded(prefix))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sqliteVersion = "sqlite_version"
        case sqliteSourceID = "sqlite_source_id"
        case compileOptions = "compile_options"
    }
}


/// Whether one manifest entry's plan was captured, or why it was not.
///
/// There is no third state. A statement whose plan could not be captured is
/// explicitly ``unsupported(reason:)`` — never absent from the report, and
/// never silently recorded as an empty plan, which would read as "SQLite
/// planned nothing" rather than "this validator learned nothing".
public enum SQLiteBuildValidationPlanCaptureOutcome: Equatable, Sendable {
    case captured(roots: [SQLiteBuildValidationPlanNode])
    case unsupported(reason: String)

    public var capturedRoots: [SQLiteBuildValidationPlanNode]? {
        guard case .captured(let roots) = self else {
            return nil
        }
        return roots
    }

    public var unsupportedReason: String? {
        guard case .unsupported(let reason) = self else {
            return nil
        }
        return reason
    }
}


extension SQLiteBuildValidationPlanCaptureOutcome: Codable {
    private enum Status: String, Codable {
        case captured
        case unsupported
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case roots
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .captured:
            self = .captured(
                roots: try container.decode(
                    [SQLiteBuildValidationPlanNode].self,
                    forKey: .roots
                )
            )
        case .unsupported:
            self = .unsupported(
                reason: try container.decode(String.self, forKey: .reason)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .captured(let roots):
            try container.encode(Status.captured, forKey: .status)
            try container.encode(roots, forKey: .roots)
        case .unsupported(let reason):
            try container.encode(Status.unsupported, forKey: .status)
            try container.encode(reason, forKey: .reason)
        }
    }
}


/// One manifest entry's plan evidence.
public struct SQLiteBuildValidationPlanRecord: Codable, Equatable, Sendable {
    public let queryID: String
    public let definitionIdentity: String
    public let descriptorIdentity: String
    /// The SQLite build that planned this statement.
    ///
    /// Absent only when the run could not read the connection's provenance
    /// at all, which necessarily makes ``outcome`` `unsupported` — a captured
    /// plan whose SQLite is unidentified would be evidence of nothing.
    public let provenance: SQLiteBuildValidationPlanProvenance?
    public let outcome: SQLiteBuildValidationPlanCaptureOutcome

    public init(
        queryID: String,
        definitionIdentity: String,
        descriptorIdentity: String,
        provenance: SQLiteBuildValidationPlanProvenance?,
        outcome: SQLiteBuildValidationPlanCaptureOutcome
    ) {
        if case .captured = outcome {
            precondition(
                provenance != nil,
                "A captured plan must name the SQLite build that produced it."
            )
        }
        self.queryID = queryID
        self.definitionIdentity = definitionIdentity
        self.descriptorIdentity = descriptorIdentity
        self.provenance = provenance
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case queryID = "query_id"
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case provenance
        case outcome
    }
}
