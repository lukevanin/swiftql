//
//  SQLQueryPeerMacroTests.swift
//  SwiftQL
//
//  Runtime tests for the `@SQLQuery` peer macro (#359): the generated
//  statement builders render placeholder SQL with a typed parameter layout,
//  and the generated executors bind invocation values and fetch rows from a
//  GRDB database.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


///
/// Spike (#369): the trapping direct-result entry point.
///
/// A `@SQLQuery` spec written with a direct result type (`[Row]` / `Row?`) calls
/// this instead of `sql {}` so the function type-checks without the
/// `XLQueryStatement` boilerplate. It is only a type-check anchor and a syntax
/// source for the macro; invoking it directly traps loudly, because the real
/// work happens in the generated executor peer. The macro rewrites this callee
/// back to `sql {}` when it emits the value-free statement builder.
///
/// The name is provisional — `sqlQuery` is already the labeled-closure statement
/// builder, so the direct-result anchor needs its own name.
///
func sqlResult<Row, Result>(
    @XLQueryExpressionBuilder _ builder: (XLSchema) -> any XLQueryStatement<Row>
) -> Result {
    fatalError(
        "'sqlResult' marks a @SQLQuery specification, not an executor. "
        + "Call the generated executor peer (e.g. fetchPersonByName) instead."
    )
}


extension GRDBDatabase {

    @SQLQuery
    func rowsMatchingID(id: String) -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    // Spike (#369): direct-result specs — no `XLQueryStatement` boilerplate.
    // `[TestTable]` dispatches to fetchAll; `TestTable?` dispatches to fetchOne.

    @SQLQuery
    func directRowsMatchingID(id: String) -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func directRowMatchingID(id: String) -> TestTable? {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func rowsMatchingIDAndMinimumValue(id: String, minimumValue: Int) -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id && table.value >= minimumValue)
        }
    }

    @SQLQuery
    func nullableRowsMatchingValue(value: Int?) -> any XLQueryStatement<TestNullablesTable> {
        sql { schema in
            let table = schema.table(TestNullablesTable.self)
            Select(table)
            From(table)
            Where(table.value == value)
        }
    }
}


final class XLQueryPeerMacroTests: XCTestCase {

    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory
            .appendingPathComponent(filename, isDirectory: false)
            .appendingPathExtension("sqlite")
        encoder = XLiteEncoder(formatter: formatter)
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        encoder = nil
        databasePool = nil
        database = nil
    }


    // MARK: - Placeholder rendering

    func testOneParameterStatementRendersNamedPlaceholderSQL() throws {
        let encoding = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(
            encoding.sql,
            "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (`t0`.`id` == :id)"
        )
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.key), [.named("id")])
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.nullability), [.required])
    }

    func testTwoParameterStatementRendersNamedPlaceholderSQL() throws {
        let encoding = encoder.makeSQL(database.rowsMatchingIDAndMinimumValueStatement())

        XCTAssertTrue(encoding.sql.contains(":id"), "expected ':id' placeholder in \(encoding.sql)")
        XCTAssertTrue(encoding.sql.contains(":minimumValue"), "expected ':minimumValue' placeholder in \(encoding.sql)")
        XCTAssertFalse(encoding.sql.contains("'"), "expected no inline value literal in \(encoding.sql)")
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.key),
            [.named("id"), .named("minimumValue")]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.nullability),
            [.required, .required]
        )
    }

    func testOptionalParameterStatementRendersNullableSlot() throws {
        let encoding = encoder.makeSQL(database.nullableRowsMatchingValueStatement())

        XCTAssertTrue(encoding.sql.contains(":value"), "expected ':value' placeholder in \(encoding.sql)")
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.key), [.named("value")])
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.nullability), [.nullable])
    }

    func testStatementBuilderRendersIdenticalSQLOnRepeatedCalls() throws {
        let first = encoder.makeSQL(database.rowsMatchingIDStatement())
        let second = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(first.sql, second.sql)
        XCTAssertEqual(first.parameterLayout, second.parameterLayout)
    }


    // MARK: - Execution

    func testOneParameterExecutorFetchesMatchingRowsForEachInvocation() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "alpha"),
            [TestTable(id: "alpha", value: 1)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 2)]
        )
        XCTAssertEqual(try database.fetchRowsMatchingID(id: "gamma"), [])
    }

    func testTwoParameterExecutorFetchesMatchingRows() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "alpha", minimumValue: 2),
            [TestTable(id: "alpha", value: 5)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "alpha", minimumValue: 0).count,
            2
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "beta", minimumValue: 10),
            []
        )
    }

    func testOptionalParameterExecutorBindsValueAndSQLNull() throws {
        try createNullablesTable()
        try insert(TestNullablesTable(id: "with-value", value: 42))
        try insert(TestNullablesTable(id: "without-value", value: nil))

        XCTAssertEqual(
            try database.fetchNullableRowsMatchingValue(value: 42),
            [TestNullablesTable(id: "with-value", value: 42)]
        )
        // Optional equality renders as SQL `IS`, which is null-safe: a nil
        // binding matches the row whose column is NULL.
        XCTAssertEqual(
            try database.fetchNullableRowsMatchingValue(value: nil),
            [TestNullablesTable(id: "without-value", value: nil)]
        )
    }


    // MARK: - Spike #369: direct-result execution

    func testDirectResultArrayExecutorFetchesAllMatchingRows() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        // `-> [TestTable]` dispatched to fetchAll and returned every match.
        XCTAssertEqual(
            try database.fetchDirectRowsMatchingID(id: "alpha").count,
            2
        )
        XCTAssertEqual(
            try database.fetchDirectRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 9)]
        )
        XCTAssertEqual(try database.fetchDirectRowsMatchingID(id: "gamma"), [])
    }

    func testDirectResultOptionalExecutorFetchesSingleRow() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        // `-> TestTable?` dispatched to fetchOne and returned an optional row.
        XCTAssertEqual(
            try database.fetchDirectRowMatchingID(id: "beta"),
            TestTable(id: "beta", value: 9)
        )
        XCTAssertNil(try database.fetchDirectRowMatchingID(id: "gamma"))
    }

    func testDirectResultStatementRendersSamePlaceholderSQLAsLegacyForm() throws {
        // The direct-result spec produces the same value-free statement as the
        // legacy XLQueryStatement spelling: a named placeholder, no inline
        // literal. The `sqlResult` -> `sql` callee swap is transparent.
        let direct = encoder.makeSQL(database.directRowsMatchingIDStatement())
        let legacy = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(direct.sql, legacy.sql)
        XCTAssertTrue(direct.sql.contains(":id"))
        XCTAssertFalse(direct.sql.contains("'"))
        XCTAssertEqual(direct.parameterLayout.slots.map(\.key), [.named("id")])
    }


    // MARK: - Helpers

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func createNullablesTable() throws {
        try database.makeRequest(with: sqlCreate(TestNullablesTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }

    private func insert(_ row: TestNullablesTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
