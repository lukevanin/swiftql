//
//  SQLDataChangingExecutionTests.swift
//
//  Real-SQLite execution coverage for the v1.4.4 data-changing statements.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
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


    // MARK: - REPLACE

    func testReplaceOverwritesConflictingRow() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let statement = replace(t).values(TestTable.MetaInsert(TestTable(id: "a", value: 2)))
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 2)])
    }


    // MARK: - ON CONFLICT upsert

    func testUpsertDoUpdateUsesExcludedValue() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let excluded = schema.excluded(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 5)))
            .onConflict("id", doUpdate: { row in row.value = excluded.value })
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 5)])
    }

    func testUpsertDoNothingKeepsExistingRow() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 99)))
            .onConflictDoNothing("id")
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 1)])
    }

    // MARK: - INSERT ... RETURNING

    func testInsertReturningYieldsInsertedRow() throws {
        try createUniqueTestTable()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 1)))
            .returning(t)

        let returned: [TestTable] = try database.makeRequest(with: statement).fetchAll()

        XCTAssertEqual(returned, [TestTable(id: "a", value: 1)])
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 1)])
    }

    func testUpsertDoUpdateReturningYieldsUpdatedRow() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let excluded = schema.excluded(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 5)))
            .onConflict("id", doUpdate: { row in row.value = excluded.value })
            .returning(t)

        // RETURNING reports the row as it exists after the upsert applies.
        let returned: [TestTable] = try database.makeRequest(with: statement).fetchAll()

        XCTAssertEqual(returned, [TestTable(id: "a", value: 5)])
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 5)])
    }

    func testInsertReturningIsNotObservable() throws {
        try createUniqueTestTable()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 1)))
            .returning(t)
        let request = database.makeRequest(with: statement)

        // A data-changing statement executes once; observing it would re-run the
        // insert on every database change, so publishing must fail instead.
        let failed = expectation(description: "publisher fails")
        var receivedError: Error?
        let cancellable = request.publish().sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    receivedError = error
                    failed.fulfill()
                }
            },
            receiveValue: { _ in }
        )
        wait(for: [failed], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(
            receivedError as? XLReturningRequestError,
            .observationUnsupported
        )
        // The failed observation must not have executed the insert.
        XCTAssertEqual(try allTestRows(), [])
    }

    // MARK: - DELETE ... RETURNING

    func testDeleteReturningYieldsDeletedRows() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let statement = delete(t)
            .where(t.id == "a")
            .returning(projection)

        let deleted: [TestTable] = try database.makeRequest(with: statement).fetchAll()

        XCTAssertEqual(deleted, [TestTable(id: "a", value: 1)])
        XCTAssertEqual(try allTestRows(), [TestTable(id: "b", value: 2)])
    }

    func testUpsertDoUpdateWithWhereOnlyUpdatesQualifyingRows() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 10))).execute()

        func upsert(candidate value: Int) throws {
            let schema = XLSchema()
            let t = schema.table(TestTable.self)
            let excluded = schema.excluded(TestTable.self)
            let statement = insert(t)
                .values(TestTable.MetaInsert(TestTable(id: "a", value: value)))
                .onConflict(
                    OnConflict.doUpdate(
                        on: "id",
                        set: { row in row.value = excluded.value },
                        where: excluded.value > t.value
                    )
                )
            try database.makeRequest(with: statement).execute()
        }

        // The predicate keeps the larger existing value: excluded.value (5) is
        // not greater than the stored value (10), so the update is skipped.
        try upsert(candidate: 5)
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 10)])

        // A larger candidate wins.
        try upsert(candidate: 42)
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 42)])
    }
}
