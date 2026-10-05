//
//  SQLAsyncRequestTests.swift
//  SwiftQL
//
//  Issue #681: the asynchronous request surface. A request's `async` view
//  runs the same SQL with the same bindings as its synchronous fetches, and a
//  declared query spelled `async throws` compiles and awaits it.
//

import Foundation
import XCTest
import GRDB
@_spi(GRDB) import SwiftQL


extension GRDBDatabase {

    @SQLQuery
    func asyncRowsMatchingID(id: String) async throws -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
            OrderBy(table.value.ascending())
        }
    }

    // `async` alone: the executor still throws, because binding and fetching
    // can fail.
    @SQLQuery
    func asyncRowMatchingID(id: String) async -> TestTable? {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func asyncTheOnlyRowMatchingID(id: String) async throws -> TestTable {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    // `throws` alone keeps the synchronous executor.
    @SQLQuery
    func throwingRowsMatchingID(id: String) throws -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func asyncProbedRowsMatchingID(id: String) async throws -> [TestTable] {
        sqlResult { schema in
            let _ = DeclaredQueryRenderProbe.peerAsyncRows.record()
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }
}


final class XLAsyncRequestTests: XCTestCase {

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


    // MARK: - Declared queries

    func testAsyncDeclaredQueryFetchesAllMatchingRows() async throws {
        try seed()

        let alpha = try await database.fetchAsyncRowsMatchingID(id: "alpha")
        let gamma = try await database.fetchAsyncRowsMatchingID(id: "gamma")

        XCTAssertEqual(alpha, [TestTable(id: "alpha", value: 1), TestTable(id: "alpha", value: 5)])
        XCTAssertEqual(gamma, [])
    }

    func testAsyncDeclaredQueryWithoutThrowsFetchesOneRow() async throws {
        try seed()

        let beta = try await database.fetchAsyncRowMatchingID(id: "beta")
        let gamma = try await database.fetchAsyncRowMatchingID(id: "gamma")

        XCTAssertEqual(beta, TestTable(id: "beta", value: 9))
        XCTAssertNil(gamma)
    }

    func testAsyncExactlyOneReturnsTheRowAndRejectsZeroOrMany() async throws {
        try seed()

        let beta = try await database.fetchAsyncTheOnlyRowMatchingID(id: "beta")
        XCTAssertEqual(beta, TestTable(id: "beta", value: 9))

        do {
            _ = try await database.fetchAsyncTheOnlyRowMatchingID(id: "gamma")
            XCTFail("No row matched.")
        }
        catch {
            XCTAssertEqual(error as? XLQueryCardinalityError, .noRowsMatched)
        }
        do {
            _ = try await database.fetchAsyncTheOnlyRowMatchingID(id: "alpha")
            XCTFail("Two rows matched.")
        }
        catch {
            XCTAssertEqual(error as? XLQueryCardinalityError, .moreThanOneRowMatched)
        }
    }

    func testThrowingDeclaredQueryKeepsASynchronousExecutor() throws {
        try seed()

        XCTAssertEqual(
            try database.fetchThrowingRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 9)]
        )
    }

    func testAsyncDeclaredQueryRendersOnceAcrossCalls() async throws {
        try seed()
        let before = DeclaredQueryRenderProbe.peerAsyncRows.count

        let alpha = try await database.fetchAsyncProbedRowsMatchingID(id: "alpha")
        let beta = try await database.fetchAsyncProbedRowsMatchingID(id: "beta")
        let gamma = try await database.fetchAsyncProbedRowsMatchingID(id: "gamma")

        XCTAssertEqual(alpha.count, 2)
        XCTAssertEqual(beta, [TestTable(id: "beta", value: 9)])
        XCTAssertEqual(gamma, [])
        // Each test opens a new pool, so the first call renders for its key
        // and the two later calls reuse that render.
        XCTAssertEqual(
            DeclaredQueryRenderProbe.peerAsyncRows.count - before,
            1,
            "the first call renders once, and every later call reuses it"
        )
    }


    // MARK: - The request's async view

    func testAsyncViewReturnsWhatTheSynchronousFetchesReturn() async throws {
        try seed()
        let request = database.makeRequest(with: rowsMatchingIDStatement())
        let packet = try packet(for: request, id: "alpha")

        let all = try await request.async.fetchAll(bindings: packet)
        let one = try await request.async.fetchOne(bindings: packet)
        let atMostOne = try await request.async.fetchAtMost(1, bindings: packet)

        XCTAssertEqual(all, try request.fetchAll(bindings: packet))
        XCTAssertEqual(all, [TestTable(id: "alpha", value: 1), TestTable(id: "alpha", value: 5)])
        XCTAssertEqual(one, try request.fetchOne(bindings: packet))
        XCTAssertEqual(atMostOne, try request.fetchAtMost(1, bindings: packet))
        XCTAssertEqual(atMostOne, [TestTable(id: "alpha", value: 1)])
    }

    func testAsyncViewCarriesTheBindingsSetWhenItWasTaken() async throws {
        try seed()
        let id = XLNamedBindingReference<String>(name: "id")
        var request = database.makeRequest(with: rowsMatchingIDStatement())
        request.set(id, "beta")
        let view = request.async
        request.set(id, "alpha")

        let viewRows = try await view.fetchAll()
        let viewRow = try await view.fetchOne()
        let requestRows = try await request.async.fetchAll()

        XCTAssertEqual(viewRows, [TestTable(id: "beta", value: 9)])
        XCTAssertEqual(viewRow, TestTable(id: "beta", value: 9))
        XCTAssertEqual(requestRows.count, 2)
    }

    func testAsyncWriteRequestExecutes() async throws {
        try createTestTable()

        try await database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).async.execute()

        XCTAssertEqual(try allRows(), [TestTable(id: "alpha", value: 1)])
    }

    func testAsyncFetchOfAReturningStatementAppliesItOnTheWriter() async throws {
        try await databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        }
        let schema = XLSchema()
        let table = schema.table(TestTable.self)
        let statement = insert(table)
            .values(TestTable.MetaInsert(TestTable(id: "alpha", value: 1)))
            .returning(table)

        let returned = try await database.makeRequest(with: statement).async.fetchAll()

        XCTAssertEqual(returned, [TestTable(id: "alpha", value: 1)])
        XCTAssertEqual(try allRows(), [TestTable(id: "alpha", value: 1)])
    }

    /// `fetchOne` on a `RETURNING` statement decodes its row inside the
    /// statement's transaction, as `fetchAll` does, so a row that fails to
    /// decode rolls the statement back instead of committing it.
    func testAsyncFetchOneOfAReturningStatementRollsBackWhenTheRowFailsToDecode() async throws {
        try await createNullableValueTestTable()
        let statement = deleteEveryRowReturningTestTable()

        do {
            let row = try await database.makeRequest(with: statement).async.fetchOne()
            XCTFail("A NULL value cannot decode as TestTable.value, but fetchOne returned \(String(describing: row)).")
        }
        catch {
            // The decode failure is expected; what matters is the rollback.
        }
        XCTAssertEqual(try nullableValueRowCount(), 1, "the DELETE must roll back")
    }

    func testCancelledTaskIsNotLentAConnection() async throws {
        try seed()
        let read = database.makeRequest(with: rowsMatchingIDStatement())
        let write = database.makeRequest(with: sqlInsert(TestTable(id: "delta", value: 4)))
        let packet = try packet(for: read, id: "alpha")
        let readView = read.async
        let writeView = write.async

        let fetch = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await readView.fetchAll(bindings: packet)
        }
        let execute = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            try await writeView.execute()
        }
        fetch.cancel()
        execute.cancel()

        switch await fetch.result {
        case .success(let rows):
            XCTFail("A cancelled task fetched \(rows).")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        switch await execute.result {
        case .success:
            XCTFail("A cancelled task executed the insert.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(try allRows().contains(TestTable(id: "delta", value: 4)))
    }

    /// A cancelled task gets `CancellationError` before anything else, even
    /// when its bindings are incomplete and would otherwise fail validation.
    func testCancelledTaskIsReportedBeforeItsBindingsAreValidated() async throws {
        try seed()
        let view = database.makeRequest(with: rowsMatchingIDStatement()).async

        let fetch = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await view.fetchAll()
        }
        fetch.cancel()

        switch await fetch.result {
        case .success(let rows):
            XCTFail("A cancelled task fetched \(rows).")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// GRDB's view suspends in the driver's asynchronous scope, which
    /// interrupts a running statement when its task is cancelled. The
    /// blocking default could only check for cancellation before it starts,
    /// so this also shows that a GRDB request does not fall back to it.
    func testCancellingARunningAsyncFetchInterruptsIt() async throws {
        try createTestTable()
        try await databasePool.write { db in
            for index in 0..<1_000 {
                try db.execute(
                    sql: "INSERT INTO Test (id, value) VALUES (?, ?)",
                    arguments: ["row-\(index)", index]
                )
            }
        }
        // A three-way cross join of 1,000 rows steps SQLite 10^9 times before
        // it returns its one count, far longer than this test waits.
        let statement = sql { schema in
            let first = schema.table(TestTable.self)
            let second = schema.table(TestTable.self)
            let third = schema.table(TestTable.self)
            Select(first.value.count())
            From(first)
            Join.Cross(second)
            Join.Cross(third)
        }
        let view = database.makeRequest(with: statement).async

        let fetch = Task {
            try await view.fetchOne()
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let cancelledAt = Date()
        fetch.cancel()

        switch await fetch.result {
        case .success(let count):
            XCTFail("The fetch ran to completion and counted \(String(describing: count)).")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(cancelledAt),
            10,
            "cancelling must interrupt the statement, not wait for it"
        )
    }

    func testRequestFromATransactionScopeCannotBeAwaited() async throws {
        try seed()
        let statement = rowsMatchingIDStatement()
        let escaped = try database.withTransaction { scope in
            var request = scope.makeRequest(with: statement)
            request.set(XLNamedBindingReference<String>(name: "id"), "alpha")
            return request.async
        }

        do {
            _ = try await escaped.fetchAll()
            XCTFail("A transaction scope's request has no asynchronous form.")
        }
        catch {
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped, "\(type(of: error)): \(error)")
        }
    }


    // MARK: - Helpers

    /// A `Test` table holding one row whose `value` is NULL, which
    /// `TestTable.value` cannot decode.
    private func createNullableValueTestTable() async throws {
        try await databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER)")
            try db.execute(sql: "INSERT INTO Test (id, value) VALUES ('alpha', NULL)")
        }
    }

    private func deleteEveryRowReturningTestTable() -> any XLReturningStatement<TestTable> {
        let schema = XLSchema()
        let table = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        return delete(table)
            .where(table.id == table.id)
            .returning(projection)
    }

    private func nullableValueRowCount() throws -> Int {
        try databasePool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Test") ?? 0
        }
    }

    private func rowsMatchingIDStatement() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == XLNamedBindingReference<String>(name: "id"))
            OrderBy(table.value.ascending())
        }
    }

    private func packet(
        for request: any XLRequest<TestTable>,
        id: String
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        let layout = request.parameterLayout
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try _xlQueryParameterBinding(id, named: "id", in: layout, using: XLSQLiteDialect.self)]
        ).validatingComplete()
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

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func allRows() throws -> [TestTable] {
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending(), table.value.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll()
    }
}
