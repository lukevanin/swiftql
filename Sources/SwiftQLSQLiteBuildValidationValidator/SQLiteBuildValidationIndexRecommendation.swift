import Foundation


/// A verified index recommendation: the plan before, the DDL, and the plan
/// after.
///
/// The triple is the point. A recommendation that only says "add this index"
/// asks a developer to take it on trust; one that carries its own before and
/// after plan is a reviewable artifact they can judge without re-deriving the
/// reasoning.
public struct SQLiteBuildValidationIndexRecommendation:
    Codable,
    Equatable,
    Sendable
{
    public let candidate: SQLiteBuildValidationIndexCandidate
    /// The statement the before/after plans were captured for.
    public let statementID: String
    public let descriptorIdentity: String
    public let beforePlan: [SQLiteBuildValidationPlanNode]
    public let afterPlan: [SQLiteBuildValidationPlanNode]
    /// The improvement rule that accepted this candidate, by version, so a
    /// recommendation stays readable after the rule changes.
    public let improvementRuleVersion: String
    public let improvementReason: String
    /// What the index costs on writes, so the advice is not presented as
    /// free.
    public let writeCostNote: String

    public init(
        candidate: SQLiteBuildValidationIndexCandidate,
        statementID: String,
        descriptorIdentity: String,
        beforePlan: [SQLiteBuildValidationPlanNode],
        afterPlan: [SQLiteBuildValidationPlanNode],
        improvementRuleVersion: String,
        improvementReason: String,
        writeCostNote: String
    ) {
        self.candidate = candidate
        self.statementID = statementID
        self.descriptorIdentity = descriptorIdentity
        self.beforePlan = beforePlan
        self.afterPlan = afterPlan
        self.improvementRuleVersion = improvementRuleVersion
        self.improvementReason = improvementReason
        self.writeCostNote = writeCostNote
    }

    private enum CodingKeys: String, CodingKey {
        case candidate
        case statementID = "statement_id"
        case descriptorIdentity = "descriptor_identity"
        case beforePlan = "before_plan"
        case afterPlan = "after_plan"
        case improvementRuleVersion = "improvement_rule_version"
        case improvementReason = "improvement_reason"
        case writeCostNote = "write_cost_note"
    }
}


/// A candidate verification did not accept, and why.
///
/// Rejected ideas are reported rather than dropped. A candidate that vanishes
/// silently is indistinguishable from one that was never generated, and the
/// reason it failed is often the more useful half of the answer.
public struct SQLiteBuildValidationUnverifiedIndexCandidate:
    Codable,
    Equatable,
    Sendable
{
    public let candidate: SQLiteBuildValidationIndexCandidate
    public let statementID: String
    public let reason: String
    /// Present when the plans were captured and the rule simply rejected
    /// them; absent when verification could not get that far.
    public let beforePlan: [SQLiteBuildValidationPlanNode]?
    public let afterPlan: [SQLiteBuildValidationPlanNode]?

    public init(
        candidate: SQLiteBuildValidationIndexCandidate,
        statementID: String,
        reason: String,
        beforePlan: [SQLiteBuildValidationPlanNode]? = nil,
        afterPlan: [SQLiteBuildValidationPlanNode]? = nil
    ) {
        self.candidate = candidate
        self.statementID = statementID
        self.reason = reason
        self.beforePlan = beforePlan
        self.afterPlan = afterPlan
    }

    private enum CodingKeys: String, CodingKey {
        case candidate
        case statementID = "statement_id"
        case reason
        case beforePlan = "before_plan"
        case afterPlan = "after_plan"
    }
}


/// Everything one verification pass produced.
public struct SQLiteBuildValidationIndexRecommendationSet:
    Codable,
    Equatable,
    Sendable
{
    public let improvementRuleVersion: String
    public let recommendations: [SQLiteBuildValidationIndexRecommendation]
    public let unverified: [SQLiteBuildValidationUnverifiedIndexCandidate]

    public init(
        improvementRuleVersion: String = SQLiteBuildValidationIndexCandidateVerifier
            .improvementRuleVersion,
        recommendations: [SQLiteBuildValidationIndexRecommendation] = [],
        unverified: [SQLiteBuildValidationUnverifiedIndexCandidate] = []
    ) {
        self.improvementRuleVersion = improvementRuleVersion
        self.recommendations = recommendations.sorted {
            SQLiteBuildValidationIndexCandidate.canonicalOrder($0.candidate, $1.candidate)
        }
        self.unverified = unverified.sorted {
            SQLiteBuildValidationIndexCandidate.canonicalOrder($0.candidate, $1.candidate)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case improvementRuleVersion = "improvement_rule_version"
        case recommendations
        case unverified
    }
}
