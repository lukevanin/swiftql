//
//  LiveQueryBufferingSemanticsTests.swift
//
//
//  Created by Claude on 2026/07/29.
//

import Foundation
import GRDB
import XCTest


private struct AwaitNextTimeoutError: Error {}


// MARK: - Evidence-only prototype (see Sources/SwiftQL/SwiftQL.docc/LiveQueries.md,
// "Buffering and Resumed-Demand Semantics (#291)")
//
// `LazyBufferedGRDBBridge` is NOT production SwiftQL API. It exists only to
// produce deterministic, real-GRDB evidence that the buffering, cancellation,
// and lazy-start policy selected by issue #291 is implementable on the
// pinned Swift 5.9 / GRDB 6.29.3 toolchain, ahead of #308 building the real
// canonical `AsyncThrowingStream` source. It intentionally reuses GRDB's own
// low-level `ValueObservation.start(in:scheduling:onError:onChange:)`, the
// same primitive `GRDBLiveQueryRetryPolicy.swift` already builds retry on top
// of for the Combine path.
//
// Design, empirically verified against the pinned Swift toolchain before
// writing these tests (see the session's throwaway `probe.swift` /
// `probe2.swift` scripts, not checked into the repository):
//
// - `AsyncThrowingStream<Element, Error>(unfolding:)` performs zero work
//   until the first `next()` call, and calls its `produce` closure exactly
//   once per consumer pull — it does not pull ahead of consumption or
//   accumulate a backlog on its own. This is what makes it possible to
//   return the literal `AsyncThrowingStream<[Row], Error>` type required by
//   #308 while still deferring GRDB observation start to first iteration.
// - `AsyncThrowingStream`'s `unfolding:` initializer has no `onCancel`
//   parameter (unlike `AsyncStream`). Cancellation must be handled inside
//   the `produce` closure itself, by wrapping the suspension point in
//   `withTaskCancellationHandler(operation:onCancel:)`.
private final class SingleSlotMailbox<Value>: @unchecked Sendable {

    private let lock = NSLock()

    /// The buffering bound selected by #291: at most one snapshot is ever
    /// held. A newly yielded value replaces (not queues behind) any
    /// previously buffered, undelivered value.
    private var pendingValue: Value?

    private var pendingError: Error?

    private var isFinished = false

    private var waiter: CheckedContinuation<Value?, Error>?

    /// Number of values ever placed into the mailbox (delivered immediately
    /// to a waiter, or buffered and possibly later replaced). Used by tests
    /// to observe how many times GRDB actually produced a fresh value,
    /// independent of consumer pacing.
    private(set) var totalYieldCount = 0

    func yield(_ value: Value) {
        lock.lock()
        // Termination wins over any value that arrives at or after it: once
        // finished, a mailbox never buffers or delivers a further value, so a
        // GRDB refresh racing with cancellation/completion cannot resurrect
        // delivery after the stream has ended.
        guard !isFinished else {
            lock.unlock()
            return
        }
        totalYieldCount += 1
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: value)
            return
        }
        pendingValue = value
        lock.unlock()
    }

    func finish(throwing error: Error?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        // Termination wins over any value already buffered (or about to be
        // buffered by a `yield` that lost the lock race to this call): a
        // buffered-but-undelivered snapshot must not surface after the
        // stream has ended.
        pendingValue = nil
        if let waiter {
            self.waiter = nil
            lock.unlock()
            if let error {
                waiter.resume(throwing: error)
            }
            else {
                waiter.resume(returning: nil)
            }
            return
        }
        pendingError = error
        lock.unlock()
    }

    /// Ends the mailbox without an error: a cancelled bridge resolves any
    /// outstanding or future `next()` call to `nil`, exactly like a normal,
    /// non-erroring end of iteration. Cancellation is never surfaced to the
    /// consumer as a thrown `CancellationError` or as a completion failure,
    /// mirroring how cancelling a Combine subscription today never delivers
    /// a `.failure` completion.
    func cancel() {
        finish(throwing: nil)
    }

    private enum FastPathOutcome {
        case value(Value)
        case error(Error)
        case finished
        case pending
    }

    /// All plain synchronous locked mutation is kept out of `next()`'s
    /// `async` body: recent Foundation marks `NSLock.lock()`/`unlock()` as
    /// unavailable directly inside asynchronous contexts (an error under the
    /// Swift 6 language mode), so both the initial fast-path check and the
    /// re-check performed once a continuation is available live in plain,
    /// non-`async` helper methods instead.
    private func checkFastPath() -> FastPathOutcome {
        lock.lock()
        defer { lock.unlock() }
        if let value = pendingValue {
            pendingValue = nil
            return .value(value)
        }
        if isFinished {
            if let pendingError {
                self.pendingError = nil
                return .error(pendingError)
            }
            return .finished
        }
        return .pending
    }

    /// Re-checks and, if still pending, registers the continuation as the
    /// single outstanding waiter — all inside one locked critical section.
    /// This must not be split into a separate check-then-register pair of
    /// locked calls: a value or termination arriving on another thread in
    /// the gap between them would otherwise be lost (`yield`/`finish` only
    /// resume a `waiter` that is already registered; anything arriving
    /// before registration would sit in `pendingValue`/`isFinished` and
    /// never wake this continuation).
    private func resolveImmediatelyOrRegister(_ continuation: CheckedContinuation<Value?, Error>) {
        lock.lock()
        if let value = pendingValue {
            pendingValue = nil
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        if isFinished {
            let error = pendingError
            pendingError = nil
            lock.unlock()
            if let error {
                continuation.resume(throwing: error)
            }
            else {
                continuation.resume(returning: nil)
            }
            return
        }
        waiter = continuation
        lock.unlock()
    }

    func next() async throws -> Value? {
        switch checkFastPath() {
        case .value(let value):
            return value
        case .error(let error):
            throw error
        case .finished:
            return nil
        case .pending:
            return try await withCheckedThrowingContinuation { continuation in
                resolveImmediatelyOrRegister(continuation)
            }
        }
    }
}


/// Bridges a raw GRDB `ValueObservation` into a lazily-started, single-slot
/// ("newest wins") buffered `AsyncThrowingStream`. Observation starts only on
/// the first `next()` call — never merely by constructing the bridge or its
/// `stream()` value — and a cancelled consuming `Task` tears down the
/// underlying GRDB `AnyDatabaseCancellable` promptly.
private final class LazyBufferedGRDBBridge<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var didStart = false

    private var cancellable: AnyDatabaseCancellable?

    private let mailbox = SingleSlotMailbox<Value>()

    private let startObservation: (
        @escaping (Error) -> Void,
        @escaping (Value) -> Void
    ) -> AnyDatabaseCancellable

    /// Number of times this bridge has actually started the underlying GRDB
    /// observation. Must be 0 for a bridge whose stream is never iterated,
    /// and at most 1 for the lifetime of one bridge (one `stream()` call is
    /// one independent, single-consumer observation).
    private(set) var startCount = 0

    init(
        start: @escaping (
            @escaping (Error) -> Void,
            @escaping (Value) -> Void
        ) -> AnyDatabaseCancellable
    ) {
        self.startObservation = start
    }

    var totalYieldCount: Int { mailbox.totalYieldCount }

    /// Synchronous locked mutation kept out of `next()`'s `async` body (see
    /// the equivalent note on `SingleSlotMailbox`). Returns `true` exactly
    /// once, for the call that must actually start the GRDB observation.
    private func claimStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didStart else { return false }
        didStart = true
        startCount += 1
        return true
    }

    private func storeCancellable(_ newCancellable: AnyDatabaseCancellable) {
        lock.lock()
        cancellable = newCancellable
        lock.unlock()
    }

    func next() async throws -> Value? {
        if claimStart() {
            let mailbox = self.mailbox
            let newCancellable = startObservation(
                { error in mailbox.finish(throwing: error) },
                { value in mailbox.yield(value) }
            )
            storeCancellable(newCancellable)
        }

        return try await withTaskCancellationHandler(
            operation: { try await mailbox.next() },
            onCancel: { [weak self] in self?.cancel() }
        )
    }

    /// Cancels the underlying GRDB observation and ends the mailbox. Safe to
    /// call more than once, and safe to call whether or not `next()` was
    /// ever invoked. Claims the start slot itself when observation never
    /// began, so a `next()` call arriving after `cancel()` finds the mailbox
    /// already finished instead of starting a fresh GRDB observation that
    /// nothing will ever consume.
    func cancel() {
        lock.lock()
        didStart = true
        let existing = cancellable
        lock.unlock()
        existing?.cancel()
        mailbox.cancel()
    }

    /// The publicly-shaped return type #308 must expose. Constructing this
    /// value performs no database work: only the first `next()` call (i.e.
    /// the first iteration attempt, whether via `for try await` or a manual
    /// `makeAsyncIterator().next()`) starts the GRDB observation.
    func stream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(unfolding: { [weak self] in
            try await self?.next()
        })
    }
}


/// Minimal demand-aware puller validating the #309 async-to-Combine demand
/// mapping: pulls from the bridge exactly once per unit of granted demand,
/// never ahead of demand, and never through a second unbounded queue.
private final class DemandDrivenPuller<Value>: @unchecked Sendable {

    private let bridge: LazyBufferedGRDBBridge<Value>

    private let lock = NSLock()

    private var remainingDemand = 0

    private var isPulling = false

    private var isFinished = false

    private let onValue: (Value) -> Void

    private let onFinish: (Error?) -> Void

    init(
        bridge: LazyBufferedGRDBBridge<Value>,
        onValue: @escaping (Value) -> Void,
        onFinish: @escaping (Error?) -> Void
    ) {
        self.bridge = bridge
        self.onValue = onValue
        self.onFinish = onFinish
    }

    /// Combine's `request(_:)` maps onto this: granting demand only ever
    /// starts pulling if nothing is currently in flight, and the pull loop
    /// stops the instant remaining demand reaches zero rather than reading
    /// ahead into a side buffer.
    func requestDemand(_ amount: Int) {
        guard amount > 0 else {
            return
        }
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        remainingDemand += amount
        let shouldStartPulling = !isPulling && remainingDemand > 0
        if shouldStartPulling {
            isPulling = true
        }
        lock.unlock()
        if shouldStartPulling {
            pumpNext()
        }
    }

    func cancel() {
        lock.lock()
        isFinished = true
        lock.unlock()
        bridge.cancel()
    }

    private func pumpNext() {
        Task {
            do {
                guard let value = try await bridge.next() else {
                    markFinished()
                    onFinish(nil)
                    return
                }
                onValue(value)
                if decrementDemandAndCheckWhetherToContinue() {
                    pumpNext()
                }
            }
            catch {
                markFinished()
                onFinish(error)
            }
        }
    }

    /// Synchronous locked mutation extracted out of the `async` `pumpNext`
    /// body: recent Foundation marks `NSLock.lock()`/`unlock()` as
    /// unavailable directly inside asynchronous contexts (an error under the
    /// Swift 6 language mode), so every mutation happens in a plain,
    /// non-`async` helper instead.
    private func markFinished() {
        lock.lock()
        isFinished = true
        isPulling = false
        lock.unlock()
    }

    private func decrementDemandAndCheckWhetherToContinue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        remainingDemand -= 1
        let shouldContinue = remainingDemand > 0 && !isFinished
        if !shouldContinue {
            isPulling = false
        }
        return shouldContinue
    }
}


private final class LockedCounter: @unchecked Sendable {

    private let lock = NSLock()

    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}


private final class LockedArray<Element>: @unchecked Sendable {

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


final class LiveQueryBufferingSemanticsTests: XCTestCase {

    private var databaseDirectoryURL: URL!
    private var databasePool: DatabasePool!

    override func setUpWithError() throws {
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "evidence.sqlite",
            isDirectory: false
        )
        databasePool = try DatabasePool(path: fileURL.path)
        try databasePool.write { database in
            try database.execute(
                sql: "CREATE TABLE Row (id TEXT NOT NULL PRIMARY KEY, value INT NOT NULL)"
            )
        }
    }

    override func tearDown() {
        databasePool = nil
        if let databaseDirectoryURL {
            try? FileManager.default.removeItem(at: databaseDirectoryURL)
        }
        databaseDirectoryURL = nil
    }

    // MARK: - Unused stream (edge case: unused stream)

    func testUnusedStreamPerformsNoFetch() throws {
        let fetchCounter = LockedCounter()
        var bridge: LazyBufferedGRDBBridge<Int>? = makeBridge(fetchProbe: { fetchCounter.increment() })
        _ = bridge!.stream() // constructed, never iterated

        drainMainQueue()
        XCTAssertEqual(fetchCounter.read(), 0, "Constructing an unused stream must perform no fetch.")
        XCTAssertEqual(bridge!.startCount, 0, "Constructing an unused stream must not start an observation.")
        bridge = nil
    }

    // MARK: - Slow/paused consumer + rapid commits (edge cases: slow async
    // consumer, rapid commits, in-flight fetch, buffer replacement)

    func testPausedConsumerWithRapidCommitsSeesOnlyTheNewestBoundedSnapshot() throws {
        let writeCount = 20
        let bridge = makeBridge()

        let initialValue = try awaitNext(bridge)
        XCTAssertEqual(initialValue, 0)

        // Consumer is "paused": twenty relevant commits happen back to back,
        // synchronously, with no intervening `next()` call. GRDB's own
        // change-notification scheduling decides how many of these coalesce
        // into a single re-fetch, so this deliberately does not assume
        // exactly one re-fetch reflects all twenty writes (it may not:
        // a concurrent reader-based re-fetch can race ahead of the writer
        // loop and observe an intermediate row count). What the bounded,
        // newest-wins mailbox *does* guarantee is that resuming iteration
        // never needs one `next()` call per write to catch up.
        for index in 0 ..< writeCount {
            try insert("row-\(index)", index)
        }

        var observedValues: [Int] = []
        for attempt in 1 ... writeCount {
            guard let value = try awaitNext(bridge) else {
                XCTFail("Bridge terminated unexpectedly while draining to the final snapshot.")
                break
            }
            observedValues.append(value)
            if value == writeCount {
                XCTAssertLessThan(
                    attempt,
                    writeCount,
                    "Bounded buffering must coalesce most of \(writeCount) rapid commits into far "
                        + "fewer delivered snapshots than one `next()` call per write."
                )
                break
            }
        }
        XCTAssertEqual(observedValues.last, writeCount, "Resuming must eventually reach the current state.")

        bridge.cancel()
    }

    // MARK: - Resumed iteration does not itself trigger a fetch

    func testResumingIterationDoesNotItselfStartASecondObservationOrForceAFetch() throws {
        let fetchCounter = LockedCounter()
        let bridge = makeBridge(fetchProbe: { fetchCounter.increment() })

        _ = try awaitNext(bridge)
        XCTAssertEqual(bridge.startCount, 1)
        let fetchCountAfterInitial = fetchCounter.read()
        XCTAssertGreaterThanOrEqual(fetchCountAfterInitial, 1)

        // Resume iteration with no relevant write in between. Starting a
        // fresh observation increments `startCount` synchronously inside
        // `next()`, so this check is not a timing race: an already-started
        // bridge must never touch it again.
        let secondExpectation = expectation(description: "second next() resolves only after a later write")
        let secondValue = LockedValueBox<Int?>(nil)
        Task {
            secondValue.set(try await bridge.next())
            secondExpectation.fulfill()
        }
        drainMainQueue()
        XCTAssertEqual(bridge.startCount, 1, "Resuming iteration must not start a second observation.")
        XCTAssertEqual(fetchCounter.read(), fetchCountAfterInitial, "Resuming iteration must not itself force a fetch.")

        try insert("later", 1)
        wait(for: [secondExpectation], timeout: 2)
        XCTAssertEqual(secondValue.get(), 1)

        bridge.cancel()
    }

    // MARK: - Cancellation ownership (edge cases: cancellation during
    // fetch/backoff is covered by the existing GRDBLiveQueryRetryTests
    // suite; this covers cancellation of the buffered bridge itself)

    func testExplicitCancelStopsDeliveryAndTearsDownTheUnderlyingObservation() throws {
        let fetchCounter = LockedCounter()
        let bridge = makeBridge(fetchProbe: { fetchCounter.increment() })

        _ = try awaitNext(bridge)
        let fetchCountBeforeCancel = fetchCounter.read()

        bridge.cancel()

        let afterCancel = try awaitNext(bridge)
        XCTAssertNil(afterCancel, "A cancelled bridge resolves to nil, never a value or an error.")

        try insert("after-cancel", 1)
        drainMainQueue()
        XCTAssertEqual(
            fetchCounter.read(),
            fetchCountBeforeCancel,
            "Cancellation must stop the underlying GRDB observation from fetching again."
        )
    }

    func testCancellingTheConsumingTaskCancelsTheUnderlyingObservation() throws {
        let fetchCounter = LockedCounter()
        let bridge = makeBridge(fetchProbe: { fetchCounter.increment() })
        let stream = bridge.stream()
        let seen = LockedArray<Int>()
        let loopExpectation = expectation(description: "loop ends after task cancellation")

        let task = Task {
            do {
                for try await value in stream {
                    seen.append(value)
                }
            }
            catch {
                XCTFail("Unexpected stream error: \(error)")
            }
            loopExpectation.fulfill()
        }

        waitForCount(seen, atLeast: 1)
        task.cancel()
        wait(for: [loopExpectation], timeout: 2)
        XCTAssertEqual(seen.read(), [0])

        let fetchCountAtCancel = fetchCounter.read()
        try insert("after-task-cancel", 99)
        drainMainQueue()
        XCTAssertEqual(
            fetchCounter.read(),
            fetchCountAtCancel,
            "Cancelling the consuming task must cancel the underlying GRDB observation."
        )
    }

    // MARK: - Terminal error (edge case: terminal error)

    func testTerminalErrorIsForwardedExactlyOnceThroughTheBridge() throws {
        struct ProbeError: Error, Equatable {}
        let bridge = LazyBufferedGRDBBridge<Int> { onError, onChange in
            ValueObservation
                .tracking { db -> Int in
                    _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Row")
                    throw ProbeError()
                }
                .start(in: self.databasePool, onError: onError, onChange: onChange)
        }

        do {
            _ = try awaitNext(bridge)
            XCTFail("Expected the bridge to throw ProbeError")
        }
        catch {
            XCTAssertTrue(error is ProbeError)
        }

        // Exactly once: a second call after termination resolves to nil, it
        // does not re-throw, hang, or deliver a second error.
        let afterTerminal = try awaitNext(bridge)
        XCTAssertNil(afterTerminal)
    }

    // MARK: - Independent streams (edge cases: two consumers created from
    // separate calls, independent databases)

    func testTwoIndependentBridgesDoNotShareBufferedStateOrCrossTrigger() throws {
        let bridgeA = makeBridge()
        let bridgeB = makeBridge()

        XCTAssertEqual(try awaitNext(bridgeA), 0)
        XCTAssertEqual(try awaitNext(bridgeB), 0)

        try insert("shared-write", 1)

        XCTAssertEqual(try awaitNext(bridgeA), 1)
        XCTAssertEqual(try awaitNext(bridgeB), 1)

        bridgeA.cancel()
        bridgeB.cancel()
    }

    // MARK: - Demand mapping (edge cases: zero demand, incremental demand,
    // unlimited demand, demand added from receive)

    func testDemandDrivenPullerConsumesExactlyDemandedCountWithoutEagerDraining() throws {
        let bridge = makeBridge()
        let delivered = LockedArray<Int>()
        let puller = DemandDrivenPuller(
            bridge: bridge,
            onValue: { delivered.append($0) },
            onFinish: { _ in }
        )

        // Zero demand: the puller must not touch the bridge at all.
        drainMainQueue()
        XCTAssertEqual(bridge.startCount, 0, "Zero demand must not start the observation.")
        XCTAssertEqual(delivered.read(), [])

        // Grant demand for exactly one value.
        puller.requestDemand(1)
        waitForCount(delivered, atLeast: 1)
        XCTAssertEqual(delivered.read(), [0])

        // Multiple rapid writes while demand is exhausted (zero outstanding):
        // the puller must not pull ahead of demand. The bridge observes
        // `COUNT(*)`, so two inserts into this fresh table move the row
        // count from 0 to 2 (the `value` columns, 1 and 2, are unrelated to
        // the observed count).
        try insert("a", 1)
        try insert("b", 2)
        drainMainQueue()
        XCTAssertEqual(
            delivered.read(),
            [0],
            "With no demand outstanding, the puller must not deliver further values."
        )

        // Resuming demand delivers exactly one more value: the bridge's
        // single buffered "newest" snapshot, not a backlog of every write
        // that occurred while paused.
        puller.requestDemand(1)
        waitForCount(delivered, atLeast: 2)
        XCTAssertEqual(delivered.read(), [0, 2])

        puller.cancel()
    }

    func testUnlimitedDemandDeliversAsValuesBecomeAvailableWithoutSpinningOrDoubleDelivery() throws {
        let bridge = makeBridge()
        let delivered = LockedArray<Int>()
        let finished = LockedValueBox<Error??>(nil)
        let puller = DemandDrivenPuller(
            bridge: bridge,
            onValue: { delivered.append($0) },
            onFinish: { finished.set($0) }
        )

        // A very large demand simulates Combine's `.unlimited`.
        puller.requestDemand(1_000_000)
        waitForCount(delivered, atLeast: 1)
        XCTAssertEqual(delivered.read(), [0])

        // The bridge observes `COUNT(*)`, so one insert into this fresh
        // table moves the row count from 0 to 1 (the inserted row's own
        // `value` column, 42, is unrelated to the observed count).
        try insert("x", 42)
        waitForCount(delivered, atLeast: 2)
        XCTAssertEqual(delivered.read(), [0, 1])

        // No further writes: the puller must not spin, error, or duplicate
        // delivery while waiting for the next relevant commit.
        drainMainQueue()
        XCTAssertEqual(delivered.read(), [0, 1])
        XCTAssertNil(finished.get() ?? nil)

        puller.cancel()
    }

    // MARK: - Helpers

    private func makeBridge(fetchProbe: @escaping () -> Void = {}) -> LazyBufferedGRDBBridge<Int> {
        let pool = databasePool!
        return LazyBufferedGRDBBridge<Int> { onError, onChange in
            ValueObservation
                .tracking { db -> Int in
                    fetchProbe()
                    return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Row") ?? 0
                }
                .start(in: pool, onError: onError, onChange: onChange)
        }
    }

    private func insert(_ id: String, _ value: Int) throws {
        try databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO Row (id, value) VALUES (?, ?)",
                arguments: [id, value]
            )
        }
    }

    /// Awaits one `next()` call from a synchronous (non-`async`) XCTestCase
    /// test method. `wait(for:timeout:)` pumps the run loop, which is what
    /// lets GRDB's default main-queue scheduler actually deliver values
    /// while this method blocks — the same mechanism the existing Combine
    /// publisher tests rely on via `sink`.
    private func awaitNext<Value>(_ bridge: LazyBufferedGRDBBridge<Value>) throws -> Value? {
        let resultBox = LockedValueBox<Result<Value?, Error>?>(nil)
        let barrier = expectation(description: "awaitNext")
        Task {
            do {
                resultBox.set(.success(try await bridge.next()))
            }
            catch {
                resultBox.set(.failure(error))
            }
            barrier.fulfill()
        }
        wait(for: [barrier], timeout: 2)
        guard let result = resultBox.get() else {
            throw AwaitNextTimeoutError()
        }
        return try result.get()
    }

    private func drainMainQueue() {
        let barrier = expectation(description: "main-queue barrier")
        DispatchQueue.main.async {
            barrier.fulfill()
        }
        wait(for: [barrier], timeout: 2)
    }

    private func waitForCount<Element>(_ array: LockedArray<Element>, atLeast minimumCount: Int) {
        for attempt in 1 ... 200 {
            if array.read().count >= minimumCount {
                return
            }
            let poll = expectation(description: "array poll \(attempt)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                poll.fulfill()
            }
            wait(for: [poll], timeout: 0.2)
        }
        XCTFail("Expected at least \(minimumCount) delivered values; received \(array.read().count).")
    }
}


private final class LockedValueBox<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
