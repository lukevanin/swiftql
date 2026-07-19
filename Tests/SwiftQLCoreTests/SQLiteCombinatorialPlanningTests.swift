import Foundation
import XCTest

import SwiftQLSQLiteConformanceFixtures


final class SQLiteCombinatorialPlanningTests: XCTestCase {

    func testPlanIsByteDeterministicSortedAndUnique() throws {
        let first = try makePlanner().solve()
        let second = try makePlanner().solve()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.assignments).count, first.assignments.count)
        XCTAssertEqual(first.assignments, first.assignments.sorted(by: assignmentPrecedes))
        XCTAssertEqual(
            first.constraintDescriptors.map(\.id),
            first.constraintDescriptors.map(\.id).sorted()
        )
    }

    func testEveryFeasibleValuePairIsCovered() throws {
        let plan = try makePlanner().solve()
        let excludedPairs = Set(plan.exclusions.map(\.pair))
        let allPairs = pairs(in: plan.dimensions)

        for pair in allPairs where !excludedPairs.contains(pair) {
            XCTAssertTrue(
                plan.assignments.contains { assignment in
                    assignment[pair.first.dimensionID] == pair.first.valueID
                        && assignment[pair.second.dimensionID] == pair.second.valueID
                },
                "Uncovered feasible pair: \(pair)"
            )
        }

        XCTAssertEqual(plan.coverage.totalPairCount, allPairs.count)
        XCTAssertEqual(
            plan.coverage.feasiblePairCount,
            allPairs.count - excludedPairs.count
        )
        XCTAssertEqual(
            plan.coverage.coveredFeasiblePairCount,
            plan.coverage.feasiblePairCount
        )
        XCTAssertTrue(plan.coverage.hasCompleteFeasiblePairCoverage)
    }

    func testInfeasiblePairsCarryMachineReadableConstraintEvidence() throws {
        let plan = try makePlanner().solve()
        let exclusion = try XCTUnwrap(
            plan.exclusions.first { exclusion in
                exclusion.pair.first.dimensionID == "join"
                    && exclusion.pair.first.valueID == "left"
                    && exclusion.pair.second.dimensionID == "filter"
                    && exclusion.pair.second.valueID == "aggregate"
            }
        )

        XCTAssertEqual(
            exclusion.constraintDescriptors,
            [
                SQLiteCombinatorialConstraintDescriptor(
                    id: "left-aggregate-forbidden",
                    rationale: "LEFT JOIN aggregate cases require a grouped projection."
                )
            ]
        )
        XCTAssertFalse(exclusion.constraintDescriptors[0].id.isEmpty)
        XCTAssertFalse(exclusion.constraintDescriptors[0].rationale.isEmpty)
        XCTAssertEqual(plan.coverage.infeasiblePairCount, 1)
    }

    func testRequiredHigherOrderTupleIsCovered() throws {
        let plan = try makePlanner().solve()
        let tuple = try XCTUnwrap(plan.requiredTuples.first)

        XCTAssertEqual(tuple.assignment.entries.count, 3)
        XCTAssertTrue(plan.assignments.contains { $0.contains(tuple.assignment) })
        XCTAssertEqual(plan.coverage.requiredTupleCount, 1)
        XCTAssertEqual(plan.coverage.coveredRequiredTupleCount, 1)
        XCTAssertTrue(plan.coverage.hasCompleteRequiredTupleCoverage)
    }

    func testDuplicateRequiredCompletionsAndPairSeedsAreDeduplicated() throws {
        let entries = [
            entry("first", "only"),
            entry("second", "only"),
        ]
        let planner = SQLiteCombinatorialPlanner(
            dimensions: [
                dimension("first", ["only"]),
                dimension("second", ["only"]),
            ],
            requiredTuples: [
                SQLiteCombinatorialRequiredTuple(
                    id: "required.a",
                    rationale: "First explicit seed.",
                    entries: entries
                ),
                SQLiteCombinatorialRequiredTuple(
                    id: "required.b",
                    rationale: "The same selections remain one output case.",
                    entries: entries.reversed()
                ),
            ]
        )

        let plan = try planner.solve()

        XCTAssertEqual(plan.assignments.count, 1)
        XCTAssertEqual(Set(plan.assignments).count, 1)
        XCTAssertEqual(plan.coverage.generatedCaseCount, 1)
        XCTAssertEqual(plan.coverage.coveredRequiredTupleCount, 2)
        XCTAssertEqual(plan.coverage.coveredFeasiblePairCount, 1)
    }

    func testSearchNodeBudgetFailsInsteadOfClaimingInfeasibility() {
        let constraint = SQLiteCombinatorialConstraint(
            id: "only-final-all-one",
            rationale: "Only the all-one full assignment is accepted."
        ) { assignment in
            guard assignment.entries.count == 3 else {
                return true
            }
            return assignment.entries.allSatisfy { $0.valueID == "one" }
        }
        let planner = SQLiteCombinatorialPlanner(
            dimensions: [
                dimension("a", ["zero", "one"]),
                dimension("b", ["zero", "one"]),
                dimension("c", ["zero", "one"]),
            ],
            constraints: [constraint],
            limits: SQLiteCombinatorialPlanningLimits(
                maximumSearchNodes: 2,
                maximumCases: 100,
                maximumRequiredTuples: 10,
                maximumRequiredTupleArity: 3
            )
        )

        XCTAssertThrowsError(try planner.solve()) { error in
            XCTAssertEqual(
                error as? SQLiteCombinatorialPlanningError,
                .searchNodeLimitExceeded(limit: 2)
            )
        }
    }

    func testCaseBudgetIsEnforcedBeforeAddingAnotherUniqueAssignment() {
        let planner = SQLiteCombinatorialPlanner(
            dimensions: [
                dimension("a", ["zero", "one"]),
                dimension("b", ["zero", "one"]),
            ],
            limits: SQLiteCombinatorialPlanningLimits(
                maximumSearchNodes: 100,
                maximumCases: 1,
                maximumRequiredTuples: 10,
                maximumRequiredTupleArity: 2
            )
        )

        XCTAssertThrowsError(try planner.solve()) { error in
            XCTAssertEqual(
                error as? SQLiteCombinatorialPlanningError,
                .caseLimitExceeded(limit: 1)
            )
        }
    }

    func testRequiredTupleCountAndArityBoundsAreEnforced() {
        let dimensions = [
            dimension("a", ["one"]),
            dimension("b", ["one"]),
        ]
        let tuple = SQLiteCombinatorialRequiredTuple(
            id: "required.ab",
            rationale: "Exercises both dimensions.",
            entries: [entry("a", "one"), entry("b", "one")]
        )

        let countBoundPlanner = SQLiteCombinatorialPlanner(
            dimensions: dimensions,
            requiredTuples: [tuple],
            limits: SQLiteCombinatorialPlanningLimits(
                maximumSearchNodes: 10,
                maximumCases: 10,
                maximumRequiredTuples: 0,
                maximumRequiredTupleArity: 2
            )
        )
        XCTAssertThrowsError(try countBoundPlanner.solve()) { error in
            XCTAssertEqual(
                error as? SQLiteCombinatorialPlanningError,
                .requiredTupleCountLimitExceeded(limit: 0, actual: 1)
            )
        }

        let arityBoundPlanner = SQLiteCombinatorialPlanner(
            dimensions: dimensions,
            requiredTuples: [tuple],
            limits: SQLiteCombinatorialPlanningLimits(
                maximumSearchNodes: 10,
                maximumCases: 10,
                maximumRequiredTuples: 1,
                maximumRequiredTupleArity: 1
            )
        )
        XCTAssertThrowsError(try arityBoundPlanner.solve()) { error in
            XCTAssertEqual(
                error as? SQLiteCombinatorialPlanningError,
                .requiredTupleArityLimitExceeded(
                    id: "required.ab",
                    limit: 1,
                    actual: 2
                )
            )
        }
    }
}


private extension SQLiteCombinatorialPlanningTests {
    func makePlanner() -> SQLiteCombinatorialPlanner {
        let forbiddenPair = SQLiteCombinatorialConstraint(
            id: "left-aggregate-forbidden",
            rationale: "LEFT JOIN aggregate cases require a grouped projection."
        ) { assignment in
            !(assignment["join"] == "left" && assignment["filter"] == "aggregate")
        }
        let requiredTuple = SQLiteCombinatorialRequiredTuple(
            id: "required.inner-aggregate-one",
            rationale: "Retain one explicit three-way aggregate boundary.",
            entries: [
                entry("limit", "one"),
                entry("join", "inner"),
                entry("filter", "aggregate"),
            ]
        )
        return SQLiteCombinatorialPlanner(
            dimensions: [
                dimension("join", ["left", "inner"]),
                dimension("filter", ["none", "aggregate"]),
                dimension("limit", ["one", "none"]),
            ],
            constraints: [forbiddenPair],
            requiredTuples: [requiredTuple]
        )
    }

    func dimension(
        _ id: String,
        _ valueIDs: [String]
    ) -> SQLiteCombinatorialDimension {
        SQLiteCombinatorialDimension(id: id, valueIDs: valueIDs)
    }

    func entry(
        _ dimensionID: String,
        _ valueID: String
    ) -> SQLiteCombinatorialAssignmentEntry {
        SQLiteCombinatorialAssignmentEntry(
            dimensionID: dimensionID,
            valueID: valueID
        )
    }

    func pairs(
        in dimensions: [SQLiteCombinatorialDimension]
    ) -> [SQLiteCombinatorialPair] {
        guard dimensions.count >= 2 else {
            return []
        }

        var result: [SQLiteCombinatorialPair] = []
        for firstIndex in dimensions.indices.dropLast() {
            for secondIndex in dimensions.index(after: firstIndex)..<dimensions.endIndex {
                for firstValue in dimensions[firstIndex].values {
                    for secondValue in dimensions[secondIndex].values {
                        result.append(
                            SQLiteCombinatorialPair(
                                first: entry(dimensions[firstIndex].id, firstValue.id),
                                second: entry(dimensions[secondIndex].id, secondValue.id)
                            )
                        )
                    }
                }
            }
        }
        return result
    }

    func assignmentPrecedes(
        _ lhs: SQLiteCombinatorialAssignment,
        _ rhs: SQLiteCombinatorialAssignment
    ) -> Bool {
        let dimensions = [
            ("join", ["left", "inner"]),
            ("filter", ["none", "aggregate"]),
            ("limit", ["one", "none"]),
        ]
        for (dimensionID, values) in dimensions {
            guard
                let lhsValue = lhs[dimensionID],
                let rhsValue = rhs[dimensionID],
                lhsValue != rhsValue
            else {
                continue
            }
            return values.firstIndex(of: lhsValue)! < values.firstIndex(of: rhsValue)!
        }
        return false
    }
}
