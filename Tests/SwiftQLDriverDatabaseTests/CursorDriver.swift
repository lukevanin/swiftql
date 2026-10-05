//
//  CursorDriver.swift
//  SwiftQLDriverDatabaseTests
//
//  Issue #678: a driver whose connection lends its own row handle, read one
//  column at a time, as a native SQLite driver would over `sqlite3_column_*`.
//  It uses SwiftQL's public API only -- this file imports SwiftQL without
//  `@testable` -- so a driver outside SwiftQL can back a streaming result set
//  with no package access. It runs no SQL: a test scripts the rows, and the
//  driver records every step, column read, and eager fetch in order.
//

import Foundation
import SwiftQL


/// The scripted rows and the record of what the cursor did, shared by the
/// driver's connections.
final class CursorLog: @unchecked Sendable {

    private let lock = NSLock()

    private var scriptedRows: [[XLSQLiteValue]] = []

    private var log: [String] = []

    /// The rows every query returns from now on.
    var rows: [[XLSQLiteValue]] {
        get { locked { scriptedRows } }
        set { locked { scriptedRows = newValue } }
    }

    /// Every step, column read, and eager fetch so far, in order: `step 0`
    /// for the first row, `read 0.1` for its second column, and `fetchAll`
    /// for an eager fetch.
    var events: [String] {
        locked { log }
    }

    func record(_ event: String) {
        locked { log.append(event) }
    }

    func reset() {
        locked { log.removeAll() }
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}


/// The row a ``CursorConnection`` is on. It implements only `value(at:)`, and
/// takes the five column reads from SwiftQL's defaults for SQLite values, so
/// every read SwiftQL makes is one recorded `value(at:)` call.
struct CursorRowHandle: XLRowHandle {

    let rowIndex: Int

    let row: [XLSQLiteValue]

    let log: CursorLog

    var columnCount: Int {
        row.count
    }

    func value(at index: Int) throws -> XLSQLiteValue {
        log.record("read \(rowIndex).\(index)")
        guard row.indices.contains(index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: nil,
                failure: .indexOutOfBounds(valueCount: row.count)
            )
        }
        return row[index]
    }
}


/// A connection that steps the scripted rows one at a time and lends each as
/// a ``CursorRowHandle``. Its value-level members are the contract's eager
/// defaults, over a `fetchAll(_:)` that records itself.
struct CursorConnection: XLDatabaseDriverConnection {

    typealias Dialect = XLSQLiteDialect

    typealias PhysicalStatement = String

    typealias RowHandle = CursorRowHandle

    let driverIdentifier: XLDriverIdentifier
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect: XLSQLiteDialect
    let log: CursorLog

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> String {
        statement.logicalStatement.sql
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: String
    ) throws -> String {
        statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        log.record("fetchAll")
        return log.rows
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        try fetchAll(statement).first
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .write)
    }

    mutating func forEachRowHandle(
        _ statement: String,
        _ body: (CursorRowHandle) throws -> XLRowStreamControl
    ) throws {
        for (index, row) in log.rows.enumerated() {
            log.record("step \(index)")
            if try body(CursorRowHandle(rowIndex: index, row: row, log: log)) == .stop {
                return
            }
        }
    }

    mutating func withRowHandleStepper<Result>(
        _ statement: String,
        _ body: (@escaping () throws -> CursorRowHandle?) throws -> Result
    ) throws -> Result {
        let rows = log.rows
        let log = log
        var nextIndex = 0
        return try body {
            guard nextIndex < rows.count else {
                return nil
            }
            let index = nextIndex
            nextIndex += 1
            log.record("step \(index)")
            return CursorRowHandle(rowIndex: index, row: rows[index], log: log)
        }
    }
}


/// A blocking, observing driver over ``CursorConnection``. It observes by
/// fetching once, which is all these tests need.
struct CursorDriver: XLBlockingDatabaseDriver, XLObservingDatabaseDriver {

    let driverIdentifier = XLDriverIdentifier(rawValue: "cursor-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let defaultTransactionKind = XLTransactionKind.immediate
    let log = CursorLog()

    func withBlockingReadConnection<Result>(
        _ operation: (inout CursorConnection) throws -> Result
    ) throws -> Result {
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withBlockingWriteConnection<Result>(
        _ operation: (inout CursorConnection) throws -> Result
    ) throws -> Result {
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withBlockingTransaction<Result>(
        _ operation: (inout CursorConnection) throws -> Result
    ) throws -> Result {
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout CursorConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout CursorConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout CursorConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        var connection = makeConnection()
        return try operation(&connection)
    }

    func observe<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        fetch: @escaping @Sendable (inout CursorConnection) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        var connection = makeConnection()
        let result = Result { try fetch(&connection) }
        return AsyncThrowingStream { continuation in
            continuation.yield(with: result)
            continuation.finish()
        }
    }

    private func makeConnection() -> CursorConnection {
        CursorConnection(
            driverIdentifier: driverIdentifier,
            databaseIdentifier: databaseIdentifier,
            dialect: dialect,
            log: log
        )
    }
}
