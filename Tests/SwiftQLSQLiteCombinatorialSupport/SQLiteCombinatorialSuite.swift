import Foundation
import SwiftQL
import SwiftQLSQLiteConformanceFixtures


/// Deterministic construction failures that occur between the typed case
/// factory and the canonical SQLite combinatorial manifest.
public enum SQLiteCombinatorialSuiteError: Error, Equatable, Sendable {
    case invalidAssignment(reason: String)
    case duplicateCaseID(String)
    case caseLimitExceeded(limit: Int, actual: Int)
    case renderingFailed(caseID: String, message: String)
    case duplicateBinding(caseID: String, key: String)
    case conflictingBinding(caseID: String, key: String)
    case missingBinding(caseID: String, key: String)
    case unusedBinding(caseID: String, key: String)
    case missingRenderedPlaceholder(caseID: String, key: String)
    case inventoryVersionMismatch(manifest: String, inventory: String)
    case unknownInventoryFeature(caseID: String, featureID: String)
    case unknownNorthwindAnchor(caseID: String, anchorID: String)
}


/// Builds the bounded issue #191 plan, typed drafts, and canonical manifest,
/// including the finite overload-matrix extension completed by issue #286.
///
/// The default plan is pairwise across nine ordered SELECT dimensions, seeded
/// with explicit three- and six-way clause interactions plus three exact
/// nine-way semantic assignments. WHERE, GROUP BY, HAVING, ORDER BY, LIMIT, and
/// OFFSET remain independent dimensions, with SQL legality encoded as
/// machine-readable constraints. Supplemental CTE/compound and
/// adopted-expression cases are finite typed factories; gated prerequisites
/// are represented only as manifest exclusions and are never executable.
public enum SQLiteCombinatorialSuite {

    public static let maximumSelectCaseCount = 128
    public static let maximumCaseCount = 224
    public static let generatorVersion = "c191-v2"

    /// Returns the deterministic, bounded pairwise SELECT plan.
    public static func makePlan() throws -> SQLiteCombinatorialPlan {
        let rawPlan = try SQLiteCombinatorialPlanner(
            dimensions: selectDimensions,
            constraints: selectConstraints,
            requiredTuples: requiredSelectTuples,
            limits: SQLiteCombinatorialPlanningLimits(
                maximumSearchNodes: 100_000,
                maximumCases: 512,
                maximumRequiredTuples: requiredSelectTuples.count,
                maximumRequiredTupleArity: SQLiteTypedCombinatorialCases.dimensionOrder.count
            )
        ).solve()
        return try compact(rawPlan)
    }

    /// Builds all typed drafts from the default deterministic plan.
    public static func makeDrafts() throws -> [SQLiteCombinatorialCaseDraft] {
        try makeDrafts(from: makePlan())
    }

    /// Builds typed SELECT drafts from `plan`, then appends the finite typed
    /// CTE/compound and adopted-expression drafts.
    public static func makeDrafts(
        from plan: SQLiteCombinatorialPlan
    ) throws -> [SQLiteCombinatorialCaseDraft] {
        try validatePlanShape(plan)

        var requiredStrengthByAssignment: [String: Int] = [:]
        for tuple in plan.requiredTuples {
            guard let assignment = plan.assignments.first(where: {
                $0.contains(tuple.assignment)
            }) else {
                throw SQLiteCombinatorialSuiteError.invalidAssignment(
                    reason: "Plan omitted required tuple \(tuple.id)."
                )
            }
            let identity = stableAssignmentIdentity(assignment)
            requiredStrengthByAssignment[identity] = max(
                requiredStrengthByAssignment[identity] ?? 0,
                tuple.assignment.entries.count
            )
        }
        var drafts = try plan.assignments.map { assignment in
            let values = try assignmentDictionary(assignment)
            let strength = requiredStrengthByAssignment[stableAssignmentIdentity(values)]
                .map { "required-\($0)-way" }
                ?? "pairwise"
            return SQLiteTypedCombinatorialCases.selectCase(
                assignment: values,
                strength: strength
            )
        }
        drafts.append(contentsOf: SQLiteTypedCombinatorialCases.compoundAndCTECases())
        drafts.append(contentsOf: SQLiteTypedCombinatorialCases.northwindAdaptationCases())
        drafts.append(contentsOf: SQLiteTypedCombinatorialCases.adoptedExpressionCases())
        drafts.append(contentsOf: SQLiteTypedCombinatorialCases.inSubqueryCases())
        drafts.append(
            contentsOf: SQLiteTypedCombinatorialCases.booleanComparisonEqualityCases()
        )
        drafts.append(
            contentsOf: SQLiteTypedCombinatorialCases.arithmeticTextOptionalCases()
        )
        drafts.sort { $0.id < $1.id }

        try requireUniqueCaseIDs(drafts.map(\.id))
        let selectCount = drafts.count - supplementalDraftCount
        guard selectCount <= maximumSelectCaseCount else {
            throw SQLiteCombinatorialSuiteError.caseLimitExceeded(
                limit: maximumSelectCaseCount,
                actual: selectCount
            )
        }
        guard drafts.count <= maximumCaseCount else {
            throw SQLiteCombinatorialSuiteError.caseLimitExceeded(
                limit: maximumCaseCount,
                actual: drafts.count
            )
        }
        return drafts
    }

    /// Renders all default-plan drafts through SwiftQL's validated SQLite
    /// encoder and resolves every logical parameter slot to one supplied value.
    public static func makeCases() throws -> [SQLiteCombinatorialCase] {
        let plan = try makePlan()
        return try makeCases(from: plan)
    }

    /// Renders all drafts for an already-computed plan.
    public static func makeCases(
        from plan: SQLiteCombinatorialPlan
    ) throws -> [SQLiteCombinatorialCase] {
        let cases = try makeDrafts(from: plan).map {
            try render($0, selectConstraintIDs: Set(plan.constraintDescriptors.map(\.id)))
        }.sorted { $0.id < $1.id }
        try requireUniqueCaseIDs(cases.map(\.id))
        return cases
    }

    /// Produces the canonical manifest for the default plan.
    public static func makeManifest(
        inventoryVersion: String? = nil
    ) throws -> SQLiteCombinatorialManifest {
        try makeManifest(from: makePlan(), inventoryVersion: inventoryVersion)
    }

    /// Produces a canonical manifest from a previously computed plan.
    public static func makeManifest(
        from plan: SQLiteCombinatorialPlan,
        inventoryVersion: String? = nil
    ) throws -> SQLiteCombinatorialManifest {
        let inventory = try SQLiteConformanceInventory.load()
        let resolvedInventoryVersion = inventoryVersion ?? inventory.inventoryVersion
        guard resolvedInventoryVersion == inventory.inventoryVersion else {
            throw SQLiteCombinatorialSuiteError.inventoryVersionMismatch(
                manifest: resolvedInventoryVersion,
                inventory: inventory.inventoryVersion
            )
        }
        let manifest = SQLiteCombinatorialManifest(
            schemaVersion: 1,
            generatorVersion: generatorVersion,
            issue: 191,
            inventoryVersion: resolvedInventoryVersion,
            hardBounds: hardBounds,
            dimensions: manifestDimensions,
            constraints: manifestConstraints(from: plan),
            exclusions: manifestPairExclusions(from: plan) + gatedExclusions,
            coverage: manifestCoverage(from: plan),
            cases: try makeCases(from: plan)
        )
        try manifest.validate()
        try validateInventoryReferences(manifest, inventory: inventory)
        return manifest
    }
}


private extension SQLiteCombinatorialSuite {

    static func validateInventoryReferences(
        _ manifest: SQLiteCombinatorialManifest,
        inventory: SQLiteConformanceInventory
    ) throws {
        let featureIDs = Set(inventory.features.map(\.id))
        for testCase in manifest.cases {
            for featureID in testCase.inventoryFeatureIDs where !featureIDs.contains(featureID) {
                throw SQLiteCombinatorialSuiteError.unknownInventoryFeature(
                    caseID: testCase.id,
                    featureID: featureID
                )
            }
            for anchorID in testCase.northwindAnchorCaseIDs ?? []
                where !featureIDs.contains(anchorID) {
                throw SQLiteCombinatorialSuiteError.unknownNorthwindAnchor(
                    caseID: testCase.id,
                    anchorID: anchorID
                )
            }
        }
    }

    struct GatedPrerequisite {
        let issue: Int
        let id: String
        let title: String
    }

    static let gatedPrerequisites = [
        GatedPrerequisite(
            issue: 43,
            id: "direct-scalar-compounds",
            title: "direct scalar compounds"
        ),
        GatedPrerequisite(
            issue: 10,
            id: "cte-materialization-hints",
            title: "CTE materialization hints"
        ),
        GatedPrerequisite(issue: 139, id: "typed-ddl", title: "typed DDL"),
        GatedPrerequisite(issue: 57, id: "dml-returning", title: "DML RETURNING"),
        GatedPrerequisite(
            issue: 45,
            id: "natural-using-joins",
            title: "NATURAL and USING joins"
        ),
        GatedPrerequisite(
            issue: 70,
            id: "nullable-subquery-shapes",
            title: "nullable subquery shapes"
        ),
    ]

    static var supplementalDraftCount: Int {
        SQLiteTypedCombinatorialCases.compoundAndCTECases().count
            + SQLiteTypedCombinatorialCases.northwindAdaptationCases().count
            + SQLiteTypedCombinatorialCases.adoptedExpressionCases().count
            + SQLiteTypedCombinatorialCases.inSubqueryCases().count
            + SQLiteTypedCombinatorialCases.booleanComparisonEqualityCases().count
            + SQLiteTypedCombinatorialCases.arithmeticTextOptionalCases().count
    }

    static var selectDimensions: [SQLiteCombinatorialDimension] {
        SQLiteTypedCombinatorialCases.dimensionValues.map {
            SQLiteCombinatorialDimension(id: $0.id, valueIDs: $0.values)
        }
    }

    static var selectConstraints: [SQLiteCombinatorialConstraint] {
        [
            SQLiteCombinatorialConstraint(
                id: "select.having-requires-grouping",
                rationale: "A non-empty HAVING clause requires a non-empty GROUP BY clause."
            ) { assignment in
                guard let grouping = assignment["grouping"],
                      let having = assignment["having"] else {
                    return true
                }
                return having == "none" || grouping != "none"
            },
            SQLiteCombinatorialConstraint(
                id: "select.offset-requires-limit",
                rationale: "A non-empty OFFSET clause requires a non-empty LIMIT clause."
            ) { assignment in
                guard let limit = assignment["limit"],
                      let offset = assignment["offset"] else {
                    return true
                }
                return offset == "none" || limit != "none"
            },
        ]
    }

    static var requiredSelectTuples: [SQLiteCombinatorialRequiredTuple] {
        let partialClauseInteractions = [
            SQLiteCombinatorialRequiredTuple(
                id: "required-three-way-where-group-having",
                rationale: "High-risk WHERE, GROUP BY, and HAVING clause interaction.",
                entries: [
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "predicate",
                        valueID: "precedence"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "grouping",
                        valueID: "customer-id"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "having",
                        valueID: "count-greater-than-one"
                    ),
                ]
            ),
            SQLiteCombinatorialRequiredTuple(
                id: "required-six-way-where-group-order-pagination",
                rationale: "High-risk WHERE, GROUP BY, ORDER BY, LIMIT, and OFFSET staging with a bound predicate.",
                entries: [
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "predicate",
                        valueID: "named-binding"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "grouping",
                        valueID: "customer-id"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "having",
                        valueID: "none"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "ordering",
                        valueID: "ascending"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "limit",
                        valueID: "five"
                    ),
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: "offset",
                        valueID: "two"
                    ),
                ]
            ),
        ]
        let semanticInteractions = SQLiteTypedCombinatorialCases
            .requiredHigherOrderAssignments.enumerated().map {
            offset, assignment in
            SQLiteCombinatorialRequiredTuple(
                id: "required-nine-way-semantic-\(offset + 1)",
                rationale: "Explicit issue #191 nine-way semantic interaction \(offset + 1).",
                entries: SQLiteTypedCombinatorialCases.dimensionOrder.map {
                    SQLiteCombinatorialAssignmentEntry(
                        dimensionID: $0,
                        valueID: assignment[$0]!
                    )
                }
            )
        }
        return partialClauseInteractions + semanticInteractions
    }

    static let hardBounds = SQLiteCombinatorialHardBounds(
        maximumCaseCount: maximumCaseCount,
        maximumDimensionsPerCase: 9,
        maximumBindingsPerCase: 8,
        maximumRenderedSQLBytes: 4_096,
        maximumReproductionCommandBytes: 512,
        maximumReductionAttempts: 64
    )

    static var manifestDimensions: [SQLiteCombinatorialManifestDimension] {
        let select = SQLiteTypedCombinatorialCases.dimensionValues.map {
            SQLiteCombinatorialManifestDimension(
                id: $0.id,
                title: dimensionTitle($0.id),
                values: $0.values.map {
                    SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
                }
            )
        }
        let cteShape = SQLiteCombinatorialManifestDimension(
            id: "cte-shape",
            title: "CTE shape",
            values: ["ordinary-required", "ordinary-nullable", "recursive-required"].map {
                SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
            }
        )
        let compoundOperator = SQLiteCombinatorialManifestDimension(
            id: "compound-operator",
            title: "Compound operator",
            values: ["union", "union-all", "intersect", "except"].map {
                SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
            }
        )
        let expressionCases = SQLiteTypedCombinatorialCases.adoptedExpressionCases()
            .compactMap { $0.selections.first?.valueID }
        let expression = SQLiteCombinatorialManifestDimension(
            id: "expression-case",
            title: "Adopted expression case",
            values: expressionCases.map {
                SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
            }
        )
        let northwindAdaptation = SQLiteCombinatorialManifestDimension(
            id: "northwind-adaptation",
            title: "Pinned Northwind adaptation",
            values: SQLiteTypedCombinatorialCases.northwindAdaptationCases()
                .compactMap { $0.selections.first?.valueID }
                .map {
                    SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
                }
        )
        let inSubquery = SQLiteCombinatorialManifestDimension(
            id: "in-subquery-case",
            title: "Query-backed IN entry point",
            values: SQLiteTypedCombinatorialCases.inSubqueryCases()
                .compactMap { $0.selections.first?.valueID }
                .map {
                    SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
                }
        )
        let operatorCases = SQLiteCombinatorialManifestDimension(
            id: "operator-case",
            title: "Packed operator overload family",
            values: (SQLiteTypedCombinatorialCases.booleanComparisonEqualityCases()
                + SQLiteTypedCombinatorialCases.arithmeticTextOptionalCases())
                .compactMap { $0.selections.first?.valueID }
                .map {
                    SQLiteCombinatorialManifestDimensionValue(id: $0, label: $0)
                }
        )
        let gated = SQLiteCombinatorialManifestDimension(
            id: "gated-prerequisite",
            title: "Explicitly gated typed prerequisite",
            values: gatedPrerequisites.map {
                SQLiteCombinatorialManifestDimensionValue(
                    id: "issue-\($0.issue)-\($0.id)",
                    label: "#\($0.issue) \($0.title)"
                )
            }
        )
        return select + [
            cteShape,
            compoundOperator,
            expression,
            northwindAdaptation,
            inSubquery,
            operatorCases,
            gated,
        ]
    }

    static var gatedExclusions: [SQLiteCombinatorialManifestExclusion] {
        gatedPrerequisites.map { prerequisite in
            SQLiteCombinatorialManifestExclusion(
                id: "gated.issue-\(prerequisite.issue).\(prerequisite.id)",
                constraintID: nil,
                reason: "Not executable in issue #191: typed prerequisite #\(prerequisite.issue) (\(prerequisite.title)) is not implemented.",
                dimensionVector: [
                    SQLiteCombinatorialCaseDimensionSelection(
                        dimensionID: "gated-prerequisite",
                        valueID: "issue-\(prerequisite.issue)-\(prerequisite.id)"
                    ),
                ]
            )
        }
    }

    static func dimensionTitle(_ id: String) -> String {
        switch id {
        case "projection": return "Projection"
        case "source": return "Source shape"
        case "join": return "Join shape"
        case "predicate": return "Predicate shape"
        case "grouping": return "GROUP BY shape"
        case "having": return "HAVING shape"
        case "ordering": return "Ordering term"
        case "limit": return "LIMIT shape"
        case "offset": return "OFFSET shape"
        default: return id
        }
    }

    static func manifestConstraints(
        from plan: SQLiteCombinatorialPlan
    ) -> [SQLiteCombinatorialManifestConstraint] {
        plan.constraintDescriptors.map { descriptor in
            let dimensions: [String]
            switch descriptor.id {
            case "select.having-requires-grouping":
                dimensions = ["grouping", "having"]
            case "select.offset-requires-limit":
                dimensions = ["limit", "offset"]
            default:
                dimensions = []
            }
            return SQLiteCombinatorialManifestConstraint(
                id: descriptor.id,
                dimensionIDs: dimensions,
                description: descriptor.rationale
            )
        }.sorted { $0.id < $1.id }
    }

    static func manifestPairExclusions(
        from plan: SQLiteCombinatorialPlan
    ) -> [SQLiteCombinatorialManifestExclusion] {
        plan.exclusions.map { exclusion in
            let descriptors = exclusion.constraintDescriptors.sorted()
            let first = exclusion.pair.first
            let second = exclusion.pair.second
            return SQLiteCombinatorialManifestExclusion(
                id: "pair.\(first.dimensionID)-\(first.valueID).\(second.dimensionID)-\(second.valueID)",
                constraintID: descriptors.count == 1 ? descriptors[0].id : nil,
                reason: descriptors.map { "\($0.id): \($0.rationale)" }
                    .joined(separator: "; "),
                dimensionVector: [
                    SQLiteCombinatorialCaseDimensionSelection(
                        dimensionID: first.dimensionID,
                        valueID: first.valueID
                    ),
                    SQLiteCombinatorialCaseDimensionSelection(
                        dimensionID: second.dimensionID,
                        valueID: second.valueID
                    ),
                ]
            )
        }.sorted { $0.id < $1.id }
    }

    static func manifestCoverage(
        from plan: SQLiteCombinatorialPlan
    ) -> [SQLiteCombinatorialManifestCoverage] {
        var coverage = [
            SQLiteCombinatorialManifestCoverage(
                strength: 2,
                dimensionIDs: SQLiteTypedCombinatorialCases.dimensionOrder,
                requiredTupleCount: plan.coverage.feasiblePairCount,
                coveredTupleCount: plan.coverage.coveredFeasiblePairCount,
                excludedTupleCount: plan.coverage.infeasiblePairCount
            ),
            SQLiteCombinatorialManifestCoverage(
                strength: 2,
                dimensionIDs: ["cte-shape", "compound-operator"],
                requiredTupleCount: SQLiteTypedCombinatorialCases
                    .compoundAndCTECases().count,
                coveredTupleCount: SQLiteTypedCombinatorialCases
                    .compoundAndCTECases().count,
                excludedTupleCount: 0
            ),
            SQLiteCombinatorialManifestCoverage(
                strength: 1,
                dimensionIDs: ["expression-case"],
                requiredTupleCount: SQLiteTypedCombinatorialCases
                    .adoptedExpressionCases().count,
                coveredTupleCount: SQLiteTypedCombinatorialCases
                    .adoptedExpressionCases().count,
                excludedTupleCount: 0
            ),
            SQLiteCombinatorialManifestCoverage(
                strength: 1,
                dimensionIDs: ["northwind-adaptation"],
                requiredTupleCount: SQLiteTypedCombinatorialCases
                    .northwindAdaptationCases().count,
                coveredTupleCount: SQLiteTypedCombinatorialCases
                    .northwindAdaptationCases().count,
                excludedTupleCount: 0
            ),
        ]

        let requiredByDimensions = Dictionary(grouping: plan.requiredTuples) { tuple in
            requiredTupleDimensionIDs(tuple).joined(separator: "|")
        }
        let groups = requiredByDimensions.values.sorted { lhs, rhs in
            let lhsDimensions = requiredTupleDimensionIDs(lhs[0])
            let rhsDimensions = requiredTupleDimensionIDs(rhs[0])
            if lhsDimensions.count != rhsDimensions.count {
                return lhsDimensions.count < rhsDimensions.count
            }
            return lhsDimensions.lexicographicallyPrecedes(rhsDimensions)
        }
        coverage.append(contentsOf: groups.map { tuples in
            let dimensions = requiredTupleDimensionIDs(tuples[0])
            let covered = tuples.filter { tuple in
                plan.assignments.contains { $0.contains(tuple.assignment) }
            }.count
            return SQLiteCombinatorialManifestCoverage(
                strength: dimensions.count,
                dimensionIDs: dimensions,
                requiredTupleCount: tuples.count,
                coveredTupleCount: covered,
                excludedTupleCount: 0
            )
        })
        return coverage
    }

    static func requiredTupleDimensionIDs(
        _ tuple: SQLiteCombinatorialRequiredTuple
    ) -> [String] {
        let selected = Set(tuple.assignment.entries.map(\.dimensionID))
        return SQLiteTypedCombinatorialCases.dimensionOrder.filter(selected.contains)
    }

    static func validatePlanShape(_ plan: SQLiteCombinatorialPlan) throws {
        guard plan.dimensions == selectDimensions else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "Plan dimensions do not match the ordered issue #191 SELECT dimensions."
            )
        }
        guard plan.constraintDescriptors == selectConstraints.map(\.descriptor).sorted() else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "Plan constraints do not match the executable issue #191 SELECT constraints."
            )
        }
        guard plan.requiredTuples == requiredSelectTuples.sorted(by: requiredTuplePrecedes) else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "Plan does not carry the exact issue #191 three-, six-, and nine-way tuples."
            )
        }
        guard plan.coverage.hasCompleteFeasiblePairCoverage else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "Plan does not cover every feasible value pair."
            )
        }
        guard plan.coverage.hasCompleteRequiredTupleCoverage else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "Plan does not cover every required higher-order tuple."
            )
        }
    }

    static func compact(
        _ rawPlan: SQLiteCombinatorialPlan
    ) throws -> SQLiteCombinatorialPlan {
        let excludedPairs = Set(rawPlan.exclusions.map(\.pair))
        let feasiblePairs = allPairs(in: rawPlan.dimensions).filter {
            !excludedPairs.contains($0)
        }
        var selected: [SQLiteCombinatorialAssignment] = []
        var selectedSet: Set<SQLiteCombinatorialAssignment> = []

        // Seed the exact completion selected for every required partial or full
        // tuple before the deterministic pairwise compaction pass.
        for tuple in rawPlan.requiredTuples {
            guard let assignment = rawPlan.assignments.first(where: {
                $0.contains(tuple.assignment)
            }) else {
                throw SQLiteCombinatorialSuiteError.invalidAssignment(
                    reason: "Raw plan omitted required tuple \(tuple.id)."
                )
            }
            if selectedSet.insert(assignment).inserted {
                selected.append(assignment)
            }
        }

        var uncovered = Set(feasiblePairs.filter { pair in
            !selected.contains(where: { covers($0, pair: pair) })
        })
        let candidates = rawPlan.assignments.sorted(by: assignmentPrecedes)
        while !uncovered.isEmpty {
            var best: SQLiteCombinatorialAssignment?
            var bestScore = 0
            for candidate in candidates where !selectedSet.contains(candidate) {
                let score = uncovered.reduce(into: 0) { count, pair in
                    if covers(candidate, pair: pair) {
                        count += 1
                    }
                }
                if score > bestScore {
                    best = candidate
                    bestScore = score
                }
            }
            guard let best, bestScore > 0 else {
                throw SQLiteCombinatorialSuiteError.invalidAssignment(
                    reason: "Raw plan could not cover every feasible pair during deterministic compaction."
                )
            }
            selected.append(best)
            selectedSet.insert(best)
            uncovered = Set(uncovered.filter { !covers(best, pair: $0) })
        }

        // A stable reverse deletion pass removes a case only when every pair
        // and full required tuple remains represented by another selected case.
        let requiredAssignments = Set(rawPlan.requiredTuples.compactMap { tuple in
            selected.first(where: { $0.contains(tuple.assignment) })
        })
        for candidate in selected.sorted(by: assignmentPrecedes).reversed()
            where !requiredAssignments.contains(candidate) {
            let remainder = selected.filter { $0 != candidate }
            if feasiblePairs.allSatisfy({ pair in
                remainder.contains(where: { covers($0, pair: pair) })
            }) {
                selected = remainder
            }
        }
        selected.sort(by: assignmentPrecedes)

        guard selected.count <= maximumSelectCaseCount else {
            throw SQLiteCombinatorialSuiteError.caseLimitExceeded(
                limit: maximumSelectCaseCount,
                actual: selected.count
            )
        }
        let coverage = SQLiteCombinatorialCoverageMetrics(
            totalPairCount: rawPlan.coverage.totalPairCount,
            feasiblePairCount: rawPlan.coverage.feasiblePairCount,
            coveredFeasiblePairCount: rawPlan.coverage.feasiblePairCount,
            infeasiblePairCount: rawPlan.coverage.infeasiblePairCount,
            generatedCaseCount: selected.count,
            requiredTupleCount: rawPlan.coverage.requiredTupleCount,
            coveredRequiredTupleCount: rawPlan.coverage.requiredTupleCount,
            searchNodeCount: rawPlan.coverage.searchNodeCount
        )
        return SQLiteCombinatorialPlan(
            dimensions: rawPlan.dimensions,
            constraintDescriptors: rawPlan.constraintDescriptors,
            requiredTuples: rawPlan.requiredTuples,
            assignments: selected,
            exclusions: rawPlan.exclusions,
            coverage: coverage
        )
    }

    static func allPairs(
        in dimensions: [SQLiteCombinatorialDimension]
    ) -> [SQLiteCombinatorialPair] {
        guard dimensions.count > 1 else { return [] }
        var pairs: [SQLiteCombinatorialPair] = []
        for firstIndex in dimensions.indices.dropLast() {
            for secondIndex in dimensions.index(after: firstIndex)..<dimensions.endIndex {
                for firstValue in dimensions[firstIndex].values {
                    for secondValue in dimensions[secondIndex].values {
                        pairs.append(
                            SQLiteCombinatorialPair(
                                first: SQLiteCombinatorialAssignmentEntry(
                                    dimensionID: dimensions[firstIndex].id,
                                    valueID: firstValue.id
                                ),
                                second: SQLiteCombinatorialAssignmentEntry(
                                    dimensionID: dimensions[secondIndex].id,
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

    static func covers(
        _ assignment: SQLiteCombinatorialAssignment,
        pair: SQLiteCombinatorialPair
    ) -> Bool {
        assignment[pair.first.dimensionID] == pair.first.valueID
            && assignment[pair.second.dimensionID] == pair.second.valueID
    }

    static func assignmentPrecedes(
        _ lhs: SQLiteCombinatorialAssignment,
        _ rhs: SQLiteCombinatorialAssignment
    ) -> Bool {
        for dimension in selectDimensions {
            guard let lhsValue = lhs[dimension.id],
                  let rhsValue = rhs[dimension.id],
                  lhsValue != rhsValue else {
                continue
            }
            let lhsIndex: Int
            if let index = dimension.values.firstIndex(where: { $0.id == lhsValue }) {
                lhsIndex = index
            } else {
                lhsIndex = dimension.values.endIndex
            }
            let rhsIndex: Int
            if let index = dimension.values.firstIndex(where: { $0.id == rhsValue }) {
                rhsIndex = index
            } else {
                rhsIndex = dimension.values.endIndex
            }
            return NSNumber(value: lhsIndex).compare(NSNumber(value: rhsIndex))
                == .orderedAscending
        }
        return false
    }

    static func requiredTuplePrecedes(
        _ lhs: SQLiteCombinatorialRequiredTuple,
        _ rhs: SQLiteCombinatorialRequiredTuple
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return lhs.rationale < rhs.rationale
    }

    static func assignmentDictionary(
        _ assignment: SQLiteCombinatorialAssignment
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for entry in assignment.entries {
            guard result.updateValue(entry.valueID, forKey: entry.dimensionID) == nil else {
                throw SQLiteCombinatorialSuiteError.invalidAssignment(
                    reason: "Duplicate dimension \(entry.dimensionID)."
                )
            }
        }
        guard result.count == SQLiteTypedCombinatorialCases.dimensionOrder.count,
              SQLiteTypedCombinatorialCases.dimensionOrder.allSatisfy({ result[$0] != nil }) else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "A SELECT assignment is incomplete."
            )
        }
        for dimension in selectDimensions {
            guard let value = result[dimension.id],
                  dimension.values.contains(where: { $0.id == value }) else {
                throw SQLiteCombinatorialSuiteError.invalidAssignment(
                    reason: "Unknown value in dimension \(dimension.id)."
                )
            }
        }
        let partial = SQLiteCombinatorialPartialAssignment(
            entries: SQLiteTypedCombinatorialCases.dimensionOrder.map {
                SQLiteCombinatorialAssignmentEntry(
                    dimensionID: $0,
                    valueID: result[$0]!
                )
            }
        )
        guard selectConstraints.allSatisfy({ $0.allows(partial) }) else {
            throw SQLiteCombinatorialSuiteError.invalidAssignment(
                reason: "A SELECT assignment violates an executable issue #191 constraint."
            )
        }
        return result
    }

    static func stableAssignmentIdentity(_ assignment: [String: String]) -> String {
        SQLiteTypedCombinatorialCases.dimensionOrder.map {
            "\($0)=\(assignment[$0] ?? "<missing>")"
        }.joined(separator: "|")
    }

    static func stableAssignmentIdentity(
        _ assignment: SQLiteCombinatorialAssignment
    ) -> String {
        SQLiteTypedCombinatorialCases.dimensionOrder.map {
            "\($0)=\(assignment[$0] ?? "<missing>")"
        }.joined(separator: "|")
    }

    static func requireUniqueCaseIDs(_ ids: [String]) throws {
        var observed: Set<String> = []
        for id in ids where !observed.insert(id).inserted {
            throw SQLiteCombinatorialSuiteError.duplicateCaseID(id)
        }
    }

    static func render(
        _ draft: SQLiteCombinatorialCaseDraft,
        selectConstraintIDs: Set<String>
    ) throws -> SQLiteCombinatorialCase {
        let encoding: XLEncoding
        do {
            encoding = try XLiteEncoder(dialect: XLSQLiteDialect())
                .makeValidatedSQL(draft.statement)
        } catch {
            throw SQLiteCombinatorialSuiteError.renderingFailed(
                caseID: draft.id,
                message: String(describing: error)
            )
        }

        let bindings = try resolveBindings(
            draft.bindings,
            layout: encoding.parameterLayout,
            renderedSQL: encoding.sql,
            caseID: draft.id
        )
        let oracle = draft.semanticOracleID.map {
            SQLiteCombinatorialOracle(id: $0, kind: oracleKind(for: draft))
        }
        let isSelect = draft.selections.map(\.dimensionID)
            == SQLiteTypedCombinatorialCases.dimensionOrder

        return SQLiteCombinatorialCase(
            id: draft.id,
            template: draft.templateID,
            strength: draft.strength,
            dimensionVector: draft.selections.map {
                SQLiteCombinatorialCaseDimensionSelection(
                    dimensionID: $0.dimensionID,
                    valueID: $0.valueID
                )
            },
            constraintIDs: isSelect ? selectConstraintIDs.sorted() : [],
            inventoryFeatureIDs: draft.inventoryFeatureIDs,
            northwindAnchorCaseIDs: draft.northwindAnchorCaseIDs,
            requiredCapabilities: draft.requiredCapabilities,
            renderedSQL: encoding.sql,
            bindings: bindings,
            mode: oracle == nil ? .prepareOnly : .semantic,
            oracle: oracle,
            reproductionCommand: "SWIFTQL_COMBINATORIAL_CASE=\(draft.id) swift test --filter SQLiteCombinatorialConformanceTests"
        )
    }

    static func oracleKind(
        for draft: SQLiteCombinatorialCaseDraft
    ) -> SQLiteCombinatorialOracle.Kind {
        if draft.id.hasPrefix("c191.v1.cte.") {
            return .fixedValue
        }
        return .rawSQL
    }

    static func resolveBindings(
        _ supplied: [SQLiteCombinatorialDraftBinding],
        layout: XLParameterLayout,
        renderedSQL: String,
        caseID: String
    ) throws -> [SQLiteCombinatorialBinding] {
        var suppliedByKey: [XLBindingKey: XLSQLiteValue] = [:]
        for binding in supplied {
            if let existing = suppliedByKey[binding.key] {
                let key = bindingKeyDescription(binding.key)
                if existing == binding.value {
                    // A repeated logical placeholder may be listed at each
                    // typed construction site. Equal values coalesce; the SQL
                    // traversal below remains the source of repeatCount.
                    continue
                }
                throw SQLiteCombinatorialSuiteError.conflictingBinding(
                    caseID: caseID,
                    key: key
                )
            }
            suppliedByKey[binding.key] = binding.value
        }

        let layoutKeys = Set(layout.slots.map(\.key))
        for key in suppliedByKey.keys.sorted(by: bindingKeyPrecedes)
            where !layoutKeys.contains(key) {
            throw SQLiteCombinatorialSuiteError.unusedBinding(
                caseID: caseID,
                key: bindingKeyDescription(key)
            )
        }

        let occurrences = placeholderOccurrences(in: renderedSQL)
        return try layout.slots.map { slot in
            guard let value = suppliedByKey[slot.key] else {
                throw SQLiteCombinatorialSuiteError.missingBinding(
                    caseID: caseID,
                    key: bindingKeyDescription(slot.key)
                )
            }
            let repeatCount = occurrences[slot.key, default: 0]
            guard repeatCount > 0 else {
                throw SQLiteCombinatorialSuiteError.missingRenderedPlaceholder(
                    caseID: caseID,
                    key: bindingKeyDescription(slot.key)
                )
            }
            return SQLiteCombinatorialBinding(
                slot: slot,
                value: value,
                repeatCount: repeatCount
            )
        }
    }

    static func bindingKeyDescription(_ key: XLBindingKey) -> String {
        switch key {
        case .named(let name): return ":\(name)"
        case .indexed(let index): return "?\(index + 1)"
        }
    }

    static func bindingKeyPrecedes(_ lhs: XLBindingKey, _ rhs: XLBindingKey) -> Bool {
        bindingKeyDescription(lhs) < bindingKeyDescription(rhs)
    }

    /// Counts placeholders while ignoring quoted strings, quoted identifiers,
    /// and SQL comments. SwiftQL's SQLite dialect emits only `:name` and `?N`.
    static func placeholderOccurrences(in sql: String) -> [XLBindingKey: Int] {
        enum State {
            case normal
            case singleQuote
            case doubleQuote
            case backtick
            case bracket
            case lineComment
            case blockComment
        }

        let bytes = Array(sql.utf8)
        var state = State.normal
        var counts: [XLBindingKey: Int] = [:]
        var index = 0

        func isNameByte(_ byte: UInt8) -> Bool {
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 95
        }

        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : nil

            switch state {
            case .normal:
                if byte == 39 {
                    state = .singleQuote
                    index += 1
                } else if byte == 34 {
                    state = .doubleQuote
                    index += 1
                } else if byte == 96 {
                    state = .backtick
                    index += 1
                } else if byte == 91 {
                    state = .bracket
                    index += 1
                } else if byte == 45, next == 45 {
                    state = .lineComment
                    index += 2
                } else if byte == 47, next == 42 {
                    state = .blockComment
                    index += 2
                } else if byte == 58 {
                    var end = index + 1
                    while end < bytes.count, isNameByte(bytes[end]) {
                        end += 1
                    }
                    if end > index + 1,
                       let name = String(bytes: bytes[(index + 1)..<end], encoding: .utf8) {
                        counts[.named(name), default: 0] += 1
                        index = end
                    } else {
                        index += 1
                    }
                } else if byte == 63 {
                    var end = index + 1
                    while end < bytes.count, bytes[end] >= 48, bytes[end] <= 57 {
                        end += 1
                    }
                    if end > index + 1,
                       let text = String(bytes: bytes[(index + 1)..<end], encoding: .utf8),
                       let physicalIndex = Int(text),
                       physicalIndex > 0 {
                        counts[.indexed(physicalIndex - 1), default: 0] += 1
                        index = end
                    } else {
                        index += 1
                    }
                } else {
                    index += 1
                }

            case .singleQuote:
                if byte == 39, next == 39 {
                    index += 2
                } else if byte == 39 {
                    state = .normal
                    index += 1
                } else {
                    index += 1
                }

            case .doubleQuote:
                if byte == 34, next == 34 {
                    index += 2
                } else if byte == 34 {
                    state = .normal
                    index += 1
                } else {
                    index += 1
                }

            case .backtick:
                if byte == 96, next == 96 {
                    index += 2
                } else if byte == 96 {
                    state = .normal
                    index += 1
                } else {
                    index += 1
                }

            case .bracket:
                if byte == 93 {
                    state = .normal
                }
                index += 1

            case .lineComment:
                if byte == 10 || byte == 13 {
                    state = .normal
                }
                index += 1

            case .blockComment:
                if byte == 42, next == 47 {
                    state = .normal
                    index += 2
                } else {
                    index += 1
                }
            }
        }
        return counts
    }
}
