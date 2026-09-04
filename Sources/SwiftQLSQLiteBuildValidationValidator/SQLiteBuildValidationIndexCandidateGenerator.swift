import Foundation
import SwiftQLSQLiteBuildValidationManifest


/// Derives deterministic index candidates from captured plans and the
/// statements that produced them.
///
/// Generation only. Nothing here opens a database, creates an index, or
/// decides that a candidate is worth taking — verification (#397) owns that,
/// and no candidate may be reported as recommended before it.
public enum SQLiteBuildValidationIndexCandidateGenerator {

    /// The plan shapes worth proposing a candidate for.
    ///
    /// A `full_table_scan` is the obvious one: nothing indexes the table yet.
    /// `automatic_covering_index` belongs beside it because it is SQLite's
    /// own ephemeral workaround for the same situation — it builds and throws
    /// away a covering index on every execution, which is exactly what a
    /// persistent index replaces. The spike's re-plan evidence found this
    /// second shape necessary; without it the one real improvement it
    /// measured would not have been proposed.
    static let remediableShapes: Set<SQLiteBuildValidationPlanShape> = [
        .fullTableScan,
        .automaticCoveringIndex,
    ]

    /// One remediable `(statement, alias)` pair, before deduplication.
    private struct Remediable {
        let table: String
        let alias: String
        let columns: [SQLiteBuildValidationIndexCandidateColumn]
        let queryID: String
        let descriptorIdentity: String
    }

    public static func generate(
        queries: [SQLiteBuildValidationQueryEntry],
        planRoots: [String: [SQLiteBuildValidationPlanNode]],
        limits: SQLiteBuildValidationIndexCandidateLimits = .init()
    ) -> SQLiteBuildValidationIndexCandidateSet {
        var remediables: [Remediable] = []
        var truncations: [SQLiteBuildValidationIndexCandidateTruncation] = []
        var declines: [SQLiteBuildValidationIndexCandidateDecline] = []

        for query in queries.sorted(by: { $0.id < $1.id }) {
            guard let roots = planRoots[query.id] else {
                continue
            }
            let (statementRemediables, statementTruncations, statementDeclines) = analyze(
                query: query,
                roots: roots,
                limits: limits
            )
            remediables.append(contentsOf: statementRemediables)
            truncations.append(contentsOf: statementTruncations)
            declines.append(contentsOf: statementDeclines)
        }

        let (candidates, tableTruncations) = deduplicated(remediables, limits: limits)
        return SQLiteBuildValidationIndexCandidateSet(
            limits: limits,
            candidates: candidates,
            truncations: truncations + tableTruncations,
            declines: declines
        )
    }

    /// The column list for one alias, in SQLite's own composite-index order.
    ///
    /// Equality-constrained columns first — and **a join key is an equality
    /// constraint too**, so `WHERE`-equality columns and join-key columns
    /// share this leading tier. Then at most one range column: SQLite stops
    /// narrowing the seek at the first range term, so a second one adds
    /// width without adding selectivity. Then `ORDER BY` terms, so the same
    /// index can also satisfy the sort.
    ///
    /// This ordering is measured, not assumed. On a `LEFT JOIN` whose
    /// looked-up table is filtered on both a join key and a range,
    /// `Products(CategoryID, UnitPrice)` — join key first — is the index
    /// SQLite adopts, replacing its own ephemeral automatic index;
    /// `Products(UnitPrice, CategoryID)` is silently ignored and the plan
    /// comes back byte-identical to the baseline. A composite index can only
    /// be seeded by an equality prefix.
    public static func candidateColumns(
        for alias: String,
        in sql: String
    ) -> (columns: [SQLiteBuildValidationIndexCandidateColumn], isOrderingComplete: Bool) {
        let comparisons = SQLiteBuildValidationIndexPredicateExtractor.whereComparisons(
            for: alias,
            in: sql
        )
        let joinKeys = SQLiteBuildValidationIndexPredicateExtractor.joinKeys(
            for: alias,
            in: sql
        )
        let ordering = SQLiteBuildValidationIndexPredicateExtractor.orderByTerms(
            for: alias,
            in: sql
        )

        var columns: [SQLiteBuildValidationIndexCandidateColumn] = []
        var seen: Set<String> = []

        func append(_ column: SQLiteBuildValidationIndexCandidateColumn) {
            guard seen.insert(column.name).inserted else {
                return
            }
            columns.append(column)
        }

        // Tier one: equality-style constraints. `WHERE` equalities come
        // before join keys only to fix an order — SQLite treats the two
        // alike, and this artifact's bytes are a determinism gate.
        for comparison in comparisons where comparison.kind == .equality {
            append(SQLiteBuildValidationIndexCandidateColumn(name: comparison.column))
        }
        for key in joinKeys {
            append(SQLiteBuildValidationIndexCandidateColumn(name: key.column))
        }
        // Tier two: at most one range column.
        if let range = comparisons.first(where: { comparison in
            comparison.kind == .range && !seen.contains(comparison.column)
        }) {
            append(SQLiteBuildValidationIndexCandidateColumn(name: range.column))
        }
        // Tier three: the sort.
        for term in ordering.terms {
            append(SQLiteBuildValidationIndexCandidateColumn(
                name: term.column,
                direction: term.direction.map {
                    switch $0 {
                    case .ascending:
                        return .ascending
                    case .descending:
                        return .descending
                    }
                },
                collation: term.collation
            ))
        }
        return (columns, ordering.isComplete)
    }

    private static func analyze(
        query: SQLiteBuildValidationQueryEntry,
        roots: [SQLiteBuildValidationPlanNode],
        limits: SQLiteBuildValidationIndexCandidateLimits
    ) -> (
        [Remediable],
        [SQLiteBuildValidationIndexCandidateTruncation],
        [SQLiteBuildValidationIndexCandidateDecline]
    ) {
        let aliases = SQLiteBuildValidationPlanTableResolver.tableAliases(in: query.sql)
        var remediables: [Remediable] = []
        var truncations: [SQLiteBuildValidationIndexCandidateTruncation] = []
        var declines: [SQLiteBuildValidationIndexCandidateDecline] = []
        var seenAliases: Set<String> = []

        // Root nodes only. Remediating a scan nested inside a subquery needs
        // the subquery's own `FROM` scope, which this extractor does not
        // track; the spike scoped it out for the same reason.
        for root in roots where remediableShapes.contains(root.shape) {
            guard let alias = root.attributes.table,
                  seenAliases.insert(alias).inserted else {
                continue
            }
            guard let table = aliases[alias] else {
                declines.append(SQLiteBuildValidationIndexCandidateDecline(
                    queryID: query.id,
                    alias: alias,
                    table: nil,
                    reason: "The statement's FROM and JOIN clauses do not resolve \"\(alias)\" to one table, so no CREATE INDEX target can be named."
                ))
                continue
            }
            let (columns, isOrderingComplete) = candidateColumns(
                for: alias,
                in: query.sql
            )
            guard !columns.isEmpty else {
                declines.append(SQLiteBuildValidationIndexCandidateDecline(
                    queryID: query.id,
                    alias: alias,
                    table: table,
                    reason: isOrderingComplete
                        ? "The statement constrains \"\(alias)\" by no equality, range, join, or ORDER BY column this extractor can read, so there is nothing to index."
                        : "The statement's ORDER BY terms for \"\(alias)\" could not be read as plain columns with a determinable direction and collation."
                ))
                continue
            }
            var bounded = columns
            if bounded.count > limits.maximumColumns {
                truncations.append(SQLiteBuildValidationIndexCandidateTruncation(
                    kind: .columns,
                    queryID: query.id,
                    table: table,
                    limit: limits.maximumColumns,
                    observed: bounded.count
                ))
                bounded = Array(bounded.prefix(limits.maximumColumns))
            }
            remediables.append(Remediable(
                table: table,
                alias: alias,
                columns: bounded,
                queryID: query.id,
                descriptorIdentity: query.descriptorIdentity
            ))
        }

        if remediables.count > limits.maximumCandidatesPerStatement {
            truncations.append(SQLiteBuildValidationIndexCandidateTruncation(
                kind: .candidatesPerStatement,
                queryID: query.id,
                table: nil,
                limit: limits.maximumCandidatesPerStatement,
                observed: remediables.count
            ))
            remediables = Array(
                remediables
                    .sorted { $0.table < $1.table }
                    .prefix(limits.maximumCandidatesPerStatement)
            )
        }
        return (remediables, truncations, declines)
    }

    /// Merges candidates for the same `(table, columns)`, collapses a
    /// candidate whose columns are an exact prefix of a wider one on the same
    /// table, and applies the per-table bound.
    ///
    /// A dropped prefix folds its source statements into every wider
    /// candidate it prefixes before it goes, so a statement that only ever
    /// produced the narrower index is still attributed to the one that now
    /// serves it.
    private static func deduplicated(
        _ remediables: [Remediable],
        limits: SQLiteBuildValidationIndexCandidateLimits
    ) -> (
        [SQLiteBuildValidationIndexCandidate],
        [SQLiteBuildValidationIndexCandidateTruncation]
    ) {
        var merged: [String: (
            table: String,
            columns: [SQLiteBuildValidationIndexCandidateColumn],
            sources: [(queryID: String, descriptorIdentity: String, alias: String)]
        )] = [:]
        for remediable in remediables {
            let key = ([remediable.table] + remediable.columns.map(\.canonicalKey))
                .joined(separator: "\u{0}")
            merged[key, default: (remediable.table, remediable.columns, [])]
                .sources
                .append((remediable.queryID, remediable.descriptorIdentity, remediable.alias))
        }

        let all = Array(merged.values)

        func widerThan(_ candidate: (
            table: String,
            columns: [SQLiteBuildValidationIndexCandidateColumn],
            sources: [(queryID: String, descriptorIdentity: String, alias: String)]
        )) -> [Int] {
            all.indices.filter { index in
                let other = all[index]
                return other.table == candidate.table
                    && other.columns.count > candidate.columns.count
                    && other.columns.prefix(candidate.columns.count).map(\.canonicalKey)
                        == candidate.columns.map(\.canonicalKey)
            }
        }

        var foldedSources: [Int: [(queryID: String, descriptorIdentity: String, alias: String)]] = [:]
        for candidate in all {
            for index in widerThan(candidate) {
                foldedSources[index, default: []].append(contentsOf: candidate.sources)
            }
        }

        var candidates: [SQLiteBuildValidationIndexCandidate] = []
        for (index, candidate) in all.enumerated() where widerThan(candidate).isEmpty {
            let sources = candidate.sources + (foldedSources[index] ?? [])
            // The representative is the lexicographically first source, not
            // whichever happened to be discovered first: discovery order
            // follows manifest order, and this output must not.
            guard let representative = sources.min(by: { $0.queryID < $1.queryID }) else {
                continue
            }
            candidates.append(SQLiteBuildValidationIndexCandidate(
                table: candidate.table,
                columns: candidate.columns,
                sourceQueryIDs: sources.map(\.queryID),
                sourceDescriptorIdentities: sources.map(\.descriptorIdentity),
                representativeQueryID: representative.queryID,
                representativeAlias: representative.alias
            ))
        }
        candidates.sort(by: SQLiteBuildValidationIndexCandidate.canonicalOrder)

        var truncations: [SQLiteBuildValidationIndexCandidateTruncation] = []
        var keptPerTable: [String: Int] = [:]
        var observedPerTable: [String: Int] = [:]
        for candidate in candidates {
            observedPerTable[candidate.table, default: 0] += 1
        }
        var bounded: [SQLiteBuildValidationIndexCandidate] = []
        for candidate in candidates {
            let kept = keptPerTable[candidate.table, default: 0]
            guard kept < limits.maximumCandidatesPerTable else {
                continue
            }
            keptPerTable[candidate.table] = kept + 1
            bounded.append(candidate)
        }
        for (table, observed) in observedPerTable
        where observed > limits.maximumCandidatesPerTable {
            truncations.append(SQLiteBuildValidationIndexCandidateTruncation(
                kind: .candidatesPerTable,
                queryID: nil,
                table: table,
                limit: limits.maximumCandidatesPerTable,
                observed: observed
            ))
        }
        return (bounded, truncations)
    }
}
