import SwiftQL
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteConformanceFixtures
import XCTest


final class SQLiteCombinatorialClauseCoverageTests: XCTestCase {

    func testSelectDimensionsCoverEveryLegalPairWithTwoExactExclusions() throws {
        let plan = try SQLiteCombinatorialSuite.makePlan()
        let expectedDimensionIDs = [
            "projection",
            "source",
            "join",
            "predicate",
            "grouping",
            "having",
            "ordering",
            "limit",
            "offset",
        ]

        XCTAssertEqual(plan.dimensions.map(\.id), expectedDimensionIDs)
        XCTAssertEqual(
            SQLiteTypedCombinatorialCases.dimensionOrder,
            expectedDimensionIDs
        )
        XCTAssertLessThanOrEqual(
            plan.assignments.count,
            SQLiteCombinatorialSuite.maximumSelectCaseCount
        )
        XCTAssertEqual(plan.assignments.count, 114)
        XCTAssertTrue(plan.coverage.hasCompleteFeasiblePairCoverage)

        let havingConstraint = SQLiteCombinatorialConstraintDescriptor(
            id: "select.having-requires-grouping",
            rationale: "A non-empty HAVING clause requires a non-empty GROUP BY clause."
        )
        let offsetConstraint = SQLiteCombinatorialConstraintDescriptor(
            id: "select.offset-requires-limit",
            rationale: "A non-empty OFFSET clause requires a non-empty LIMIT clause."
        )
        XCTAssertEqual(
            plan.constraintDescriptors,
            [havingConstraint, offsetConstraint]
        )
        XCTAssertEqual(
            Set(plan.exclusions),
            Set([
                SQLiteCombinatorialExclusion(
                    pair: pair(
                        "grouping", "none",
                        "having", "count-greater-than-one"
                    ),
                    constraintDescriptors: [havingConstraint]
                ),
                SQLiteCombinatorialExclusion(
                    pair: pair("limit", "none", "offset", "two"),
                    constraintDescriptors: [offsetConstraint]
                ),
            ])
        )

        let excludedPairs = Set(plan.exclusions.map(\.pair))
        for candidate in allPairs(in: plan.dimensions)
            where !excludedPairs.contains(candidate) {
            XCTAssertTrue(
                plan.assignments.contains { assignment in
                    assignment[candidate.first.dimensionID]
                        == candidate.first.valueID
                        && assignment[candidate.second.dimensionID]
                        == candidate.second.valueID
                },
                "Uncovered legal pair: \(candidate)"
            )
        }
    }

    func testRequiredTuplesAndCoverageReportTheirTrueArities() throws {
        let plan = try SQLiteCombinatorialSuite.makePlan()
        let arityByID = Dictionary(uniqueKeysWithValues: plan.requiredTuples.map {
            ($0.id, $0.assignment.entries.count)
        })

        XCTAssertEqual(
            arityByID,
            [
                "required-three-way-where-group-having": 3,
                "required-six-way-where-group-order-pagination": 6,
                "required-nine-way-semantic-1": 9,
                "required-nine-way-semantic-2": 9,
                "required-nine-way-semantic-3": 9,
            ]
        )
        XCTAssertEqual(plan.coverage.requiredTupleCount, 5)
        XCTAssertEqual(plan.coverage.coveredRequiredTupleCount, 5)
        for tuple in plan.requiredTuples {
            XCTAssertTrue(
                plan.assignments.contains { $0.contains(tuple.assignment) },
                "Missing required tuple: \(tuple.id)"
            )
        }

        let manifest = try SQLiteCombinatorialSuite.makeManifest(from: plan)
        XCTAssertLessThanOrEqual(
            manifest.cases.count,
            SQLiteCombinatorialSuite.maximumCaseCount
        )
        // Issue #286 adds 27 finite expression cases, issue #288 adds five
        // finite query-backed IN cases, and issue #287 adds 35 packed
        // operator-family cases to issue #191's original 141-case manifest.
        // None of them changes the SELECT pairwise plan.
        XCTAssertEqual(manifest.cases.count, 208)
        let requiredStrengthCounts = Dictionary(
            grouping: try SQLiteCombinatorialSuite.makeDrafts(from: plan)
                .filter { $0.strength.hasPrefix("required-") },
            by: { $0.strength }
        ).mapValues { $0.count }
        XCTAssertEqual(
            requiredStrengthCounts,
            [
                "required-3-way": 1,
                "required-6-way": 1,
                "required-9-way": 3,
            ]
        )
        assertCoverage(
            manifest,
            strength: 2,
            dimensions: SQLiteTypedCombinatorialCases.dimensionOrder,
            required: plan.coverage.feasiblePairCount,
            covered: plan.coverage.coveredFeasiblePairCount,
            excluded: 2
        )
        assertCoverage(
            manifest,
            strength: 2,
            dimensions: ["cte-shape", "compound-operator"],
            required: 12,
            covered: 12
        )
        assertCoverage(
            manifest,
            strength: 1,
            dimensions: ["expression-case"],
            required: SQLiteTypedCombinatorialCases.adoptedExpressionCases().count,
            covered: SQLiteTypedCombinatorialCases.adoptedExpressionCases().count
        )
        assertCoverage(
            manifest,
            strength: 1,
            dimensions: ["northwind-adaptation"],
            required: SQLiteTypedCombinatorialCases.northwindAdaptationCases().count,
            covered: SQLiteTypedCombinatorialCases.northwindAdaptationCases().count
        )
        assertCoverage(
            manifest,
            strength: 3,
            dimensions: ["predicate", "grouping", "having"],
            required: 1,
            covered: 1
        )
        assertCoverage(
            manifest,
            strength: 6,
            dimensions: [
                "predicate", "grouping", "having", "ordering", "limit", "offset",
            ],
            required: 1,
            covered: 1
        )
        assertCoverage(
            manifest,
            strength: 9,
            dimensions: SQLiteTypedCombinatorialCases.dimensionOrder,
            required: 3,
            covered: 3
        )
    }

    func testAllLegalClauseStageCombinationsUsePublicSwiftQLOrdering() throws {
        let predicateValues = ["none", "literal"]
        let groupingHavingValues = [
            ("none", "none"),
            ("customer-id", "none"),
            ("customer-id", "count-greater-than-one"),
        ]
        let orderingValues = ["none", "ascending"]
        let limitOffsetValues = [
            ("none", "none"),
            ("five", "none"),
            ("five", "two"),
        ]
        var renderedCount = 0

        for predicate in predicateValues {
            for (grouping, having) in groupingHavingValues {
                for ordering in orderingValues {
                    for (limit, offset) in limitOffsetValues {
                        let assignment = baseAssignment(
                            predicate: predicate,
                            grouping: grouping,
                            having: having,
                            ordering: ordering,
                            limit: limit,
                            offset: offset
                        )
                        let draft = SQLiteTypedCombinatorialCases.selectCase(
                            assignment: assignment
                        )
                        let sql = try XLiteEncoder(dialect: XLSQLiteDialect())
                            .makeValidatedSQL(draft.statement).sql

                        XCTAssertEqual(
                            draft.selections.map(\.dimensionID),
                            SQLiteTypedCombinatorialCases.dimensionOrder
                        )
                        XCTAssertEqual(
                            draft.templateID,
                            expectedTemplateID(for: assignment)
                        )
                        assertClause(
                            "WHERE",
                            isPresent: predicate != "none",
                            in: sql
                        )
                        assertClause(
                            "GROUP BY",
                            isPresent: grouping != "none",
                            in: sql
                        )
                        assertClause(
                            "HAVING",
                            isPresent: having != "none",
                            in: sql
                        )
                        assertClause(
                            "ORDER BY",
                            isPresent: ordering != "none",
                            in: sql
                        )
                        assertClause(
                            "LIMIT",
                            isPresent: limit != "none",
                            in: sql
                        )
                        assertClause(
                            "OFFSET",
                            isPresent: offset != "none",
                            in: sql
                        )
                        assertClauseOrder(in: sql)
                        renderedCount += 1
                    }
                }
            }
        }

        XCTAssertEqual(renderedCount, 36)
    }

    func testSemanticAssignmentsRetainExactClauseShapesAndOracleIDs() throws {
        let drafts = try SQLiteCombinatorialSuite.makeDrafts()
        let expectedOracleIDs: Set<String> = [
            "oracle.c191.left-null-grouped-pagination",
            "oracle.c191.repeated-binding-aggregate",
            "oracle.c191.injection-binding",
        ]
        let semantic: [String: SQLiteCombinatorialCaseDraft] = Dictionary(
            uniqueKeysWithValues: drafts.compactMap {
                draft -> (String, SQLiteCombinatorialCaseDraft)? in
                guard let oracleID = draft.semanticOracleID,
                      expectedOracleIDs.contains(oracleID) else {
                    return nil
                }
                return (oracleID, draft)
            }
        )
        XCTAssertEqual(Set(semantic.keys), expectedOracleIDs)

        let left = try XCTUnwrap(
            semantic["oracle.c191.left-null-grouped-pagination"]
        )
        let leftSQL = try render(left)
        XCTAssertEqual(left.strength, "required-9-way")
        XCTAssertEqual(
            left.templateID,
            "select.where.group-by.having.order-by.limit.offset"
        )
        XCTAssertTrue(leftSQL.contains("LEFT JOIN"))
        XCTAssertTrue(leftSQL.contains("COLLATE"))
        assertClauseOrder(in: leftSQL)

        let repeated = try XCTUnwrap(
            semantic["oracle.c191.repeated-binding-aggregate"]
        )
        let repeatedSQL = try render(repeated)
        XCTAssertEqual(repeated.strength, "required-9-way")
        XCTAssertTrue(repeatedSQL.contains("INNER JOIN"))
        XCTAssertTrue(repeatedSQL.contains("DESC"))
        XCTAssertEqual(
            repeatedSQL.components(separatedBy: ":repeated_employee_id").count - 1,
            2
        )
        assertClauseOrder(in: repeatedSQL)

        let injection = try XCTUnwrap(
            semantic["oracle.c191.injection-binding"]
        )
        let injectionSQL = try render(injection)
        XCTAssertEqual(injection.strength, "required-9-way")
        XCTAssertEqual(injection.templateID, "select.where")
        XCTAssertTrue(injectionSQL.contains("CROSS JOIN"))
        XCTAssertTrue(injectionSQL.contains(":customer_input"))
        assertClause("WHERE", isPresent: true, in: injectionSQL)
        for clause in ["GROUP BY", "HAVING", "ORDER BY", "LIMIT", "OFFSET"] {
            assertClause(clause, isPresent: false, in: injectionSQL)
        }
    }
}


private extension SQLiteCombinatorialClauseCoverageTests {
    func baseAssignment(
        predicate: String,
        grouping: String,
        having: String,
        ordering: String,
        limit: String,
        offset: String
    ) -> [String: String] {
        [
            "projection": "order-id",
            "source": "table-auto",
            "join": "none",
            "predicate": predicate,
            "grouping": grouping,
            "having": having,
            "ordering": ordering,
            "limit": limit,
            "offset": offset,
        ]
    }

    func expectedTemplateID(for assignment: [String: String]) -> String {
        var clauses = ["select"]
        for (dimension, clause) in [
            ("predicate", "where"),
            ("grouping", "group-by"),
            ("having", "having"),
            ("ordering", "order-by"),
            ("limit", "limit"),
            ("offset", "offset"),
        ] where assignment[dimension] != "none" {
            clauses.append(clause)
        }
        if clauses.count == 1 {
            clauses.append("base")
        }
        return clauses.joined(separator: ".")
    }

    func render(_ draft: SQLiteCombinatorialCaseDraft) throws -> String {
        try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(draft.statement).sql
    }

    func assertClause(
        _ clause: String,
        isPresent: Bool,
        in sql: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            sql.contains(clause),
            isPresent,
            "Unexpected \(clause) presence in: \(sql)",
            file: file,
            line: line
        )
    }

    func assertClauseOrder(
        in sql: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var prior: String.Index?
        for clause in ["WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT", "OFFSET"] {
            guard let range = sql.range(of: clause) else { continue }
            if let prior {
                XCTAssertLessThan(
                    prior,
                    range.lowerBound,
                    "Clause order is invalid in: \(sql)",
                    file: file,
                    line: line
                )
            }
            prior = range.lowerBound
        }
    }

    func assertCoverage(
        _ manifest: SQLiteCombinatorialManifest,
        strength: Int,
        dimensions: [String],
        required: Int,
        covered: Int,
        excluded: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            manifest.coverage.contains {
                $0.strength == strength
                    && $0.dimensionIDs == dimensions
                    && $0.requiredTupleCount == required
                    && $0.coveredTupleCount == covered
                    && $0.excludedTupleCount == excluded
            },
            "Missing coverage row for strength \(strength), dimensions \(dimensions)",
            file: file,
            line: line
        )
    }

    func pair(
        _ firstDimension: String,
        _ firstValue: String,
        _ secondDimension: String,
        _ secondValue: String
    ) -> SQLiteCombinatorialPair {
        SQLiteCombinatorialPair(
            first: SQLiteCombinatorialAssignmentEntry(
                dimensionID: firstDimension,
                valueID: firstValue
            ),
            second: SQLiteCombinatorialAssignmentEntry(
                dimensionID: secondDimension,
                valueID: secondValue
            )
        )
    }

    func allPairs(
        in dimensions: [SQLiteCombinatorialDimension]
    ) -> [SQLiteCombinatorialPair] {
        guard dimensions.count > 1 else { return [] }
        var result: [SQLiteCombinatorialPair] = []
        for firstIndex in dimensions.indices.dropLast() {
            for secondIndex in dimensions.index(after: firstIndex)..<dimensions.endIndex {
                for first in dimensions[firstIndex].values {
                    for second in dimensions[secondIndex].values {
                        result.append(
                            pair(
                                dimensions[firstIndex].id,
                                first.id,
                                dimensions[secondIndex].id,
                                second.id
                            )
                        )
                    }
                }
            }
        }
        return result
    }
}
