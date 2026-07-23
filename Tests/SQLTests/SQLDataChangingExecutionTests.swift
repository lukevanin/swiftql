//
//  SQLDataChangingExecutionTests.swift
//
//  Real-SQLite execution coverage for the v1.4.4 data-changing statements.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLDataChangingExecutionTests: XCTestCase {

    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
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
        try? databasePool?.close()
        encoder = nil
        databasePool = nil
        database = nil
    }

    /// Creates a `Test(id TEXT PRIMARY KEY, value INTEGER)` table so uniqueness
    /// conflicts can be triggered. SwiftQL's DDL does not emit key constraints,
    /// so the constrained schema is created directly.
    private func createUniqueTestTable() throws {
        try databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        }
    }

    private func allTestRows() throws -> [TestTable] {
        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
            OrderBy(t.id.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll()
    }


    // MARK: - INSERT OR

    func testInsertOrIgnoreKeepsExistingRow() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t, or: .ignore)
            Values(TestTable.MetaInsert(TestTable(id: "a", value: 99)))
        }
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 1)])
    }

    func testInsertOrReplaceOverwritesExistingRow() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t, or: .replace)
            Values(TestTable.MetaInsert(TestTable(id: "a", value: 7)))
        }
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 7)])
    }
}
