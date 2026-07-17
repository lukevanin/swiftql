import GRDB
import XCTest

@testable import SwiftQL


@SQLResult
struct RecursiveCTEConstructionPrototypeRow: Equatable {
    let value: Int
    let depth: Int
}


final class RecursiveCTEConstructionPrototypeTests: XCTestCase {

    func testGeneratedCompositeReferenceRendersAndExecutesRecursiveCTE() throws {
        var draft = makeCompositeDraft(
            RecursiveCTEConstructionPrototypeRow.self,
            alias: "number_walk",
            referenceAlias: "recursive_row"
        )
        let definition = try draft.complete { recursiveRow in
            select(
                RecursiveCTEConstructionPrototypeRow.columns(
                    value: 1,
                    depth: 0
                )
            )
            .unionAll {
                select(
                    RecursiveCTEConstructionPrototypeRow.columns(
                        value: recursiveRow.value + 1,
                        depth: recursiveRow.depth + 1
                    )
                )
                .from(recursiveRow)
                .where(recursiveRow.depth < 2)
            }
        }

        let output = makeCompositeReference(
            RecursiveCTEConstructionPrototypeRow.self,
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

        let rows: [RecursiveCTEConstructionPrototypeRow] = try readRows(sql) { row in
            RecursiveCTEConstructionPrototypeRow(
                value: row["value"],
                depth: row["depth"]
            )
        }
        XCTAssertEqual(
            rows,
            [
                RecursiveCTEConstructionPrototypeRow(value: 1, depth: 0),
                RecursiveCTEConstructionPrototypeRow(value: 2, depth: 1),
                RecursiveCTEConstructionPrototypeRow(value: 3, depth: 2),
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
            PrototypeUnionAll(
                select(
                    PrototypeAliasedExpression(
                        expression: 1,
                        alias: "value"
                    )
                ),
                select(
                    PrototypeAliasedExpression(
                        expression: recursiveValue.value + 1,
                        alias: "value"
                    )
                )
                .from(recursiveValue)
                .where(recursiveValue.value < 4)
            )
        }

        let output = PrototypeScalarReference<Int>(
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
            return select(PrototypeAliasedExpression<Int>(expression: 1, alias: "value"))
        }

        XCTAssertThrowsError(try original.completedAlias()) { error in
            XCTAssertEqual(error as? PrototypeConstructionError, .incomplete("stable_alias"))
        }
        XCTAssertEqual(try copy.completedAlias(), "stable_alias")

        let originalDefinition = try original.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`stable_alias` AS `recursive_value`"
            )
            return select(PrototypeAliasedExpression<Int>(expression: 2, alias: "value"))
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
                PrototypeUnionAll(
                    select(
                        PrototypeAliasedExpression<Int>(
                            expression: 1,
                            alias: "value"
                        )
                    ),
                    select(
                        PrototypeAliasedExpression(
                            expression: innerRecursiveValue.value + 1,
                            alias: "value"
                        )
                    )
                    .from(innerRecursiveValue)
                    .where(innerRecursiveValue.value < 2)
                )
            }
            let innerOutput = PrototypeScalarReference<Int>(
                cteAlias: innerDefinition.alias,
                tableAlias: "inner_seed",
                columnAlias: "value"
            )
            return PrototypeUnionAll(
                XLWithStatement([innerDefinition])
                    .select(
                        PrototypeAliasedExpression(
                            expression: innerOutput.value * 10,
                            alias: "value"
                        )
                    )
                    .from(innerOutput)
                    .where(innerOutput.value == 1),
                select(
                    PrototypeAliasedExpression(
                        expression: recursiveValue.value + 10,
                        alias: "value"
                    )
                )
                .from(recursiveValue)
                .where(recursiveValue.value < 30)
            )
        }

        let output = PrototypeScalarReference<Int>(
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
            XCTAssertEqual(error as? PrototypeConstructionError, .incomplete("single_completion"))
        }

        _ = try draft.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`single_completion` AS `recursive_value`"
            )
            return select(PrototypeAliasedExpression<Int>(expression: 1, alias: "value"))
        }
        var secondBodyWasEvaluated = false
        XCTAssertThrowsError(
            try draft.complete { _ in
                secondBodyWasEvaluated = true
                return select(PrototypeAliasedExpression<Int>(expression: 2, alias: "value"))
            }
        ) { error in
            XCTAssertEqual(error as? PrototypeConstructionError, .alreadyCompleted("single_completion"))
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
                error as? PrototypeConstructionError,
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
                PrototypeAliasedExpression<Int>(expression: 1, alias: "value")
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
            try draft.complete { recursiveValue -> XLQuerySelectStatement<Int> in
                XCTAssertEqual(
                    render(recursiveValue),
                    "`retry_after_failure` AS `recursive_value`"
                )
                throw PrototypeConstructionError.bodyFailure
            }
        ) { error in
            XCTAssertEqual(error as? PrototypeConstructionError, .bodyFailure)
        }
        XCTAssertEqual(draft.alias, "retry_after_failure")
        XCTAssertThrowsError(try draft.completedAlias()) { error in
            XCTAssertEqual(error as? PrototypeConstructionError, .incomplete("retry_after_failure"))
        }

        let definition = try draft.complete { recursiveValue in
            XCTAssertEqual(
                render(recursiveValue),
                "`retry_after_failure` AS `recursive_value`"
            )
            return select(PrototypeAliasedExpression<Int>(expression: 7, alias: "value"))
        }
        XCTAssertEqual(definition.alias, "retry_after_failure")
        XCTAssertEqual(
            renderScalarDefinition(definition),
            "WITH `retry_after_failure` AS (SELECT 7 AS `value`) SELECT `output`.`value` FROM `retry_after_failure` AS `output`"
        )
    }
}


private enum PrototypeConstructionError: Error, Equatable {
    case incomplete(XLName)
    case alreadyCompleted(XLName)
    case reentrantCompletion(XLName)
    case bodyFailure
}


/// Test-only model of an alias-first, two-phase recursive CTE construction.
///
/// Completion mutates only this struct value. A failed body leaves the draft in
/// its declared state, and copying the draft copies its completion state instead
/// of sharing the mutable indirection used by the current production API.
private struct PrototypeRecursiveCTEDraft<Layout> where Layout: PrototypeReferenceLayout {

    private enum State {
        case declared
        case building
        case completed
    }

    let alias: XLName
    let layout: Layout
    private var state: State = .declared

    init(alias: XLName, layout: Layout) {
        self.alias = alias
        self.layout = layout
    }

    mutating func complete<Body>(
        _ makeBody: (Layout.Reference) throws -> Body
    ) throws -> XLCommonTableDependency where Body: XLEncodable {
        let reference = try beginCompletion()
        do {
            let body = try makeBody(reference)
            state = .completed
            return XLCommonTableDependency(alias: alias, statement: body)
        } catch {
            rollbackCompletion()
            throw error
        }
    }

    mutating func beginCompletion() throws -> Layout.Reference {
        switch state {
        case .declared:
            state = .building
            return layout.makeReference(cteAlias: alias)
        case .building:
            throw PrototypeConstructionError.reentrantCompletion(alias)
        case .completed:
            throw PrototypeConstructionError.alreadyCompleted(alias)
        }
    }

    mutating func rollbackCompletion() {
        guard case .building = state else {
            return
        }
        state = .declared
    }

    func completedAlias() throws -> XLName {
        guard case .completed = state else {
            throw PrototypeConstructionError.incomplete(alias)
        }
        return alias
    }
}


/// Immutable data needed to create a fresh current-v1 typed reference for one
/// completion attempt. The draft retains this value layout, never a generated
/// result, `XLNamespace`, statement body, or completed dependency.
private protocol PrototypeReferenceLayout {
    associatedtype Reference

    func makeReference(cteAlias: XLName) -> Reference
}


private struct PrototypeCompositeReferenceLayout<Row>: PrototypeReferenceLayout where Row: XLResult {
    let tableAlias: XLName

    func makeReference(cteAlias: XLName) -> Row.MetaNamedResult {
        makeCompositeReference(
            Row.self,
            cteAlias: cteAlias,
            tableAlias: tableAlias
        )
    }
}


private struct PrototypeScalarReferenceLayout<Value>: PrototypeReferenceLayout where Value: XLLiteral {
    let tableAlias: XLName
    let columnAlias: XLName

    func makeReference(cteAlias: XLName) -> PrototypeScalarReference<Value> {
        PrototypeScalarReference(
            cteAlias: cteAlias,
            tableAlias: tableAlias,
            columnAlias: columnAlias
        )
    }
}


/// Test-only direct scalar equivalent of a macro-generated named result.
private struct PrototypeScalarReference<Value>: XLMetaNamedResult where Value: XLLiteral {
    typealias Row = Value

    let _namespace: XLNamespace
    let _dependency: XLNamedTableDeclaration
    let value: XLColumnReference<Value>

    init(cteAlias: XLName, tableAlias: XLName, columnAlias: XLName) {
        let commonTable = prototypeAliasOnlyDependency(alias: cteAlias)
        let dependency = XLFromCommonTableDependency(
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


private struct PrototypeAliasedExpression<Value>: XLExpression where Value: XLLiteral {
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


/// The direct-scalar prototype cannot use SwiftQL's current compound-query
/// constraint because that constraint requires `Row: XLResult`. Keeping this
/// node test-only demonstrates the rendering seam without implementing #43.
private struct PrototypeUnionAll: XLEncodable {
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


/// This body must never render. References need only the immutable CTE alias;
/// they do not retain or mutate the definition that is completed later.
private struct PrototypeAliasOnlyBody: XLEncodable {
    func makeSQL(context: inout XLBuilder) {
        preconditionFailure("An alias-only recursive CTE reference cannot render a definition")
    }
}


private func prototypeAliasOnlyDependency(alias: XLName) -> XLCommonTableDependency {
    XLCommonTableDependency(alias: alias, statement: PrototypeAliasOnlyBody())
}


private func makeCompositeReference<Row>(
    _ type: Row.Type,
    cteAlias: XLName,
    tableAlias: XLName
) -> Row.MetaNamedResult where Row: XLResult {
    let dependency = XLFromCommonTableDependency(
        commonTable: prototypeAliasOnlyDependency(alias: cteAlias),
        alias: tableAlias
    )
    return Row.makeSQLAnonymousNamedResult(
        namespace: .table(),
        dependency: dependency
    )
}


private func makeCompositeDraft<Row>(
    _ type: Row.Type,
    alias: XLName,
    referenceAlias: XLName
) -> PrototypeRecursiveCTEDraft<PrototypeCompositeReferenceLayout<Row>> where Row: XLResult {
    PrototypeRecursiveCTEDraft(
        alias: alias,
        layout: PrototypeCompositeReferenceLayout(
            tableAlias: referenceAlias
        )
    )
}


private func makeScalarDraft<Value>(
    _ type: Value.Type,
    alias: XLName,
    referenceAlias: XLName,
    columnAlias: XLName
) -> PrototypeRecursiveCTEDraft<PrototypeScalarReferenceLayout<Value>> where Value: XLLiteral {
    PrototypeRecursiveCTEDraft(
        alias: alias,
        layout: PrototypeScalarReferenceLayout(
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
    let output = PrototypeScalarReference<Int>(
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
            PrototypeAliasedExpression<Int>(
                expression: index,
                alias: "value"
            )
        )
    }
    let output = PrototypeScalarReference<Int>(
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
