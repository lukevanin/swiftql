//
//  SQLQueriesContainerTests.swift
//  SwiftQL
//
//  Runtime tests for the `@SQLQueries` member macro (#369, container
//  encoding): the macro attaches to a database extension on the v1.x
//  toolchain floor, reads the specifications from the nested (fileprivate)
//  `Query` container, and generates working executors — connection-scoped on
//  `Context` and one-shot on the database.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLQueries
extension GRDBDatabase {

    // The container is deliberately `fileprivate`: generated code never
    // references it, so the trapping specification functions are invisible
    // outside this file. Only the generated executors are callable.
    fileprivate struct Query {

        func containerRowsMatchingID(id: String) -> [TestTable] {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id == id)
            }
        }

        func containerRowMatchingID(id: String) -> TestTable? {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id == id)
            }
        }
    }
}


final class XLQueriesContainerTests: XCTestCase {

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
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        databasePool = nil
        database = nil
    }


    // MARK: - Database-level executors (implicit, one-shot)

    func testDatabaseExecutorFetchesAllMatchingRows() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        XCTAssertEqual(try database.containerRowsMatchingID(id: "alpha").count, 2)
        XCTAssertEqual(
            try database.containerRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 9)]
        )
        XCTAssertEqual(try database.containerRowsMatchingID(id: "gamma"), [])
    }

    func testDatabaseExecutorFetchesSingleOptionalRow() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))

        XCTAssertEqual(
            try database.containerRowMatchingID(id: "alpha"),
            TestTable(id: "alpha", value: 1)
        )
        XCTAssertNil(try database.containerRowMatchingID(id: "gamma"))
    }


    // MARK: - Context-scoped execution (explicit)

    func testExecuteClosureProvidesContextScopedExecutors() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        let rows = try database.execute { context in
            try context.containerRowsMatchingID(id: "alpha")
        }
        XCTAssertEqual(rows, [TestTable(id: "alpha", value: 1)])
    }

    func testExecuteClosureRunsMultipleQueriesInOneScope() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        let (all, one) = try database.execute { context in
            (
                try context.containerRowsMatchingID(id: "alpha"),
                try context.containerRowMatchingID(id: "beta")
            )
        }
        XCTAssertEqual(all, [TestTable(id: "alpha", value: 1)])
        XCTAssertEqual(one, TestTable(id: "beta", value: 9))
    }


    // MARK: - Helpers

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
