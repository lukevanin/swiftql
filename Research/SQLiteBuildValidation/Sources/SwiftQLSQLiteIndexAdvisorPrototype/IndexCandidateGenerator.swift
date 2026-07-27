import Foundation
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype


/// One remediable (statement, table alias) pair before deduplication: a
/// `full_table_scan` root whose statement yielded a non-empty candidate
/// column list for that alias.
package struct RemediableCandidate: Equatable, Sendable {
    package let table: String
    package let columns: [String]
    package let statementID: String
    package let alias: String
}


/// A candidate index: a real table name plus an ordered column list, ready
/// to render as `CREATE INDEX` DDL. `representativeStatementID`/`Alias`
/// name one concrete statement this candidate can be verified against (the
/// first one found); `sourceStatementIDs` keeps every contributing
/// statement for provenance.
package struct IndexCandidate: Equatable, Sendable {
    package let table: String
    package let columns: [String]
    package let sourceStatementIDs: [String]
    package let representativeStatementID: String
    package let representativeAlias: String

    package init(
        table: String,
        columns: [String],
        sourceStatementIDs: [String],
        representativeStatementID: String,
        representativeAlias: String
    ) {
        self.table = table
        self.columns = columns
        self.sourceStatementIDs = sourceStatementIDs.sorted()
        self.representativeStatementID = representativeStatementID
        self.representativeAlias = representativeAlias
    }

    package var indexName: String {
        let sanitizedTable = table.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let sanitizedColumns = columns.map { column in
            String(column.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
        }
        return (["ix_advisor"] + [String(sanitizedTable)] + sanitizedColumns).joined(separator: "_")
    }

    package var ddl: String {
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        return "CREATE INDEX \"\(indexName)\" ON \"\(table)\" (\(columnList))"
    }
}


package enum IndexCandidateGenerator {
    /// Derives one candidate's column list for `alias` in `sql`, following
    /// SQLite's own left-to-right composite-index rule: equality-constrained
    /// columns first (any number of them can narrow a B-tree seek), then at
    /// most one range-constrained column (a second range column after the
    /// first cannot narrow the seek any further — SQLite stops using the
    /// index for narrowing at the first range term), then join-key columns,
    /// then `ORDER BY` columns (so the index can also satisfy sort order
    /// without a temp B-tree). Each column is included only once, at its
    /// highest-precedence position.
    package static func candidateColumns(for alias: String, in sql: String) -> [String] {
        let comparisons = IndexCandidateExtraction.whereComparisons(for: alias, in: sql)
        let equalityColumns = orderedUnique(comparisons.filter { $0.kind == .equality }.map(\.column))
        let rangeColumns = orderedUnique(comparisons.filter { $0.kind == .range }.map(\.column))
        let joinColumns = orderedUnique(IndexCandidateExtraction.joinKeys(for: alias, in: sql).map(\.column))
        let orderColumns = IndexCandidateExtraction.orderByColumns(for: alias, in: sql)

        var columns: [String] = []
        columns.append(contentsOf: equalityColumns)
        if let firstRange = rangeColumns.first(where: { !columns.contains($0) }) {
            columns.append(firstRange)
        }
        for column in joinColumns where !columns.contains(column) {
            columns.append(column)
        }
        for column in orderColumns where !columns.contains(column) {
            columns.append(column)
        }
        return columns
    }

    /// Finds every `full_table_scan` **root** node in a classified plan —
    /// deliberately not a recursive walk into every child node; see this
    /// issue's write-up ("only the driving table's roots are considered" —
    /// remediating a nested scan is left as future work) — and, where this
    /// statement's SQL yields a non-empty candidate column list for that
    /// node's table alias and the alias resolves to a real table (see
    /// `IndexCandidateExtraction.tableAliasMap`), produces a remediable
    /// candidate. A full table scan with no equality/range/join/order-by
    /// signal, or whose alias can't be confidently resolved, yields nothing
    /// — never a guess.
    package static func remediableCandidates(
        for statement: EQPVarianceStatement,
        plan: EQPPlan
    ) -> [RemediableCandidate] {
        let tableAliases = IndexCandidateExtraction.tableAliasMap(in: statement.renderedSQL)
        var candidates: [RemediableCandidate] = []
        for root in plan.roots {
            guard root.shape == .fullTableScan,
                  let alias = root.attributes.table,
                  let table = tableAliases[alias] else {
                continue
            }
            let columns = candidateColumns(for: alias, in: statement.renderedSQL)
            guard !columns.isEmpty else {
                continue
            }
            candidates.append(RemediableCandidate(
                table: table,
                columns: columns,
                statementID: statement.id,
                alias: alias
            ))
        }
        return candidates
    }

    /// Merges remediable candidates for the same `(table, columns)`
    /// (recording every contributing statement id, and keeping the first
    /// occurrence as the representative to verify against), then drops any
    /// candidate whose column list is an exact prefix of another surviving
    /// candidate on the same table — a wider index already serves every
    /// query the narrower prefix would have, so keeping both is redundant.
    package static func deduplicate(_ remediables: [RemediableCandidate]) -> [IndexCandidate] {
        var merged: [String: IndexCandidate] = [:]
        for remediable in remediables {
            let key = "\(remediable.table)\u{0}\(remediable.columns.joined(separator: "\u{0}"))"
            if let existing = merged[key] {
                merged[key] = IndexCandidate(
                    table: existing.table,
                    columns: existing.columns,
                    sourceStatementIDs: existing.sourceStatementIDs + [remediable.statementID],
                    representativeStatementID: existing.representativeStatementID,
                    representativeAlias: existing.representativeAlias
                )
            } else {
                merged[key] = IndexCandidate(
                    table: remediable.table,
                    columns: remediable.columns,
                    sourceStatementIDs: [remediable.statementID],
                    representativeStatementID: remediable.statementID,
                    representativeAlias: remediable.alias
                )
            }
        }

        let all = Array(merged.values)
        return all.filter { candidate in
            !all.contains { other in
                other.table == candidate.table
                    && other.columns.count > candidate.columns.count
                    && Array(other.columns.prefix(candidate.columns.count)) == candidate.columns
            }
        }.sorted { lhs, rhs in
            lhs.table != rhs.table ? lhs.table < rhs.table : lhs.columns.lexicographicallyPrecedes(rhs.columns)
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
