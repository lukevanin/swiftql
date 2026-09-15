//
//  SQLQueriesContainerTests.swift
//  SwiftQL
//
//  Runtime tests for the `@SQLQueries` member macro (issues #18/#26,
//  container encoding): the macro attaches to a database extension on the
//  v1.x toolchain floor, reads the specifications from the nested
//  (fileprivate) `Query` container, and generates working executors —
//  connection-scoped on `Context` and one-shot on the database. Ported from
//  the milestone #28 spike on `experiment/sqlquery-peer-macro`, extended with
//  `.exactlyOne` cardinality coverage added for v1.5.1.
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


/// Counts how many times a declared query's statement is built (issue #660).
///
/// `sql { }` runs its builder closure immediately, and the render-once cache
/// calls the statement builder only when it renders, so a probe inside the
/// specification body counts renders without any internal hook.
final class DeclaredQueryRenderProbe: @unchecked Sendable {

    static let containerObservedRows = DeclaredQueryRenderProbe()

    static let peerObservedRows = DeclaredQueryRenderProbe()

    private let lock = NSLock()

    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func record() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}


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

        func containerTheOnlyRowMatchingID(id: String) -> TestTable {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id == id)
            }
        }

        // Issue #661: the container inlines the rewritten statement where the
        // parameter values are in scope, so this pins that `like`, `regexp`,
        // and `Limit` arguments bind rather than capture.
        func containerRowsMatching(pattern: String, expression: String, count: Int) -> [TestTable] {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id.like(pattern) && table.id.regexp(expression))
                OrderBy(table.value.ascending())
                Limit(count)
            }
        }

        // Issue #661: a parameter reached through a local binding and through
        // a nested closure (`Limit`'s builder closure) is still rewritten, so
        // each call binds its own values rather than capturing the first.
        func containerRowsThroughAliasAndClosure(pattern: String, count: Int) -> [TestTable] {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                let alias = pattern
                Select(table)
                From(table)
                Where(table.id.like(alias))
                OrderBy(table.value.ascending())
                Limit { count }
            }
        }

        // Issue #660: observed through `prepared`. The probe counts statement
        // builds, so a test can prove that the executor and the prepared form
        // share one render.
        func containerObservedRows(pattern: String) -> [TestTable] {
            sqlResult { schema in
                let _ = DeclaredQueryRenderProbe.containerObservedRows.record()
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id.like(pattern))
                OrderBy(table.value.ascending())
            }
        }
    }
}


/// Captures logged SQL text so a test can inspect what was actually rendered
/// and executed, without any internal render-count hook.
private final class RecordingLogger: XLLogger {
    private let lock = NSLock()
    private var messages: [String] = []

    func log(level: XLLogLevel, message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    var allMessages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
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
        try? databasePool?.close()
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

    func testDatabaseExecutorFetchesExactlyOneRow() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))

        XCTAssertEqual(
            try database.containerTheOnlyRowMatchingID(id: "alpha"),
            TestTable(id: "alpha", value: 1)
        )
        XCTAssertThrowsError(try database.containerTheOnlyRowMatchingID(id: "gamma")) { error in
            XCTAssertEqual(
                error as? XLQueryCardinalityError,
                .noRowsMatched
            )
        }
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


    // MARK: - Render-once caching

    ///
    /// The container form's `Context` executor is prepared through its own
    /// `XLRenderOnceCache` (Copilot review, PR #386) the same way the
    /// `@SQLQuery` peer macro's executor is, rather than re-rendering SQL on
    /// every call. Proven the same way `SQLQueryRenderOnceCacheTests` proves
    /// it for the peer form: the executed SQL text is byte-identical across
    /// calls with different argument values and carries a named placeholder,
    /// never an inlined literal -- a re-rendering-per-call implementation
    /// would inline each call's `id` value into the SQL text instead.
    ///
    func testContextExecutorRendersOnceAcrossCallsWithDifferentArguments() throws {
        let logger = RecordingLogger()
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let loggingDatabase = try GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: logger)
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        _ = try loggingDatabase.containerRowsMatchingID(id: "alpha")
        _ = try loggingDatabase.containerRowsMatchingID(id: "beta")
        _ = try loggingDatabase.containerRowsMatchingID(id: "alpha")

        let fetchLogs = logger.allMessages.filter { $0.contains("fetchAll:") }
        XCTAssertEqual(fetchLogs.count, 3, "expected one log line per call")
        let renderedSQLTexts = Set(
            fetchLogs.compactMap { message -> String? in
                guard let start = message.range(of: "<<<"), let end = message.range(of: ">>>") else {
                    return nil
                }
                return String(message[start.upperBound..<end.lowerBound])
            }
        )
        XCTAssertEqual(renderedSQLTexts.count, 1, "every call must reuse the same rendered SQL text")
        let renderedSQL = try XCTUnwrap(renderedSQLTexts.first)
        XCTAssertTrue(renderedSQL.contains(":id"), "the reused SQL must bind a placeholder")
        XCTAssertFalse(renderedSQL.contains("'alpha'"), "no call's argument may be inlined as a literal")
        XCTAssertFalse(renderedSQL.contains("'beta'"), "no call's argument may be inlined as a literal")
    }

    func testContainerExecutorBindsLikeRegexpAndLimitParameters() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpine", value: 2))
        try insert(TestTable(id: "alps", value: 3))
        try insert(TestTable(id: "beta", value: 4))

        XCTAssertEqual(
            try database.containerRowsMatching(pattern: "al%", expression: "p", count: 10).map(\.id),
            ["alpha", "alpine", "alps"]
        )
        XCTAssertEqual(
            try database.containerRowsMatching(pattern: "al%", expression: "e$", count: 10).map(\.id),
            ["alpine"]
        )
        XCTAssertEqual(
            try database.containerRowsMatching(pattern: "%", expression: "a", count: 2).map(\.id),
            ["alpha", "alpine"]
        )
    }

    func testContainerExecutorBindsParametersThroughLocalBindingAndNestedClosure() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpine", value: 2))
        try insert(TestTable(id: "beta", value: 3))

        XCTAssertEqual(
            try database.containerRowsThroughAliasAndClosure(pattern: "al%", count: 10).map(\.id),
            ["alpha", "alpine"]
        )
        // A different value through the local binding changes the rows.
        XCTAssertEqual(
            try database.containerRowsThroughAliasAndClosure(pattern: "b%", count: 10).map(\.id),
            ["beta"]
        )
        // A different value through the nested closure changes the row count.
        XCTAssertEqual(
            try database.containerRowsThroughAliasAndClosure(pattern: "al%", count: 1).map(\.id),
            ["alpha"]
        )
    }


    // MARK: - Observation (issue #660)

    ///
    /// The prepared form and the executor emit the same preparation code, so
    /// they must share one render and one packet. The probe proves one render
    /// across both forms, the logged fetch lines prove the same SQL text and
    /// the same bound values, and the packet equals the one built by hand.
    ///
    func testPreparedQueryUsesTheExecutorsCachedRequestAndBindings() throws {
        let logger = RecordingLogger()
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let loggingDatabase = try GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: logger)
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpine", value: 2))
        try insert(TestTable(id: "beta", value: 3))

        let rendersBefore = DeclaredQueryRenderProbe.containerObservedRows.count
        let called = try loggingDatabase.containerObservedRows(pattern: "al%")
        let prepared = try loggingDatabase.prepared.containerObservedRows(pattern: "al%")
        let preparedAgain = try loggingDatabase.prepared.containerObservedRows(pattern: "al%")
        XCTAssertEqual(
            DeclaredQueryRenderProbe.containerObservedRows.count - rendersBefore,
            1,
            "the executor and the prepared form must share one render"
        )

        XCTAssertEqual(called.map(\.id), ["alpha", "alpine"])
        XCTAssertEqual(try prepared.request.fetchAll(bindings: prepared.bindings), called)

        let layout = prepared.request.parameterLayout
        let slot = try XCTUnwrap(layout.slot(for: .named("pattern")))
        let expectedBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .text("al%"))]
        ).validatingComplete()
        XCTAssertEqual(prepared.bindings, expectedBindings)
        XCTAssertEqual(preparedAgain.bindings, expectedBindings)

        let fetchLogs = logger.allMessages.filter { $0.contains("fetchAll:") }
        XCTAssertEqual(fetchLogs.count, 2, "expected one log line for the executor and one for the prepared fetch")
        XCTAssertEqual(
            Set(fetchLogs).count,
            1,
            "the executor and the prepared form must fetch the same SQL text with the same bindings"
        )
        let fetchLog = try XCTUnwrap(fetchLogs.first)
        XCTAssertTrue(fetchLog.contains(":pattern"), "the shared SQL must bind a placeholder")
        XCTAssertFalse(fetchLog.contains("LIKE 'al%'"), "no argument may be inlined as a literal")
    }

    func testPreparedQueryStreamEmitsUpdatedRowsAfterAWrite() async throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        let query = try database.prepared.containerObservedRows(pattern: "al%")
        let initialRows = [TestTable(id: "alpha", value: 1)]
        let updatedRows = [TestTable(id: "alpha", value: 1), TestTable(id: "alpine", value: 3)]

        var snapshots = 0
        for try await rows in query.stream() {
            snapshots += 1
            if snapshots == 1 {
                XCTAssertEqual(rows, initialRows)
                // Neither write matches the pattern except `alpine`, so the
                // observation must deliver it and never `beta` or `gamma`.
                try insert(TestTable(id: "gamma", value: 4))
                try insert(TestTable(id: "alpine", value: 3))
                continue
            }
            XCTAssertTrue(
                rows == initialRows || rows == updatedRows,
                "the packet must keep selecting the pattern 'al%', got \(rows)"
            )
            if rows == updatedRows {
                break
            }
        }
        XCTAssertGreaterThan(snapshots, 1, "the observation must deliver the write")
    }

    func testPreparedQueryPublisherEmitsUpdatedRowsAfterAWrite() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))

        let query = try database.prepared.containerObservedRows(pattern: "al%")
        let initialExpectation = expectation(description: "initial snapshot")
        let updateExpectation = expectation(description: "snapshot after the write")
        var sawInitial = false
        var sawUpdate = false
        var cancellables = Set<AnyCancellable>()

        query.publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    if !sawInitial {
                        sawInitial = true
                        XCTAssertEqual(rows, [TestTable(id: "alpha", value: 1)])
                        initialExpectation.fulfill()
                    }
                    else if rows.map(\.id) == ["alpha", "alpine"] && !sawUpdate {
                        sawUpdate = true
                        updateExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try insert(TestTable(id: "alpine", value: 2))
        wait(for: [updateExpectation], timeout: 2)
        cancellables.removeAll()
    }


    // MARK: - Helpers

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
