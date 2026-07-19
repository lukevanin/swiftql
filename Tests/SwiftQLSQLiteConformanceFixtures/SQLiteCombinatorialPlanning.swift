import Foundation


/// One stable value in an ordered combinatorial dimension.
public struct SQLiteCombinatorialValue: Codable, Equatable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}


/// An ordered dimension. Value declaration order is the solver's search order.
public struct SQLiteCombinatorialDimension:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let id: String
    public let values: [SQLiteCombinatorialValue]

    public init(id: String, values: [SQLiteCombinatorialValue]) {
        self.id = id
        self.values = values
    }

    public init(id: String, valueIDs: [String]) {
        self.init(
            id: id,
            values: valueIDs.map(SQLiteCombinatorialValue.init(id:))
        )
    }
}


/// A stable dimension/value selection used by partial and full assignments.
public struct SQLiteCombinatorialAssignmentEntry:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let dimensionID: String
    public let valueID: String

    public init(dimensionID: String, valueID: String) {
        self.dimensionID = dimensionID
        self.valueID = valueID
    }
}


/// An ordered subset of dimension selections supplied to constraint predicates.
///
/// The planner always presents entries in dimension declaration order. Public
/// construction remains intentionally lightweight; the planner validates and
/// canonicalizes required tuples before using them.
public struct SQLiteCombinatorialPartialAssignment:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let entries: [SQLiteCombinatorialAssignmentEntry]

    public init(entries: [SQLiteCombinatorialAssignmentEntry]) {
        self.entries = entries
    }

    public func valueID(for dimensionID: String) -> String? {
        entries.first { $0.dimensionID == dimensionID }?.valueID
    }

    public subscript(dimensionID: String) -> String? {
        valueID(for: dimensionID)
    }
}


/// One complete assignment, ordered by dimension declaration order.
public struct SQLiteCombinatorialAssignment:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let entries: [SQLiteCombinatorialAssignmentEntry]

    public init(entries: [SQLiteCombinatorialAssignmentEntry]) {
        self.entries = entries
    }

    public func valueID(for dimensionID: String) -> String? {
        entries.first { $0.dimensionID == dimensionID }?.valueID
    }

    public subscript(dimensionID: String) -> String? {
        valueID(for: dimensionID)
    }

    public func contains(_ partialAssignment: SQLiteCombinatorialPartialAssignment) -> Bool {
        partialAssignment.entries.allSatisfy { entry in
            valueID(for: entry.dimensionID) == entry.valueID
        }
    }
}


/// Stable, serializable identity and explanation for an executable constraint.
public struct SQLiteCombinatorialConstraintDescriptor:
    Codable,
    Comparable,
    Equatable,
    Hashable,
    Sendable
{
    public let id: String
    public let rationale: String

    public init(id: String, rationale: String) {
        self.id = id
        self.rationale = rationale
    }

    public static func < (
        lhs: SQLiteCombinatorialConstraintDescriptor,
        rhs: SQLiteCombinatorialConstraintDescriptor
    ) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.rationale < rhs.rationale
    }
}


/// A predicate must return `false` as soon as a partial assignment is known to
/// be impossible. Missing dimensions should otherwise be treated as undecided.
public typealias SQLiteCombinatorialConstraintPredicate = @Sendable (
    SQLiteCombinatorialPartialAssignment
) -> Bool


/// An executable constraint paired with a stable machine-readable descriptor.
public struct SQLiteCombinatorialConstraint: Sendable {
    public let descriptor: SQLiteCombinatorialConstraintDescriptor
    private let predicate: SQLiteCombinatorialConstraintPredicate

    public init(
        descriptor: SQLiteCombinatorialConstraintDescriptor,
        predicate: @escaping SQLiteCombinatorialConstraintPredicate
    ) {
        self.descriptor = descriptor
        self.predicate = predicate
    }

    public init(
        id: String,
        rationale: String,
        predicate: @escaping SQLiteCombinatorialConstraintPredicate
    ) {
        self.init(
            descriptor: SQLiteCombinatorialConstraintDescriptor(
                id: id,
                rationale: rationale
            ),
            predicate: predicate
        )
    }

    public func allows(_ assignment: SQLiteCombinatorialPartialAssignment) -> Bool {
        predicate(assignment)
    }
}


/// A partial assignment that must be represented by at least one generated case.
public struct SQLiteCombinatorialRequiredTuple:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let id: String
    public let rationale: String
    public let assignment: SQLiteCombinatorialPartialAssignment

    public init(
        id: String,
        rationale: String,
        assignment: SQLiteCombinatorialPartialAssignment
    ) {
        self.id = id
        self.rationale = rationale
        self.assignment = assignment
    }

    public init(
        id: String,
        rationale: String,
        entries: [SQLiteCombinatorialAssignmentEntry]
    ) {
        self.init(
            id: id,
            rationale: rationale,
            assignment: SQLiteCombinatorialPartialAssignment(entries: entries)
        )
    }
}


/// One value pair from two distinct dimensions, in dimension declaration order.
public struct SQLiteCombinatorialPair:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let first: SQLiteCombinatorialAssignmentEntry
    public let second: SQLiteCombinatorialAssignmentEntry

    public init(
        first: SQLiteCombinatorialAssignmentEntry,
        second: SQLiteCombinatorialAssignmentEntry
    ) {
        self.first = first
        self.second = second
    }
}


/// A value pair proven infeasible by exhaustive bounded search.
public struct SQLiteCombinatorialExclusion:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let pair: SQLiteCombinatorialPair
    public let constraintDescriptors: [SQLiteCombinatorialConstraintDescriptor]

    public init(
        pair: SQLiteCombinatorialPair,
        constraintDescriptors: [SQLiteCombinatorialConstraintDescriptor]
    ) {
        self.pair = pair
        self.constraintDescriptors = constraintDescriptors
    }
}


/// Auditable coverage and bounded-search accounting for a generated plan.
public struct SQLiteCombinatorialCoverageMetrics:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let totalPairCount: Int
    public let feasiblePairCount: Int
    public let coveredFeasiblePairCount: Int
    public let infeasiblePairCount: Int
    public let generatedCaseCount: Int
    public let requiredTupleCount: Int
    public let coveredRequiredTupleCount: Int
    public let searchNodeCount: Int

    public init(
        totalPairCount: Int,
        feasiblePairCount: Int,
        coveredFeasiblePairCount: Int,
        infeasiblePairCount: Int,
        generatedCaseCount: Int,
        requiredTupleCount: Int,
        coveredRequiredTupleCount: Int,
        searchNodeCount: Int
    ) {
        self.totalPairCount = totalPairCount
        self.feasiblePairCount = feasiblePairCount
        self.coveredFeasiblePairCount = coveredFeasiblePairCount
        self.infeasiblePairCount = infeasiblePairCount
        self.generatedCaseCount = generatedCaseCount
        self.requiredTupleCount = requiredTupleCount
        self.coveredRequiredTupleCount = coveredRequiredTupleCount
        self.searchNodeCount = searchNodeCount
    }

    public var hasCompleteFeasiblePairCoverage: Bool {
        coveredFeasiblePairCount == feasiblePairCount
    }

    public var hasCompleteRequiredTupleCoverage: Bool {
        coveredRequiredTupleCount == requiredTupleCount
    }
}


/// Hard limits that keep accidental search-space growth observable and bounded.
public struct SQLiteCombinatorialPlanningLimits:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let maximumSearchNodes: Int
    public let maximumCases: Int
    public let maximumRequiredTuples: Int
    public let maximumRequiredTupleArity: Int

    public init(
        maximumSearchNodes: Int = 100_000,
        maximumCases: Int = 1_000,
        maximumRequiredTuples: Int = 256,
        maximumRequiredTupleArity: Int = 16
    ) {
        self.maximumSearchNodes = maximumSearchNodes
        self.maximumCases = maximumCases
        self.maximumRequiredTuples = maximumRequiredTuples
        self.maximumRequiredTupleArity = maximumRequiredTupleArity
    }
}


/// A deterministic, serializable snapshot of generated assignments and coverage.
public struct SQLiteCombinatorialPlan:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let dimensions: [SQLiteCombinatorialDimension]
    public let constraintDescriptors: [SQLiteCombinatorialConstraintDescriptor]
    public let requiredTuples: [SQLiteCombinatorialRequiredTuple]
    public let assignments: [SQLiteCombinatorialAssignment]
    public let exclusions: [SQLiteCombinatorialExclusion]
    public let coverage: SQLiteCombinatorialCoverageMetrics

    public init(
        dimensions: [SQLiteCombinatorialDimension],
        constraintDescriptors: [SQLiteCombinatorialConstraintDescriptor],
        requiredTuples: [SQLiteCombinatorialRequiredTuple],
        assignments: [SQLiteCombinatorialAssignment],
        exclusions: [SQLiteCombinatorialExclusion],
        coverage: SQLiteCombinatorialCoverageMetrics
    ) {
        self.dimensions = dimensions
        self.constraintDescriptors = constraintDescriptors
        self.requiredTuples = requiredTuples
        self.assignments = assignments
        self.exclusions = exclusions
        self.coverage = coverage
    }
}


/// Structured validation and budget failures. Budget exhaustion is never
/// reported as an infeasible value pair.
public enum SQLiteCombinatorialPlanningError: Error, Equatable, Sendable {
    case invalidLimit(name: String, value: Int)
    case invalidDimension(reason: String)
    case invalidConstraint(reason: String)
    case invalidRequiredTuple(id: String, reason: String)
    case requiredTupleCountLimitExceeded(limit: Int, actual: Int)
    case requiredTupleArityLimitExceeded(id: String, limit: Int, actual: Int)
    case requiredTupleInfeasible(
        id: String,
        constraintDescriptors: [SQLiteCombinatorialConstraintDescriptor]
    )
    case searchNodeLimitExceeded(limit: Int)
    case caseLimitExceeded(limit: Int)
    case internalCoverageFailure(pair: SQLiteCombinatorialPair)
}


/// Deterministic pair-seeded constraint solver.
///
/// The solver retains only the current depth-first search path and selected
/// output cases. It never materializes the full Cartesian product.
public struct SQLiteCombinatorialPlanner: Sendable {
    public let dimensions: [SQLiteCombinatorialDimension]
    public let constraints: [SQLiteCombinatorialConstraint]
    public let requiredTuples: [SQLiteCombinatorialRequiredTuple]
    public let limits: SQLiteCombinatorialPlanningLimits

    public init(
        dimensions: [SQLiteCombinatorialDimension],
        constraints: [SQLiteCombinatorialConstraint] = [],
        requiredTuples: [SQLiteCombinatorialRequiredTuple] = [],
        limits: SQLiteCombinatorialPlanningLimits = .init()
    ) {
        self.dimensions = dimensions
        self.constraints = constraints
        self.requiredTuples = requiredTuples
        self.limits = limits
    }

    public func solve() throws -> SQLiteCombinatorialPlan {
        let validatedRequiredTuples = try validate()
        let pairs = allPairs()
        var searchNodeCount = 0
        var assignments: [SQLiteCombinatorialAssignment] = []
        var uniqueAssignments: Set<SQLiteCombinatorialAssignment> = []
        var exclusions: [SQLiteCombinatorialExclusion] = []

        func appendUnique(_ assignment: SQLiteCombinatorialAssignment) throws {
            guard !uniqueAssignments.contains(assignment) else {
                return
            }
            guard uniqueAssignments.count < limits.maximumCases else {
                throw SQLiteCombinatorialPlanningError.caseLimitExceeded(
                    limit: limits.maximumCases
                )
            }
            uniqueAssignments.insert(assignment)
            assignments.append(assignment)
        }

        // Required higher-order tuples are seeded first. Their completed cases
        // can cover later pairs and avoid unnecessary generated cases.
        for tuple in validatedRequiredTuples {
            let completion = try complete(
                tuple.assignment,
                searchNodeCount: &searchNodeCount
            )
            switch completion {
            case .assignment(let assignment):
                try appendUnique(assignment)
            case .infeasible(let descriptors):
                throw SQLiteCombinatorialPlanningError.requiredTupleInfeasible(
                    id: tuple.id,
                    constraintDescriptors: descriptors
                )
            }
        }

        for pair in pairs {
            if assignments.contains(where: { $0.contains(pair.partialAssignment) }) {
                continue
            }

            let completion = try complete(
                pair.partialAssignment,
                searchNodeCount: &searchNodeCount
            )
            switch completion {
            case .assignment(let assignment):
                try appendUnique(assignment)
            case .infeasible(let descriptors):
                exclusions.append(
                    SQLiteCombinatorialExclusion(
                        pair: pair,
                        constraintDescriptors: descriptors
                    )
                )
            }
        }

        assignments.sort(by: assignmentPrecedes)

        let excludedPairs = Set(exclusions.map(\.pair))
        var coveredFeasiblePairCount = 0
        for pair in pairs where !excludedPairs.contains(pair) {
            guard assignments.contains(where: { $0.contains(pair.partialAssignment) }) else {
                throw SQLiteCombinatorialPlanningError.internalCoverageFailure(
                    pair: pair
                )
            }
            coveredFeasiblePairCount += 1
        }

        let coveredRequiredTupleCount = validatedRequiredTuples.reduce(into: 0) {
            count, tuple in
            if assignments.contains(where: { $0.contains(tuple.assignment) }) {
                count += 1
            }
        }
        let feasiblePairCount = pairs.count - exclusions.count
        let coverage = SQLiteCombinatorialCoverageMetrics(
            totalPairCount: pairs.count,
            feasiblePairCount: feasiblePairCount,
            coveredFeasiblePairCount: coveredFeasiblePairCount,
            infeasiblePairCount: exclusions.count,
            generatedCaseCount: assignments.count,
            requiredTupleCount: validatedRequiredTuples.count,
            coveredRequiredTupleCount: coveredRequiredTupleCount,
            searchNodeCount: searchNodeCount
        )

        return SQLiteCombinatorialPlan(
            dimensions: dimensions,
            constraintDescriptors: constraints.map(\.descriptor).sorted(),
            requiredTuples: validatedRequiredTuples,
            assignments: assignments,
            exclusions: exclusions,
            coverage: coverage
        )
    }
}


private extension SQLiteCombinatorialPair {
    var partialAssignment: SQLiteCombinatorialPartialAssignment {
        SQLiteCombinatorialPartialAssignment(entries: [first, second])
    }
}


private extension SQLiteCombinatorialPlanner {
    enum Completion {
        case assignment(SQLiteCombinatorialAssignment)
        case infeasible([SQLiteCombinatorialConstraintDescriptor])
    }

    func validate() throws -> [SQLiteCombinatorialRequiredTuple] {
        guard limits.maximumSearchNodes > 0 else {
            throw SQLiteCombinatorialPlanningError.invalidLimit(
                name: "maximumSearchNodes",
                value: limits.maximumSearchNodes
            )
        }
        guard limits.maximumCases > 0 else {
            throw SQLiteCombinatorialPlanningError.invalidLimit(
                name: "maximumCases",
                value: limits.maximumCases
            )
        }
        guard limits.maximumRequiredTuples >= 0 else {
            throw SQLiteCombinatorialPlanningError.invalidLimit(
                name: "maximumRequiredTuples",
                value: limits.maximumRequiredTuples
            )
        }
        guard limits.maximumRequiredTupleArity > 0 else {
            throw SQLiteCombinatorialPlanningError.invalidLimit(
                name: "maximumRequiredTupleArity",
                value: limits.maximumRequiredTupleArity
            )
        }
        guard !dimensions.isEmpty else {
            throw SQLiteCombinatorialPlanningError.invalidDimension(
                reason: "At least one dimension is required."
            )
        }

        var dimensionIDs: Set<String> = []
        var valuesByDimension: [String: Set<String>] = [:]
        for dimension in dimensions {
            guard !dimension.id.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidDimension(
                    reason: "Dimension IDs must not be empty."
                )
            }
            guard dimensionIDs.insert(dimension.id).inserted else {
                throw SQLiteCombinatorialPlanningError.invalidDimension(
                    reason: "Duplicate dimension ID: \(dimension.id)"
                )
            }
            guard !dimension.values.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidDimension(
                    reason: "Dimension \(dimension.id) has no values."
                )
            }

            var valueIDs: Set<String> = []
            for value in dimension.values {
                guard !value.id.isEmpty else {
                    throw SQLiteCombinatorialPlanningError.invalidDimension(
                        reason: "Dimension \(dimension.id) has an empty value ID."
                    )
                }
                guard valueIDs.insert(value.id).inserted else {
                    throw SQLiteCombinatorialPlanningError.invalidDimension(
                        reason: "Dimension \(dimension.id) has duplicate value ID: \(value.id)"
                    )
                }
            }
            valuesByDimension[dimension.id] = valueIDs
        }

        var constraintIDs: Set<String> = []
        for constraint in constraints {
            let descriptor = constraint.descriptor
            guard !descriptor.id.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidConstraint(
                    reason: "Constraint IDs must not be empty."
                )
            }
            guard !descriptor.rationale.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidConstraint(
                    reason: "Constraint \(descriptor.id) has no rationale."
                )
            }
            guard constraintIDs.insert(descriptor.id).inserted else {
                throw SQLiteCombinatorialPlanningError.invalidConstraint(
                    reason: "Duplicate constraint ID: \(descriptor.id)"
                )
            }
        }

        guard requiredTuples.count <= limits.maximumRequiredTuples else {
            throw SQLiteCombinatorialPlanningError.requiredTupleCountLimitExceeded(
                limit: limits.maximumRequiredTuples,
                actual: requiredTuples.count
            )
        }

        var tupleIDs: Set<String> = []
        var validatedTuples: [SQLiteCombinatorialRequiredTuple] = []
        for tuple in requiredTuples.sorted(by: requiredTuplePrecedes) {
            guard !tuple.id.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                    id: tuple.id,
                    reason: "Required tuple IDs must not be empty."
                )
            }
            guard tupleIDs.insert(tuple.id).inserted else {
                throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                    id: tuple.id,
                    reason: "Duplicate required tuple ID."
                )
            }
            guard !tuple.assignment.entries.isEmpty else {
                throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                    id: tuple.id,
                    reason: "Required tuples must select at least one dimension."
                )
            }
            guard tuple.assignment.entries.count <= limits.maximumRequiredTupleArity else {
                throw SQLiteCombinatorialPlanningError.requiredTupleArityLimitExceeded(
                    id: tuple.id,
                    limit: limits.maximumRequiredTupleArity,
                    actual: tuple.assignment.entries.count
                )
            }

            var selectedDimensionIDs: Set<String> = []
            var selectionsByDimension: [String: String] = [:]
            for entry in tuple.assignment.entries {
                guard dimensionIDs.contains(entry.dimensionID) else {
                    throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                        id: tuple.id,
                        reason: "Unknown dimension ID: \(entry.dimensionID)"
                    )
                }
                guard selectedDimensionIDs.insert(entry.dimensionID).inserted else {
                    throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                        id: tuple.id,
                        reason: "Duplicate dimension selection: \(entry.dimensionID)"
                    )
                }
                guard valuesByDimension[entry.dimensionID]?.contains(entry.valueID) == true else {
                    throw SQLiteCombinatorialPlanningError.invalidRequiredTuple(
                        id: tuple.id,
                        reason: "Unknown value \(entry.valueID) for dimension \(entry.dimensionID)."
                    )
                }
                selectionsByDimension[entry.dimensionID] = entry.valueID
            }

            let canonicalEntries = dimensions.compactMap { dimension -> SQLiteCombinatorialAssignmentEntry? in
                guard let valueID = selectionsByDimension[dimension.id] else {
                    return nil
                }
                return SQLiteCombinatorialAssignmentEntry(
                    dimensionID: dimension.id,
                    valueID: valueID
                )
            }
            validatedTuples.append(
                SQLiteCombinatorialRequiredTuple(
                    id: tuple.id,
                    rationale: tuple.rationale,
                    entries: canonicalEntries
                )
            )
        }
        return validatedTuples
    }

    func allPairs() -> [SQLiteCombinatorialPair] {
        guard dimensions.count >= 2 else {
            return []
        }

        var pairs: [SQLiteCombinatorialPair] = []
        for firstIndex in dimensions.indices.dropLast() {
            let firstDimension = dimensions[firstIndex]
            for secondIndex in dimensions.index(after: firstIndex)..<dimensions.endIndex {
                let secondDimension = dimensions[secondIndex]
                for firstValue in firstDimension.values {
                    for secondValue in secondDimension.values {
                        pairs.append(
                            SQLiteCombinatorialPair(
                                first: SQLiteCombinatorialAssignmentEntry(
                                    dimensionID: firstDimension.id,
                                    valueID: firstValue.id
                                ),
                                second: SQLiteCombinatorialAssignmentEntry(
                                    dimensionID: secondDimension.id,
                                    valueID: secondValue.id
                                )
                            )
                        )
                    }
                }
            }
        }
        return pairs
    }

    func complete(
        _ seed: SQLiteCombinatorialPartialAssignment,
        searchNodeCount: inout Int
    ) throws -> Completion {
        var selectedValues = Dictionary(
            uniqueKeysWithValues: seed.entries.map { ($0.dimensionID, $0.valueID) }
        )
        var violatedDescriptors: Set<SQLiteCombinatorialConstraintDescriptor> = []
        let assignment = try search(
            selectedValues: &selectedValues,
            violatedDescriptors: &violatedDescriptors,
            searchNodeCount: &searchNodeCount
        )

        if let assignment {
            return .assignment(assignment)
        }
        return .infeasible(violatedDescriptors.sorted())
    }

    func search(
        selectedValues: inout [String: String],
        violatedDescriptors: inout Set<SQLiteCombinatorialConstraintDescriptor>,
        searchNodeCount: inout Int
    ) throws -> SQLiteCombinatorialAssignment? {
        guard searchNodeCount < limits.maximumSearchNodes else {
            throw SQLiteCombinatorialPlanningError.searchNodeLimitExceeded(
                limit: limits.maximumSearchNodes
            )
        }
        searchNodeCount += 1

        let partialAssignment = canonicalPartialAssignment(from: selectedValues)
        let violations = constraints.filter { !$0.allows(partialAssignment) }
        if !violations.isEmpty {
            violatedDescriptors.formUnion(violations.map(\.descriptor))
            return nil
        }

        guard let nextDimension = dimensions.first(where: {
            selectedValues[$0.id] == nil
        }) else {
            return SQLiteCombinatorialAssignment(entries: partialAssignment.entries)
        }

        for value in nextDimension.values {
            selectedValues[nextDimension.id] = value.id
            if let assignment = try search(
                selectedValues: &selectedValues,
                violatedDescriptors: &violatedDescriptors,
                searchNodeCount: &searchNodeCount
            ) {
                selectedValues.removeValue(forKey: nextDimension.id)
                return assignment
            }
            selectedValues.removeValue(forKey: nextDimension.id)
        }
        return nil
    }

    func canonicalPartialAssignment(
        from selectedValues: [String: String]
    ) -> SQLiteCombinatorialPartialAssignment {
        SQLiteCombinatorialPartialAssignment(
            entries: dimensions.compactMap { dimension in
                guard let valueID = selectedValues[dimension.id] else {
                    return nil
                }
                return SQLiteCombinatorialAssignmentEntry(
                    dimensionID: dimension.id,
                    valueID: valueID
                )
            }
        )
    }

    func assignmentPrecedes(
        _ lhs: SQLiteCombinatorialAssignment,
        _ rhs: SQLiteCombinatorialAssignment
    ) -> Bool {
        for dimension in dimensions {
            guard
                let lhsValueID = lhs.valueID(for: dimension.id),
                let rhsValueID = rhs.valueID(for: dimension.id),
                lhsValueID != rhsValueID
            else {
                continue
            }

            let lhsIndex = dimension.values.firstIndex { $0.id == lhsValueID }
            let rhsIndex = dimension.values.firstIndex { $0.id == rhsValueID }
            return (lhsIndex ?? dimension.values.endIndex)
                < (rhsIndex ?? dimension.values.endIndex)
        }
        return false
    }

    func requiredTuplePrecedes(
        _ lhs: SQLiteCombinatorialRequiredTuple,
        _ rhs: SQLiteCombinatorialRequiredTuple
    ) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.rationale < rhs.rationale
    }
}
