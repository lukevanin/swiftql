import Foundation


/// One raw `EXPLAIN QUERY PLAN` row, in SQLite's own column order.
///
/// `id` and `parent` are consumed to rebuild the tree and are then discarded:
/// #390 measured them as the one field that legitimately differs between two
/// SQLite builds planning the same statement, so they never reach the
/// normalised plan.
public struct SQLiteBuildValidationPlanRow: Equatable, Sendable {
    public let id: Int64
    public let parent: Int64
    public let detail: String

    public init(id: Int64, parent: Int64, detail: String) {
        self.id = id
        self.parent = parent
        self.detail = detail
    }
}


/// Builds a normalised plan tree from one statement's raw EQP rows and
/// classifies every node into a named shape.
///
/// Rows are indexed by `parent` id and the tree is then built top-down from
/// the roots (`parent == 0`), so parent/child adjacency comes from each row's
/// own `parent` field rather than from its position in the row list. Sibling
/// order follows the order SQLite emitted the rows in, which is stable for a
/// given statement on a given build.
///
/// Classification is a pure function of the row's own `detail` text plus its
/// already-known parent shape — needed only to tell a correlated scalar
/// subquery from an uncorrelated one, see ``isRowLoopingShape(_:)``. It never
/// reads the SQLite version, the host, or any other provenance field.
public enum SQLiteBuildValidationPlanShapeClassifier {
    public static func classify(
        rows: [SQLiteBuildValidationPlanRow]
    ) -> [SQLiteBuildValidationPlanNode] {
        var childrenByParent: [Int64: [SQLiteBuildValidationPlanRow]] = [:]
        for row in rows {
            childrenByParent[row.parent, default: []].append(row)
        }
        return (childrenByParent[0] ?? []).map {
            node($0, parentShape: nil, childrenByParent: childrenByParent)
        }
    }

    private static func node(
        _ row: SQLiteBuildValidationPlanRow,
        parentShape: SQLiteBuildValidationPlanShape?,
        childrenByParent: [Int64: [SQLiteBuildValidationPlanRow]]
    ) -> SQLiteBuildValidationPlanNode {
        let (shape, attributes) = classify(
            detail: row.detail,
            parentShape: parentShape
        )
        let children = (childrenByParent[row.id] ?? []).map {
            node($0, parentShape: shape, childrenByParent: childrenByParent)
        }
        return SQLiteBuildValidationPlanNode(
            detail: row.detail,
            shape: shape,
            attributes: attributes,
            children: children
        )
    }

    /// Classifies one detail string. Exposed so tests can exercise a detail
    /// form directly, without building a whole row tree for every case.
    static func classify(
        detail: String,
        parentShape: SQLiteBuildValidationPlanShape?
    ) -> (SQLiteBuildValidationPlanShape, SQLiteBuildValidationPlanAttributes) {
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
        let compoundTempBTreeSuffix = " USING TEMP B-TREE"
        if detail.hasSuffix(compoundTempBTreeSuffix),
           ["UNION", "EXCEPT", "INTERSECT"].contains(
               String(detail.dropLast(compoundTempBTreeSuffix.count))
           ) {
            return (.tempBTreeForCompoundOperation, .none)
        }
        if detail.hasPrefix("CO-ROUTINE ") {
            return (.coRoutineSubqueryOrCTE, .none)
        }
        if detail.hasPrefix("MATERIALIZE ") {
            return (.materializedSubqueryOrCTE, .none)
        }
        // SQLite says so itself on every build this repo tests against. Its
        // own word is the signal; the structural fallback below exists only
        // for a build that does not print it.
        if detail.hasPrefix("CORRELATED SCALAR SUBQUERY") {
            return (.correlatedScalarSubquery, .none)
        }
        if detail.hasPrefix("SCALAR SUBQUERY") {
            let shape: SQLiteBuildValidationPlanShape = isRowLoopingShape(parentShape)
                ? .correlatedScalarSubquery
                : .scalarSubquery
            return (shape, .none)
        }
        if detail.hasPrefix("LIST SUBQUERY") {
            return (.listSubquery, .none)
        }
        if let access = parseAccess(detail) {
            return classify(access)
        }
        return (.unclassified, .none)
    }

    /// Structural fallback for a SQLite build that does not label a
    /// correlated scalar subquery in its own detail text: a subquery SQLite
    /// can evaluate once is hoisted as a sibling of the driving row source,
    /// while one it must re-evaluate per outer row is nested under whichever
    /// row-producing node supplies the correlation.
    ///
    /// It is a fallback, not the primary signal, and #395's real fixture is
    /// why. On the SQLite this repo tests against, a genuinely correlated
    /// scalar subquery is emitted as a **top-level sibling** (`parent == 0`)
    /// carrying the explicit `CORRELATED SCALAR SUBQUERY` detail — so this
    /// heuristic alone would have called that real correlated subquery
    /// uncorrelated. The spike (#391) had no real corpus statement to catch
    /// that; the fixture this issue required did.
    private static func isRowLoopingShape(
        _ shape: SQLiteBuildValidationPlanShape?
    ) -> Bool {
        guard let shape else {
            return false
        }
        switch shape {
        case .fullTableScan, .coveringIndexScan, .indexSearch,
             .automaticCoveringIndex, .coRoutineSubqueryOrCTE,
             .recursiveCTEStep:
            return true
        case .tempBTreeForOrderBy, .tempBTreeForGroupBy,
             .tempBTreeForDistinctAggregate, .tempBTreeForCompoundOperation,
             .scalarSubquery, .correlatedScalarSubquery, .listSubquery,
             .materializedSubqueryOrCTE, .compoundQueryStrategy,
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

    private static func parseAccess(_ detail: String) -> ParsedAccess? {
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
            return ParsedAccess(
                isSearch: isSearch,
                table: remainder,
                using: nil,
                constraint: nil
            )
        }

        let table = String(remainder[remainder.startIndex..<usingRange.lowerBound])
        var usingClause = String(remainder[usingRange.upperBound...])
        var constraint: String?
        if let parenStart = usingClause.firstIndex(of: "("), usingClause.hasSuffix(")") {
            constraint = String(
                usingClause[
                    usingClause.index(after: parenStart)..<usingClause.index(
                        before: usingClause.endIndex
                    )
                ]
            )
            usingClause = String(usingClause[usingClause.startIndex..<parenStart])
                .trimmingCharacters(in: .whitespaces)
        }
        return ParsedAccess(
            isSearch: isSearch,
            table: table,
            using: usingClause,
            constraint: constraint
        )
    }

    private static func classify(
        _ access: ParsedAccess
    ) -> (SQLiteBuildValidationPlanShape, SQLiteBuildValidationPlanAttributes) {
        guard let using = access.using else {
            let shape: SQLiteBuildValidationPlanShape = access.isSearch
                ? .indexSearch
                : .fullTableScan
            return (shape, SQLiteBuildValidationPlanAttributes(table: access.table))
        }

        let columns = access.constraint.map(constrainedColumns(from:)) ?? []

        if using == "INTEGER PRIMARY KEY" || using == "PRIMARY KEY" {
            return (
                .indexSearch,
                SQLiteBuildValidationPlanAttributes(
                    table: access.table,
                    indexName: using,
                    constrainedColumns: columns
                )
            )
        }
        if using.hasPrefix("AUTOMATIC COVERING INDEX")
            || using.hasPrefix("AUTOMATIC PARTIAL COVERING INDEX") {
            return (
                .automaticCoveringIndex,
                SQLiteBuildValidationPlanAttributes(
                    table: access.table,
                    constrainedColumns: columns,
                    isCovering: true,
                    isAutomatic: true
                )
            )
        }
        if using.hasPrefix("COVERING INDEX ") {
            let name = String(using.dropFirst("COVERING INDEX ".count))
            let shape: SQLiteBuildValidationPlanShape = access.isSearch
                ? .indexSearch
                : .coveringIndexScan
            return (
                shape,
                SQLiteBuildValidationPlanAttributes(
                    table: access.table,
                    indexName: name,
                    constrainedColumns: columns,
                    isCovering: true
                )
            )
        }
        if using.hasPrefix("INDEX ") {
            let name = String(using.dropFirst("INDEX ".count))
            return (
                .indexSearch,
                SQLiteBuildValidationPlanAttributes(
                    table: access.table,
                    indexName: name,
                    constrainedColumns: columns
                )
            )
        }

        // An unrecognized "USING ..." form: keep the parsed table for audit,
        // but do not guess a shape for text this classifier has never seen.
        return (
            .unclassified,
            SQLiteBuildValidationPlanAttributes(table: access.table)
        )
    }

    private static func constrainedColumns(from constraint: String) -> [String] {
        constraint
            .components(separatedBy: " AND ")
            .compactMap { clause -> String? in
                let trimmed = clause.trimmingCharacters(in: .whitespaces)
                for comparison in [">=", "<=", "<>", "!=", "=", "<", ">"] {
                    if let range = trimmed.range(of: comparison) {
                        let column = String(
                            trimmed[trimmed.startIndex..<range.lowerBound]
                        ).trimmingCharacters(in: .whitespaces)
                        return column.isEmpty ? nil : column
                    }
                }
                return trimmed.isEmpty ? nil : trimmed
            }
    }
}
