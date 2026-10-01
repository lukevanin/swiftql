//
//  ScriptedDriver.swift
//  SwiftQLDriverDatabaseTests
//
//  A driver that implements SwiftQL's driver contract with no GRDB import
//  (issue #682). It runs no SQL: a test scripts the rows a query returns, and
//  the driver records every statement it executes with the values bound to
//  it. A write tells each observation that reads a written entity to fetch
//  again.
//

import Foundation
import SwiftQL


/// What the driver's connections share: the scripted rows, the record of
/// executed statements, and the observations to notify.
final class ScriptedStore: @unchecked Sendable {

    /// One statement a connection ran.
    struct Execution: Equatable {
        let sql: String
        let bindings: [XLBindingKey: XLSQLiteValue]
        let returnsRows: Bool
    }

    private let lock = NSLock()

    private var scriptedRows: [[XLSQLiteValue]] = []

    private var log: [Execution] = []

    private var scopeLog: [String] = []

    private var observers: [UUID: (entities: Set<String>, changed: AsyncStream<Void>.Continuation)] = [:]

    /// The rows every query returns from now on.
    var rows: [[XLSQLiteValue]] {
        get { locked { scriptedRows } }
        set { locked { scriptedRows = newValue } }
    }

    /// Every statement run so far, in order.
    var executions: [Execution] {
        locked { log }
    }

    /// The scope each connection was lent through, in order.
    var scopes: [String] {
        locked { scopeLog }
    }

    func recordScope(_ scope: String) {
        locked { scopeLog.append(scope) }
    }

    func record(_ execution: Execution) {
        locked { log.append(execution) }
    }

    /// Tells every observation that reads one of `entities`.
    func changed(_ entities: Set<String>) {
        let notified = locked {
            observers.values
                .filter { !$0.entities.isDisjoint(with: entities) }
                .map(\.changed)
        }
        for continuation in notified {
            continuation.yield()
        }
    }

    /// Changes to `entities`, one element per write, newest pending only.
    func changes(to entities: Set<String>) -> AsyncStream<Void> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            self?.locked { _ = self?.observers.removeValue(forKey: identifier) }
        }
        locked { observers[identifier] = (entities, continuation) }
        return stream
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}


/// A statement prepared by ``ScriptedConnection``: the SQL, what it reads or
/// writes, and the values bound so far.
struct ScriptedStatement {
    let sql: String
    let entities: Set<String>
    var bindings: [XLBindingKey: XLSQLiteValue] = [:]
}


/// A connection that returns the store's scripted rows for every query.
///
/// It overrides neither `forEachRow(_:_:)` nor `withValuesStepper(_:_:)`, so
/// result sets run on the contract's eager defaults.
struct ScriptedConnection: XLDatabaseDriverConnection {

    typealias Dialect = XLSQLiteDialect

    typealias PhysicalStatement = ScriptedStatement

    let driverIdentifier: XLDriverIdentifier
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect: XLSQLiteDialect
    let store: ScriptedStore

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> ScriptedStatement {
        ScriptedStatement(
            sql: statement.logicalStatement.sql,
            entities: statement.logicalStatement.entities
        )
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: ScriptedStatement
    ) throws -> ScriptedStatement {
        var bound = statement
        bound.bindings[key] = value
        return bound
    }

    mutating func fetchAll(_ statement: ScriptedStatement) throws -> [[XLSQLiteValue]] {
        store.record(.init(sql: statement.sql, bindings: statement.bindings, returnsRows: true))
        return store.rows
    }

    mutating func fetchOne(_ statement: ScriptedStatement) throws -> [XLSQLiteValue]? {
        try fetchAll(statement).first
    }

    mutating func execute(_ statement: ScriptedStatement) throws -> XLExecutionResult {
        store.record(.init(sql: statement.sql, bindings: statement.bindings, returnsRows: false))
        store.changed(statement.entities)
        return XLExecutionResult(rowsAffected: 1, access: .write)
    }
}


/// A blocking, observing driver of the SQLite dialect, built only on
/// SwiftQLCore's protocols.
struct ScriptedDriver: XLBlockingDatabaseDriver, XLObservingDatabaseDriver {

    let driverIdentifier = XLDriverIdentifier(rawValue: "scripted-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let defaultTransactionKind = XLTransactionKind.immediate
    let store = ScriptedStore()

    func withBlockingReadConnection<Result>(
        _ operation: (inout ScriptedConnection) throws -> Result
    ) throws -> Result {
        store.recordScope("blocking read")
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withBlockingWriteConnection<Result>(
        _ operation: (inout ScriptedConnection) throws -> Result
    ) throws -> Result {
        store.recordScope("blocking write")
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withBlockingTransaction<Result>(
        _ operation: (inout ScriptedConnection) throws -> Result
    ) throws -> Result {
        store.recordScope("blocking transaction")
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout ScriptedConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        store.recordScope("read")
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout ScriptedConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        store.recordScope("write")
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout ScriptedConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        store.recordScope("transaction")
        var connection = makeConnection()
        return try operation(&connection)
    }

    /// Fetches now, then after each write to an entity `statement` reads.
    func observe<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        fetch: @escaping @Sendable (inout ScriptedConnection) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        let observation = ScriptedObservation(
            changes: { [store] in store.changes(to: statement.entities) },
            fetch: { [self] in
                var connection = makeConnection()
                return try fetch(&connection)
            }
        )
        return AsyncThrowingStream(unfolding: { try await observation.next() })
    }

    private func makeConnection() -> ScriptedConnection {
        ScriptedConnection(
            driverIdentifier: driverIdentifier,
            databaseIdentifier: databaseIdentifier,
            dialect: dialect,
            store: store
        )
    }
}


/// One observation of the scripted store: registers on its first `next()`,
/// fetches, then fetches again after each change.
private final class ScriptedObservation<Value: Sendable>: @unchecked Sendable {

    private let makeChanges: @Sendable () -> AsyncStream<Void>

    private let fetch: @Sendable () throws -> Value

    private let lock = NSLock()

    private var changes: AsyncStream<Void>.AsyncIterator?

    private var started = false

    init(
        changes: @escaping @Sendable () -> AsyncStream<Void>,
        fetch: @escaping @Sendable () throws -> Value
    ) {
        self.makeChanges = changes
        self.fetch = fetch
    }

    func next() async throws -> Value? {
        guard !Task.isCancelled else {
            return nil
        }
        if claimStart() {
            return try fetch()
        }
        guard var iterator = takeChanges(), await iterator.next() != nil else {
            return nil
        }
        restore(iterator)
        return try fetch()
    }

    private func claimStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !started else {
            return false
        }
        started = true
        changes = makeChanges().makeAsyncIterator()
        return true
    }

    private func takeChanges() -> AsyncStream<Void>.AsyncIterator? {
        lock.lock()
        defer { lock.unlock() }
        let current = changes
        changes = nil
        return current
    }

    private func restore(_ iterator: AsyncStream<Void>.AsyncIterator) {
        lock.lock()
        changes = iterator
        lock.unlock()
    }
}
