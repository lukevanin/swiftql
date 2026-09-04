import Foundation
import SwiftQLSQLiteBuildValidationManifest


/// Turns a captured plan into advisory findings.
///
/// A pure function of the classified plan, the statement's own SQL (only to
/// resolve an alias to its table), and the run's settings. It reads no
/// correctness verdict, produces nothing that can change one, and fires only
/// on shapes the classifier named — never on raw `EXPLAIN QUERY PLAN`
/// wording, which is the classifier's input rather than this layer's.
///
/// The four shapes it diagnoses are the ones the #390 measurement found
/// identical across two real SQLite builds for every statement that exercised
/// them, plus the correlated scalar subquery that #395's own Northwind
/// fixture pinned down.
public enum SQLiteBuildValidationPlanDiagnoser {

    /// The tables whose row counts the scan rule needs for this plan.
    ///
    /// Separate from ``diagnostics(for:roots:tableRowCounts:settings:)`` so
    /// the caller that owns the connection can count exactly these tables,
    /// once each, and the rule itself stays a pure function.
    public static func tablesNeedingRowCounts(
        for query: SQLiteBuildValidationQueryEntry,
        roots: [SQLiteBuildValidationPlanNode]
    ) -> Set<String> {
        let aliases = SQLiteBuildValidationPlanTableResolver.tableAliases(in: query.sql)
        var tables: Set<String> = []
        forEachNode(in: roots) { node, _ in
            guard node.shape == .fullTableScan,
                  let spelling = node.attributes.table,
                  let table = aliases[spelling] else {
                return
            }
            tables.insert(table)
        }
        return tables
    }

    public static func diagnostics(
        for query: SQLiteBuildValidationQueryEntry,
        roots: [SQLiteBuildValidationPlanNode],
        tableRowCounts: [String: Int],
        settings: SQLiteBuildValidationPlanDiagnosticSettings
    ) -> [SQLiteBuildValidationPlanDiagnostic] {
        let aliases = SQLiteBuildValidationPlanTableResolver.tableAliases(in: query.sql)
        var diagnostics: [SQLiteBuildValidationPlanDiagnostic] = []
        var emitted: Set<String> = []

        func emit(
            _ code: SQLiteBuildValidationPlanDiagnosticCode,
            node: SQLiteBuildValidationPlanNode,
            table: String?,
            alias: String?,
            tableRowCount: Int?,
            message: String
        ) {
            // One plan can name the same shape twice — two scans of the same
            // alias, say. The finding is the same finding.
            let key = [code.rawValue, alias ?? "", node.detail].joined(separator: "\u{0}")
            guard emitted.insert(key).inserted else {
                return
            }
            diagnostics.append(SQLiteBuildValidationPlanDiagnostic(
                code: code,
                queryID: query.id,
                definitionIdentity: query.definitionIdentity,
                descriptorIdentity: query.descriptorIdentity,
                table: table,
                alias: alias,
                tableRowCount: tableRowCount,
                planNodeShape: node.shape,
                planNodeDetail: node.detail,
                message: message
            ))
        }

        forEachNode(in: roots) { node, _ in
            switch node.shape {
            case .fullTableScan:
                // The rule reads a row count, so it needs a real table. An
                // alias this validator cannot resolve, or a table it cannot
                // count, produces no finding rather than a guessed one.
                guard let spelling = node.attributes.table,
                      let table = aliases[spelling],
                      let rowCount = tableRowCounts[table],
                      rowCount > settings.fullTableScanRowThreshold else {
                    return
                }
                emit(
                    .fullTableScan,
                    node: node,
                    table: table,
                    alias: spelling,
                    tableRowCount: rowCount,
                    message: "SQLite reads every row of \"\(table)\" (\(rowCount) rows, above the \(settings.fullTableScanRowThreshold)-row advisory threshold) to answer this query. An index covering the columns it filters, joins, and orders by would let SQLite seek instead of scan."
                )
            case .tempBTreeForOrderBy:
                emit(
                    .tempBTreeForOrderBy,
                    node: node,
                    table: nil,
                    alias: nil,
                    tableRowCount: nil,
                    message: "SQLite materializes a temporary B-tree to satisfy this query's ORDER BY, because no index already returns the rows in that order. An index whose trailing columns match the ORDER BY terms removes the sort."
                )
            case .tempBTreeForGroupBy:
                emit(
                    .tempBTreeForGroupBy,
                    node: node,
                    table: nil,
                    alias: nil,
                    tableRowCount: nil,
                    message: "SQLite materializes a temporary B-tree to group this query's rows, because no index already returns them in grouping order. An index leading with the GROUP BY columns removes the sort."
                )
            case .correlatedScalarSubquery:
                emit(
                    .correlatedScalarSubquery,
                    node: node,
                    table: nil,
                    alias: nil,
                    tableRowCount: nil,
                    message: "This query evaluates a scalar subquery once per outer row, because the subquery reads a column of the outer row. A join, or an index that makes the inner lookup a seek, avoids repeating the work."
                )
            case .coveringIndexScan, .indexSearch, .automaticCoveringIndex,
                 .tempBTreeForDistinctAggregate, .tempBTreeForCompoundOperation,
                 .scalarSubquery, .listSubquery, .coRoutineSubqueryOrCTE,
                 .materializedSubqueryOrCTE, .compoundQueryStrategy,
                 .recursiveCTEStep, .constantRowScan, .bloomFilter,
                 .unclassified:
                // Not a diagnosed shape. `unclassified` is listed explicitly
                // rather than swept into a `default`, so a shape this
                // validator does not recognise can never acquire a
                // diagnostic by accident.
                return
            }
        }

        return diagnostics.sorted(by: SQLiteBuildValidationPlanDiagnostic.canonicalOrder)
    }

    /// Partitions `diagnostics` into what survives the checked-in
    /// suppressions and what those suppressions silenced.
    ///
    /// A silenced diagnostic is kept, with the reason the repository gave, so
    /// a decision to ignore a finding leaves a trace.
    public static func applying(
        suppressions: [SQLiteBuildValidationPlanSuppression],
        to diagnostics: [SQLiteBuildValidationPlanDiagnostic]
    ) -> (
        reported: [SQLiteBuildValidationPlanDiagnostic],
        suppressed: [SQLiteBuildValidationSuppressedPlanDiagnostic]
    ) {
        var reported: [SQLiteBuildValidationPlanDiagnostic] = []
        var suppressed: [SQLiteBuildValidationSuppressedPlanDiagnostic] = []
        for diagnostic in diagnostics {
            if let rule = suppressions.first(where: { $0.silences(diagnostic) }) {
                suppressed.append(SQLiteBuildValidationSuppressedPlanDiagnostic(
                    diagnostic: diagnostic,
                    reason: rule.reason
                ))
            } else {
                reported.append(diagnostic)
            }
        }
        return (reported, suppressed)
    }

    /// The rules that silenced nothing in this run.
    ///
    /// A suppression whose finding has since been fixed, or whose query has
    /// been renamed, is a stale instruction to ignore something. Naming it
    /// lets a reviewer delete it.
    public static func unusedSuppressions(
        _ suppressions: [SQLiteBuildValidationPlanSuppression],
        against diagnostics: [SQLiteBuildValidationPlanDiagnostic]
    ) -> [SQLiteBuildValidationPlanSuppression] {
        suppressions.filter { rule in
            !diagnostics.contains(where: rule.silences)
        }
    }

    private static func forEachNode(
        in roots: [SQLiteBuildValidationPlanNode],
        _ body: (SQLiteBuildValidationPlanNode, SQLiteBuildValidationPlanNode?) -> Void
    ) {
        func walk(
            _ node: SQLiteBuildValidationPlanNode,
            parent: SQLiteBuildValidationPlanNode?
        ) {
            body(node, parent)
            for child in node.children {
                walk(child, parent: node)
            }
        }
        for root in roots {
            walk(root, parent: nil)
        }
    }
}
