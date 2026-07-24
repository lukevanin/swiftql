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
