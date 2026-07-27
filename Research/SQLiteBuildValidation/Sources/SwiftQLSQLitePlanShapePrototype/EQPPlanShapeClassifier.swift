import Foundation
import SwiftQLSQLiteEQPVariancePrototype


/// Builds a normalised plan tree from one statement's raw EQP rows and
/// classifies every node into a named shape.
///
/// First indexes rows by `parent` id, then recursively builds the tree
/// top-down from the roots (`parent == 0`) through that index. Parent-child
/// adjacency comes entirely from each row's own `parent` field, not from its
/// position in the row list. Sibling order is not independent of input order,
/// though: children of the same parent (and the top-level roots) keep the
/// relative order they had in the input rows, so this is deterministic for a
/// given capture but not permutation-invariant against an arbitrary
/// reordering of the same rows. Classification is a pure function of the
/// row's own `detail` text plus its already-known parent shape (needed only
/// to distinguish a correlated scalar subquery, see `isRowLoopingShape`); it
/// never depends on SQLite version, host, or any other provenance field.
package enum EQPPlanShapeClassifier {
    package static func classify(rows: [EQPRow], statementID: String) -> EQPPlan {
        var childrenByParent: [Int64: [EQPRow]] = [:]
        for row in rows {
            childrenByParent[row.parent, default: []].append(row)
        }
        let roots = (childrenByParent[0] ?? []).map {
            buildNode($0, parentShape: nil, childrenByParent: childrenByParent)
        }
        return EQPPlan(statementID: statementID, roots: roots)
    }

    private static func buildNode(
        _ row: EQPRow,
        parentShape: EQPPlanShapeKind?,
        childrenByParent: [Int64: [EQPRow]]
    ) -> EQPPlanNode {
        let (shape, attributes) = classifyDetail(row.detail, parentShape: parentShape)
        let children = (childrenByParent[row.id] ?? []).map {
            buildNode($0, parentShape: shape, childrenByParent: childrenByParent)
        }
        return EQPPlanNode(detail: row.detail, shape: shape, attributes: attributes, children: children)
    }

    /// `internal` (not `private`) so classifier tests can exercise detail
    /// strings directly, without needing a full row tree for every case.
    static func classifyDetail(
        _ detail: String,
        parentShape: EQPPlanShapeKind?
    ) -> (EQPPlanShapeKind, EQPPlanShapeAttributes) {
        if detail == "SCAN CONSTANT ROW" {
            return (.constantRowScan, .none)
        }
        if detail == "CREATE BLOOM FILTER" {
            return (.bloomFilter, .none)
        }
        if detail == "SETUP" || detail == "RECURSIVE STEP" {
            return (.recursiveCTEStep, .none)
        }
        if detail == "COMPOUND QUERY" || detail == "LEFT-MOST SUBQUERY"
            || detail == "LEFT" || detail == "RIGHT"
            || detail == "UNION ALL" || detail.hasPrefix("MERGE (") {
            return (.compoundQueryStrategy, .none)
        }
        if detail == "USE TEMP B-TREE FOR ORDER BY" {
            return (.tempBTreeForOrderBy, .none)
        }
        if detail == "USE TEMP B-TREE FOR GROUP BY" {
            return (.tempBTreeForGroupBy, .none)
        }
        if detail.hasPrefix("USE TEMP B-TREE FOR "), detail.hasSuffix("(DISTINCT)") {
            return (.tempBTreeForDistinctAggregate, .none)
        }
        if detail.hasSuffix(" USING TEMP B-TREE"),
           ["UNION", "EXCEPT", "INTERSECT"].contains(String(detail.dropLast(" USING TEMP B-TREE".count))) {
            return (.tempBTreeForCompoundOperation, .none)
        }
        if detail.hasPrefix("CO-ROUTINE ") {
            return (.coRoutineSubqueryOrCTE, .none)
        }
        if detail.hasPrefix("MATERIALIZE ") {
            return (.materializedSubqueryOrCTE, .none)
        }
        if detail.hasPrefix("SCALAR SUBQUERY") {
            let shape: EQPPlanShapeKind = isRowLoopingShape(parentShape) ? .correlatedScalarSubquery : .scalarSubquery
            return (shape, .none)
        }
        if detail.hasPrefix("LIST SUBQUERY") {
            return (.listSubquery, .none)
        }
        if let parsed = parseSearchOrScan(detail) {
            return classifySearchOrScan(parsed)
        }
        return (.unclassified, .none)
    }

    /// A scalar subquery SQLite can evaluate once (uncorrelated) is hoisted
    /// as a sibling of the driving row source, with `parent == 0`. One it
    /// must re-evaluate per outer row (correlated) is nested as a child of
    /// whatever row-producing node supplies the correlation — a table scan,
    /// index search, or another per-row-loop shape. This is a heuristic on
    /// EQP's tree structure, not a guarantee: it has no real-corpus
    /// counter-example in this repo's evidence, but is not proven exhaustive
    /// against every SQLite version or query shape.
    private static func isRowLoopingShape(_ shape: EQPPlanShapeKind?) -> Bool {
        guard let shape else {
            return false
        }
        switch shape {
        case .fullTableScan, .coveringIndexScan, .indexSearch, .automaticCoveringIndex,
             .coRoutineSubqueryOrCTE, .recursiveCTEStep:
            return true
        case .tempBTreeForOrderBy, .tempBTreeForGroupBy, .tempBTreeForDistinctAggregate,
             .tempBTreeForCompoundOperation, .scalarSubquery, .correlatedScalarSubquery,
             .listSubquery, .materializedSubqueryOrCTE, .compoundQueryStrategy,
             .constantRowScan, .bloomFilter, .unclassified:
            return false
        }
    }

    private struct ParsedAccess {
        let isSearch: Bool
        let table: String
        let using: String?
        let constraint: String?
    }

    private static func parseSearchOrScan(_ detail: String) -> ParsedAccess? {
        let isSearch: Bool
        let prefixLength: Int
        if detail.hasPrefix("SEARCH ") {
            isSearch = true
            prefixLength = "SEARCH ".count
        } else if detail.hasPrefix("SCAN ") {
            isSearch = false
            prefixLength = "SCAN ".count
        } else {
            return nil
        }

        var remainder = String(detail.dropFirst(prefixLength))
        if let joinRange = remainder.range(of: " LEFT-JOIN") {
            remainder = String(remainder[remainder.startIndex..<joinRange.lowerBound])
        }

        guard let usingRange = remainder.range(of: " USING ") else {
            return ParsedAccess(isSearch: isSearch, table: remainder, using: nil, constraint: nil)
        }

        let table = String(remainder[remainder.startIndex..<usingRange.lowerBound])
        var usingClause = String(remainder[usingRange.upperBound...])
        var constraint: String?
        if let parenStart = usingClause.firstIndex(of: "("), usingClause.hasSuffix(")") {
            constraint = String(usingClause[usingClause.index(after: parenStart)..<usingClause.index(before: usingClause.endIndex)])
            usingClause = String(usingClause[usingClause.startIndex..<parenStart])
                .trimmingCharacters(in: .whitespaces)
        }
        return ParsedAccess(isSearch: isSearch, table: table, using: usingClause, constraint: constraint)
    }

    private static func classifySearchOrScan(
        _ parsed: ParsedAccess
    ) -> (EQPPlanShapeKind, EQPPlanShapeAttributes) {
        guard let using = parsed.using else {
            let shape: EQPPlanShapeKind = parsed.isSearch ? .indexSearch : .fullTableScan
            return (shape, EQPPlanShapeAttributes(table: parsed.table))
        }

        let columns = parsed.constraint.map(constrainedColumns(from:)) ?? []

        if using == "INTEGER PRIMARY KEY" || using == "PRIMARY KEY" {
            return (
                .indexSearch,
                EQPPlanShapeAttributes(table: parsed.table, indexName: using, constrainedColumns: columns)
            )
        }
        if using.hasPrefix("AUTOMATIC COVERING INDEX") || using.hasPrefix("AUTOMATIC PARTIAL COVERING INDEX") {
            return (
                .automaticCoveringIndex,
                EQPPlanShapeAttributes(
                    table: parsed.table,
                    constrainedColumns: columns,
                    isCovering: true,
                    isAutomatic: true
                )
            )
        }
        if using.hasPrefix("COVERING INDEX ") {
            let name = String(using.dropFirst("COVERING INDEX ".count))
            let shape: EQPPlanShapeKind = parsed.isSearch ? .indexSearch : .coveringIndexScan
            return (
                shape,
                EQPPlanShapeAttributes(table: parsed.table, indexName: name, constrainedColumns: columns, isCovering: true)
            )
        }
        if using.hasPrefix("INDEX ") {
            let name = String(using.dropFirst("INDEX ".count))
            return (
                .indexSearch,
                EQPPlanShapeAttributes(table: parsed.table, indexName: name, constrainedColumns: columns)
            )
        }

        // An unrecognised "USING ..." form: preserve the parsed table for
        // audit, but do not guess a shape for text this classifier has
        // never seen — that would be exactly the coercion #391 forbids.
        return (.unclassified, EQPPlanShapeAttributes(table: parsed.table))
    }

    private static func constrainedColumns(from constraint: String) -> [String] {
        constraint
            .components(separatedBy: " AND ")
            .compactMap { clause -> String? in
                let trimmed = clause.trimmingCharacters(in: .whitespaces)
                for comparisonOperator in [">=", "<=", "<>", "!=", "=", "<", ">"] {
                    if let range = trimmed.range(of: comparisonOperator) {
                        let column = String(trimmed[trimmed.startIndex..<range.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                        return column.isEmpty ? nil : column
                    }
                }
                return trimmed.isEmpty ? nil : trimmed
            }
    }
}
