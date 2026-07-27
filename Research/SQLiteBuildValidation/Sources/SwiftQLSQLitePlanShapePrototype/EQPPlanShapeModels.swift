import Foundation


/// A named EQP plan-node shape. Deliberately more granular than the seven
/// shapes issue #391 requires (`fullTableScan`, `indexSearch`,
/// `automaticCoveringIndex`, `tempBTreeForOrderBy`, `tempBTreeForGroupBy`,
/// `correlatedScalarSubquery`, `materializedSubqueryOrCTE`): the #390 corpus's
/// real captures also contain compound-query, CTE-coroutine, and
/// recursive-CTE structural nodes that are not any of those seven, and
/// forcing them into one would be exactly the coercion this issue forbids.
/// Naming every distinct pattern precisely, with `unclassified` reserved for
/// genuinely unrecognised detail text, keeps every classification honest.
package enum EQPPlanShapeKind: String, Codable, Equatable, Sendable {
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
/// the shape carries it. Every field is optional/empty rather than defaulted
/// to a placeholder, so absence is visible in the encoded evidence.
package struct EQPPlanShapeAttributes: Codable, Equatable, Sendable {
    package let table: String?
    package let indexName: String?
    package let constrainedColumns: [String]
    package let isCovering: Bool
    package let isAutomatic: Bool

    package init(
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

    package static let none = EQPPlanShapeAttributes()

    private enum CodingKeys: String, CodingKey {
        case table
        case indexName = "index_name"
        case constrainedColumns = "constrained_columns"
        case isCovering = "is_covering"
        case isAutomatic = "is_automatic"
    }
}


/// One classified node in the normalised plan tree. The raw `detail` string
/// is always retained alongside its classification so a misclassification is
/// auditable rather than silent, per this issue's required approach.
package struct EQPPlanNode: Codable, Equatable, Sendable {
    package let detail: String
    package let shape: EQPPlanShapeKind
    package let attributes: EQPPlanShapeAttributes
    package let children: [EQPPlanNode]

    package init(
        detail: String,
        shape: EQPPlanShapeKind,
        attributes: EQPPlanShapeAttributes,
        children: [EQPPlanNode]
    ) {
        self.detail = detail
        self.shape = shape
        self.attributes = attributes
        self.children = children
    }
}


/// The normalised plan for one statement: a forest of `EQPPlanNode` roots (a
/// single statement commonly has more than one top-level node, e.g. a table
/// scan alongside a sibling "USE TEMP B-TREE FOR ORDER BY"). A pure function
/// of the captured rows: no timestamp, host, or SQLite-version field, so the
/// same rows always normalise to the same plan regardless of which build
/// captured them.
package struct EQPPlan: Codable, Equatable, Sendable {
    package let statementID: String
    package let roots: [EQPPlanNode]

    package init(statementID: String, roots: [EQPPlanNode]) {
        self.statementID = statementID
        self.roots = roots
    }

    private enum CodingKeys: String, CodingKey {
        case statementID = "statement_id"
        case roots
    }
}
