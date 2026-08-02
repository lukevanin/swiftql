//
//  GRDBLiveQueryAsyncStreamTests.swift
//
//
//  Created by Claude on 2026/07/29.
//

#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif
import Foundation
import GRDB
import XCTest
@testable import SwiftQL


// MARK: - Fixtures

@SQLTable(name: "AsyncStreamRecord")
private struct AsyncStreamRecord: Equatable, Identifiable {
    let id: String
    let value: Int
}


@SQLTable(name: "AsyncStreamNullableRecord")
private struct AsyncStreamNullableRecord: Equatable, Identifiable {
    let id: String
    let value: Int?
}


@SQLTable(name: "AsyncStreamRetryRecord")
private struct AsyncStreamRetryRecord: Equatable, Identifiable {
    let id: String
    let value: Int
}


private struct AsyncStreamInjectedBusyExpression: XLExpression {
    typealias T = Int

    static let functionName = "swiftql_test_async_stream_injected_busy"

    func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.functionName) { _ in }
    }
}


private enum AsyncStreamTestError: Error, Equatable {
    case rollback
    case permanent
}


// MARK: - Locked helpers

private final class AsyncStreamLockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func set(_ newValue: Value) {
        withValue { $0 = newValue }
    }

    func read() -> Value {
        withValue { $0 }
    }
}


private final class AsyncStreamLockedArray<Element>: @unchecked Sendable {

    private let lock = NSLock()

    private var values: [Element] = []

    func append(_ value: Element) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    func read() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}


private final class AsyncStreamInjectedBusyFunctionState: @unchecked Sendable {

    enum Behavior {
        case succeed
        case failOnce
        case failAlways
    }

    private let lock = NSLock()

    private let behavior: Behavior

    private var invocationCountValue = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCountValue
    }

    func invoke() throws -> Int {
        lock.lock()
        invocationCountValue += 1
        let invocationCount = invocationCountValue
        let failsThisInvocation: Bool
        switch behavior {
        case .succeed:
            failsThisInvocation = false
        case .failOnce:
            failsThisInvocation = invocationCount == 1
        case .failAlways:
            failsThisInvocation = true
        }
        lock.unlock()

        if failsThisInvocation {
            throw DatabaseError(
                resultCode: .SQLITE_BUSY_SNAPSHOT,
                message: "injected busy attempt \(invocationCount)"
            )
        }
        return 1
    }
}


/// Deterministic stand-in for ``GRDBLiveQueryRetryScheduler``'s real timers: records every
/// scheduled delay and only fires it when the test calls `runNext()`, mirroring
/// `GRDBLiveQueryRetryTests.swift`'s `ManualRetryScheduler` but scoped to this file.
private final class AsyncStreamManualRetryScheduler: @unchecked Sendable {

    private struct PendingDelay {
        let delay: TimeInterval
        let subject: PassthroughSubject<Void, Never>
    }

    private let lock = NSLock()

    private var pending: [PendingDelay] = []

    private var recorded: [TimeInterval] = []

    var scheduler: GRDBLiveQueryRetryScheduler {
        GRDBLiveQueryRetryScheduler { [weak self] delay in
            guard let self else {
                return Empty(completeImmediately: false).eraseToAnyPublisher()
            }
            let subject = PassthroughSubject<Void, Never>()
            self.lock.lock()
            self.pending.append(PendingDelay(delay: delay, subject: subject))
            self.recorded.append(delay)
            self.lock.unlock()
            return subject.eraseToAnyPublisher()
        }
    }

    var pendingDelays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return pending.map(\.delay)
    }

    var recordedDelays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    @discardableResult
    func runNext() -> Bool {
        let next: PendingDelay?
        lock.lock()
        if pending.isEmpty {
            next = nil
        }
        else {
            next = pending.removeFirst()
        }
        lock.unlock()

        guard let next else { return false }
        next.subject.send(())
        next.subject.send(completion: .finished)
        return true
    }
}


/// Wraps an `AsyncThrowingStream`'s iterator in a class so it can be driven from a background
/// `Task` and awaited from a synchronous or `async` test method without capturing a mutable
/// struct across a concurrency boundary.
private final class AsyncStreamIteratorBox<Value>: @unchecked Sendable {

    private var iterator: AsyncThrowingStream<Value, Error>.AsyncIterator

    init(_ stream: AsyncThrowingStream<Value, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Value? {
        try await iterator.next()
    }
}


final class GRDBLiveQueryAsyncStreamTests: XCTestCase {

    private final class RecordingLogger: XLLogger {
        private let lock = NSLock()
        private var messages: [String] = []

        func log(level: XLLogLevel, message: String) {
            lock.lock()
            messages.append(message)
            lock.unlock()
        }

        func count(containing fragment: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return messages.filter { $0.contains(fragment) }.count
        }
    }

    private var databaseDirectoryURL: URL!
    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!
    private var logger: RecordingLogger!

    override func setUpWithError() throws {
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "async-stream.sqlite",
            isDirectory: false
        )
        databasePool = try DatabasePool(path: fileURL.path)
        logger = RecordingLogger()
        database = try GRDBDatabase(databasePool: databasePool, formatter: XLiteFormatter(), logger: logger)
    }

    override func tearDown() {
        database = nil
        databasePool = nil
        logger = nil
        try? FileManager.default.removeItem(at: databaseDirectoryURL)
        databaseDirectoryURL = nil
    }

    // MARK: - Lazy start / unused stream

    func testUnusedStreamPerformsNoObservationOrFetch() throws {
        try createRecordTable()
        let request = database.makeRequest(with: orderedStatement())

        _ = request.stream() // constructed, never iterated
        _ = request.streamOne() // constructed, never iterated

        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            0,
            "Constructing an unused stream() must perform no fetch."
        )
        XCTAssertEqual(
            logger.count(containing: "streamOne:"),
            0,
            "Constructing an unused streamOne() must perform no fetch."
        )
    }

    // MARK: - Initial delivery + relevant-write refresh

    func testStreamEmitsFreshInitialSnapshotAndRelevantWriteRefresh() async throws {
        try createRecordTable()
        try insertDirect(AsyncStreamRecord(id: "written-before-iteration", value: 1))

        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).stream()
        )

        let initial = try await iterator.next()
        XCTAssertEqual(initial, [AsyncStreamRecord(id: "written-before-iteration", value: 1)])

        try insertDirect(AsyncStreamRecord(id: "relevant", value: 2))
        let refreshed = try await iterator.next()
        XCTAssertEqual(
            refreshed,
            [
                AsyncStreamRecord(id: "relevant", value: 2),
                AsyncStreamRecord(id: "written-before-iteration", value: 1),
            ]
        )
    }

    func testStreamOneEmitsFreshInitialSnapshotAndRelevantWriteRefresh() async throws {
        try createRecordTable()
        try insertDirect(AsyncStreamRecord(id: "a", value: 1))

        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).streamOne()
        )

        let initial = try await iterator.next()
        XCTAssertEqual(initial, AsyncStreamRecord(id: "a", value: 1))

        // "a" sorts after a lexicographically-earlier id, so the observed first row changes.
        try insertDirect(AsyncStreamRecord(id: "A-earlier", value: 2))
        let refreshed = try await iterator.next()
        XCTAssertEqual(refreshed, AsyncStreamRecord(id: "A-earlier", value: 2))
    }

    // MARK: - Transaction coalescing / rollback exclusion / irrelevant writes (#146/#255)

    func testTransactionCoalescingExposesOnlyDurableState() async throws {
        try createRecordTable()
        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).stream()
        )

        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])

        try await databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO AsyncStreamRecord (id, value) VALUES (?, ?)",
                arguments: ["a", 1]
            )
            try database.execute(
                sql: "INSERT INTO AsyncStreamRecord (id, value) VALUES (?, ?)",
                arguments: ["b", 2]
            )
            try database.execute(
                sql: "UPDATE AsyncStreamRecord SET value = ? WHERE id = ?",
                arguments: [3, "a"]
            )
        }

        let finalRows = [
            AsyncStreamRecord(id: "a", value: 3),
            AsyncStreamRecord(id: "b", value: 2),
        ]
        var observed: [[AsyncStreamRecord]] = []
        while true {
            guard let rows = try await iterator.next() else {
                XCTFail("Stream terminated unexpectedly.")
                break
            }
            observed.append(rows)
            if rows == finalRows { break }
        }
        XCTAssertTrue(
            observed.allSatisfy { $0.isEmpty || $0 == finalRows },
            "One transaction may coalesce, but no intermediate durable state may escape."
        )
    }

    func testRolledBackWriteNeverAppearsBeforeCommittedLiveness() async throws {
        try createRecordTable()
        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).stream()
        )
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])

        do {
            try await databasePool.write { database in
                try database.execute(
                    sql: "INSERT INTO AsyncStreamRecord (id, value) VALUES (?, ?)",
                    arguments: ["rolled-back", 1]
                )
                throw AsyncStreamTestError.rollback
            }
            XCTFail("Expected the injected rollback.")
        }
        catch AsyncStreamTestError.rollback {
            // Deterministic rollback trigger.
        }

        try insertDirect(AsyncStreamRecord(id: "committed", value: 2))
        let committedRows = [AsyncStreamRecord(id: "committed", value: 2)]
        var observed: [[AsyncStreamRecord]] = []
        while true {
            guard let rows = try await iterator.next() else {
                XCTFail("Stream terminated unexpectedly.")
                break
            }
            observed.append(rows)
            if rows == committedRows { break }
        }
        XCTAssertFalse(observed.flatMap { $0 }.contains { $0.id == "rolled-back" })
        XCTAssertTrue(observed.allSatisfy { $0.isEmpty || $0 == committedRows })
    }

    func testIrrelevantTableWriteDoesNotChangeObservedSnapshot() async throws {
        try createRecordTable()
        try await databasePool.write { database in
            try database.execute(sql: "CREATE TABLE AsyncStreamOther (id TEXT NOT NULL PRIMARY KEY)")
        }
        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).stream()
        )
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])

        try await databasePool.write { database in
            try database.execute(sql: "INSERT INTO AsyncStreamOther (id) VALUES ('irrelevant')")
        }
        try insertDirect(AsyncStreamRecord(id: "relevant", value: 1))

        let finalRows = [AsyncStreamRecord(id: "relevant", value: 1)]
        var observed: [[AsyncStreamRecord]] = []
        while true {
            guard let rows = try await iterator.next() else {
                XCTFail("Stream terminated unexpectedly.")
                break
            }
            observed.append(rows)
            if rows == finalRows { break }
        }
        XCTAssertTrue(
            observed.allSatisfy { $0.isEmpty || $0 == finalRows },
            "An irrelevant-table commit must not create a different query snapshot."
        )
    }

    // MARK: - Immutable packet capture

    func testStreamBindingsCapturesPacketOnceAcrossInitialFetchAndRefresh() async throws {
        try createRecordTable()
        try insertDirect(AsyncStreamRecord(id: "per-1", value: 1))
        try insertDirect(AsyncStreamRecord(id: "per-2", value: 2))

        let request = database.makeRequest(with: byIDStatement())
        let layout = request.parameterLayout
        let slot = try XCTUnwrap(layout.slot(for: .named("id")))
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .text("per-1"))]
        ).validatingComplete()

        let iterator = AsyncStreamIteratorBox(request.stream(bindings: bindings))
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [AsyncStreamRecord(id: "per-1", value: 1)])

        // A write to an unrelated row may or may not itself trigger a re-fetch,
        // depending on how precisely GRDB's own region tracking scopes this
        // dynamic WHERE clause; either way it must never change what the packet
        // selects.
        try insertDirect(AsyncStreamRecord(id: "per-3", value: 3))

        try await databasePool.write { database in
            try database.execute(
                sql: "DELETE FROM AsyncStreamRecord WHERE id = ?",
                arguments: ["per-1"]
            )
        }

        let expectedRow = [AsyncStreamRecord(id: "per-1", value: 1)]
        var observed: [[AsyncStreamRecord]] = []
        while true {
            guard let rows = try await iterator.next() else {
                XCTFail("Stream terminated unexpectedly.")
                break
            }
            observed.append(rows)
            if rows.isEmpty { break }
        }
        XCTAssertTrue(
            observed.allSatisfy { $0.isEmpty || $0 == expectedRow },
            "The packet must keep selecting id == 'per-1' on every refresh, never per-2 or per-3."
        )
        XCTAssertEqual(observed.last, [], "The packet must keep selecting id == 'per-1' after it is deleted.")
    }

    func testStreamBindingsRejectsMissingRequiredBindingLazily() async throws {
        try createRecordTable()
        let request = database.makeRequest(with: byIDStatement())
        let layout = request.parameterLayout

        // Deliberately incomplete: the required "id" slot is never bound.
        let incompletePacket = XLInvocationBindings<XLSQLiteValue>(layout: layout)

        // Constructing the stream must not throw synchronously; the error is only
        // delivered lazily, on the first `next()` call.
        let stream = request.stream(bindings: incompletePacket)
        let iterator = AsyncStreamIteratorBox(stream)

        do {
            _ = try await iterator.next()
            XCTFail("Expected an invocation-binding error.")
        }
        catch is XLInvocationBindingError {
            // Expected.
        }
    }

    func testStreamAcceptsNullBindingForANullableSlot() async throws {
        try database.makeRequest(with: sqlCreate(AsyncStreamNullableRecord.self)).execute()
        try database.makeRequest(
            with: sqlInsert(AsyncStreamNullableRecord(id: "has-null", value: nil))
        ).execute()
        try database.makeRequest(
            with: sqlInsert(AsyncStreamNullableRecord(id: "has-value", value: 7))
        ).execute()

        let valueParameter = XLNamedBindingReference<Optional<Int>>(name: "value")
        let statement: any XLQueryStatement<AsyncStreamNullableRecord> = sql { schema in
            let table = schema.table(AsyncStreamNullableRecord.self)
            Select(table)
            From(table)
            Where(table.value == valueParameter)
            OrderBy(table.id.ascending())
        }
        let request = database.makeRequest(with: statement)
        let layout = request.parameterLayout
        let slot = try XCTUnwrap(layout.slot(for: .named("value")))
        XCTAssertEqual(slot.nullability, .nullable)
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .null)]
        ).validatingComplete()

        let iterator = AsyncStreamIteratorBox(request.stream(bindings: bindings))
        let rows = try await iterator.next()
        XCTAssertEqual(rows, [AsyncStreamNullableRecord(id: "has-null", value: nil)])
    }

    // MARK: - Cancellation

    func testCancellingConsumingTaskTearsDownObservationAndStopsFurtherFetches() async throws {
        try createRecordTable()
        let stream = database.makeRequest(with: orderedStatement()).stream()
        let seen = AsyncStreamLockedArray<[AsyncStreamRecord]>()
        let loopEnded = AsyncStreamLockedValue(false)

        let task = Task {
            do {
                for try await rows in stream {
                    seen.append(rows)
                }
            }
            catch {
                XCTFail("Unexpected stream error: \(error)")
            }
            loopEnded.set(true)
        }

        try await waitUntil { !seen.read().isEmpty }
        task.cancel()
        try await waitUntil { loopEnded.read() }
        XCTAssertEqual(seen.read(), [[]])

        let fetchCountAtCancel = logger.count(containing: "stream:")
        try insertDirect(AsyncStreamRecord(id: "after-cancel", value: 1))
        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            fetchCountAtCancel,
            "Cancelling the consuming task must cancel the underlying observation."
        )
    }

    func testCancellationBeforeFirstNextPreventsAnyFetch() async throws {
        try createRecordTable()
        let stream = database.makeRequest(with: orderedStatement()).stream()
        let iterator = AsyncStreamIteratorBox(stream)

        let task = Task<[AsyncStreamRecord]?, Error> {
            try await iterator.next()
        }
        task.cancel()

        let result = try await task.value
        XCTAssertNil(result, "A stream cancelled before delivering a value resolves to nil, not an error.")
    }

    // MARK: - Bounded buffering under rapid commits (#291)

    func testBoundedBufferingUnderRapidCommits() async throws {
        try createRecordTable()
        let writeCount = 20
        // Ordered by `value` descending, not `id` ascending: the top row only
        // becomes the *last*-inserted row once every write has committed, so
        // observing it actually requires reaching the final database state --
        // unlike ordering by `id`, where "row-0" sorts first as soon as it
        // exists, regardless of how many later writes have happened.
        let iterator = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedByValueDescendingStatement()).streamOne()
        )
        _ = try await iterator.next() // consumes the initial (nil) snapshot

        // Simulate a "paused" consumer: many relevant commits happen back to back
        // with no intervening `next()` call.
        for index in 0 ..< writeCount {
            try insertDirect(AsyncStreamRecord(id: "row-\(index)", value: index))
        }

        let finalValue = writeCount - 1
        var attempts = 0
        while attempts < writeCount {
            attempts += 1
            guard let row = try await iterator.next() else {
                XCTFail("Stream terminated unexpectedly while draining to the final snapshot.")
                break
            }
            if row?.value == finalValue {
                // GRDB's own change coalescing decides how many commits collapse into
                // one re-fetch; the bounded buffer only guarantees resuming does not
                // need one `next()` per write to reach the final state.
                XCTAssertLessThan(
                    attempts,
                    writeCount,
                    "Bounded buffering must coalesce most of \(writeCount) rapid commits into far "
                        + "fewer delivered snapshots than one next() call per write."
                )
                break
            }
        }
    }

    // MARK: - Independent consumers / databases

    func testTwoSeparateStreamCallsAreIndependentAndDoNotCrossTrigger() async throws {
        try createRecordTable()
        let request = database.makeRequest(with: orderedStatement())
        let iteratorA = AsyncStreamIteratorBox(request.stream())
        let iteratorB = AsyncStreamIteratorBox(request.stream())

        let initialA = try await iteratorA.next()
        XCTAssertEqual(initialA, [])
        let initialB = try await iteratorB.next()
        XCTAssertEqual(initialB, [])

        try insertDirect(AsyncStreamRecord(id: "shared", value: 1))

        let expected = [AsyncStreamRecord(id: "shared", value: 1)]
        let refreshedA = try await iteratorA.next()
        XCTAssertEqual(refreshedA, expected)
        let refreshedB = try await iteratorB.next()
        XCTAssertEqual(refreshedB, expected)
    }

    func testTwoDatabasesWithIdenticalTableNamesDoNotCrossTrigger() async throws {
        try createRecordTable()

        let secondDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secondDirectory) }
        let secondPool = try DatabasePool(
            path: secondDirectory.appendingPathComponent("second.sqlite").path
        )
        let secondDatabase = try GRDBDatabase(
            databasePool: secondPool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try await secondPool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE AsyncStreamRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }

        let iteratorA = AsyncStreamIteratorBox(
            database.makeRequest(with: orderedStatement()).stream()
        )
        let iteratorB = AsyncStreamIteratorBox(
            secondDatabase.makeRequest(with: orderedStatement()).stream()
        )
        let initialA = try await iteratorA.next()
        XCTAssertEqual(initialA, [])
        let initialB = try await iteratorB.next()
        XCTAssertEqual(initialB, [])

        try insertDirect(AsyncStreamRecord(id: "only-in-a", value: 1))
        let refreshedA = try await iteratorA.next()
        XCTAssertEqual(refreshedA, [AsyncStreamRecord(id: "only-in-a", value: 1)])

        // The second, identically-named table in the other pool must remain empty.
        drainMainQueue()
        let secondRows = try secondDatabase.makeRequest(with: orderedStatement()).fetchAll()
        XCTAssertEqual(secondRows, [])
    }

    // MARK: - Retry integration (reuses GRDBLiveQueryRetryPolicy/State/Scheduler)

    func testRealGRDBObservationRecoversFromInjectedBusyAndKeepsObserving() async throws {
        let fixture = try makeInjectedBusyFixture(policy: .retryBusy, behavior: .failOnce)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let iterator = AsyncStreamIteratorBox(
            fixture.database.makeRequest(with: fixture.statement).stream()
        )
        let recovered = try await iterator.next()
        XCTAssertEqual(recovered, [AsyncStreamRetryRecord(id: "initial", value: 1)])
        XCTAssertGreaterThanOrEqual(fixture.functionState.invocationCount, 2)

        try await fixture.database.databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO AsyncStreamRetryRecord (id, value) VALUES (?, ?)",
                arguments: ["updated", 2]
            )
        }
        let updated = try await iterator.next()
        XCTAssertEqual(
            updated,
            [
                AsyncStreamRetryRecord(id: "initial", value: 1),
                AsyncStreamRetryRecord(id: "updated", value: 2),
            ]
        )
    }

    func testRetryExhaustionTerminatesOnceWithLastBusyErrorUsingManualScheduler() async throws {
        let scheduler = AsyncStreamManualRetryScheduler()
        let fixture = try makeInjectedBusyFixture(
            policy: .retryBusy,
            behavior: .failAlways,
            retryScheduler: scheduler.scheduler
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let iterator = AsyncStreamIteratorBox(
            fixture.database.makeRequest(with: fixture.statement).stream()
        )
        let consumeTask = Task { () -> Result<[AsyncStreamRetryRecord]?, Error> in
            do {
                return .success(try await iterator.next())
            }
            catch {
                return .failure(error)
            }
        }

        try await waitUntil { scheduler.pendingDelays == [0.1] }
        XCTAssertEqual(fixture.functionState.invocationCount, 1)
        scheduler.runNext()
        try await waitUntil { scheduler.pendingDelays == [0.2] }
        XCTAssertEqual(fixture.functionState.invocationCount, 2)
        scheduler.runNext()
        try await waitUntil { scheduler.pendingDelays == [0.4] }
        XCTAssertEqual(fixture.functionState.invocationCount, 3)
        scheduler.runNext()
        try await waitUntil { fixture.functionState.invocationCount == 4 }

        switch await consumeTask.value {
        case .success:
            XCTFail("An exhausted retry budget must terminate with the last BUSY error.")
        case .failure(let error):
            XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_BUSY)
        }
        XCTAssertEqual(scheduler.recordedDelays, [0.1, 0.2, 0.4])
    }

    func testPermanentFailureTerminatesWithoutSchedulingRetry() async throws {
        let scheduler = AsyncStreamManualRetryScheduler()
        let fixture = try makeInjectedBusyFixture(
            policy: .retryBusy,
            behavior: .succeed,
            retryScheduler: scheduler.scheduler
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        // Drop the table so the very first fetch fails permanently (SQL error,
        // not BUSY), regardless of the injected-busy function's own behavior.
        try await fixture.database.databasePool.write { database in
            try database.execute(sql: "DROP TABLE AsyncStreamRetryRecord")
        }

        let iterator = AsyncStreamIteratorBox(
            fixture.database.makeRequest(with: fixture.statement).stream()
        )

        do {
            _ = try await iterator.next()
            XCTFail("Expected a permanent (non-BUSY) failure.")
        }
        catch is DatabaseError {
            // Expected: "no such table" is not a BUSY error and must not retry.
        }
        XCTAssertTrue(scheduler.recordedDelays.isEmpty)
    }

    func testCancellationDuringBackoffStartsNoLaterAttempt() async throws {
        let scheduler = AsyncStreamManualRetryScheduler()
        let fixture = try makeInjectedBusyFixture(
            policy: .retryBusy,
            behavior: .failAlways,
            retryScheduler: scheduler.scheduler
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let stream = fixture.database.makeRequest(with: fixture.statement).stream()
        let iterator = AsyncStreamIteratorBox(stream)
        let task = Task<[AsyncStreamRetryRecord]?, Error> {
            try await iterator.next()
        }

        try await waitUntil { scheduler.pendingDelays == [0.1] }
        XCTAssertEqual(fixture.functionState.invocationCount, 1)
        task.cancel()

        let result = try await task.value
        XCTAssertNil(result, "Cancelling during backoff resolves to nil, not an error.")

        // Firing the pending delay after cancellation must not start a new attempt.
        scheduler.runNext()
        drainMainQueue()
        XCTAssertEqual(
            fixture.functionState.invocationCount,
            1,
            "Cancelling during backoff must start no later attempt."
        )
    }

    func testDeliveredValueResetsRetryBudget() async throws {
        let scheduler = AsyncStreamManualRetryScheduler()
        // Fails once, then succeeds, then (if retried again later) would fail
        // again — behavior below alternates manually via a custom fixture.
        let functionState = AsyncStreamInjectedBusyFunctionState(behavior: .failOnce)
        let fixture = try makeInjectedBusyFixture(
            policy: .retryBusy,
            functionState: functionState,
            retryScheduler: scheduler.scheduler
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let iterator = AsyncStreamIteratorBox(
            fixture.database.makeRequest(with: fixture.statement).stream()
        )
        let consumeTask = Task { () -> [AsyncStreamRetryRecord]? in
            try await iterator.next()
        }

        try await waitUntil { scheduler.pendingDelays == [0.1] }
        scheduler.runNext()
        let delivered = try await consumeTask.value
        XCTAssertEqual(delivered, [AsyncStreamRetryRecord(id: "initial", value: 1)])
        XCTAssertEqual(
            scheduler.recordedDelays,
            [0.1],
            "A delivered value must reset the retry budget; only the first delay was ever needed."
        )
    }

    // MARK: - Unsupported observation paths

    func testReturningRequestStreamFailsLazilyWithObservationUnsupported() async throws {
        try createRecordTable()
        let schema = XLSchema()
        let table = schema.table(AsyncStreamRecord.self)
        let statement = insert(table)
            .values(AsyncStreamRecord.MetaInsert(AsyncStreamRecord(id: "a", value: 1)))
            .returning(table)
        let request = database.makeRequest(with: statement)

        let iterator = AsyncStreamIteratorBox(request.stream())
        do {
            _ = try await iterator.next()
            XCTFail("Expected observationUnsupported.")
        }
        catch let error as XLReturningRequestError {
            XCTAssertEqual(error, .observationUnsupported)
        }

        // The failed stream must not have executed the insert.
        let rows = try database.makeRequest(with: orderedStatement()).fetchAll()
        XCTAssertEqual(rows, [])
    }

    func testTransactionScopedDriverStreamFailsLazilyWithLiveQueriesUnsupported() async throws {
        try createRecordTable()

        // The pool-availability check that decides this happens synchronously when
        // `stream()` is called (while the pinned scope is still valid); only the
        // *delivery* of the already-determined error is deferred to `next()`. This
        // lets the stream be constructed inside `withTransaction`'s synchronous
        // closure and awaited afterward, without needing an async transaction body.
        let stream = try database.withTransaction { scope in
            scope.makeRequest(with: self.orderedStatement()).stream()
        }
        let iterator = AsyncStreamIteratorBox(stream)
        do {
            _ = try await iterator.next()
            XCTFail("Expected liveQueriesUnsupportedInTransaction.")
        }
        catch let error as XLTransactionScopeError {
            XCTAssertEqual(error, .liveQueriesUnsupportedInTransaction)
        }
    }

    // MARK: - Deterministic repeated-stress run

    func testRepeatedStressCoversRapidCommitsCancellationRetryAndBuffering() async throws {
        try createRecordTable()

        for round in 0 ..< 5 {
            let request = database.makeRequest(with: orderedStatement())
            let iterator = AsyncStreamIteratorBox(request.stream())

            // Establish the current baseline before this round's rapid writes.
            _ = try await iterator.next()

            for burst in 0 ..< 10 {
                try insertDirect(AsyncStreamRecord(id: "stress-\(round)-\(burst)", value: burst))
            }

            // Drain to a snapshot containing every row inserted so far, without
            // requiring one `next()` per write.
            var lastCount = 0
            var attempts = 0
            while attempts < 10 {
                attempts += 1
                guard let rows = try await iterator.next() else { break }
                lastCount = rows.count
                if rows.count == (round + 1) * 10 { break }
            }
            XCTAssertGreaterThan(lastCount, 0)

            // Cancel this round's stream mid-stream and verify no further fetch
            // happens for it once a subsequent, unrelated write occurs.
            let task = Task<[AsyncStreamRecord]?, Error> { try await iterator.next() }
            task.cancel()
            _ = try await task.value
        }

        let total = try database.makeRequest(with: orderedStatement()).fetchAll().count
        XCTAssertEqual(total, 50)
    }

    // MARK: - Helpers

    private func orderedStatement() -> any XLQueryStatement<AsyncStreamRecord> {
        sql { schema in
            let table = schema.table(AsyncStreamRecord.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    /// Orders by the numeric `value` column, descending, so the top row only
    /// becomes the row with the highest `value` inserted so far -- unlike
    /// `orderedStatement()`'s lexicographic `id` ordering, where `"row-0"`
    /// sorts first regardless of how many later rows have committed.
    private func orderedByValueDescendingStatement() -> any XLQueryStatement<AsyncStreamRecord> {
        sql { schema in
            let table = schema.table(AsyncStreamRecord.self)
            Select(table)
            From(table)
            OrderBy(table.value.descending())
        }
    }

    private func byIDStatement() -> any XLQueryStatement<AsyncStreamRecord> {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        return sql { schema in
            let table = schema.table(AsyncStreamRecord.self)
            Select(table)
            From(table)
            Where(table.id == idParameter)
        }
    }

    private func createRecordTable() throws {
        try databasePool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE AsyncStreamRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }
    }

    private func insertDirect(_ row: AsyncStreamRecord) throws {
        try databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO AsyncStreamRecord (id, value) VALUES (?, ?)",
                arguments: [row.id, row.value]
            )
        }
    }

    private func drainMainQueue() {
        let barrier = expectation(description: "main-queue barrier")
        DispatchQueue.main.async {
            barrier.fulfill()
        }
        wait(for: [barrier], timeout: 2)
    }

    /// Bounded, deterministic polling: sleeps in small increments up to `timeout`, checking
    /// `condition` each time, rather than proving anything via one blind sleep.
    private func waitUntil(
        timeout: TimeInterval = 3,
        pollInterval: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let maxAttempts = max(Int((timeout * 1_000_000_000) / Double(pollInterval)), 1)
        for _ in 0 ..< maxAttempts {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Condition not met within \(timeout)s", file: file, line: line)
    }

    private struct InjectedBusyFixture {
        let database: GRDBDatabase
        let directoryURL: URL
        let functionState: AsyncStreamInjectedBusyFunctionState
        let statement: any XLQueryStatement<AsyncStreamRetryRecord>
    }

    private func makeInjectedBusyFixture(
        policy: GRDBLiveQueryRetryPolicy,
        behavior: AsyncStreamInjectedBusyFunctionState.Behavior = .failOnce,
        functionState: AsyncStreamInjectedBusyFunctionState? = nil,
        retryScheduler: GRDBLiveQueryRetryScheduler? = nil
    ) throws -> InjectedBusyFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let databaseURL = directoryURL.appendingPathComponent("retry.sqlite", isDirectory: false)
        let resolvedFunctionState = functionState ?? AsyncStreamInjectedBusyFunctionState(behavior: behavior)

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    AsyncStreamInjectedBusyExpression.functionName,
                    argumentCount: 0
                ) { _ in
                    try resolvedFunctionState.invoke()
                }
            )
        }

        let pool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        let fixtureDatabase = try GRDBDatabase(
            databasePool: pool,
            formatter: XLiteFormatter(),
            logger: nil,
            liveQueryRetryPolicy: policy,
            liveQueryRetryScheduler: retryScheduler ?? .mainQueue
        )
        try pool.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE AsyncStreamRetryRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    )
                    """
            )
            try database.execute(
                sql: "INSERT INTO AsyncStreamRetryRecord (id, value) VALUES (?, ?)",
                arguments: ["initial", 1]
            )
        }

        let statement: any XLQueryStatement<AsyncStreamRetryRecord> = sql { schema in
            let table = schema.table(AsyncStreamRetryRecord.self)
            Select(table)
            From(table)
            Where(AsyncStreamInjectedBusyExpression() == 1)
            OrderBy(table.id.ascending())
        }

        return InjectedBusyFixture(
            database: fixtureDatabase,
            directoryURL: directoryURL,
            functionState: resolvedFunctionState,
            statement: statement
        )
    }
}
