//
//  SQLDataChangingExecutionTests.swift
//
//  Real-SQLite execution coverage for the v1.4.4 data-changing statements:
//  INSERT OR / REPLACE conflict handling, ON CONFLICT upsert, and RETURNING on
//  insert, update, and delete, plus CTE-backed updates.
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


    // MARK: - RETURNING

    func testInsertReturningReturnsInsertedRow() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()

        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let returned = schema.returning(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 1)))
            .returning(returned)
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1)])

        // The row is really inserted, not merely returned.
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 1)])
    }

    func testUpdateReturningReturnsUpdatedValues() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let statement = sqlUpdateReturning { schema in
            let t = schema.into(TestTable.self)
            let returned = schema.returning(TestTable.self)
            Update(t)
            Setting<TestTable> { row in
                row.value = t.value * 10
            }
            Where(t.id == "a")
            Returning(returned.value)
        }
        let returned = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(returned, [10])
        XCTAssertEqual(try allTestRows(), [TestTable(id: "a", value: 10), TestTable(id: "b", value: 2)])
    }

    func testDeleteReturningReturnsDeletedRows() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let statement = sqlDeleteReturning { schema in
            let t = schema.into(TestTable.self)
            let returned = schema.returning(TestTable.self)
            Delete(t)
            Where(t.value == 1)
            Returning(returned.id)
        }
        let returned = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(returned, ["a"])
        XCTAssertEqual(try allTestRows(), [TestTable(id: "b", value: 2)])
    }

    func testReturningObservationIsRejected() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let returned = schema.returning(TestTable.self)
        let statement = insert(t)
            .values(TestTable.MetaInsert(TestTable(id: "a", value: 1)))
            .returning(returned.id)
        let request = database.makeRequest(with: statement)
        let expectation = expectation(description: "observation fails")
        let cancellable = request.publish().sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTAssertEqual(error as? GRDBReturningRequestError, .observationUnsupported)
                    expectation.fulfill()
                }
            },
            receiveValue: { _ in
                XCTFail("Observation should not emit a value")
            }
        )
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }


    // MARK: - UPDATE with common table expression

    func testUpdateWithCommonTableExpression() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "c", value: 3))).execute()

        // Bump every row whose value is selected by the common table expression
        // (the rows with an even value).
        let statement = sql { schema in
            let cte = schema.commonTableExpression { schema in
                let source = schema.table(TestTable.self)
                Select(source)
                From(source)
                Where(source.value == 2)
            }
            let selected = schema.table(cte)
            let t = schema.into(TestTable.self)
            With(cte)
            Update(t)
            Setting<TestTable> { row in
                row.value = t.value + 100
            }
            Where(t.id.in { _ in
                Select(selected.id)
                From(selected)
            })
        }
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(
            try allTestRows(),
            [
                TestTable(id: "a", value: 1),
                TestTable(id: "b", value: 102),
                TestTable(id: "c", value: 3),
            ]
        )
    }
}
