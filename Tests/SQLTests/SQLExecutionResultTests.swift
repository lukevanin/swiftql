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
    var fileURL: URL!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
        if let fileURL {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }
    }


    // MARK: - Execution result

    func testInsertReportsOneRow() throws {
        try createTestTable()

        let first = try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
        let second = try database.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()

        XCTAssertEqual(first, XLExecutionResult(rowsAffected: 1, access: .write))
        XCTAssertEqual(second, XLExecutionResult(rowsAffected: 1, access: .write))
    }

    func testUpdateAndDeleteReportTheRowsTheyChanged() throws {
        try seed()

        let updated = try database.makeRequest(with: setEveryValue(to: 7)).execute()
        let schema = XLSchema()
        let table = schema.into(TestTable.self)
        let deleted = try database.makeRequest(with: delete(table).where(table.id == "alpha")).execute()

        XCTAssertEqual(updated, XLExecutionResult(rowsAffected: 3, access: .write))
        XCTAssertEqual(deleted, XLExecutionResult(rowsAffected: 2, access: .write))
    }

    /// `sqlite3_changes` keeps the previous INSERT's count, so a statement that
    /// changes no rows must not report it.
    func testStatementThatChangesNoRowsReportsZeroAfterAnInsert() throws {
        try createTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()

        let create = try database.makeRequest(with: sqlCreate(TestNullablesTable.self)).execute()

        XCTAssertEqual(create, XLExecutionResult(rowsAffected: 0, access: .write))
    }

    func testAsyncExecuteReportsTheSameResult() async throws {
        try createTestTable()

        let result = try await database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).async.execute()

        XCTAssertEqual(result, XLExecutionResult(rowsAffected: 1, access: .write))
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

    func testOpeningAFileThatIsNotADatabaseIsAPortableError() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        try Data(repeating: 0x41, count: 4096).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(
            try GRDBDatabaseBuilder(url: fileURL, configuration: Configuration(), logger: nil).build()
        ) { error in
            XCTAssertEqual((error as? XLDatabaseError)?.code, .notADatabase, "\(error)")
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
