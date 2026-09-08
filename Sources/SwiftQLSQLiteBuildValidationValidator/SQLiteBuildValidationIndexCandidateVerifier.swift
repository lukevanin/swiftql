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
    /// Every version requires one thing first: the index SQLite names in the
    /// after-plan for the candidate's representative alias must be **this
    /// candidate's own**. Without that clause a candidate can be credited for
    /// an improvement some other index produced.
    ///
    /// **v2** then accepts either of two kinds of evidence:
    ///
    /// - **A narrowed scan.** The alias's node changes from
    ///   `full_table_scan` or `automatic_covering_index` to an index search
    ///   or covering index scan, and the after node reports at least one
    ///   constrained column — proving the index narrows the scan rather than
    ///   merely being present. `automatic_covering_index` counts as a
    ///   remediable "before" shape because it is SQLite's own ephemeral
    ///   workaround for exactly what a persistent index fixes.
    /// - **A removed sort.** A `USE TEMP B-TREE FOR ORDER BY` or
    ///   `FOR GROUP BY` node the before-plan had is gone from the after-plan.
    ///
    /// **v1 had only the first**, and rejected every sort-serving index —
    /// which is the whole remedy for two of the three shapes #395 diagnoses.
    /// The to-do demo (#484) is what surfaced it: `Tag(name)`,
    /// `Todo(createdAt, position)` and `TodoList(position, name)` each
    /// removed a temp B-tree outright and were each rejected for reporting
    /// no constrained columns, because an index walked in order constrains
    /// nothing. The advice a developer most needed was the advice the rule
    /// could not accept.
    ///
    /// No cost estimate or row-count comparison enters the rule. The pinned
    /// snapshot is deliberately unanalyzed, so a structural change is the
    /// only signal available that is not itself a guess.
    public static let improvementRuleVersion = "swiftql-index-improvement-rule-v2"

    static let remediableBeforeShapes: Set<SQLiteBuildValidationPlanShape> = [
        .fullTableScan,
        .automaticCoveringIndex,
    ]
    static let improvedAfterShapes: Set<SQLiteBuildValidationPlanShape> = [
        .indexSearch,
        .coveringIndexScan,
    ]
    static let sortShapes: Set<SQLiteBuildValidationPlanShape> = [
        .tempBTreeForOrderBy,
        .tempBTreeForGroupBy,
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
                    reason: "Verification could not be completed: \(deterministicDescription(of: error))"
                ))
            }
        }

        return SQLiteBuildValidationIndexRecommendationSet(
            recommendations: recommendations,
            unverified: unverified
        )
    }

    /// How a failure is described in the sidecar.
    ///
    /// Only errors this validator raises *and* knows to be
    /// host-independent are described in full. Everything else is named by
    /// type. Two failures that read differently on two machines would break
    /// the artifact's byte-identical guarantee, and the paths a filesystem
    /// error embeds — a per-run temporary directory, most of all — are
    /// exactly that.
    static func deterministicDescription(of error: Error) -> String {
        guard let probeError = error as? SQLiteExplainQueryPlanProbeError else {
            return "an error of type \(type(of: error))."
        }
        return probeError.description
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
        // Which index SQLite adopted is checked first, because nothing that
        // follows is attributable to this candidate without it.
        guard afterNode.attributes.indexName == candidate.indexName else {
            let adopted = afterNode.attributes.indexName ?? "an unnamed index"
            return (
                false,
                "SQLite used \(adopted) rather than this candidate, so the improvement is not attributable to it."
            )
        }

        let narrowsTheScan = remediableBeforeShapes.contains(beforeNode.shape)
            && improvedAfterShapes.contains(afterNode.shape)
            && !afterNode.attributes.constrainedColumns.isEmpty
        if narrowsTheScan {
            return (
                true,
                "The plan for \"\(alias)\" changed from \(beforeNode.shape.rawValue) to \(afterNode.shape.rawValue) using \(candidate.indexName), constrained by \(afterNode.attributes.constrainedColumns.joined(separator: ", "))."
            )
        }

        let removedSorts = sortNodeCounts(before).subtracting(sortNodeCounts(after))
        if let removed = removedSorts.first {
            return (
                true,
                "The plan no longer materializes a temporary B-tree (\(removed.rawValue)); SQLite walks \(candidate.indexName) in order instead."
            )
        }

        return (
            false,
            "The plan for \"\(alias)\" was \(beforeNode.shape.rawValue) and is now \(afterNode.shape.rawValue) using \(candidate.indexName), but it narrows no column and removes no sort, so there is no measured improvement to report."
        )
    }

    /// The sort shapes a plan materializes, as a set, so "the after-plan no
    /// longer sorts" is a set difference rather than a hand-rolled walk.
    private static func sortNodeCounts(
        _ roots: [SQLiteBuildValidationPlanNode]
    ) -> Set<SQLiteBuildValidationPlanShape> {
        var found: Set<SQLiteBuildValidationPlanShape> = []
        func walk(_ node: SQLiteBuildValidationPlanNode) {
            if sortShapes.contains(node.shape) {
                found.insert(node.shape)
            }
            node.children.forEach(walk)
        }
        roots.forEach(walk)
        return found
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
