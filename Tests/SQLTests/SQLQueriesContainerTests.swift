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

        func containerTheOnlyRowMatchingID(id: String) -> TestTable {
            sqlResult { schema in
                let table = schema.table(TestTable.self)
                Select(table)
                From(table)
                Where(table.id == id)
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


    // MARK: - Helpers

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
