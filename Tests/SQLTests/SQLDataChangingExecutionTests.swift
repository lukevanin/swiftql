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

    // MARK: - UPDATE with common table expression

    func testUpdateWithCommonTableAppliesDerivedValues() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let schema = XLSchema()
        let source = schema.commonTable { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t)
        }
        let t = schema.into(TestTable.self)
        let s = schema.table(source)
        let statement = with(source)
            .update(t)
            .set { row in row.value = s.value + 100 }
            .from(s)
            .where(t.id == s.id)
        try database.makeRequest(with: statement).execute()

        XCTAssertEqual(
            try allTestRows(),
            [TestTable(id: "a", value: 101), TestTable(id: "b", value: 102)]
        )
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

    // MARK: - fetchAtMost (issue #643)

    /// The invocation packet for a request whose statement declares no
    /// parameters.
    private func emptyPacket<Row>(
        for request: any XLRequest<Row>
    ) throws -> any XLInvocationBindingPacket {
        try XLInvocationBindings<XLSQLiteValue>(
            layout: request.parameterLayout,
            bindings: []
        ).validatingComplete()
    }

    private func insertRows(_ rows: [TestTable]) throws {
        for row in rows {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
    }

    /// `fetchAtMost` on a plain query reads on a pooled reader and returns at
    /// most `limit` rows.
    func testFetchAtMostOnAReadStatementReturnsAtMostLimitRows() throws {
        try createUniqueTestTable()
        try insertRows([
            TestTable(id: "a", value: 1),
            TestTable(id: "b", value: 2),
            TestTable(id: "c", value: 3),
        ])
        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
            OrderBy(t.id.ascending())
        }
        let request = database.makeRequest(with: statement)
        let packet = try emptyPacket(for: request)

        XCTAssertEqual(try request.fetchAtMost(0, bindings: packet), [])
        XCTAssertEqual(
            try request.fetchAtMost(2, bindings: packet),
            [TestTable(id: "a", value: 1), TestTable(id: "b", value: 2)]
        )
        XCTAssertEqual(try request.fetchAtMost(5, bindings: packet).count, 3)
    }

    /// A `RETURNING` request changes the database, so `fetchAtMost` must run on
    /// the writer inside a transaction, as `fetchAll` does. Before issue #643
    /// it ran on a pooled reader, which is read-only, and the statement failed.
    /// Reading fewer rows than the statement returns still applies the whole
    /// statement, because SQLite makes every change during the first step.
    func testFetchAtMostOnAReturningStatementRunsOnTheWriterAndAppliesTheWholeStatement() throws {
        try createUniqueTestTable()
        try insertRows([
            TestTable(id: "a", value: 1),
            TestTable(id: "b", value: 2),
            TestTable(id: "c", value: 3),
        ])
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let statement = delete(t)
            .where(t.value >= 1)
            .returning(projection)
        let request = database.makeRequest(with: statement)

        let deleted = try request.fetchAtMost(1, bindings: try emptyPacket(for: request))

        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(try allTestRows(), [], "every matching row must be deleted, not only the row read")
    }

    /// `@SQLQuery` generates `fetchAtMost(2, bindings:)` and a count check for
    /// a bare-row return (`.exactlyOne`). The macro renders an
    /// `XLQueryStatement`, and `XLReturningStatement` does not refine it, so a
    /// declaration cannot hold a `RETURNING` statement. This runs the generated
    /// fetch shape against a `RETURNING` request on a `DatabasePool` instead,
    /// which is the call issue #643 fixes.
    func testExactlyOneFetchShapeOverAReturningStatementSucceedsOnADatabasePool() throws {
        try createUniqueTestTable()
        try insertRows([
            TestTable(id: "a", value: 1),
            TestTable(id: "b", value: 2),
        ])
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let statement = update(t)
            .set { row in row.value = 99 }
            .where(t.id == "a")
            .returning(projection)
        let request = database.makeRequest(with: statement)

        let rows = try request.fetchAtMost(2, bindings: try emptyPacket(for: request))

        XCTAssertEqual(rows, [TestTable(id: "a", value: 99)], "exactly one row, as `.exactlyOne` requires")
        XCTAssertEqual(
            try allTestRows(),
            [TestTable(id: "a", value: 99), TestTable(id: "b", value: 2)]
        )
    }

    // MARK: - UPDATE ... RETURNING

    func testUpdateReturningYieldsUpdatedRows() throws {
        try createUniqueTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let statement = update(t)
            .set { row in row.value = 99 }
            .where(t.id == "a")
            .returning(projection)

        // RETURNING reports each updated row as it exists after the update.
        let updated: [TestTable] = try database.makeRequest(with: statement).fetchAll()

        XCTAssertEqual(updated, [TestTable(id: "a", value: 99)])
        XCTAssertEqual(
            try allTestRows(),
            [TestTable(id: "a", value: 99), TestTable(id: "b", value: 2)]
        )
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
