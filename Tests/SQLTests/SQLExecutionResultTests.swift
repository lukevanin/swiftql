//
//  SQLExecutionResultTests.swift
//  SwiftQL
//
//  Issue #679: a write reports what it did, and a database failure reaches
//  the caller as the portable `XLDatabaseError`, not as GRDB's error type.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLExecutionResultTests: XCTestCase {

    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }


    // MARK: - Execution result

    func testInsertReportsOneRowAndItsRowID() throws {
        try createTestTable()

        let first = try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
        let second = try database.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()

        XCTAssertEqual(first, XLExecutionResult(rowsAffected: 1, lastInsertedRowID: 1, access: .write))
        XCTAssertEqual(second, XLExecutionResult(rowsAffected: 1, lastInsertedRowID: 2, access: .write))
    }

    func testUpdateAndDeleteReportTheRowsTheyChangedAndNoInsertedRow() throws {
        try seed()

        let updated = try database.makeRequest(with: setEveryValue(to: 7)).execute()
        let schema = XLSchema()
        let table = schema.into(TestTable.self)
        let deleted = try database.makeRequest(with: delete(table).where(table.id == "alpha")).execute()

        XCTAssertEqual(updated, XLExecutionResult(rowsAffected: 3, lastInsertedRowID: nil, access: .write))
        XCTAssertEqual(deleted, XLExecutionResult(rowsAffected: 2, lastInsertedRowID: nil, access: .write))
    }

    /// `sqlite3_changes` keeps the previous INSERT's count, so a statement that
    /// changes no rows must not report it.
    func testStatementThatChangesNoRowsReportsZeroAfterAnInsert() throws {
        try createTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()

        let create = try database.makeRequest(with: sqlCreate(TestNullablesTable.self)).execute()

        XCTAssertEqual(create, XLExecutionResult(rowsAffected: 0, lastInsertedRowID: nil, access: .write))
    }

    /// Clearing the connection's last inserted row id to detect an insert must
    /// not change what the connection reports afterward.
    func testStatementThatInsertsNothingLeavesTheConnectionsLastInsertedRowID() throws {
        try createTestTable()
        let request = database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1)))
        try databasePool.writeWithoutTransaction { db in
            try db.execute(sql: "INSERT INTO Test (id, value) VALUES ('seed', 0)")
            XCTAssertEqual(db.lastInsertedRowID, 1)
        }

        try database.makeRequest(with: setEveryValue(to: 7)).execute()

        let lastInsertedRowID = databasePool.writeWithoutTransaction { db in
            db.lastInsertedRowID
        }
        XCTAssertEqual(lastInsertedRowID, 1)
        XCTAssertEqual(try request.execute().lastInsertedRowID, 2)
    }

    func testAsyncExecuteReportsTheSameResult() async throws {
        try createTestTable()

        let result = try await database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).async.execute()

        XCTAssertEqual(result, XLExecutionResult(rowsAffected: 1, lastInsertedRowID: 1, access: .write))
    }

    func testWriteInsideATransactionScopeReportsItsResult() throws {
        try createTestTable()

        let results = try database.withTransaction { scope in
            [
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute(),
                try scope.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute(),
            ]
        }

        XCTAssertEqual(results.map(\.rowsAffected), [1, 1])
        XCTAssertEqual(results.map(\.lastInsertedRowID), [1, 2])
    }


    // MARK: - Portable errors

    func testConstraintViolationIsAPortableErrorWithTheExtendedCode() throws {
        try databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        }
        try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()

        XCTAssertThrowsError(
            try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 2))).execute()
        ) { error in
            guard let error = error as? XLDatabaseError else {
                return XCTFail("Expected an XLDatabaseError, received \(error).")
            }
            XCTAssertEqual(error.code, .constraint)
            XCTAssertEqual(error.nativeCode, 1555, "SQLITE_CONSTRAINT_PRIMARYKEY")
            XCTAssertEqual(error.driver, XLDriverIdentifier(rawValue: "grdb"))
            XCTAssertNotNil(error.sql)
            XCTAssertTrue(error.underlying is DatabaseError)
        }
    }

    func testFailureFromAnAsyncFetchIsAPortableError() async throws {
        let request = database.makeRequest(
            with: sql { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
            }
        )

        do {
            _ = try await request.async.fetchAll()
            XCTFail("The table does not exist.")
        }
        catch {
            XCTAssertEqual((error as? XLDatabaseError)?.code, .other, "\(error)")
        }
    }


    // MARK: - Helpers

    private func setEveryValue(to value: Int) -> any XLUpdateStatement<TestTable> {
        let schema = XLSchema()
        let table = schema.into(TestTable.self)
        return update(table).set { row in row.value = value }
    }

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func seed() throws {
        try createTestTable()
        for row in [
            TestTable(id: "alpha", value: 1),
            TestTable(id: "alpha", value: 5),
            TestTable(id: "beta", value: 9),
        ] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
    }
}
