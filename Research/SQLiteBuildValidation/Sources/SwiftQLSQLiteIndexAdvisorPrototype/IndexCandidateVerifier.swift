import Foundation
import GRDB
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype


/// A candidate's before-plan, DDL, and after-plan, captured as a single
/// evidence triple, plus whether the stated improvement rule accepted it.
package struct IndexCandidateEvidence: Codable, Equatable, Sendable {
    package let table: String
    package let columns: [String]
    package let ddl: String
    package let statementID: String
    package let beforePlan: EQPPlan
    package let afterPlan: EQPPlan
    package let isImprovement: Bool
    package let improvementReason: String

    package init(
        table: String,
        columns: [String],
        ddl: String,
        statementID: String,
        beforePlan: EQPPlan,
        afterPlan: EQPPlan,
        isImprovement: Bool,
        improvementReason: String
    ) {
        self.table = table
        self.columns = columns
        self.ddl = ddl
        self.statementID = statementID
        self.beforePlan = beforePlan
        self.afterPlan = afterPlan
        self.isImprovement = isImprovement
        self.improvementReason = improvementReason
    }

    private enum CodingKeys: String, CodingKey {
        case table
        case columns
        case ddl
        case statementID = "statement_id"
        case beforePlan = "before_plan"
        case afterPlan = "after_plan"
        case isImprovement = "is_improvement"
        case improvementReason = "improvement_reason"
    }
}


package enum IndexCandidateVerificationError: Error, Sendable {
    case statementNotCaptured(String)
}


/// Verifies one index candidate by creating it on a scratch copy of the
/// pinned Northwind snapshot and re-planning — never against the canonical
/// file or a long-lived application connection.
package enum IndexCandidateVerifier {
    /// `NorthwindFixture.withTemporaryCopy` copies the canonical file to a
    /// fresh temporary directory, hands this closure a writable pool scoped
    /// to that copy, and removes the copy afterward on every exit path
    /// (success, a thrown error from this closure, or a failure creating
    /// the copy itself) — exactly the "discard on every path including
    /// failure" this issue requires, reused rather than reimplemented.
    package static func verify(
        candidate: IndexCandidate,
        statement: EQPVarianceStatement
    ) throws -> IndexCandidateEvidence {
        try NorthwindFixture.withTemporaryCopy { copy in
            let beforePlan = try classifiedPlan(for: statement, pool: copy.databasePool, label: "before")

            try copy.databasePool.write { database in
                try database.execute(sql: candidate.ddl)
            }

            let afterPlan = try classifiedPlan(for: statement, pool: copy.databasePool, label: "after")

            let (isImprovement, reason) = applyImprovementRule(
                alias: candidate.representativeAlias,
                before: beforePlan,
                after: afterPlan
            )

            return IndexCandidateEvidence(
                table: candidate.table,
                columns: candidate.columns,
                ddl: candidate.ddl,
                statementID: statement.id,
                beforePlan: beforePlan,
                afterPlan: afterPlan,
                isImprovement: isImprovement,
                improvementReason: reason
            )
        }
    }

    private static func classifiedPlan(
        for statement: EQPVarianceStatement,
        pool: DatabasePool,
        label: String
    ) throws -> EQPPlan {
        let run = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: [statement], label: label)
        }
        guard let capture = run.statements.first(where: { $0.statementID == statement.id }) else {
            throw IndexCandidateVerificationError.statementNotCaptured(statement.id)
        }
        return EQPPlanShapeClassifier.classify(rows: capture.rows, statementID: statement.id)
    }

    /// The improvement rule, stated once here and applied uniformly to every
    /// candidate: kept only when the plan node for `alias` changes from
    /// `full_table_scan` to `index_search` or `covering_index_scan`, *and*
    /// the after-plan node reports at least one constrained column — proving
    /// the new index is actually narrowing the scan, not merely present and
    /// unused. No cost estimate or row-count comparison is used: the pinned
    /// snapshot is deliberately unanalyzed (no `sqlite_stat1`), so a
    /// structural shape change is the only signal available that isn't
    /// itself an unfounded guess.
    private static func applyImprovementRule(
        alias: String,
        before: EQPPlan,
        after: EQPPlan
    ) -> (Bool, String) {
        guard let beforeNode = findNode(forTable: alias, in: before) else {
            return (false, "no before-plan node found for alias \"\(alias)\"")
        }
        guard let afterNode = findNode(forTable: alias, in: after) else {
            return (false, "no after-plan node found for alias \"\(alias)\"")
        }
        guard beforeNode.shape == .fullTableScan else {
            return (false, "before-plan shape was \(beforeNode.shape.rawValue), not full_table_scan")
        }
        guard afterNode.shape == .indexSearch || afterNode.shape == .coveringIndexScan else {
            return (
                false,
                "after-plan shape was \(afterNode.shape.rawValue), expected index_search or covering_index_scan"
            )
        }
        guard !afterNode.attributes.constrainedColumns.isEmpty else {
            return (false, "after-plan node reports no constrained columns; the new index isn't narrowing the scan")
        }
        return (
            true,
            "shape changed from full_table_scan to \(afterNode.shape.rawValue), "
                + "constrained by \(afterNode.attributes.constrainedColumns)"
        )
    }

    private static func findNode(forTable alias: String, in plan: EQPPlan) -> EQPPlanNode? {
        for root in plan.roots {
            if let found = findNode(forTable: alias, in: root) {
                return found
            }
        }
        return nil
    }

    private static func findNode(forTable alias: String, in node: EQPPlanNode) -> EQPPlanNode? {
        if node.attributes.table == alias {
            return node
        }
        for child in node.children {
            if let found = findNode(forTable: alias, in: child) {
                return found
            }
        }
        return nil
    }
}
