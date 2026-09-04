import Foundation
import GRDB
import SwiftQLSQLiteBuildValidationManifest


/// Verifies index candidates by creating each one on a disposable copy of the
/// snapshot and re-planning the statement that motivated it.
///
/// A candidate is a guess until something tries it. This is the step that
/// turns it into evidence: a before-plan, the DDL, and an after-plan, bound to
/// the statement identities that asked for it.
///
/// Nothing here touches the pinned snapshot, an application connection, or a
/// long-lived pool. Every candidate is applied to a fresh scratch copy owned
/// by this pass, on a connection this pass opens and closes, and
/// ``SQLiteBuildValidationScratchSnapshot`` proves the original is
/// byte-identical afterwards or fails closed.
public enum SQLiteBuildValidationIndexCandidateVerifier {

    /// The improvement rule, versioned so a recommendation stays readable
    /// after the rule changes.
    ///
    /// **v1:** a candidate is kept only when the plan node for the
    /// representative alias changes from `full_table_scan` or
    /// `automatic_covering_index` to `index_search` or `covering_index_scan`,
    /// the after-plan node reports at least one constrained column, **and**
    /// the index SQLite names in the after-plan is this candidate's own.
    ///
    /// `automatic_covering_index` counts as a remediable "before" shape
    /// because it is SQLite's own ephemeral workaround for the situation a
    /// real index fixes — rebuilding a throwaway index on every execution
    /// instead of reusing a persistent one.
    ///
    /// No cost estimate or row-count comparison enters the rule. The pinned
    /// snapshot is deliberately unanalyzed, so a structural shape change is
    /// the only signal available that is not itself a guess.
    public static let improvementRuleVersion = "swiftql-index-improvement-rule-v1"

    static let remediableBeforeShapes: Set<SQLiteBuildValidationPlanShape> = [
        .fullTableScan,
        .automaticCoveringIndex,
    ]
    static let improvedAfterShapes: Set<SQLiteBuildValidationPlanShape> = [
        .indexSearch,
        .coveringIndexScan,
    ]

    /// Verifies every candidate in `candidates` against a scratch copy of the
    /// snapshot at `snapshotURL`.
    ///
    /// Each candidate gets its own scratch copy, so one candidate's index can
    /// never change the plan another is judged by.
    public static func verify(
        candidates: [SQLiteBuildValidationIndexCandidate],
        queries: [SQLiteBuildValidationQueryEntry],
        snapshotURL: URL,
        scratchParentDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> SQLiteBuildValidationIndexRecommendationSet {
        var queriesByID: [String: SQLiteBuildValidationQueryEntry] = [:]
        for query in queries {
            queriesByID[query.id] = query
        }

        var recommendations: [SQLiteBuildValidationIndexRecommendation] = []
        var unverified: [SQLiteBuildValidationUnverifiedIndexCandidate] = []

        for candidate in candidates.sorted(
            by: SQLiteBuildValidationIndexCandidate.canonicalOrder
        ) {
            guard let query = queriesByID[candidate.representativeQueryID] else {
                unverified.append(SQLiteBuildValidationUnverifiedIndexCandidate(
                    candidate: candidate,
                    statementID: candidate.representativeQueryID,
                    reason: "The statement this candidate would be verified against is not in the manifest."
                ))
                continue
            }
            do {
                switch try evaluate(
                    candidate: candidate,
                    query: query,
                    snapshotURL: snapshotURL,
                    scratchParentDirectory: scratchParentDirectory
                ) {
                case .recommended(let recommendation):
                    recommendations.append(recommendation)
                case .rejected(let rejection):
                    unverified.append(rejection)
                }
            } catch {
                // A candidate that could not be verified is reported
                // unverified, never recommended.
                unverified.append(SQLiteBuildValidationUnverifiedIndexCandidate(
                    candidate: candidate,
                    statementID: query.id,
                    reason: "Verification could not be completed: \(String(describing: error))"
                ))
            }
        }

        return SQLiteBuildValidationIndexRecommendationSet(
            recommendations: recommendations,
            unverified: unverified
        )
    }

    private enum Evaluation {
        case recommended(SQLiteBuildValidationIndexRecommendation)
        case rejected(SQLiteBuildValidationUnverifiedIndexCandidate)
    }

    private static func evaluate(
        candidate: SQLiteBuildValidationIndexCandidate,
        query: SQLiteBuildValidationQueryEntry,
        snapshotURL: URL,
        scratchParentDirectory: URL
    ) throws -> Evaluation {
        try SQLiteBuildValidationScratchSnapshot.withCopy(
            of: snapshotURL,
            in: scratchParentDirectory
        ) { copyURL in
            var configuration = Configuration()
            configuration.label = "SwiftQLSQLiteBuildValidationIndexVerification"
            let queue = try DatabaseQueue(
                path: copyURL.path,
                configuration: configuration
            )
            defer { try? queue.close() }

            let beforePlan = try queue.read { database in
                try plan(for: query, in: database)
            }
            try queue.write { database in
                try database.execute(sql: candidate.ddl)
            }
            let afterPlan = try queue.read { database in
                try plan(for: query, in: database)
            }
            let tableRowCount = try queue.read { database in
                try Self.rowCount(of: candidate.table, in: database)
            }

            let outcome = applyImprovementRule(
                candidate: candidate,
                before: beforePlan,
                after: afterPlan
            )
            guard outcome.isImprovement else {
                return .rejected(SQLiteBuildValidationUnverifiedIndexCandidate(
                    candidate: candidate,
                    statementID: query.id,
                    reason: outcome.reason,
                    beforePlan: beforePlan,
                    afterPlan: afterPlan
                ))
            }
            return .recommended(SQLiteBuildValidationIndexRecommendation(
                candidate: candidate,
                statementID: query.id,
                descriptorIdentity: query.descriptorIdentity,
                beforePlan: beforePlan,
                afterPlan: afterPlan,
                improvementRuleVersion: improvementRuleVersion,
                improvementReason: outcome.reason,
                writeCostNote: writeCostNote(for: candidate, rowCount: tableRowCount)
            ))
        }
    }

    private static func plan(
        for query: SQLiteBuildValidationQueryEntry,
        in database: Database
    ) throws -> [SQLiteBuildValidationPlanNode] {
        SQLiteBuildValidationPlanShapeClassifier.classify(
            rows: try SQLiteExplainQueryPlanProbe.rows(forSQL: query.sql, in: database)
        )
    }

    private static func rowCount(
        of table: String,
        in database: Database
    ) throws -> Int? {
        try? Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(SQLiteBuildValidationIndexCandidate.quoted(table))"
        )
    }

    /// The improvement rule, stated once and applied uniformly.
    static func applyImprovementRule(
        candidate: SQLiteBuildValidationIndexCandidate,
        before: [SQLiteBuildValidationPlanNode],
        after: [SQLiteBuildValidationPlanNode]
    ) -> (isImprovement: Bool, reason: String) {
        let alias = candidate.representativeAlias
        guard let beforeNode = node(forTable: alias, in: before) else {
            return (false, "No before-plan node names \"\(alias)\".")
        }
        guard let afterNode = node(forTable: alias, in: after) else {
            return (false, "No after-plan node names \"\(alias)\".")
        }
        guard remediableBeforeShapes.contains(beforeNode.shape) else {
            return (
                false,
                "The before-plan shape for \"\(alias)\" was \(beforeNode.shape.rawValue), not a full table scan or an automatic covering index, so there was nothing for this index to remediate."
            )
        }
        guard improvedAfterShapes.contains(afterNode.shape) else {
            return (
                false,
                "The after-plan shape for \"\(alias)\" was still \(afterNode.shape.rawValue); SQLite did not switch to an index search or a covering index scan."
            )
        }
        guard !afterNode.attributes.constrainedColumns.isEmpty else {
            return (
                false,
                "The after-plan node for \"\(alias)\" reports no constrained columns, so the new index is present but is not narrowing the scan."
            )
        }
        // Which index SQLite adopted matters. Without this, a candidate would
        // be credited for an improvement an existing index produced.
        guard afterNode.attributes.indexName == candidate.indexName else {
            let adopted = afterNode.attributes.indexName ?? "an unnamed index"
            return (
                false,
                "SQLite used \(adopted) rather than this candidate, so the improvement is not attributable to it."
            )
        }
        return (
            true,
            "The plan for \"\(alias)\" changed from \(beforeNode.shape.rawValue) to \(afterNode.shape.rawValue) using \(candidate.indexName), constrained by \(afterNode.attributes.constrainedColumns.joined(separator: ", "))."
        )
    }

    /// What the index costs on writes.
    ///
    /// An index is not free, and a recommendation that only shows the read
    /// side invites a developer to add one to a table whose writes matter more
    /// than the scan it removes.
    static func writeCostNote(
        for candidate: SQLiteBuildValidationIndexCandidate,
        rowCount: Int?
    ) -> String {
        let size = rowCount.map { "\($0) rows at verification time" }
            ?? "an unmeasured number of rows"
        return "This index adds a second B-tree over \"\(candidate.table)\" (\(size), \(candidate.columns.count) indexed column(s)). Every INSERT and DELETE on that table, and every UPDATE touching \(candidate.columns.map(\.name).joined(separator: ", ")), maintains it, and it occupies storage proportional to the table."
    }

    /// Prefers a root-level match across every root before any nested node.
    ///
    /// A per-root depth-first search would return a nested match from an
    /// earlier root before reaching a later root that matches at the top
    /// level, and a real Northwind statement has exactly that shape: a root
    /// `SCAN Products` beside a sibling scalar-subquery root whose own child
    /// is a second, nested `SCAN Products`. A candidate's representative
    /// alias always names a root-level table, so the root-level match is the
    /// intended node.
    static func node(
        forTable alias: String,
        in roots: [SQLiteBuildValidationPlanNode]
    ) -> SQLiteBuildValidationPlanNode? {
        if let rootMatch = roots.first(where: { $0.attributes.table == alias }) {
            return rootMatch
        }
        for root in roots {
            if let found = node(forTable: alias, in: root) {
                return found
            }
        }
        return nil
    }

    private static func node(
        forTable alias: String,
        in node: SQLiteBuildValidationPlanNode
    ) -> SQLiteBuildValidationPlanNode? {
        if node.attributes.table == alias {
            return node
        }
        for child in node.children {
            if let found = self.node(forTable: alias, in: child) {
                return found
            }
        }
        return nil
    }
}
