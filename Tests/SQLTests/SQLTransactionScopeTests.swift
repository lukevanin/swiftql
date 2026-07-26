//
//  SQLTransactionScopeTests.swift
//  SwiftQL
//
//  Typed multi-statement transaction scopes (issue #284):
//  `XLTransactionalDatabase.withTransaction(_:)` runs an ordered sequence of
//  typed `XLRequest`/`XLWriteRequest` invocations on one pinned GRDB
//  connection, committing only after the whole body succeeds and rolling
//  back every write on any failure. These tests are state-oracle tests: every
//  commit/rollback assertion re-opens a brand-new `DatabasePool` against the
//  same SQLite file instead of reusing anything from inside the transaction,
//  so a broken implementation that merely avoided throwing could not pass by
//  accident.
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


// A peer `@SQLQuery` declaration (not `@SQLQueries`, which would redeclare
// the `Context`/`execute(_:)` pair `SQLQueriesContainerTests.swift` already
// generates once for `GRDBDatabase` in this same test target) — enough to
// prove a declared-query executor composes with `withTransaction(_:)`: it
// dispatches through whatever `self` it is called on, pinned scope or root
// database alike, with no separate query or binding runtime of its own.
extension GRDBDatabase {

    @SQLQuery
    fileprivate func transactionScopeRowByID(id: String) -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }
}


final class SQLTransactionScopeTests: XCTestCase {

    private struct UserError: Error, Equatable {
        let reason: String
    }

    var fileURL: URL!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let directory = FileManager.default.temporaryDirectory
        fileURL = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(
            databasePool: databasePool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
    }

    override func tearDown() {
        try? databasePool.close()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        databasePool = nil
        database = nil
    }

    // MARK: - Schema helpers

    /// The default `sqlCreate`-derived schema: no primary key, so it never
    /// enforces a uniqueness constraint. Used by every test that is not
    /// specifically exercising a constraint failure.
    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    /// A schema with a real `PRIMARY KEY`, created with raw SQL exactly like
    /// the shared issue #253 transaction-invariant fixtures do, so a
    /// duplicate `id` insert fails with `SQLITE_CONSTRAINT`. SwiftQL's typed
    /// `TestTable` statement builders only need the table and column names to
    /// match; they do not care how the table was declared.
    private func createConstrainedTestTable() throws {
        try databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        }
    }

    private func selectAllTestRowsQuery() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
        }
    }

    /// Reads durable state from a **fresh read boundary**: a brand-new
    /// `DatabasePool`/`GRDBDatabase` pair opened against the same file, not
    /// anything retained from `database` or from inside a transaction. A
    /// broken commit/rollback implementation that merely avoided throwing
    /// could not fool this.
    private func freshRows() throws -> [TestTable] {
        let freshPool = try DatabasePool(path: fileURL.path)
        defer { try? freshPool.close() }
        let freshDatabase = try GRDBDatabase(
            databasePool: freshPool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
        return try freshDatabase.makeRequest(with: selectAllTestRowsQuery()).fetchAll()
    }

    /// Reads only the `id` column from a fresh read boundary, bypassing
    /// `TestTable`'s typed row reader. Used by the decode-failure test, whose
    /// table intentionally contains one row that a typed reader cannot
    /// decode.
    private func freshRowIDs() throws -> [String] {
        let freshPool = try DatabasePool(path: fileURL.path)
        defer { try? freshPool.close() }
        return try freshPool.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM Test ORDER BY id")
        }
    }

    // MARK: - Public typed example: two writes and a read, committed atomically

    /// The public typed example required by issue #284's "Done When": at
    /// least two writes and one read, executed against a real temporary
    /// SQLite database, returning the expected typed result with no GRDB
    /// type anywhere in the call site.
    func testTwoWritesAndAReadExecuteInOrderAndCommitAtomically() throws {
        try createTestTable()

        let (insertedCount, alphaRows) = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            try scope.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()
            let rows = try scope.makeRequest(with: self.selectAllTestRowsQuery()).fetchAll()
            return (rows.count, rows)
        }

        XCTAssertEqual(insertedCount, 2)
        XCTAssertEqual(
            alphaRows.sorted { $0.id < $1.id },
            [TestTable(id: "alpha", value: 1), TestTable(id: "beta", value: 2)]
        )

        // Fresh read boundary after commit.
        XCTAssertEqual(
            try freshRows().sorted { $0.id < $1.id },
            [TestTable(id: "alpha", value: 1), TestTable(id: "beta", value: 2)]
        )
    }

    func testReadWithinTheTransactionObservesAnEarlierWriteInTheSameScope() throws {
        try createTestTable()

        let visibleBeforeCommit = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            return try scope.makeRequest(with: self.selectAllTestRowsQuery()).fetchAll()
        }

        XCTAssertEqual(visibleBeforeCommit, [TestTable(id: "alpha", value: 1)])
        XCTAssertEqual(try freshRows(), [TestTable(id: "alpha", value: 1)])
    }

    // MARK: - Composition with declared queries (issues #18/#26)

    /// A `@SQLQuery`-declared executor dispatches through whatever `self` it
    /// is called on. Calling it on the pinned `scope` runs it against the
    /// same pinned connection as every other operation in the body, so it
    /// observes an earlier write from the same transaction.
    func testDeclaredQueryExecutorCallableFromTheScopeObservesAWriteFromTheSameTransaction() throws {
        try createTestTable()

        let matches = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            return try scope.fetchTransactionScopeRowByID(id: "alpha")
        }

        XCTAssertEqual(matches, [TestTable(id: "alpha", value: 1)])
        XCTAssertEqual(try freshRows(), [TestTable(id: "alpha", value: 1)])
    }

    /// The `@SQLQueries` `execute(_:)`/`Context` pair (`SQLQueriesContainerTests.swift`,
    /// same test target) now runs its closure inside a real transaction too:
    /// `execute(_:)` is sugar over `withTransaction(_:)`. `context.database`
    /// is the pinned scope, so a write made through it and a later declared
    /// read both land on the same connection and commit together.
    func testDeclaredQueriesExecuteEntryPointRunsInARealCommittingTransaction() throws {
        try createTestTable()

        let rows = try database.execute { context -> [TestTable] in
            try context.database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            return try context.database.fetchTransactionScopeRowByID(id: "alpha")
        }

        XCTAssertEqual(rows, [TestTable(id: "alpha", value: 1)])
        XCTAssertEqual(try freshRows(), [TestTable(id: "alpha", value: 1)])
    }

    func testDeclaredQueriesExecuteEntryPointRollsBackOnFailure() throws {
        try createTestTable()

        struct SpecFailure: Error, Equatable {}

        XCTAssertThrowsError(
            try database.execute { context -> Void in
                try context.database.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                throw SpecFailure()
            }
        ) { error in
            XCTAssertEqual(error as? SpecFailure, SpecFailure())
        }

        XCTAssertEqual(try freshRows(), [])
    }

    // MARK: - Edge cases: empty body, single operation, repeated parameters

    func testEmptyBodyCommitsWithoutError() throws {
        try createTestTable()

        let result = try database.withTransaction { _ in
            42
        }

        XCTAssertEqual(result, 42)
        XCTAssertEqual(try freshRows(), [])
    }

    func testSingleOperationBodyCommits() throws {
        try createTestTable()

        try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "solo", value: 7))).execute()
        }

        XCTAssertEqual(try freshRows(), [TestTable(id: "solo", value: 7)])
    }

    /// One prepared read request, invoked twice with different immutable
    /// binding packets in the same scope. Each invocation must bind and
    /// fetch independently — no shared mutable binding state leaks a
    /// parameter value from the first call into the second.
    func testRepeatedParametersAcrossOperationsDoNotShareMutableBindingState() throws {
        try createTestTable()

        let idParameter = XLNamedBindingReference<String>(name: "id")
        let query = sql { schema -> any XLQueryStatement<TestTable> in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == idParameter)
        }

        let (first, second) = try database.withTransaction { scope -> ([TestTable], [TestTable]) in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "first", value: 1))).execute()
            try scope.makeRequest(with: sqlInsert(TestTable(id: "second", value: 2))).execute()

            let request = scope.makeRequest(with: query)
            let slot = try XCTUnwrap(request.parameterLayout.slot(for: .named("id")))

            let firstBindings = try XLInvocationBindings<XLSQLiteValue>(
                layout: request.parameterLayout,
                bindings: [try XLInvocationBinding(slot: slot, value: .text("first"))]
            ).validatingComplete()
            let firstResult = try request.fetchAll(bindings: firstBindings)

            let secondBindings = try XLInvocationBindings<XLSQLiteValue>(
                layout: request.parameterLayout,
                bindings: [try XLInvocationBinding(slot: slot, value: .text("second"))]
            ).validatingComplete()
            let secondResult = try request.fetchAll(bindings: secondBindings)

            return (firstResult, secondResult)
        }

        XCTAssertEqual(first, [TestTable(id: "first", value: 1)])
        XCTAssertEqual(second, [TestTable(id: "second", value: 2)])
    }

    // MARK: - Source ordering: an earlier typed result feeds a later operation

    func testEarlierTypedResultFeedsALaterOperationAndTheReturnValue() throws {
        try createTestTable()
        try database.makeRequest(with: sqlInsert(TestTable(id: "seed-1", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "seed-2", value: 2))).execute()

        let (countBefore, insertedID) = try database.withTransaction { scope -> (Int, String) in
            let existing = try scope.makeRequest(with: self.selectAllTestRowsQuery()).fetchAll()
            let nextID = "seed-\(existing.count + 1)"
            try scope.makeRequest(with: sqlInsert(TestTable(id: nextID, value: existing.count + 1))).execute()
            return (existing.count, nextID)
        }

        XCTAssertEqual(countBefore, 2)
        XCTAssertEqual(insertedID, "seed-3")
        XCTAssertEqual(try freshRows().map(\.id).sorted(), ["seed-1", "seed-2", "seed-3"])
    }

    // MARK: - Failure boundaries: every write in the body rolls back together

    func testMidSequenceConstraintFailureRollsBackEveryEarlierWriteInTheSameTransaction() throws {
        try createConstrainedTestTable()

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                try scope.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()
                // Duplicate primary key: SQLITE_CONSTRAINT.
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 999))).execute()
            }
        ) { error in
            XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT)
        }

        XCTAssertEqual(try freshRows(), [], "alpha and beta must both roll back with the failing statement.")
    }

    func testPreparationFailureRollsBackEarlierWritesAndPreservesTheOriginalError() throws {
        try createTestTable()

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                // `TestNullablesTable` maps to a table that was never
                // created in this database: "no such table" at prepare time.
                _ = try scope.makeRequest(
                    with: sql { schema -> any XLQueryStatement<TestNullablesTable> in
                        let table = schema.table(TestNullablesTable.self)
                        Select(table)
                        From(table)
                    }
                ).fetchAll()
            }
        ) { error in
            XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_ERROR)
        }

        XCTAssertEqual(try freshRows(), [])
    }

    func testBindingFailureRollsBackEarlierWritesAndPreservesTheOriginalError() throws {
        try database.makeRequest(with: sqlCreate(DoubleTest.self)).execute()

        let valueParameter = XLNamedBindingReference<Double>(name: "value")
        let query = sql { schema -> any XLQueryStatement<DoubleTest> in
            let table = schema.table(DoubleTest.self)
            Select(table)
            From(table)
            Where(table.value == valueParameter)
        }

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(DoubleTest(id: "alpha", value: 1.5))).execute()

                let request = scope.makeRequest(with: query)
                let slot = try XCTUnwrap(request.parameterLayout.slot(for: .named("value")))
                let bindings = try XLInvocationBindings<XLSQLiteValue>(
                    layout: request.parameterLayout,
                    bindings: [try XLInvocationBinding(slot: slot, value: .real(.nan))]
                ).validatingComplete()
                _ = try request.fetchAll(bindings: bindings)
            }
        ) { error in
            XCTAssertEqual(
                error as? XLSQLValueEncodingError,
                .realBindingWouldBecomeNull(
                    value: .notANumber,
                    valueType: String(reflecting: Double.self),
                    context: XLValueCodingContext(
                        site: .parameter,
                        path: XLValueCodingPath("value")
                    )
                )
            )
        }

        let freshPool = try DatabasePool(path: fileURL.path)
        defer { try? freshPool.close() }
        let freshDatabase = try GRDBDatabase(
            databasePool: freshPool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
        let remaining = try freshDatabase.makeRequest(
            with: sql { schema -> any XLQueryStatement<DoubleTest> in
                let table = schema.table(DoubleTest.self)
                Select(table)
                From(table)
            }
        ).fetchAll()
        XCTAssertEqual(remaining, [])
    }

    func testDecodeFailureAfterAWriteRollsBackThatWriteAndPreservesTheOriginalError() throws {
        try createTestTable()
        // Seed a row outside the transaction under test whose `value` column
        // holds TEXT instead of the INTEGER `TestTable.value` expects. The
        // default `sqlCreate`-derived schema declares no column type, so
        // SQLite stores this value with its own affinity instead of
        // coercing it, and a typed `TestTable` read of it decode-fails.
        try databasePool.write { db in
            try db.execute(
                sql: "INSERT INTO Test (id, value) VALUES ('corrupt', 'not-a-number')"
            )
        }

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                _ = try scope.makeRequest(with: self.selectAllTestRowsQuery()).fetchAll()
            }
        ) { error in
            XCTAssertTrue(error is XLColumnReadError, "Expected a decode failure, got \(error)")
        }

        // The pre-existing corrupt row is untouched (it was never part of
        // this transaction); the in-transaction insert must not survive.
        XCTAssertEqual(try freshRowIDs(), ["corrupt"])
    }

    func testUserThrownFailureRollsBackEarlierWritesAndPreservesTheOriginalError() throws {
        try createTestTable()

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                throw UserError(reason: "caller decided to abort")
            }
        ) { error in
            XCTAssertEqual(error as? UserError, UserError(reason: "caller decided to abort"))
        }

        XCTAssertEqual(try freshRows(), [])
    }

    // MARK: - Escaped scope

    func testUsingTheScopeAfterTheBodyReturnsThrowsScopeEscaped() throws {
        try createTestTable()

        var escapedScope: GRDBDatabase?
        try database.withTransaction { scope in
            escapedScope = scope
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
        }

        let scope = try XCTUnwrap(escapedScope)
        XCTAssertThrowsError(
            try scope.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }

        // The committed write from inside the body is unaffected; only the
        // escaped use fails.
        XCTAssertEqual(try freshRows(), [TestTable(id: "alpha", value: 1)])
    }

    // MARK: - Live queries are rejected, not crashed, inside a transaction

    func testPublishInsideATransactionFailsPredictablyInsteadOfObservingAnInvalidatedConnection() throws {
        try createTestTable()

        try database.withTransaction { scope in
            let expectation = self.expectation(description: "publish fails")
            var receivedError: Error?
            let cancellable = scope.makeRequest(with: self.selectAllTestRowsQuery())
                .publish()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            receivedError = error
                        }
                        expectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
            self.wait(for: [expectation], timeout: 5)
            cancellable.cancel()
            XCTAssertEqual(
                receivedError as? XLTransactionScopeError,
                .liveQueriesUnsupportedInTransaction
            )
        }
    }

    // MARK: - Nesting and root-executor re-entry are rejected before any pool access

    func testNestedWithTransactionOnTheScopeIsRejectedBeforeTouchingThePool() throws {
        try createTestTable()

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                try scope.withTransaction { _ in }
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }

        XCTAssertEqual(try freshRows(), [], "The outer body's write must roll back too.")
    }

    /// The dangerous case: `body` captures and calls back into the
    /// *original, unpinned* `database` value instead of the `scope` it was
    /// given — for example, by using the database-level convenience executor
    /// sugar the `@SQLQueries` macro generates over `execute`/
    /// `withTransaction`. Without the thread-scoped tracker in
    /// `GRDBDatabase.withTransaction`, this reaches GRDB's own reentrant-write
    /// guard, which is an uncatchable `fatalError` — so this test is the
    /// actual proof that root-executor re-entry is rejected, not merely that
    /// nesting on the scope value is.
    func testRootExecutorReentryThroughTheCapturedDatabaseIsRejectedBeforeTouchingThePool() throws {
        try createTestTable()

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
                // Deliberately re-enters through `self.database`, not `scope`.
                _ = try self.database.fetchTransactionScopeRowByID(id: "alpha")
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }

        XCTAssertEqual(try freshRows(), [], "The outer body's write must roll back too.")
    }

    // MARK: - Cancellation

    func testWithTransactionThrowsCancellationErrorWhenTheTaskIsAlreadyCancelledBeforeStarting() async throws {
        try createTestTable()

        // Captured locally rather than via `self.database` so the `@Sendable` `Task` closure below
        // does not need to capture the non-Sendable test-case instance.
        let database = self.database!
        let task = Task {
            try database.withTransaction { scope in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            }
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected CancellationError")
        }
        catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try freshRows(), [])
    }

    // MARK: - Concurrency: independent transactions and pool isolation

    func testConcurrentIndependentTransactionsBothCommitWithoutCorruptingEachOther() throws {
        try createTestTable()

        // Captured locally so the `@Sendable` dispatch closures below do not need to capture the
        // non-Sendable test-case instance; `firstError`/`secondError` are synchronized by
        // `DispatchGroup.enter()`/`leave()` (each is written by exactly one closure, read only
        // after both have left), which the strict-concurrency checker cannot see.
        let database = self.database!
        let group = DispatchGroup()
        nonisolated(unsafe) var firstError: Error?
        nonisolated(unsafe) var secondError: Error?

        group.enter()
        DispatchQueue.global().async {
            do {
                try database.withTransaction { scope in
                    try scope.makeRequest(with: sqlInsert(TestTable(id: "first", value: 1))).execute()
                }
            }
            catch {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            do {
                try database.withTransaction { scope in
                    try scope.makeRequest(with: sqlInsert(TestTable(id: "second", value: 2))).execute()
                }
            }
            catch {
                secondError = error
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertNil(firstError)
        XCTAssertNil(secondError)
        XCTAssertEqual(try freshRows().map(\.id).sorted(), ["first", "second"])
    }

    /// Instrumented proof of one pinned connection and one transaction
    /// boundary: while a transaction body is paused after an uncommitted
    /// write, a concurrent one-shot read through the ordinary pool-backed
    /// request path must not observe that write. Regular `DatabasePool`
    /// readers only ever see committed state; observing the write here would
    /// mean the "transaction" was not really pinned to one isolated
    /// connection (or had already committed early).
    func testConcurrentPoolReadDuringAnOpenTransactionDoesNotObserveTheUncommittedWrite() throws {
        try createTestTable()

        // Captured locally so the `@Sendable` dispatch closure below does not need to capture the
        // non-Sendable test-case instance; `observedDuringTransaction` is synchronized by the
        // `writeIsVisible`/`readIsDone` semaphores (written once, read only after `readIsDone`
        // signals), which the strict-concurrency checker cannot see.
        let database = self.database!
        nonisolated(unsafe) let selectAllQuery = selectAllTestRowsQuery()
        let writeIsVisible = DispatchSemaphore(value: 0)
        let readIsDone = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var observedDuringTransaction: [TestTable] = []

        let readerQueue = DispatchQueue(label: "transaction-scope-concurrent-reader")
        readerQueue.async {
            writeIsVisible.wait()
            observedDuringTransaction = (try? database.makeRequest(
                with: selectAllQuery
            ).fetchAll()) ?? []
            readIsDone.signal()
        }

        try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            writeIsVisible.signal()
            XCTAssertEqual(readIsDone.wait(timeout: .now() + 10), .success)
        }

        XCTAssertEqual(
            observedDuringTransaction,
            [],
            "A concurrent pool reader must not see an uncommitted write from a pinned transaction."
        )
        XCTAssertEqual(try freshRows(), [TestTable(id: "alpha", value: 1)])
    }
}
