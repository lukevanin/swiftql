import Foundation
import XCTest

import SwiftQLCore


/// Issue #684: a driver supplies its own change notification through
/// `XLObservingDatabaseDriver`. A driver with no GRDB import observes the
/// entities a statement reads, and code written only against the core
/// contract consumes it.
final class ObservingDriverContractTests: XCTestCase {

    private let driver = CountingDriver()

    func testGenericConsumerReceivesTheInitialValueAndEachTrackedChange() async throws {
        var iterator = observeCount(of: "Tracked", on: driver, fetches: FetchLog()).makeAsyncIterator()

        let initial = try await iterator.next()
        XCTAssertEqual(initial, 0)
        try await driver.insert(into: "Tracked")
        let afterFirstWrite = try await iterator.next()
        XCTAssertEqual(afterFirstWrite, 1)
        try await driver.insert(into: "Tracked")
        let afterSecondWrite = try await iterator.next()
        XCTAssertEqual(afterSecondWrite, 2)
    }

    func testAChangeToAnotherEntityDoesNotRefetch() async throws {
        let fetches = FetchLog()
        var iterator = observeCount(of: "Tracked", on: driver, fetches: fetches).makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial, 0)

        try await driver.insert(into: "Untracked")
        try await driver.insert(into: "Tracked")
        let next = try await iterator.next()

        XCTAssertEqual(next, 1)
        XCTAssertEqual(fetches.count, 2, "Only the initial fetch and the tracked change may fetch.")
    }

    func testConstructingTheStreamDoesNoWork() async throws {
        let fetches = FetchLog()
        let stream = observeCount(of: "Tracked", on: driver, fetches: fetches)

        XCTAssertEqual(fetches.count, 0)
        XCTAssertEqual(driver.observerCount, 0, "Observation begins with iteration.")

        var iterator = stream.makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial, 0)
        XCTAssertEqual(fetches.count, 1)
        XCTAssertEqual(driver.observerCount, 1)
    }

    func testAFetchErrorEndsTheStreamWithThatError() async throws {
        struct FetchFailure: Error, Equatable {}
        let statement = countStatement(of: "Tracked", on: driver)
        var iterator = driver.observe(statement, fetch: { _ -> Int in
            throw FetchFailure()
        }).makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("The fetch error must end the stream.")
        }
        catch {
            XCTAssertEqual(error as? FetchFailure, FetchFailure())
        }
        let afterFailure = try await iterator.next()
        XCTAssertNil(afterFailure)
        XCTAssertEqual(driver.observerCount, 0, "A failed observation stops observing.")
    }

    func testCancellingTheConsumingTaskEndsWithNilAndStopsObserving() async throws {
        let stream = observeCount(of: "Tracked", on: driver, fetches: FetchLog())
        let firstValue = Signal()

        let task = Task { () -> Bool in
            do {
                for try await _ in stream {
                    firstValue.fire()
                }
                return true
            }
            catch {
                return false
            }
        }
        await firstValue.wait()
        task.cancel()
        let endedWithNil = await task.value

        XCTAssertTrue(endedWithNil, "Cancellation ends iteration with nil, never an error.")
        XCTAssertEqual(driver.observerCount, 0, "Cancellation stops the observation.")
    }

    func testAnAlreadyCancelledConsumerStartsNoObservation() async throws {
        let fetches = FetchLog()
        let stream = observeCount(of: "Tracked", on: driver, fetches: fetches)
        let gate = Signal()

        let task = Task { () -> Int? in
            await gate.wait()
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        task.cancel()
        gate.fire()
        let first = try await task.value

        XCTAssertNil(first, "An already-cancelled consumer ends with nil.")
        XCTAssertEqual(fetches.count, 0, "It must not fetch.")
        XCTAssertEqual(driver.observerCount, 0, "It must not register for changes.")
    }

    // MARK: - Helpers

    /// Observes how many rows an entity holds, written only against the
    /// core contract: any observing driver whose dialect speaks SQLite and
    /// whose connections understand `COUNT <entity>` will do.
    private func observeCount<Driver: XLObservingDatabaseDriver>(
        of entity: String,
        on driver: Driver,
        fetches: FetchLog
    ) -> AsyncThrowingStream<Int, Error> where Driver.Dialect == XLSQLiteDialect {
        let statement = countStatement(of: entity, on: driver)
        return driver.observe(statement) { connection in
            fetches.record()
            let prepared = try connection.prepareValidated(statement)
            guard case .integer(let count)? = try connection.fetchOneValidated(prepared)?.first else {
                throw XLDatabaseContractError.decodeFailure(
                    dialect: XLSQLiteDialect.identity,
                    column: 0,
                    message: "expected one integer count"
                )
            }
            return Int(count)
        }
    }

    private func countStatement<Driver: XLDatabaseDriver>(
        of entity: String,
        on driver: Driver
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: "COUNT \(entity)",
            entities: [entity]
        )
    }
}


// MARK: - A driver that observes without GRDB

///
/// An in-memory driver whose database is a row count per entity.
///
/// A write commits through ``CountingStore``, which tells each observation
/// that reads a changed entity to fetch again. That is the whole of this
/// driver's change notification, and it is what `XLObservingDatabaseDriver`
/// asks a driver to supply.
///
private struct CountingDriver: XLObservingDatabaseDriver {

    let driverIdentifier = XLDriverIdentifier(rawValue: "counting-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let defaultTransactionKind = XLTransactionKind.immediate
    private let store = CountingStore()

    /// How many observations are registered for change notification.
    var observerCount: Int {
        store.observerCount
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout CountingConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        var connection = makeConnection()
        return try operation(&connection)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout CountingConnection) throws -> Result
    ) async throws -> Result {
        try await withTransaction(.immediate, operation)
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout CountingConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        var connection = makeConnection()
        let result = try operation(&connection)
        store.commit(connection.inserted)
        return result
    }

    func observe<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        fetch: @escaping @Sendable (inout CountingConnection) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        let observation = CountingObservation(
            store: store,
            entities: statement.entities,
            fetch: { [self] in
                var connection = makeConnection()
                return try fetch(&connection)
            }
        )
        // `unfolding` runs nothing until the first `next()`, so observation
        // begins with iteration.
        return AsyncThrowingStream(unfolding: { try await observation.next() })
    }

    /// Inserts one row into `entity`, through a prepared statement.
    func insert(into entity: String) async throws {
        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: "INSERT \(entity)",
            entities: [entity]
        )
        try await withTransaction { connection in
            let prepared = try connection.prepareValidated(statement)
            try connection.executeValidated(prepared)
        }
    }

    private func makeConnection() -> CountingConnection {
        CountingConnection(
            driverIdentifier: driverIdentifier,
            databaseIdentifier: databaseIdentifier,
            dialect: dialect,
            committed: store.snapshot()
        )
    }
}


/// The committed counts, and the observations to tell when they change.
private final class CountingStore: @unchecked Sendable {

    private let lock = NSLock()

    private var counts: [String: Int] = [:]

    private var observers: [UUID: (entities: Set<String>, changed: AsyncStream<Void>.Continuation)] = [:]

    var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }

    func snapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    /// Applies committed inserts, then tells each observation that reads a
    /// changed entity.
    func commit(_ inserted: [String: Int]) {
        guard !inserted.isEmpty else {
            return
        }
        lock.lock()
        for (entity, rows) in inserted {
            counts[entity, default: 0] += rows
        }
        let changed = Set(inserted.keys)
        let notified = observers.values
            .filter { !$0.entities.isDisjoint(with: changed) }
            .map(\.changed)
        lock.unlock()
        for continuation in notified {
            continuation.yield()
        }
    }

    /// Registers an observation of `entities`. The returned stream yields
    /// once per commit that changes one of them, keeping only the newest
    /// pending change. The registration ends when the stream is cancelled, or
    /// when ``unregister(_:)`` is called with the returned identifier.
    func register(_ entities: Set<String>) -> (identifier: UUID, changes: AsyncStream<Void>) {
        let identifier = UUID()
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            self?.unregister(identifier)
        }
        lock.lock()
        observers[identifier] = (entities, continuation)
        lock.unlock()
        return (identifier, changes)
    }

    func unregister(_ identifier: UUID) {
        lock.lock()
        let removed = observers.removeValue(forKey: identifier)
        lock.unlock()
        removed?.changed.finish()
    }
}


/// One observation: fetch, then fetch again after each change the store
/// reports, until the fetch fails or the consuming task is cancelled.
private final class CountingObservation<Value: Sendable>: @unchecked Sendable {

    private let store: CountingStore

    private let entities: Set<String>

    private let fetch: @Sendable () throws -> Value

    private let lock = NSLock()

    private var changes: AsyncStream<Void>.AsyncIterator?

    private var registration: UUID?

    private var isFinished = false

    init(store: CountingStore, entities: Set<String>, fetch: @escaping @Sendable () throws -> Value) {
        self.store = store
        self.entities = entities
        self.fetch = fetch
    }

    func next() async throws -> Value? {
        // A cancelled consumer ends with `nil` before any work, even on its
        // first call, as `XLObservingDatabaseDriver` requires.
        guard !Task.isCancelled else {
            finish()
            return nil
        }
        guard var iterator = takeChanges() else {
            return nil
        }
        if iterator.isStarting {
            return try fetchOrFinish(keeping: iterator.changes)
        }
        guard await iterator.changes.next() != nil, !Task.isCancelled else {
            finish()
            return nil
        }
        return try fetchOrFinish(keeping: iterator.changes)
    }

    /// The change iterator, registering on the first call. `nil` once the
    /// observation has finished.
    private func takeChanges() -> (changes: AsyncStream<Void>.AsyncIterator, isStarting: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else {
            return nil
        }
        if let changes {
            self.changes = nil
            return (changes, false)
        }
        let (identifier, changes) = store.register(entities)
        registration = identifier
        return (changes.makeAsyncIterator(), true)
    }

    private func fetchOrFinish(keeping changes: AsyncStream<Void>.AsyncIterator) throws -> Value {
        do {
            let value = try fetch()
            lock.lock()
            self.changes = changes
            lock.unlock()
            return value
        }
        catch {
            finish()
            throw error
        }
    }

    private func finish() {
        lock.lock()
        isFinished = true
        changes = nil
        let registration = registration
        self.registration = nil
        lock.unlock()
        if let registration {
            store.unregister(registration)
        }
    }
}


private struct CountingConnection: XLDatabaseDriverConnection, Sendable {

    struct Statement: Sendable {
        let verb: String
        let entity: String
    }

    let driverIdentifier: XLDriverIdentifier
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect: XLSQLiteDialect
    let committed: [String: Int]

    /// Rows this connection inserted, committed when its transaction ends.
    var inserted: [String: Int] = [:]

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> Statement {
        let words = statement.logicalStatement.sql.split(separator: " ").map(String.init)
        guard words.count == 2, words[0] == "COUNT" || words[0] == "INSERT" else {
            throw XLDatabaseContractError.prepareFailure(
                driver: driverIdentifier,
                message: "unknown statement \(statement.logicalStatement.sql)"
            )
        }
        return Statement(verb: words[0], entity: words[1])
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: Statement
    ) throws -> Statement {
        throw XLDatabaseContractError.bindFailure(
            driver: driverIdentifier,
            key: key,
            message: "counting statements take no parameters"
        )
    }

    mutating func fetchAll(_ statement: Statement) throws -> [[XLSQLiteValue]] {
        try fetchOne(statement).map { [$0] } ?? []
    }

    mutating func fetchOne(_ statement: Statement) throws -> [XLSQLiteValue]? {
        let count = committed[statement.entity, default: 0] + inserted[statement.entity, default: 0]
        return [.integer(Int64(count))]
    }

    mutating func execute(_ statement: Statement) throws -> XLExecutionResult {
        inserted[statement.entity, default: 0] += 1
        return XLExecutionResult(rowsAffected: 1, access: .write)
    }
}


/// Counts fetches; locked because a driver may fetch on any thread.
private final class FetchLog: @unchecked Sendable {

    private let lock = NSLock()

    private var fetches = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetches
    }

    func record() {
        lock.lock()
        fetches += 1
        lock.unlock()
    }
}


/// Fires once; awaiting it before or after it fires both resume.
private final class Signal: @unchecked Sendable {

    private let lock = NSLock()

    private var fired = false

    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        fired = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
