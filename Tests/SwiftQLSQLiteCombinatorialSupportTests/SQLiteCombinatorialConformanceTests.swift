import Foundation
import GRDB
import SwiftQL
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteConformanceFixtures
import XCTest


final class SQLiteCombinatorialConformanceTests: XCTestCase {

    func testManifestReferencesCanonicalInventory() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let featureIDs = Set(inventory.features.map(\.id))

        XCTAssertEqual(manifest.inventoryVersion, inventory.inventoryVersion)
        for testCase in manifest.cases {
            XCTAssertTrue(
                Set(testCase.inventoryFeatureIDs).isSubset(of: featureIDs),
                testCase.id
            )
            XCTAssertTrue(
                Set(testCase.northwindAnchorCaseIDs ?? []).isSubset(of: featureIDs),
                testCase.id
            )
        }
    }

    func testGeneratedManifestIsDeterministicAndMatchesCheckedInArtifacts() throws {
        let first = try SQLiteCombinatorialSuite.makeManifest()
        let second = try SQLiteCombinatorialSuite.makeManifest()
        let firstJSON = try first.canonicalJSONData()
        let secondJSON = try second.canonicalJSONData()
        let firstSummary = try first.markdownSummary()

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstJSON, secondJSON)
        XCTAssertEqual(firstSummary, try second.markdownSummary())
        XCTAssertFalse(first.cases.isEmpty)
        XCTAssertLessThanOrEqual(first.cases.count, first.hardBounds.maximumCaseCount)
        XCTAssertTrue(first.coverage.contains { coverage in
            coverage.strength == 2
                && coverage.requiredTupleCount == coverage.coveredTupleCount
        })
        // Six, not seven: issue #21 shipped LIKE ESCAPE, so the manifest no
        // longer gates it as an unimplemented prerequisite.
        XCTAssertEqual(
            first.exclusions.filter { $0.id.hasPrefix("gated.") }.count,
            6
        )
        XCTAssertTrue(first.cases.allSatisfy { !$0.inventoryFeatureIDs.isEmpty })

        try writeConfiguredOutput(
            data: firstJSON,
            environmentKey: "SWIFTQL_COMBINATORIAL_MANIFEST_PATH"
        )
        try writeConfiguredOutput(
            data: Data(firstSummary.utf8),
            environmentKey: "SWIFTQL_COMBINATORIAL_SUMMARY_PATH"
        )

        let checkedManifest = repositoryRoot
            .appendingPathComponent("Conformance/SQLite/COMBINATORIAL_CASES.json")
        let checkedSummary = repositoryRoot
            .appendingPathComponent("Conformance/SQLite/COMBINATORIAL_SUMMARY.md")
        if ProcessInfo.processInfo.environment["SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS"] == "1" {
            try firstJSON.write(to: checkedManifest, options: .atomic)
            try Data(firstSummary.utf8).write(to: checkedSummary, options: .atomic)
        }
        else {
            XCTAssertEqual(
                try Data(contentsOf: checkedManifest),
                firstJSON,
                "Regenerate the checked manifest with SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS=1"
            )
            XCTAssertEqual(
                try Data(contentsOf: checkedSummary),
                Data(firstSummary.utf8),
                "Regenerate the checked summary with SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS=1"
            )
        }
    }

    func testIssue286FunctionOverloadMatrixIsExplicitAndBounded() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let issue286Cases = manifest.cases.filter {
            $0.id.hasPrefix("c286.v1.expression.")
        }
        let expectedSuffixes: Set<String> = [
            "aggregate-average-distinct",
            "aggregate-count-distinct",
            "aggregate-group-concat-distinct",
            "aggregate-max-distinct",
            "aggregate-min-distinct",
            "aggregate-sum-distinct",
            "cast-blob-text",
            "cast-bool-integer",
            "cast-integer-real",
            "cast-integer-text",
            "cast-optional-blob-text",
            "cast-optional-bool-integer",
            "cast-optional-integer-real",
            "cast-optional-integer-text",
            "cast-optional-real-integer",
            "cast-optional-real-text",
            "cast-optional-text-blob",
            "cast-optional-text-integer",
            "cast-optional-text-real",
            "cast-real-integer",
            "cast-real-text",
            "cast-text-real",
            "comparable-max",
            "json-array-length-path",
            "numeric-round-no-places",
            "numeric-round-optional",
            "string-printf-array",
        ]
        let actualSuffixes = Set(issue286Cases.map {
            String($0.id.dropFirst("c286.v1.expression.".count))
        })

        XCTAssertEqual(actualSuffixes, expectedSuffixes)
        XCTAssertEqual(issue286Cases.count, 27)
        XCTAssertEqual(manifest.cases.count, 208)
        XCTAssertEqual(manifest.hardBounds.maximumCaseCount, 224)
        XCTAssertFalse(issue286Cases.contains { $0.id.contains("unixepoch") })
        XCTAssertTrue(issue286Cases.allSatisfy { $0.mode == .semantic })

        let expectedFeatureIDs: Set<String> = [
            "syntax.expression.aggregate-functions",
            "syntax.expression.json-functions",
            "syntax.expression.numeric-comparable-functions",
            "syntax.expression.string-functions",
            "syntax.expression.type-casts",
        ]
        XCTAssertEqual(
            Set(issue286Cases.flatMap(\.inventoryFeatureIDs)),
            expectedFeatureIDs
        )
        XCTAssertTrue(
            issue286Cases
                .filter { $0.inventoryFeatureIDs == ["syntax.expression.json-functions"] }
                .allSatisfy { $0.requiredCapabilities == ["sqlite-json-functions"] }
        )
    }

    func testIssue288QueryBackedINCasesAreExplicitAndBounded() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let issue288Cases = manifest.cases.filter {
            $0.id.hasPrefix("c288.v1.subquery.")
        }
        let expectedSuffixes: Set<String> = [
            "in-query-builder-empty",
            "in-query-builder-nonempty",
            "in-query-functional-nonempty",
            "in-table-empty",
            "in-table-nonempty",
        ]
        let actualSuffixes = Set(issue288Cases.map {
            String($0.id.dropFirst("c288.v1.subquery.".count))
        })

        XCTAssertEqual(actualSuffixes, expectedSuffixes)
        XCTAssertEqual(issue288Cases.count, 5)
        XCTAssertTrue(issue288Cases.allSatisfy { $0.mode == .semantic })
        XCTAssertTrue(issue288Cases.allSatisfy { $0.oracle?.kind == .rawSQL })
        XCTAssertTrue(issue288Cases.allSatisfy { $0.requiredCapabilities.isEmpty })
        XCTAssertTrue(
            issue288Cases.allSatisfy {
                $0.inventoryFeatureIDs.contains(
                    "syntax.subquery.table-and-in-prepare-gap"
                )
            }
        )

        // Every case binds exactly one named placeholder declared inside the
        // subquery or common table expression, so the rendered parameter
        // layout is evidence that nested query bindings reach the outer
        // statement's slot list.
        XCTAssertTrue(issue288Cases.allSatisfy { $0.bindings.count == 1 })
        XCTAssertTrue(
            issue288Cases.allSatisfy { $0.bindings.allSatisfy { $0.keyKind == .named } }
        )

        // Both query-backed entry points are represented: `in(expression:)`
        // renders an inline subquery and `in(_ table:)` renders SQLite's
        // `expr IN table-name` form.
        let subqueryForm = issue288Cases.filter { $0.id.contains(".in-query-") }
        let tableForm = issue288Cases.filter { $0.id.contains(".in-table-") }
        XCTAssertEqual(subqueryForm.count, 3)
        XCTAssertEqual(tableForm.count, 2)
        XCTAssertTrue(subqueryForm.allSatisfy { $0.renderedSQL.contains("IN (SELECT") })
        XCTAssertTrue(tableForm.allSatisfy { $0.renderedSQL.contains("WITH ") })
        XCTAssertFalse(tableForm.contains { $0.renderedSQL.contains("IN (SELECT") })

        // Neither NOT IN (#84) nor a nullable IN operand (#70) is constructed
        // here.
        XCTAssertFalse(issue288Cases.contains { $0.renderedSQL.contains("NOT IN") })
        XCTAssertFalse(
            issue288Cases.contains {
                $0.inventoryFeatureIDs.contains("syntax.subquery.nullable-shape-gap")
            }
        )
    }

    /// Proves the empty and non-empty pairs actually differ at execution time.
    /// Comparing an empty result against an empty oracle is not by itself
    /// evidence that the inner query selects anything, so the row counts are
    /// asserted directly against the pinned fixture.
    func testIssue288EmptyAndNonEmptyINResultsExecuteAsClaimed() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let issue288Cases = manifest.cases.filter {
            $0.id.hasPrefix("c288.v1.subquery.")
        }
        XCTAssertEqual(issue288Cases.count, 5)

        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        try pool.read { database in
            for testCase in issue288Cases {
                let actual = try resultRows(
                    database,
                    sql: testCase.renderedSQL,
                    arguments: arguments(for: testCase)
                )
                if testCase.id.hasSuffix("-empty") {
                    XCTAssertTrue(
                        actual.isEmpty,
                        "\(testCase.id) should return no rows when the inner query is empty"
                    )
                }
                else {
                    XCTAssertEqual(
                        actual.count,
                        5,
                        "\(testCase.id) should return the LIMIT-bounded non-empty page"
                    )
                }
            }
        }
    }

    /// Packed cases only count as per-overload evidence if each overload is
    /// actually present in the rendered SQL, so this asserts the operator
    /// tokens and optionality shapes each case is claimed to carry.
    func testIssue287OperatorFamilyCasesAreExplicitAndBounded() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let issue287Cases = manifest.cases.filter {
            $0.id.hasPrefix("c287.v1.expression.")
        }
        let bySuffix = Dictionary(
            uniqueKeysWithValues: issue287Cases.map {
                (String($0.id.dropFirst("c287.v1.expression.".count)), $0)
            }
        )
        let expectedSuffixes: Set<String> = [
            "boolean-and-shapes",
            "boolean-not-shapes",
            "boolean-or-shapes",
            "coalesce-storage-classes",
            "coalescing-operator",
            "comparison-both-optional",
            "comparison-left-optional",
            "comparison-required",
            "comparison-right-optional",
            "equality-optional-shapes",
            "equality-required",
            "inequality-optional-shapes",
            "integer-arithmetic-both-optional",
            "integer-arithmetic-left-optional",
            "integer-arithmetic-null-propagation",
            "integer-arithmetic-required",
            "integer-arithmetic-right-optional",
            "integer-division-boundaries",
            "optional-predicates",
            "real-arithmetic-both-optional",
            "real-arithmetic-left-optional",
            "real-arithmetic-null-propagation",
            "real-arithmetic-required",
            "real-arithmetic-right-optional",
            "real-division-boundaries",
            "text-concatenation-null",
            "text-concatenation-shapes",
            "text-glob-case-sensitivity",
            "text-glob-null-propagation",
            "text-glob-shapes",
            "text-like-ascii-case-folding",
            "text-like-null-propagation",
            "text-like-shapes",
            "unary-nesting",
            "unary-shapes",
        ]

        XCTAssertEqual(Set(bySuffix.keys), expectedSuffixes)
        XCTAssertEqual(issue287Cases.count, 35)
        XCTAssertTrue(issue287Cases.allSatisfy { $0.mode == .semantic })
        XCTAssertTrue(issue287Cases.allSatisfy { $0.oracle?.kind == .rawSQL })
        XCTAssertTrue(
            issue287Cases.allSatisfy {
                $0.inventoryFeatureIDs == ["syntax.expression.operator-prepare-gap"]
            }
        )
        XCTAssertLessThanOrEqual(
            issue287Cases.map(\.bindings.count).max() ?? 0,
            manifest.hardBounds.maximumBindingsPerCase
        )

        // Each packed case must render every operator it claims to prove.
        let requiredTokens: [String: [String]] = [
            "boolean-not-shapes": ["(NOT :bool_true)", "(NOT :bool_null)"],
            "boolean-and-shapes": [
                "(:bool_true AND :bool_false)",
                "(:bool_true AND :bool_null)",
                "(:bool_null AND :bool_true)",
                "(:bool_null AND :bool_null)",
            ],
            "boolean-or-shapes": [
                "(:bool_true OR :bool_false)",
                "(:bool_true OR :bool_null)",
                "(:bool_null OR :bool_false)",
                "(:bool_null OR :bool_null)",
            ],
            "comparison-required": [" < ", " <= ", " > ", " >= "],
            "comparison-right-optional": [" < ", " <= ", " > ", " >= "],
            "comparison-left-optional": [" < ", " <= ", " > ", " >= "],
            "comparison-both-optional": [" < ", " <= ", " > ", " >= "],
            "equality-required": [" == ", " != "],
            "equality-optional-shapes": [" IS "],
            "inequality-optional-shapes": [" IS NOT "],
            "integer-arithmetic-required": [" + ", " - ", " * ", " / ", " % "],
            "integer-arithmetic-right-optional": [" + ", " - ", " * ", " / ", " % "],
            "integer-arithmetic-left-optional": [" + ", " - ", " * ", " / ", " % "],
            "integer-arithmetic-both-optional": [" + ", " - ", " * ", " / ", " % "],
            "real-arithmetic-required": [" + ", " - ", " * ", " / "],
            "real-arithmetic-right-optional": [" + ", " - ", " * ", " / "],
            "real-arithmetic-left-optional": [" + ", " - ", " * ", " / "],
            "real-arithmetic-both-optional": [" + ", " - ", " * ", " / "],
            "integer-arithmetic-null-propagation": [
                " + ", " - ", " * ", " / ", " % ",
            ],
            "integer-division-boundaries": [" / ", " % ", " / 0)", " % 0)"],
            "real-arithmetic-null-propagation": [" + ", " - ", " * ", " / "],
            "real-division-boundaries": [" / ", " / 0.0)"],
            "unary-shapes": ["~(", "+(", "-("],
            "unary-nesting": ["-(-(", " + "],
            "coalesce-storage-classes": ["COALESCE("],
            "coalescing-operator": ["COALESCE("],
            "optional-predicates": ["ISNULL", "NOTNULL"],
            "text-concatenation-shapes": [" || "],
            "text-concatenation-null": [" || "],
            "text-like-shapes": [" LIKE "],
            "text-like-null-propagation": [" LIKE "],
            "text-like-ascii-case-folding": [" LIKE "],
            "text-glob-shapes": [" GLOB "],
            "text-glob-null-propagation": [" GLOB "],
            "text-glob-case-sensitivity": [" GLOB "],
        ]
        // A suffix with no declared tokens would be silently unchecked, so a
        // new case cannot be added without saying what it must render.
        XCTAssertEqual(
            Set(requiredTokens.keys),
            expectedSuffixes,
            "every #287 case must declare the tokens it claims to render"
        )
        for (suffix, tokens) in requiredTokens {
            let rendered = try XCTUnwrap(bySuffix[suffix]).renderedSQL
            for token in tokens {
                XCTAssertTrue(
                    rendered.contains(token),
                    "\(suffix) must render \(token)"
                )
            }
        }

        // The optional equality overloads render IS / IS NOT, never == / !=.
        for suffix in ["equality-optional-shapes", "inequality-optional-shapes"] {
            let rendered = try XCTUnwrap(bySuffix[suffix]).renderedSQL
            XCTAssertFalse(rendered.contains(" == "), suffix)
            XCTAssertFalse(rendered.contains(" != "), suffix)
        }

        // Each optionality shape must be a distinct statement, so a family
        // cannot claim four overloads while rendering the same one four times.
        for family in ["integer-arithmetic", "real-arithmetic"] {
            let shapes = ["required", "right-optional", "left-optional", "both-optional"]
                .compactMap { bySuffix["\(family)-\($0)"]?.renderedSQL }
            XCTAssertEqual(shapes.count, 4, family)
            XCTAssertEqual(Set(shapes).count, 4, "\(family) shapes must differ")
        }

        // LIKE ESCAPE stays with #21 and REGEXP / MATCH stay with #78.
        XCTAssertFalse(
            issue287Cases.contains {
                $0.renderedSQL.contains(" ESCAPE ")
                    || $0.renderedSQL.contains(" REGEXP ")
                    || $0.renderedSQL.contains(" MATCH ")
            }
        )
    }

    /// Pins the exact storage values SQLite returns for each packed column.
    ///
    /// The raw-SQL oracle already proves SwiftQL and hand-written SQL agree,
    /// but agreement alone cannot show *which* semantics they agree on. These
    /// literals record SQLite's three-valued Boolean logic and the fact that
    /// the optional equality overloads never yield NULL despite their
    /// `Optional<Bool>` Swift result type.
    func testIssue287OperatorSemanticsMatchPinnedSQLiteResults() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let expectations: [String: [DatabaseValue]] = [
            // NOT true is false; NOT NULL stays NULL.
            "boolean-not-shapes": [0.databaseValue, .null],
            // NULL AND true is unknown, but NULL AND false is false: SQLite
            // can decide the conjunction without knowing the NULL operand.
            "boolean-and-shapes": [
                0.databaseValue, .null, .null, .null, 0.databaseValue,
            ],
            // The dual: NULL OR true is true, NULL OR false is unknown.
            "boolean-or-shapes": [
                1.databaseValue, 1.databaseValue, .null, .null, .null,
            ],
            // 7 vs 3.
            "comparison-required": [
                0.databaseValue, 0.databaseValue, 1.databaseValue, 1.databaseValue,
            ],
            // 7 vs 3, then 7 vs NULL.
            "comparison-right-optional": [
                0.databaseValue, 0.databaseValue, 1.databaseValue,
                1.databaseValue, .null,
            ],
            // 3 vs 3 on the boundary, so < and <= disagree.
            "comparison-left-optional": [
                0.databaseValue, 1.databaseValue, 0.databaseValue,
                1.databaseValue, .null,
            ],
            // 3 vs 5.
            "comparison-both-optional": [
                1.databaseValue, 1.databaseValue, 0.databaseValue,
                0.databaseValue, .null,
            ],
            // 7 = 3 is false, 7 <> 3 is true, 'alfa' = 'alfa' is true.
            "equality-required": [
                0.databaseValue, 1.databaseValue, 1.databaseValue,
            ],
            // IS is total: comparing against NULL yields 0 or 1, never NULL.
            "equality-optional-shapes": [
                0.databaseValue, 1.databaseValue, 0.databaseValue,
                0.databaseValue, 1.databaseValue,
            ],
            // IS NOT is the exact complement of IS, and equally total.
            "inequality-optional-shapes": [
                1.databaseValue, 0.databaseValue, 1.databaseValue,
                1.databaseValue, 0.databaseValue,
            ],
        ]

        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        try pool.read { database in
            for (suffix, expected) in expectations {
                let id = "c287.v1.expression.\(suffix)"
                let testCase = try XCTUnwrap(
                    manifest.cases.first { $0.id == id },
                    "missing case \(id)"
                )
                let rows = try resultRows(
                    database,
                    sql: testCase.renderedSQL,
                    arguments: arguments(for: testCase)
                )
                XCTAssertEqual(rows.count, 1, suffix)
                XCTAssertEqual(rows.first, expected, suffix)
            }
        }
    }

    /// Part two's pinned values. The boundaries here are the ones a Swift
    /// signature cannot express: integer division truncates and can yield NULL
    /// from a non-optional overload, `||` propagates NULL, LIKE folds case for
    /// ASCII only, and GLOB does not fold at all.
    func testIssue287ArithmeticTextAndOptionalSemanticsMatchPinnedSQLiteResults() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let nine = 9.databaseValue
        let expectations: [String: [DatabaseValue]] = [
            "integer-arithmetic-required": [
                nine, 5.databaseValue, 14.databaseValue,
                3.databaseValue, 1.databaseValue,
            ],
            "integer-arithmetic-right-optional": [
                nine, 5.databaseValue, 14.databaseValue,
                3.databaseValue, 1.databaseValue,
            ],
            "integer-arithmetic-left-optional": [
                nine, 5.databaseValue, 14.databaseValue,
                3.databaseValue, 1.databaseValue,
            ],
            "integer-arithmetic-both-optional": [
                nine, 5.databaseValue, 14.databaseValue,
                3.databaseValue, 1.databaseValue,
            ],
            // Arithmetic has no absorbing operand: one NULL nulls the column.
            "integer-arithmetic-null-propagation": [
                .null, .null, .null, .null, .null,
            ],
            // 7/2 truncates to 3 and -7/2 truncates to -3 rather than flooring
            // to -4. Division and remainder by zero are NULL even though these
            // overloads return non-optional Int. `%` takes the dividend's sign.
            "integer-division-boundaries": [
                3.databaseValue, (-3).databaseValue, .null, .null,
                (-1).databaseValue, 1.databaseValue,
            ],
            "real-arithmetic-required": [
                (9.0).databaseValue, (5.0).databaseValue,
                (14.0).databaseValue, (3.5).databaseValue,
            ],
            "real-arithmetic-right-optional": [
                (9.0).databaseValue, (5.0).databaseValue,
                (14.0).databaseValue, (3.5).databaseValue,
            ],
            "real-arithmetic-left-optional": [
                (9.0).databaseValue, (5.0).databaseValue,
                (14.0).databaseValue, (3.5).databaseValue,
            ],
            "real-arithmetic-both-optional": [
                (9.0).databaseValue, (5.0).databaseValue,
                (14.0).databaseValue, (3.5).databaseValue,
            ],
            "real-arithmetic-null-propagation": [.null, .null, .null, .null],
            // The same 7 and 2 the integer overload truncated to 3.
            "real-division-boundaries": [(3.5).databaseValue, .null],
            "unary-shapes": [
                (-8).databaseValue, (-8).databaseValue,
                7.databaseValue, 7.databaseValue,
                (-7).databaseValue, (-7).databaseValue,
            ],
            // If the operand were not parenthesised, `-(-7)` would render as
            // `--7` and SQLite would read the rest of the line as a comment.
            "unary-nesting": [7.databaseValue, (-9).databaseValue],
            "coalesce-storage-classes": [
                0.databaseValue, 7.databaseValue,
                (1.5).databaseValue, "fallback".databaseValue,
            ],
            "coalescing-operator": [42.databaseValue],
            "optional-predicates": [
                1.databaseValue, 0.databaseValue,
                0.databaseValue, 1.databaseValue,
                7.databaseValue,
            ],
            "text-concatenation-shapes": [
                "alfabeta".databaseValue, "alfabeta".databaseValue,
                "alfabeta".databaseValue, "alfabeta".databaseValue,
            ],
            // SQLite's `||` yields NULL rather than treating NULL as ''.
            "text-concatenation-null": [
                "alfabeta".databaseValue, .null, .null, .null,
            ],
            "text-like-shapes": [
                1.databaseValue, 0.databaseValue,
                1.databaseValue, 0.databaseValue,
            ],
            // LIKE folds ASCII case in both directions but leaves non-ASCII
            // alone, so 'Ä' does not match 'ä'.
            "text-like-ascii-case-folding": [
                1.databaseValue, 1.databaseValue, 0.databaseValue,
            ],
            "text-glob-shapes": [
                1.databaseValue, 0.databaseValue,
                1.databaseValue, 0.databaseValue,
            ],
            // The optional overloads' NULL branch: a NULL operand on either
            // side yields NULL, which is why they return `Bool?`.
            "text-like-null-propagation": [
                1.databaseValue, .null, .null, .null,
            ],
            "text-glob-null-propagation": [
                1.databaseValue, .null, .null, .null,
            ],
            // GLOB is case sensitive and uses Unix wildcards, so '?' matches
            // exactly one character.
            "text-glob-case-sensitivity": [
                1.databaseValue, 0.databaseValue, 1.databaseValue,
            ],
        ]

        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        try pool.read { database in
            for (suffix, expected) in expectations {
                let id = "c287.v1.expression.\(suffix)"
                let testCase = try XCTUnwrap(
                    manifest.cases.first { $0.id == id },
                    "missing case \(id)"
                )
                let rows = try resultRows(
                    database,
                    sql: testCase.renderedSQL,
                    arguments: arguments(for: testCase)
                )
                XCTAssertEqual(rows.count, 1, suffix)
                XCTAssertEqual(rows.first, expected, suffix)
            }
        }
    }

    func testPinnedRuntimeAttestsJSONFunctionCapability() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let jsonCases = manifest.cases.filter {
            $0.inventoryFeatureIDs == ["syntax.expression.json-functions"]
        }
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }
        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }
        let signatures = Set(runtime.functions.map {
            "\($0.name.uppercased())/\($0.argumentCount)"
        })

        XCTAssertTrue(signatures.contains("JSON_VALID/1"))
        XCTAssertTrue(signatures.contains("JSON_ARRAY_LENGTH/1"))
        XCTAssertTrue(signatures.contains("JSON_ARRAY_LENGTH/2"))
        XCTAssertEqual(jsonCases.count, 3)
        XCTAssertNoThrow(try assertRequiredCapabilities(for: jsonCases, runtime: runtime))
    }

    func testEveryPositiveCasePreparesAndSemanticOraclesExecute() throws {
        let suiteStarted = Date()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let selectedCases = try selectedCases(from: manifest)
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }

        let positiveOutcomes = selectedCases.map { testCase in
            evaluatePositiveCase(testCase, runtime: runtime, pool: pool)
        }
        let positiveFailureIDs = positiveOutcomes
            .filter { $0.verdict == .failed }
            .map(\.caseID)
        var outcomes = positiveOutcomes

        let deliberateFailure = try pool.read { database in
            try makeDeliberateFailure(
                runtime: runtime,
                database: database
            )
        }
        outcomes.append(
            SQLiteCombinatorialCaseOutcome(
                caseID: deliberateFailure.testCase.id,
                stage: .prepare,
                verdict: .failed,
                elapsedMilliseconds: 0,
                failure: deliberateFailure
            )
        )
        let totalElapsedMilliseconds = Date().timeIntervalSince(suiteStarted) * 1_000

        let report = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: sha256Hex(try manifest.canonicalJSONData()),
            manifestCaseCount: manifest.cases.count,
            hardBounds: manifest.hardBounds,
            maximumRuntimeMilliseconds: combinatorialMaximumRuntimeMilliseconds,
            totalElapsedMilliseconds: totalElapsedMilliseconds,
            runtimeMetadata: runtime,
            outcomes: outcomes
        )
        try writeConfiguredOutput(
            data: try report.canonicalJSONData(),
            environmentKey: "SWIFTQL_COMBINATORIAL_RUNTIME_REPORT_PATH"
        )

        // Keep this assertion after the atomic report write. A regression in a
        // real positive case must leave replayable runtime evidence in CI.
        XCTAssertTrue(
            positiveFailureIDs.isEmpty,
            "Runtime report written before positive-case failures were reported: "
                + positiveFailureIDs.joined(separator: ", ")
        )
        XCTAssertTrue(
            report.satisfiesRuntimeBound,
            "Runtime report written before the explicit suite bound was enforced"
        )
        XCTAssertEqual(positiveOutcomes.count, selectedCases.count)
        XCTAssertEqual(
            outcomes.filter { $0.caseID == deliberateBrokenRendererCaseID }.count,
            1
        )
        XCTAssertFalse(runtime.sqliteVersion.isEmpty)
        XCTAssertFalse(runtime.sqliteSourceID.isEmpty)
        XCTAssertFalse(runtime.functions.isEmpty)
        XCTAssertFalse(runtime.collations.isEmpty)
        XCTAssertFalse(runtime.schemaFNV1A64.isEmpty)
    }

    func testDeliberatelyBrokenRendererProducesStableFailureEvidence() throws {
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let pair = try pool.read { database -> (
            SQLiteCombinatorialFailureRecord,
            SQLiteCombinatorialFailureRecord
        ) in
            let runtime = try SQLiteRuntimeMetadata.capture(from: database)
            return (
                try makeDeliberateFailure(
                    runtime: runtime,
                    database: database
                ),
                try makeDeliberateFailure(
                    runtime: runtime,
                    database: database
                )
            )
        }

        XCTAssertEqual(pair.0, pair.1)
        XCTAssertEqual(try pair.0.canonicalJSONData(), try pair.1.canonicalJSONData())
        XCTAssertEqual(pair.0.stage, .prepare)
        XCTAssertEqual(pair.0.testCase.id, deliberateBrokenRendererCaseID)
        XCTAssertEqual(pair.0.testCase.renderedSQL, pair.0.failingSQL)
        XCTAssertEqual(pair.0.originalSQL, pair.0.failingSQL)
        XCTAssertEqual(pair.0.testCase.bindings, pair.0.bindings)
        XCTAssertNil(pair.0.reducedFromCaseID)
        XCTAssertEqual(pair.0.reductionAttemptCount, 0)
        XCTAssertTrue(pair.0.reducedDimensions.isEmpty)
        XCTAssertEqual(pair.0.failureSignature.code, "1")
        XCTAssertTrue(pair.0.failureSignature.message.lowercased().contains("syntax"))
        XCTAssertFalse(pair.0.runtimeMetadata.compileOptions.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.functions.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.collations.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.schemaFNV1A64.isEmpty)
    }

    func testPositiveFailuresAreStructuredBeforeTheFailureDecision() throws {
        let suiteStarted = Date()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }
        let cases = [
            adversarialCase(
                id: "c191.v1.adversarial.prepare",
                sql: "SELECT FROM c191_adversarial_prepare",
                mode: .prepareOnly,
                oracle: nil
            ),
            adversarialCase(
                id: "c191.v1.adversarial.execution",
                sql: "SELECT ABS(-9223372036854775808)",
                mode: .semantic,
                oracle: SQLiteCombinatorialOracle(
                    id: "oracle.c191.adversarial.unreachable",
                    kind: .rawSQL
                )
            ),
            adversarialCase(
                id: "c191.v1.adversarial.oracle",
                sql: "SELECT 1",
                mode: .semantic,
                oracle: SQLiteCombinatorialOracle(
                    id: "oracle.c191.adversarial.missing",
                    kind: .rawSQL
                )
            ),
            adversarialCase(
                id: "c191.v1.adversarial.missing-capability",
                sql: "SELECT 1",
                mode: .prepareOnly,
                oracle: nil,
                requiredCapabilities: ["function:C191_DELIBERATELY_MISSING"]
            ),
        ]
        let outcomes = cases.map { testCase in
            evaluatePositiveCase(testCase, runtime: runtime, pool: pool)
        }
        let report = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: sha256Hex(try manifest.canonicalJSONData()),
            manifestCaseCount: manifest.cases.count,
            hardBounds: manifest.hardBounds,
            maximumRuntimeMilliseconds: combinatorialMaximumRuntimeMilliseconds,
            totalElapsedMilliseconds: Date().timeIntervalSince(suiteStarted) * 1_000,
            runtimeMetadata: runtime,
            outcomes: outcomes
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = outputDirectory.appendingPathComponent("runtime-report.json")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        try writeOutput(data: try report.canonicalJSONData(), to: output)

        let decoded = try JSONDecoder().decode(
            SQLiteCombinatorialRuntimeReport.self,
            from: Data(contentsOf: output)
        )
        XCTAssertEqual(decoded.runtimeMetadata, runtime)
        XCTAssertEqual(
            decoded.maximumRuntimeMilliseconds,
            combinatorialMaximumRuntimeMilliseconds
        )
        XCTAssertGreaterThan(decoded.maximumRuntimeMilliseconds, 0)
        XCTAssertTrue(decoded.satisfiesRuntimeBound)
        XCTAssertEqual(decoded.outcomes.map(\.caseID), cases.map(\.id).sorted())
        XCTAssertEqual(
            decoded.outcomes.map { $0.stage.rawValue }.sorted(),
            ["execution", "oracle", "prepare", "prepare"]
        )
        XCTAssertTrue(decoded.outcomes.allSatisfy { outcome in
            outcome.verdict == .failed
                && outcome.failure?.testCase.id == outcome.caseID
                && outcome.failure?.testCase.renderedSQL == outcome.failure?.failingSQL
                && outcome.failure?.bindings == outcome.failure?.testCase.bindings
                && outcome.failure?.runtimeMetadata == runtime
        })
        let missingCapability = try XCTUnwrap(decoded.outcomes.first { outcome in
            outcome.caseID == "c191.v1.adversarial.missing-capability"
        })
        XCTAssertEqual(
            missingCapability.failure?.failureSignature.code,
            "missing-capability"
        )
    }
}


private extension SQLiteCombinatorialConformanceTests {
    var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func selectedCases(
        from manifest: SQLiteCombinatorialManifest
    ) throws -> [SQLiteCombinatorialCase] {
        guard let requested = ProcessInfo.processInfo.environment[
            "SWIFTQL_COMBINATORIAL_CASE"
        ], !requested.isEmpty else {
            return manifest.cases
        }
        guard let selected = manifest.cases.first(where: { $0.id == requested }) else {
            throw SQLiteCombinatorialConformanceError.unknownCaseID(requested)
        }
        return [selected]
    }

    func writeConfiguredOutput(data: Data, environmentKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        try writeOutput(data: data, to: URL(fileURLWithPath: path))
    }

    func writeOutput(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func evaluatePositiveCase(
        _ testCase: SQLiteCombinatorialCase,
        runtime: SQLiteRuntimeMetadata,
        pool: DatabasePool
    ) -> SQLiteCombinatorialCaseOutcome {
        let started = Date()

        do {
            try assertRequiredCapabilities(for: [testCase], runtime: runtime)
        }
        catch {
            return failedOutcome(
                testCase,
                stage: .prepare,
                runtime: runtime,
                error: error,
                started: started
            )
        }

        do {
            return try pool.read { database in
                do {
                    let statement = try database.makeStatement(sql: testCase.renderedSQL)
                    try statement.setArguments(arguments(for: testCase))
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .prepare,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                guard testCase.mode == .semantic else {
                    return passedOutcome(testCase, stage: .prepare, started: started)
                }

                let actual: [[DatabaseValue]]
                do {
                    actual = try resultRows(
                        database,
                        sql: testCase.renderedSQL,
                        arguments: arguments(for: testCase)
                    )
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .execution,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                let expected: [[DatabaseValue]]
                do {
                    expected = try independentOracleRows(
                        for: testCase,
                        database: database
                    )
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .oracle,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                let matches: Bool
                if testCase.oracle?.kind == .fixedValue {
                    matches = canonicalRows(actual) == canonicalRows(expected)
                }
                else {
                    // Raw-SQL oracles retain row order so ORDER BY and
                    // collation regressions cannot be sorted away.
                    matches = actual == expected
                }
                guard matches else {
                    return failedOutcome(
                        testCase,
                        stage: .oracle,
                        runtime: runtime,
                        error: SQLiteCombinatorialConformanceError.semanticMismatch(
                            testCase.id
                        ),
                        started: started
                    )
                }

                return passedOutcome(testCase, stage: .execution, started: started)
            }
        }
        catch {
            return failedOutcome(
                testCase,
                stage: .prepare,
                runtime: runtime,
                error: error,
                started: started
            )
        }
    }

    func passedOutcome(
        _ testCase: SQLiteCombinatorialCase,
        stage: SQLiteCombinatorialFailureStage,
        started: Date
    ) -> SQLiteCombinatorialCaseOutcome {
        SQLiteCombinatorialCaseOutcome(
            caseID: testCase.id,
            stage: stage,
            verdict: .passed,
            elapsedMilliseconds: Date().timeIntervalSince(started) * 1_000,
            failure: nil
        )
    }

    func failedOutcome(
        _ testCase: SQLiteCombinatorialCase,
        stage: SQLiteCombinatorialFailureStage,
        runtime: SQLiteRuntimeMetadata,
        error: Error,
        started: Date
    ) -> SQLiteCombinatorialCaseOutcome {
        let failure = SQLiteCombinatorialFailureRecord(
            testCase: testCase,
            originalSQL: testCase.renderedSQL,
            failingSQL: testCase.renderedSQL,
            bindings: testCase.bindings,
            stage: stage,
            failureSignature: failureSignature(for: error),
            runtimeMetadata: runtime,
            reducedFromCaseID: nil,
            reductionAttemptCount: 0,
            reducedDimensions: [],
            reproductionCommand: testCase.reproductionCommand
        )
        return SQLiteCombinatorialCaseOutcome(
            caseID: testCase.id,
            stage: stage,
            verdict: .failed,
            elapsedMilliseconds: Date().timeIntervalSince(started) * 1_000,
            failure: failure
        )
    }

    func failureSignature(for error: Error) -> SQLiteCombinatorialFailureSignature {
        if let error = error as? DatabaseError {
            return SQLiteCombinatorialFailureSignature(
                errorType: "GRDB.DatabaseError",
                code: String(error.resultCode.rawValue),
                message: error.message ?? "SQLite error"
            )
        }
        if let error = error as? SQLiteCombinatorialConformanceError {
            let code: String
            let message: String
            switch error {
            case .unknownCaseID(let caseID):
                code = "unknown-case-id"
                message = "Unknown generated case ID: \(caseID)"
            case .missingCapability(let caseID, let capability):
                code = "missing-capability"
                message = "Case \(caseID) requires unavailable capability \(capability)"
            case .unknownCapability(let caseID, let capability):
                code = "unknown-capability"
                message = "Case \(caseID) declares unknown capability \(capability)"
            case .missingOracle(let caseID):
                code = "missing-oracle"
                message = "Case \(caseID) has no independent semantic oracle"
            case .unknownOracle(let oracleID):
                code = "unknown-oracle"
                message = "No independent semantic oracle is registered for \(oracleID)"
            case .semanticMismatch(let caseID):
                code = "rows-differ"
                message = "Independent semantic oracle mismatch for \(caseID)"
            case .brokenRendererPrepared(let sql):
                code = "broken-renderer-prepared"
                message = "Deliberately invalid SQL unexpectedly prepared: \(sql)"
            }
            return SQLiteCombinatorialFailureSignature(
                errorType: "SQLiteCombinatorialConformanceError",
                code: code,
                message: message
            )
        }
        return SQLiteCombinatorialFailureSignature(
            errorType: String(reflecting: type(of: error)),
            code: nil,
            message: String(describing: error)
        )
    }

    func adversarialCase(
        id: String,
        sql: String,
        mode: SQLiteCombinatorialCaseMode,
        oracle: SQLiteCombinatorialOracle?,
        requiredCapabilities: [String] = []
    ) -> SQLiteCombinatorialCase {
        SQLiteCombinatorialCase(
            id: id,
            template: "adversarial-runtime-evidence",
            strength: "adversarial-test",
            dimensionVector: [],
            constraintIDs: [],
            inventoryFeatureIDs: ["syntax.select.core"],
            northwindAnchorCaseIDs: nil,
            requiredCapabilities: requiredCapabilities,
            renderedSQL: sql,
            bindings: [],
            mode: mode,
            oracle: oracle,
            reproductionCommand: "swift test --filter SQLiteCombinatorialConformanceTests/\(id)"
        )
    }

    func assertRequiredCapabilities(
        for cases: [SQLiteCombinatorialCase],
        runtime: SQLiteRuntimeMetadata
    ) throws {
        let functionNames = Set(runtime.functions.map { $0.name.uppercased() })
        let functionSignatures = Set(runtime.functions.map {
            "\($0.name.uppercased())/\($0.argumentCount)"
        })
        for testCase in cases {
            for capability in testCase.requiredCapabilities {
                if capability.hasPrefix("function:") {
                    let name = String(capability.dropFirst("function:".count)).uppercased()
                    guard functionNames.contains(name) else {
                        throw SQLiteCombinatorialConformanceError.missingCapability(
                            caseID: testCase.id,
                            capability: capability
                        )
                    }
                }
                else if capability == "sqlite-json-functions" {
                    let requiredSignatures: Set<String> = [
                        "JSON_ARRAY_LENGTH/1",
                        "JSON_ARRAY_LENGTH/2",
                        "JSON_VALID/1",
                    ]
                    guard requiredSignatures.isSubset(of: functionSignatures) else {
                        throw SQLiteCombinatorialConformanceError.missingCapability(
                            caseID: testCase.id,
                            capability: capability
                        )
                    }
                }
                else {
                    throw SQLiteCombinatorialConformanceError.unknownCapability(
                        caseID: testCase.id,
                        capability: capability
                    )
                }
            }
        }
    }

    func arguments(for testCase: SQLiteCombinatorialCase) -> StatementArguments {
        if testCase.bindings.allSatisfy({ $0.keyKind == .named }) {
            let pairs = testCase.bindings.map { binding in
                (binding.keyName!, databaseValue(binding.taggedValue))
            }
            return StatementArguments(Dictionary(uniqueKeysWithValues: pairs))
        }
        return StatementArguments(
            testCase.bindings
                .sorted { $0.logicalIndex < $1.logicalIndex }
                .map { databaseValue($0.taggedValue) }
        )
    }

    func databaseValue(_ value: SQLiteCombinatorialTaggedValue) -> DatabaseValue {
        switch value {
        case .null:
            return .null
        case .integer(let value):
            return value.databaseValue
        case .real(let value):
            return value.databaseValue
        case .text(let value):
            return value.databaseValue
        case .blob(let value):
            return value.databaseValue
        }
    }

    func resultRows(
        _ database: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [[DatabaseValue]] {
        try Row.fetchAll(database, sql: sql, arguments: arguments).map { row in
            (0..<row.count).map { index -> DatabaseValue in row[index] }
        }
    }

    func independentOracleRows(
        for testCase: SQLiteCombinatorialCase,
        database: Database
    ) throws -> [[DatabaseValue]] {
        guard let oracle = testCase.oracle else {
            throw SQLiteCombinatorialConformanceError.missingOracle(testCase.id)
        }

        if testCase.id.hasPrefix("c191.v1.expression.")
            || testCase.id.hasPrefix("c286.v1.expression.")
            || testCase.id.hasPrefix("c287.v1.expression.") {
            return try resultRows(
                database,
                sql: try expressionOracleSQL(for: testCase.id),
                arguments: arguments(for: testCase)
            )
        }
        if testCase.id.hasPrefix("c191.v1.cte.") {
            return try fixedCTERows(for: testCase.id)
        }

        switch oracle.id {
        case "oracle.c191.northwind.customer-supplier-cities":
            return try resultRows(
                database,
                sql: """
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Customers' AS relationship
                    FROM Customers
                    UNION
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Suppliers' AS relationship
                    FROM Suppliers
                    ORDER BY city, companyName, relationship, contactName
                    """
            )
        case "oracle.c191.northwind.cte-order-subtotals":
            return try resultRows(
                database,
                sql: """
                    WITH order_subtotals AS (
                        SELECT OrderID AS orderID,
                               SUM(UnitPrice * Quantity * (1.0 - Discount)) AS subtotal
                        FROM "Order Details"
                        GROUP BY OrderID
                    )
                    SELECT orderID, subtotal
                    FROM order_subtotals
                    WHERE orderID = 10248
                    ORDER BY orderID
                    """
            )
        case "oracle.c191.left-null-grouped-pagination":
            return try resultRows(
                database,
                sql: """
                    SELECT o.ShipRegion
                    FROM Orders AS o
                    LEFT JOIN Employees AS e ON o.EmployeeID = e.EmployeeID
                    WHERE o.ShipRegion IS NULL
                    GROUP BY o.CustomerID
                    HAVING COUNT(o.OrderID) > 1
                    ORDER BY o.CustomerID COLLATE NOCASE ASC
                    LIMIT 5 OFFSET 2
                    """
            )
        case "oracle.c191.repeated-binding-aggregate":
            return try resultRows(
                database,
                sql: """
                    SELECT COUNT(o.OrderID)
                    FROM (
                        SELECT
                            source_orders.OrderID,
                            source_orders.CustomerID,
                            source_orders.EmployeeID,
                            source_orders.ShippedDate,
                            source_orders.ShipRegion
                        FROM Orders AS source_orders
                    ) AS o
                    INNER JOIN Customers AS c ON o.CustomerID = c.CustomerID
                    WHERE o.EmployeeID >= :repeated_employee_id
                      AND o.EmployeeID <= :repeated_employee_id
                    GROUP BY o.CustomerID
                    HAVING COUNT(o.OrderID) > 1
                    ORDER BY o.OrderID DESC
                    LIMIT 5 OFFSET 2
                    """,
                arguments: arguments(for: testCase)
            )
        case "oracle.c288.subquery.in-query-builder-nonempty",
             "oracle.c288.subquery.in-query-builder-empty":
            return try resultRows(
                database,
                sql: """
                    SELECT o.OrderID
                    FROM Orders AS o
                    WHERE o.EmployeeID IN (
                        SELECT e.EmployeeID
                        FROM Employees AS e
                        WHERE e.EmployeeID = :in_subquery_employee_id
                    )
                    ORDER BY o.OrderID ASC
                    LIMIT 5
                    """,
                arguments: arguments(for: testCase)
            )
        case "oracle.c288.subquery.in-query-functional-nonempty":
            return try resultRows(
                database,
                sql: """
                    SELECT o.OrderID
                    FROM Orders AS o
                    WHERE o.CustomerID IN (
                        SELECT c.CustomerID
                        FROM Customers AS c
                        WHERE c.CustomerID = :in_subquery_customer_id
                    )
                    ORDER BY o.OrderID ASC
                    LIMIT 5
                    """,
                arguments: arguments(for: testCase)
            )
        case "oracle.c288.subquery.in-table-nonempty",
             "oracle.c288.subquery.in-table-empty":
            // Written as an inline subquery rather than SQLite's
            // `expr IN table-name` form so the oracle stays independent of the
            // construction under test.
            return try resultRows(
                database,
                sql: """
                    SELECT o.OrderID
                    FROM Orders AS o
                    WHERE o.EmployeeID IN (
                        SELECT e.EmployeeID
                        FROM Employees AS e
                        WHERE e.EmployeeID = :in_table_employee_id
                    )
                    ORDER BY o.OrderID ASC
                    LIMIT 5
                    """,
                arguments: arguments(for: testCase)
            )
        case "oracle.c191.injection-binding":
            return try resultRows(
                database,
                sql: """
                    SELECT o.OrderID
                    FROM Orders AS o
                    CROSS JOIN Customers AS c
                    WHERE o.CustomerID = :customer_input
                    """,
                arguments: arguments(for: testCase)
            )
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(oracle.id)
        }
    }

    func expressionOracleSQL(for caseID: String) throws -> String {
        let suffix: String
        if caseID.hasPrefix("c191.v1.expression.") {
            suffix = String(caseID.dropFirst("c191.v1.expression.".count))
        }
        else if caseID.hasPrefix("c286.v1.expression.") {
            suffix = String(caseID.dropFirst("c286.v1.expression.".count))
        }
        else if caseID.hasPrefix("c287.v1.expression.") {
            suffix = String(caseID.dropFirst("c287.v1.expression.".count))
        }
        else {
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        switch suffix {
        case "aggregate-count-distinct":
            return "SELECT COUNT(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-min-distinct":
            return "SELECT MIN(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-max-distinct":
            return "SELECT MAX(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-average-distinct":
            return "SELECT AVG(DISTINCT CAST(EmployeeID AS REAL)) FROM Orders"
        case "aggregate-sum-distinct":
            return "SELECT SUM(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-group-concat-distinct":
            return "SELECT GROUP_CONCAT(DISTINCT CustomerID) FROM Orders"
        case "indexed-binding":
            return "SELECT ?1"
        case "numeric-abs":
            return "SELECT ABS(:integer_value)"
        case "numeric-round":
            return "SELECT ROUND(:real_value, 2)"
        case "numeric-round-no-places":
            return "SELECT ROUND(:real_value)"
        case "numeric-round-optional":
            return "SELECT ROUND(:optional_real_value)"
        case "numeric-floor":
            return "SELECT FLOOR(:real_value)"
        case "comparable-min":
            return "SELECT MIN(:integer_value, 191)"
        case "comparable-max":
            return "SELECT MAX(:integer_value, 191)"
        case "string-printf":
            return "SELECT PRINTF('%s-%d', :text_value, :integer_value)"
        case "string-printf-array":
            return "SELECT PRINTF('%s-%d', :text_value, :integer_value)"
        case "cast-bool-integer":
            return "SELECT :boolean_value"
        case "cast-optional-bool-integer":
            return "SELECT :optional_boolean_value"
        case "cast-integer-real":
            return "SELECT CAST(:integer_value AS REAL)"
        case "cast-integer-text":
            return "SELECT CAST(:integer_value AS TEXT)"
        case "cast-optional-integer-real":
            return "SELECT CAST(:optional_integer_value AS REAL)"
        case "cast-optional-integer-text":
            return "SELECT CAST(:optional_integer_value AS TEXT)"
        case "cast-real-integer":
            return "SELECT CAST(:real_value AS INTEGER)"
        case "cast-real-text":
            return "SELECT CAST(:real_value AS TEXT)"
        case "cast-optional-real-integer":
            return "SELECT CAST(:optional_real_value AS INTEGER)"
        case "cast-optional-real-text":
            return "SELECT CAST(:optional_real_value AS TEXT)"
        case "cast-text-integer":
            return "SELECT CAST(:text_value AS INTEGER)"
        case "cast-text-real":
            return "SELECT CAST(:text_value AS REAL)"
        case "cast-text-blob":
            return "SELECT CAST(:text_value AS BLOB)"
        case "cast-optional-text-integer":
            return "SELECT CAST(:optional_text_value AS INTEGER)"
        case "cast-optional-text-real":
            return "SELECT CAST(:optional_text_value AS REAL)"
        case "cast-optional-text-blob":
            return "SELECT CAST(:optional_text_value AS BLOB)"
        case "cast-blob-text":
            return "SELECT CAST(:blob_value AS TEXT)"
        case "cast-optional-blob-text":
            return "SELECT CAST(:optional_blob_value AS TEXT)"
        case "date-unixepoch":
            return "SELECT UNIXEPOCH(:text_value)"
        case "json-valid":
            return "SELECT JSON_VALID(:text_value)"
        case "json-array-length":
            return "SELECT JSON_ARRAY_LENGTH(:text_value)"
        case "json-array-length-path":
            return "SELECT JSON_ARRAY_LENGTH(:text_value, '$.items')"
        case "operator-arithmetic-precedence":
            return "SELECT (:integer_value + 7) * 2"
        case "operator-glob":
            return "SELECT :text_value GLOB 'A*'"

        // Issue #287 packed operator families. Written without SwiftQL's
        // defensive parentheses so the oracle is an independent statement
        // rather than a transcription of the rendered SQL.
        case "boolean-not-shapes":
            return "SELECT NOT :bool_true, NOT :bool_null"
        case "boolean-and-shapes":
            return """
                SELECT :bool_true AND :bool_false,
                       :bool_true AND :bool_null,
                       :bool_null AND :bool_true,
                       :bool_null AND :bool_null,
                       :bool_null AND :bool_false
                """
        case "boolean-or-shapes":
            return """
                SELECT :bool_true OR :bool_false,
                       :bool_true OR :bool_null,
                       :bool_null OR :bool_false,
                       :bool_null OR :bool_null,
                       :bool_false OR :bool_null
                """
        case "comparison-required":
            return """
                SELECT :int_left < :int_right,
                       :int_left <= :int_right,
                       :int_left > :int_right,
                       :int_left >= :int_right
                """
        case "comparison-right-optional":
            return """
                SELECT :int_left < :int_optional,
                       :int_left <= :int_optional,
                       :int_left > :int_optional,
                       :int_left >= :int_optional,
                       :int_left > :int_null
                """
        case "comparison-left-optional":
            return """
                SELECT :int_optional < :int_right,
                       :int_optional <= :int_right,
                       :int_optional > :int_right,
                       :int_optional >= :int_right,
                       :int_null > :int_right
                """
        case "comparison-both-optional":
            return """
                SELECT :int_optional < :int_optional_b,
                       :int_optional <= :int_optional_b,
                       :int_optional > :int_optional_b,
                       :int_optional >= :int_optional_b,
                       :int_optional > :int_null
                """
        case "equality-required":
            return """
                SELECT :int_left = :int_right,
                       :int_left <> :int_right,
                       :text_left = :text_left
                """
        case "equality-optional-shapes":
            return """
                SELECT :int_left IS :int_optional,
                       :int_optional IS :int_right,
                       :int_optional IS :int_optional_b,
                       :int_left IS :int_null,
                       :int_null IS :int_null
                """
        case "inequality-optional-shapes":
            return """
                SELECT :int_left IS NOT :int_optional,
                       :int_optional IS NOT :int_right,
                       :int_optional IS NOT :int_optional_b,
                       :int_left IS NOT :int_null,
                       :int_null IS NOT :int_null
                """
        case "integer-arithmetic-required":
            return """
                SELECT :int_seven + :int_two, :int_seven - :int_two,
                       :int_seven * :int_two, :int_seven / :int_two,
                       :int_seven % :int_two
                """
        case "integer-arithmetic-right-optional":
            return """
                SELECT :int_seven + :int_optional_two,
                       :int_seven - :int_optional_two,
                       :int_seven * :int_optional_two,
                       :int_seven / :int_optional_two,
                       :int_seven % :int_optional_two
                """
        case "integer-arithmetic-left-optional":
            return """
                SELECT :int_optional_seven + :int_two,
                       :int_optional_seven - :int_two,
                       :int_optional_seven * :int_two,
                       :int_optional_seven / :int_two,
                       :int_optional_seven % :int_two
                """
        case "integer-arithmetic-both-optional":
            return """
                SELECT :int_optional_seven + :int_optional_two,
                       :int_optional_seven - :int_optional_two,
                       :int_optional_seven * :int_optional_two,
                       :int_optional_seven / :int_optional_two,
                       :int_optional_seven % :int_optional_two
                """
        case "integer-arithmetic-null-propagation":
            return """
                SELECT :int_seven + :int_null, :int_null - :int_two,
                       :int_optional_seven * :int_null, :int_seven / :int_null,
                       :int_null % :int_two
                """
        case "integer-division-boundaries":
            return """
                SELECT :int_seven / :int_two, :int_negative_seven / :int_two,
                       :int_seven / 0, :int_seven % 0,
                       :int_negative_seven % :int_three,
                       :int_seven % :int_negative_three
                """
        case "real-arithmetic-required":
            return """
                SELECT :real_seven + :real_two, :real_seven - :real_two,
                       :real_seven * :real_two, :real_seven / :real_two
                """
        case "real-arithmetic-right-optional":
            return """
                SELECT :real_seven + :real_optional_two,
                       :real_seven - :real_optional_two,
                       :real_seven * :real_optional_two,
                       :real_seven / :real_optional_two
                """
        case "real-arithmetic-left-optional":
            return """
                SELECT :real_optional_seven + :real_two,
                       :real_optional_seven - :real_two,
                       :real_optional_seven * :real_two,
                       :real_optional_seven / :real_two
                """
        case "real-arithmetic-both-optional":
            return """
                SELECT :real_optional_seven + :real_optional_two,
                       :real_optional_seven - :real_optional_two,
                       :real_optional_seven * :real_optional_two,
                       :real_optional_seven / :real_optional_two
                """
        case "real-arithmetic-null-propagation":
            return """
                SELECT :real_seven + :real_null, :real_null - :real_two,
                       :real_optional_seven * :real_null,
                       :real_seven / :real_null
                """
        case "real-division-boundaries":
            return "SELECT :real_seven / :real_two, :real_seven / 0.0"
        case "unary-shapes":
            return """
                SELECT ~:int_seven, ~:int_optional_seven,
                       +:int_seven, +:int_optional_seven,
                       -(:int_seven), -(:int_optional_seven)
                """
        case "unary-nesting":
            return "SELECT -(-(:int_seven)), -(:int_seven + :int_two)"
        case "coalesce-storage-classes":
            return """
                SELECT COALESCE(:int_null, 0),
                       COALESCE(:int_optional_seven, 0),
                       COALESCE(:real_null, 1.5),
                       COALESCE(:text_null, 'fallback')
                """
        case "coalescing-operator":
            return "SELECT COALESCE(:int_null, 42)"
        case "optional-predicates":
            return """
                SELECT :int_null IS NULL, :int_optional_seven IS NULL,
                       :int_null IS NOT NULL, :int_optional_seven IS NOT NULL,
                       :int_seven
                """
        case "text-concatenation-shapes":
            return """
                SELECT :text_alfa || :text_beta,
                       :text_alfa || :text_optional_beta,
                       :text_optional_alfa || :text_beta,
                       :text_optional_alfa || :text_optional_beta
                """
        case "text-concatenation-null":
            return """
                SELECT :text_alfa || :text_beta, :text_alfa || :text_null,
                       :text_null || :text_beta, :text_null || :text_null
                """
        case "text-like-shapes":
            return """
                SELECT :text_alfa LIKE 'a%',
                       :text_alfa LIKE :text_optional_beta,
                       :text_optional_alfa LIKE 'a%',
                       :text_optional_alfa LIKE :text_optional_beta
                """
        case "text-like-ascii-case-folding":
            return """
                SELECT :text_alfa LIKE 'A%', :text_upper LIKE 'a%',
                       :text_accented LIKE 'ä'
                """
        case "text-glob-shapes":
            return """
                SELECT :text_alfa GLOB 'a*',
                       :text_alfa GLOB :text_optional_beta,
                       :text_optional_alfa GLOB 'a*',
                       :text_optional_alfa GLOB :text_optional_beta
                """
        case "text-like-null-propagation":
            return """
                SELECT :text_alfa LIKE 'a%', :text_alfa LIKE :text_null,
                       :text_null LIKE 'a%', :text_null LIKE :text_null
                """
        case "text-glob-null-propagation":
            return """
                SELECT :text_alfa GLOB 'a*', :text_alfa GLOB :text_null,
                       :text_null GLOB 'a*', :text_null GLOB :text_null
                """
        case "text-glob-case-sensitivity":
            return """
                SELECT :text_alfa GLOB 'a*', :text_alfa GLOB 'A*',
                       :text_alfa GLOB '?lfa'
                """
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
    }

    func fixedCTERows(for caseID: String) throws -> [[DatabaseValue]] {
        let parts = caseID.split(separator: ".").map(String.init)
        guard parts.count == 5 else {
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        let shape = parts[3]
        let operation = parts[4]
        let integers: [Int64?]
        switch (shape, operation) {
        case ("ordinary-required", "union"),
             ("ordinary-required", "union-all"):
            integers = [1, 2]
        case ("ordinary-required", "intersect"),
             ("ordinary-required", "except"):
            integers = [1]
        case ("ordinary-nullable", "union"),
             ("ordinary-nullable", "union-all"):
            integers = [1, nil]
        case ("ordinary-nullable", "intersect"),
             ("ordinary-nullable", "except"):
            integers = [1]
        case ("recursive-required", "union"):
            integers = [1, 2, 3]
        case ("recursive-required", "union-all"):
            integers = [1, 2, 2, 3]
        case ("recursive-required", "intersect"):
            integers = [2]
        case ("recursive-required", "except"):
            integers = [1, 3]
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        return integers.map { value in
            [value.map { $0.databaseValue } ?? .null]
        }
    }

    func canonicalRows(_ rows: [[DatabaseValue]]) -> [[DatabaseValue]] {
        rows.sorted { databaseRowKey($0) < databaseRowKey($1) }
    }

    func databaseRowKey(_ row: [DatabaseValue]) -> String {
        row.map { String(reflecting: $0.storage) }.joined(separator: "\u{1f}")
    }

    func makeDeliberateFailure(
        runtime: SQLiteRuntimeMetadata,
        database: Database
    ) throws -> SQLiteCombinatorialFailureRecord {
        let brokenSQL = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(DeliberatelyBrokenRenderer())
            .sql
        let brokenCase = SQLiteCombinatorialCase(
            id: deliberateBrokenRendererCaseID,
            template: "deliberately-broken-renderer",
            strength: "deliberate-negative-control",
            dimensionVector: [],
            constraintIDs: [],
            inventoryFeatureIDs: ["syntax.select.core"],
            northwindAnchorCaseIDs: nil,
            requiredCapabilities: [],
            renderedSQL: brokenSQL,
            bindings: [],
            mode: .prepareOnly,
            oracle: nil,
            reproductionCommand: "swift test --filter SQLiteCombinatorialConformanceTests/testDeliberatelyBrokenRendererProducesStableFailureEvidence"
        )

        do {
            _ = try database.makeStatement(sql: brokenSQL)
            throw SQLiteCombinatorialConformanceError.brokenRendererPrepared(brokenSQL)
        }
        catch let error as DatabaseError {
            return SQLiteCombinatorialFailureRecord(
                testCase: brokenCase,
                originalSQL: brokenSQL,
                failingSQL: brokenSQL,
                bindings: [],
                stage: .prepare,
                failureSignature: SQLiteCombinatorialFailureSignature(
                    errorType: "GRDB.DatabaseError",
                    code: String(error.resultCode.rawValue),
                    message: error.message ?? "SQLite prepare error"
                ),
                runtimeMetadata: runtime,
                reducedFromCaseID: nil,
                reductionAttemptCount: 0,
                reducedDimensions: [],
                reproductionCommand: brokenCase.reproductionCommand
            )
        }
    }

    func sha256Hex(_ data: Data) -> String {
        PortableSHA256.hexDigest(of: data)
    }
}


private let deliberateBrokenRendererCaseID = "c191.v1.deliberately-broken-renderer"
private let combinatorialMaximumRuntimeMilliseconds = 120_000


private struct DeliberatelyBrokenRenderer: XLEncodable {
    func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("SELECT") { builder in
            builder.unaryPrefix("FROM") { nested in
                nested.name("broken_renderer_source")
            }
        }
    }
}


private enum SQLiteCombinatorialConformanceError: Error, Equatable {
    case unknownCaseID(String)
    case missingCapability(caseID: String, capability: String)
    case unknownCapability(caseID: String, capability: String)
    case missingOracle(String)
    case unknownOracle(String)
    case semanticMismatch(String)
    case brokenRendererPrepared(String)
}
