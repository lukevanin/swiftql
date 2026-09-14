import GRDB
import XCTest

@testable import SwiftQL


@SQLResult
struct RecursiveCommonTableConstructionRow: Equatable {
    let value: Int
    let depth: Int
}


///
/// Exercises the production alias-first recursive CTE construction lifecycle
/// (`XLRecursiveCommonTableDraft`, `XLRecursiveCommonTableReferenceLayout`, and
/// `XLRecursiveCommonTableConstructionError`) introduced by #205.
///
/// The tests use a test-only direct-scalar layout to prove the reference/layout
/// contract is generic enough for #43's one-column layout, and a composite
/// layout to prove the generated surface renders and executes. Byte-for-byte SQL
/// preservation of the public `recursiveCommonTable` /
/// `recursiveCommonTableExpression` surface is covered separately by
/// `XLSyntaxTests` and `XLExecutionTests`.
///
final class RecursiveCommonTableConstructionTests: XCTestCase {

    func testCompositeReferenceRendersAndExecutesRecursiveCTE() throws {
        var draft = XLRecursiveCommonTableDraft(
            alias: "number_walk",
            layout: TestCompositeLayout<RecursiveCommonTableConstructionRow>(
                schema: XLSchema(),
                commonTableNamespace: .common(),
                tableAlias: "recursive_row"
            )
        )
        let definition = try draft.complete { recursiveRow in
            select(
                RecursiveCommonTableConstructionRow.columns(
                    value: 1,
                    depth: 0
                )
            )
            .unionAll {
                select(
                    RecursiveCommonTableConstructionRow.columns(
                        value: recursiveRow.value + 1,
                        depth: recursiveRow.depth + 1
                    )
                )
                .from(recursiveRow)
                .where(recursiveRow.depth < 2)
            }
        }

        let output = makeCompositeReference(
            RecursiveCommonTableConstructionRow.self,
            cteAlias: definition.alias,
            tableAlias: "result_row"
        )
        let query = XLWithStatement([definition])
            .select(output)
            .from(output)
            .orderBy(output.value.ascending())
        let sql = render(query)

        XCTAssertEqual(
            sql,
            "WITH `number_walk` AS (SELECT 1 AS `value`, 0 AS `depth` UNION ALL SELECT (`recursive_row`.`value` + 1) AS `value`, (`recursive_row`.`depth` + 1) AS `depth` FROM `number_walk` AS `recursive_row` WHERE (`recursive_row`.`depth` < 2)) SELECT `result_row`.`value` AS `value`, `result_row`.`depth` AS `depth` FROM `number_walk` AS `result_row` ORDER BY `result_row`.`value` ASC"
        )

        let rows: [RecursiveCommonTableConstructionRow] = try readRows(sql) { row in
            RecursiveCommonTableConstructionRow(
                value: row["value"],
                depth: row["depth"]
            )
        }
        XCTAssertEqual(
            rows,
            [
                RecursiveCommonTableConstructionRow(value: 1, depth: 0),
                RecursiveCommonTableConstructionRow(value: 2, depth: 1),
                RecursiveCommonTableConstructionRow(value: 3, depth: 2),
            ]
        )
    }

    func testDirectScalarReferenceRendersAndExecutesRecursiveCTE() throws {
        var draft = makeScalarDraft(
            Int.self,
            alias: "count_up",
            referenceAlias: "recursive_value",
            columnAlias: "value"
        )
        let definition = try draft.complete { recursiveValue in
            TestUnionAll(
                select(
                    TestAliasedExpression(
                        expression: 1,
                        alias: "value"
                    )
                ),
                select(
                    TestAliasedExpression(
                        expression: recursiveValue.value + 1,
                        alias: "value"
                    )
                )
                .from(recursiveValue)
                .where(recursiveValue.value < 4)
            )
        }

        let output = TestScalarReference<Int>(
            cteAlias: definition.alias,
            tableAlias: "result_value",
            columnAlias: "value"
        )
        let query = XLWithStatement([definition])
            .select(output.value)
            .from(output)
            .orderBy(output.value.ascending())
        let sql = render(query)

        XCTAssertEqual(
            sql,
            "WITH `count_up` AS (SELECT 1 AS `value` UNION ALL SELECT (`recursive_value`.`value` + 1) AS `value` FROM `count_up` AS `recursive_value` WHERE (`recursive_value`.`value` < 4)) SELECT `result_value`.`value` FROM `count_up` AS `result_value` ORDER BY `result_value`.`value` ASC"
        )
        XCTAssertEqual(
            try readRows(sql) { row -> Int in row["value"] },
            [1, 2, 3, 4]
        )
    }

    func testCopiesOwnCompletionStateWhileKeepingTheDeclaredAlias() throws {
        var original = makeScalarDraft(
            Int.self,
            alias: "stable_alias",
            referenceAlias: "recursive_value",
            columnAlias: "value"
        )
        var copy = original

        let copyDefinition = try copy.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`stable_alias` AS `recursive_value`"
            )
            return select(TestAliasedExpression<Int>(expression: 1, alias: "value"))
        }

        XCTAssertThrowsError(try original.completedAlias()) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .incomplete("stable_alias")
            )
        }
        XCTAssertEqual(try copy.completedAlias(), "stable_alias")

        let originalDefinition = try original.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`stable_alias` AS `recursive_value`"
            )
            return select(TestAliasedExpression<Int>(expression: 2, alias: "value"))
        }
        XCTAssertEqual(originalDefinition.alias, copyDefinition.alias)
        XCTAssertEqual(
            renderScalarDefinition(originalDefinition),
            "WITH `stable_alias` AS (SELECT 2 AS `value`) SELECT `output`.`value` FROM `stable_alias` AS `output`"
        )
        XCTAssertEqual(
            renderScalarDefinition(copyDefinition),
            "WITH `stable_alias` AS (SELECT 1 AS `value`) SELECT `output`.`value` FROM `stable_alias` AS `output`"
        )
    }

    func testNestedRecursiveDefinitionsRenderAndExecute() throws {
        var outerDraft = makeScalarDraft(
            Int.self,
            alias: "outer_series",
            referenceAlias: "outer_recursive",
            columnAlias: "value"
        )
        let outerDefinition = try outerDraft.complete { recursiveValue in
            var innerDraft = makeScalarDraft(
                Int.self,
                alias: "inner_series",
                referenceAlias: "inner_recursive",
                columnAlias: "value"
            )
            let innerDefinition = try innerDraft.complete { innerRecursiveValue in
                TestUnionAll(
                    select(
                        TestAliasedExpression<Int>(
                            expression: 1,
                            alias: "value"
                        )
                    ),
                    select(
                        TestAliasedExpression(
                            expression: innerRecursiveValue.value + 1,
                            alias: "value"
                        )
                    )
                    .from(innerRecursiveValue)
                    .where(innerRecursiveValue.value < 2)
                )
            }
            let innerOutput = TestScalarReference<Int>(
                cteAlias: innerDefinition.alias,
                tableAlias: "inner_seed",
                columnAlias: "value"
            )
            return TestUnionAll(
                XLWithStatement([innerDefinition])
                    .select(
                        TestAliasedExpression(
                            expression: innerOutput.value * 10,
                            alias: "value"
                        )
                    )
                    .from(innerOutput)
                    .where(innerOutput.value == 1),
                select(
                    TestAliasedExpression(
                        expression: recursiveValue.value + 10,
                        alias: "value"
                    )
                )
                .from(recursiveValue)
                .where(recursiveValue.value < 30)
            )
        }

        let output = TestScalarReference<Int>(
            cteAlias: outerDefinition.alias,
            tableAlias: "outer_result",
            columnAlias: "value"
        )
        let query = XLWithStatement([outerDefinition])
            .select(output.value)
            .from(output)
            .orderBy(output.value.ascending())
        let sql = render(query)

        XCTAssertEqual(
            sql,
            "WITH `outer_series` AS (WITH `inner_series` AS (SELECT 1 AS `value` UNION ALL SELECT (`inner_recursive`.`value` + 1) AS `value` FROM `inner_series` AS `inner_recursive` WHERE (`inner_recursive`.`value` < 2)) SELECT (`inner_seed`.`value` * 10) AS `value` FROM `inner_series` AS `inner_seed` WHERE (`inner_seed`.`value` == 1) UNION ALL SELECT (`outer_recursive`.`value` + 10) AS `value` FROM `outer_series` AS `outer_recursive` WHERE (`outer_recursive`.`value` < 30)) SELECT `outer_result`.`value` FROM `outer_series` AS `outer_result` ORDER BY `outer_result`.`value` ASC"
        )
        XCTAssertEqual(
            try readRows(sql) { row -> Int in row["value"] },
            [10, 20, 30]
        )
    }

    func testIndependentConstructionCanRunConcurrently() async throws {
        let results = try await withThrowingTaskGroup(
            of: (Int, String).self,
            returning: [Int: String].self
        ) { group in
            for index in 0 ..< 16 {
                group.addTask {
                    (index, try makeIndependentScalarSQL(index: index))
                }
            }

            var results: [Int: String] = [:]
            for try await (index, sql) in group {
                results[index] = sql
            }
            return results
        }

        XCTAssertEqual(results.count, 16)
        for index in 0 ..< 16 {
            XCTAssertEqual(
                results[index],
                "WITH `series_\(index)` AS (SELECT \(index) AS `value`) SELECT `output_\(index)`.`value` FROM `series_\(index)` AS `output_\(index)`"
            )
        }
    }

    func testIncompleteAndMultipleCompletionAreRejected() throws {
        var draft = makeScalarDraft(
            Int.self,
            alias: "single_completion",
            referenceAlias: "recursive_value",
            columnAlias: "value"
        )

        XCTAssertThrowsError(try draft.completedAlias()) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .incomplete("single_completion")
            )
        }

        _ = try draft.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`single_completion` AS `recursive_value`"
            )
            return select(TestAliasedExpression<Int>(expression: 1, alias: "value"))
        }
        var secondBodyWasEvaluated = false
        XCTAssertThrowsError(
            try draft.complete { _ in
                secondBodyWasEvaluated = true
                return select(TestAliasedExpression<Int>(expression: 2, alias: "value"))
            }
        ) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .alreadyCompleted("single_completion")
            )
        }
        XCTAssertFalse(secondBodyWasEvaluated)
    }

    func testReentrantCompletionHasAStructuredOwnerAndRollsBack() throws {
        var draft = makeScalarDraft(
            Int.self,
            alias: "reentrant_completion",
            referenceAlias: "recursive_value",
            columnAlias: "value"
        )

        _ = try draft.beginCompletion()
        XCTAssertThrowsError(try draft.beginCompletion()) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .reentrantCompletion("reentrant_completion")
            )
        }
        draft.rollbackCompletion()

        let definition = try draft.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`reentrant_completion` AS `recursive_value`"
            )
            return select(
                TestAliasedExpression<Int>(expression: 1, alias: "value")
            )
        }
        XCTAssertEqual(definition.alias, "reentrant_completion")
        XCTAssertEqual(try draft.completedAlias(), "reentrant_completion")
    }

    func testFailedCompletionLeavesDraftReusableAndAliasStable() throws {
        var draft = makeScalarDraft(
            Int.self,
            alias: "retry_after_failure",
            referenceAlias: "recursive_value",
            columnAlias: "value"
        )

        XCTAssertThrowsError(
            try draft.complete { recursiveValue -> any XLEncodable in
                XCTAssertEqual(
                    render(recursiveValue),
                    "`retry_after_failure` AS `recursive_value`"
                )
                throw TestBodyError.bodyFailure
            }
        ) { error in
            XCTAssertEqual(error as? TestBodyError, .bodyFailure)
        }
        XCTAssertEqual(draft.alias, "retry_after_failure")
        XCTAssertThrowsError(try draft.completedAlias()) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .incomplete("retry_after_failure")
            )
        }

        let definition = try draft.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`retry_after_failure` AS `recursive_value`"
            )
            return select(TestAliasedExpression<Int>(expression: 7, alias: "value"))
        }
        XCTAssertEqual(definition.alias, "retry_after_failure")
        XCTAssertEqual(
            renderScalarDefinition(definition),
            "WITH `retry_after_failure` AS (SELECT 7 AS `value`) SELECT `output`.`value` FROM `retry_after_failure` AS `output`"
        )
    }

    func testDuplicateAliasesAreRejected() throws {
        let unique = [
            XLCommonTableDependency(alias: "a", statement: TestAliasedExpression<Int>(expression: 1, alias: "value")),
            XLCommonTableDependency(alias: "b", statement: TestAliasedExpression<Int>(expression: 2, alias: "value")),
        ]
        XCTAssertNoThrow(try xlValidateUniqueCommonTableAliases(unique))

        // Duplicate detection is case-insensitive, matching SQLite identifier resolution.
        let duplicated = [
            XLCommonTableDependency(alias: "series", statement: TestAliasedExpression<Int>(expression: 1, alias: "value")),
            XLCommonTableDependency(alias: "other", statement: TestAliasedExpression<Int>(expression: 2, alias: "value")),
            XLCommonTableDependency(alias: "SERIES", statement: TestAliasedExpression<Int>(expression: 3, alias: "value")),
        ]
        XCTAssertThrowsError(try xlValidateUniqueCommonTableAliases(duplicated)) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .duplicateAlias("SERIES")
            )
        }
    }

    func testResultLayoutMismatchIsRejected() throws {
        var draft = XLRecursiveCommonTableDraft(
            alias: "shaped",
            layout: TestScalarLayout<Int>(
                tableAlias: "recursive_value",
                columnAlias: "value"
            )
        )
        _ = try draft.beginCompletion()

        XCTAssertNoThrow(try draft.validateResultLayout(actualColumns: ["value"]))
        XCTAssertThrowsError(try draft.validateResultLayout(actualColumns: ["value", "extra"])) { error in
            XCTAssertEqual(
                error as? XLRecursiveCommonTableConstructionError,
                .resultLayoutMismatch(alias: "shaped", expected: ["value"], actual: ["value", "extra"])
            )
        }
    }
}


private enum TestBodyError: Error, Equatable {
    case bodyFailure
}


/// Test-only direct-scalar reference layout — demonstrates that the production
/// `XLRecursiveCommonTableReferenceLayout` contract is generic enough for a
/// one-column scalar reference (the shape #43 will add to the library).
private struct TestScalarLayout<Value>: XLRecursiveCommonTableReferenceLayout where Value: XLLiteral {
    let tableAlias: XLName
    let columnAlias: XLName

    var resultColumns: [XLName] { [columnAlias] }

    func makeReference(cteAlias: XLName) -> TestScalarReference<Value> {
        TestScalarReference(
            cteAlias: cteAlias,
            tableAlias: tableAlias,
            columnAlias: columnAlias
        )
    }
}


/// Test-only composite reference layout backed by the production alias-only
/// self-reference primitives, but pinning the reference table alias so the
/// rendered SQL is deterministic in the render test.
private struct TestCompositeLayout<Row>: XLRecursiveCommonTableReferenceLayout where Row: XLResult {
    let schema: XLSchema
    let commonTableNamespace: XLNamespace
    let tableAlias: XLName

    func makeReference(cteAlias: XLName) -> Row.MetaCommonTable.Result.MetaNamedResult {
        let dependency = XLCommonTableDependency(
            alias: cteAlias,
            statement: XLAliasOnlyCommonTableBody()
        )
        let commonTable = Row.makeSQLCommonTable(
            namespace: commonTableNamespace,
            dependency: dependency
        )
        return schema.table(commonTable, as: tableAlias)
    }
}


/// Test-only direct scalar equivalent of a macro-generated named result.
private struct TestScalarReference<Value>: XLMetaNamedResult where Value: XLLiteral {
    typealias Row = Value

    let _namespace: XLNamespace
    let _dependency: XLNamedTableDeclaration
    let value: XLColumnReference<Value>

    init(cteAlias: XLName, tableAlias: XLName, columnAlias: XLName) {
        let commonTable = XLCommonTableDependency(
            alias: cteAlias,
            statement: XLAliasOnlyCommonTableBody()
        )
        let dependency = XLFromTableDependency(
            commonTable: commonTable,
            alias: tableAlias
        )
        self._namespace = .table()
        self._dependency = dependency
        self.value = XLColumnReference(dependency: dependency, as: columnAlias)
    }

    func makeSQL(context: inout XLBuilder) {
        _dependency.makeSQL(context: &context)
    }
}


private struct TestAliasedExpression<Value>: XLExpression where Value: XLLiteral {
    typealias T = Value

    let expression: any XLExpression<Value>
    let alias: XLName

    init(expression: any XLExpression<Value>, alias: XLName) {
        self.expression = expression
        self.alias = alias
    }

    func makeSQL(context: inout XLBuilder) {
        context.alias(alias, expression: expression.makeSQL)
    }
}


/// A minimal `UNION ALL` node for the test-only direct-scalar path, which cannot
/// use SwiftQL's compound-query combinator until #43 relaxes its `Row: XLResult`
/// constraint.
private struct TestUnionAll: XLEncodable {
    let lhs: any XLEncodable
    let rhs: any XLEncodable

    init<L, R>(_ lhs: L, _ rhs: R) where L: XLEncodable, R: XLEncodable {
        self.lhs = lhs
        self.rhs = rhs
    }

    func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "UNION ALL",
            left: lhs.makeSQL,
            right: rhs.makeSQL
        )
    }
}


private func makeCompositeReference<Row>(
    _ type: Row.Type,
    cteAlias: XLName,
    tableAlias: XLName
) -> Row.MetaNamedResult where Row: XLResult {
    let dependency = XLFromTableDependency(
        commonTable: XLCommonTableDependency(
            alias: cteAlias,
            statement: XLAliasOnlyCommonTableBody()
        ),
        alias: tableAlias
    )
    return Row.makeSQLAnonymousNamedResult(
        namespace: .table(),
        dependency: dependency
    )
}


private func makeScalarDraft<Value>(
    _ type: Value.Type,
    alias: XLName,
    referenceAlias: XLName,
    columnAlias: XLName
) -> XLRecursiveCommonTableDraft<TestScalarLayout<Value>> where Value: XLLiteral {
    XLRecursiveCommonTableDraft(
        alias: alias,
        layout: TestScalarLayout(
            tableAlias: referenceAlias,
            columnAlias: columnAlias
        )
    )
}


private func render(_ expression: any XLEncodable) -> String {
    let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
    return XLiteEncoder(formatter: formatter).makeSQL(expression).sql
}


private func renderScalarDefinition(_ definition: XLCommonTableDependency) -> String {
    let output = TestScalarReference<Int>(
        cteAlias: definition.alias,
        tableAlias: "output",
        columnAlias: "value"
    )
    return render(
        XLWithStatement([definition])
            .select(output.value)
            .from(output)
    )
}


private func makeIndependentScalarSQL(index: Int) throws -> String {
    let alias = XLName("series_\(index)")
    var draft = makeScalarDraft(
        Int.self,
        alias: alias,
        referenceAlias: XLName("recursive_\(index)"),
        columnAlias: "value"
    )
    let definition = try draft.complete { _ in
        select(
            TestAliasedExpression<Int>(
                expression: index,
                alias: "value"
            )
        )
    }
    let output = TestScalarReference<Int>(
        cteAlias: definition.alias,
        tableAlias: XLName("output_\(index)"),
        columnAlias: "value"
    )
    return render(
        XLWithStatement([definition])
            .select(output.value)
            .from(output)
    )
}


private func readRows<Value>(
    _ sql: String,
    transform: (Row) throws -> Value
) throws -> [Value] {
    let databaseQueue = try DatabaseQueue()
    return try databaseQueue.read { database in
        try Row.fetchAll(database, sql: sql).map(transform)
    }
}
