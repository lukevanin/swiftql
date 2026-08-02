//
//  LiveQueryBufferingSemanticsTests.swift
//

import Foundation
// GRDB predates Sendable auditing; `@preconcurrency` downgrades its types' missing Sendable
// conformances (e.g. `AnyDatabaseCancellable`, stored and returned across this file's locked state)
// from blocking errors to warnings under complete strict-concurrency checking, matching the
// compiler's own suggested fix rather than working around it with an unrelated annotation.
@preconcurrency import GRDB
import XCTest
#if canImport(os)
import os
#endif


private struct AwaitNextTimeoutError: Error {}


#if !canImport(os)
/// Minimal `OSAllocatedUnfairLock`-compatible shim for platforms without
/// Darwin's `os` module (e.g. this package's Linux CI cells), matching only
/// the two initializers and the single `withLock` method this file uses.
/// Exposes *only* `withLock`, never a bare `lock()`/`unlock()` pair, so
/// nothing on this fallback path can reach for the discouraged manual-unlock
/// pattern even though it is, unavoidably, backed by `NSLock` internally —
/// there is no Darwin-style unfair lock to wrap on this platform.
private final class OSAllocatedUnfairLock<State>: @unchecked Sendable {

    private let lock = NSLock()

    private var state: State

    init(uncheckedState initialState: State) {
        state = initialState
    }

    init(initialState: State) where State: Sendable {
        state = initialState
    }

    @discardableResult
    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
#endif


// MARK: - Evidence-only prototype (see Sources/SwiftQL/SwiftQL.docc/LiveQueries.md,
// "Buffering and Resumed-Demand Semantics (#291)")
//
// `LazyBufferedGRDBBridge` is NOT production SwiftQL API. It exists only to
// produce deterministic, real-GRDB evidence that the buffering, cancellation,
// and lazy-start policy selected by issue #291 is implementable on the
// pinned Swift 5.9 / GRDB 6.29.3 toolchain, ahead of #308 building the real
// canonical `AsyncThrowingStream` source. It intentionally reuses GRDB's own
// low-level `ValueObservation.start(in:scheduling:onError:onChange:)` --
// at the time this prototype was written, the same primitive
// `GRDBSQLDatabase.swift`'s pre-#309 `publisher(fetch:)` helper called for
// the OpenCombine path, with retry supplied by `GRDBLiveQueryRetryPolicy
// .swift`'s `makeGRDBLiveQueryRetryPublisher` wrapping that source. Both of
// those were removed once #309 rebuilt `publish()`/`publishOne()` as
// adapters over `stream()`/`streamOne()`, which reuse the same
// `ValueObservation.start` primitive through `GRDBLiveQueryAsyncBridge`
// instead (see `Sources/SwiftQL/GRDBLiveQueryAsyncStream.swift`).
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

    /// All mutable state guarded by one `OSAllocatedUnfairLock`, per this
    /// codebase's locking standard: the state lives *inside* the lock, so
    /// there is no path to it unguarded (unlike a separately-declared `var`
    /// next to a bare `NSLock`).
    private struct State {

        /// The buffering bound selected by #291: at most one snapshot is ever
        /// held. A newly yielded value replaces (not queues behind) any
        /// previously buffered, undelivered value.
        var pendingValue: Value?

        var pendingError: Error?

        var isFinished = false

        var waiter: CheckedContinuation<Value?, Error>?

        /// Number of values ever placed into the mailbox (delivered
        /// immediately to a waiter, or buffered and possibly later
        /// replaced). Used by tests to observe how many times GRDB actually
        /// produced a fresh value, independent of consumer pacing.
        var totalYieldCount = 0
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// The most recent value this mailbox has been handed, whether it was delivered straight to a
    /// waiter or buffered. Separate from `State` and awaitable, so a test can wait for the
    /// *observation* to have produced a particular snapshot -- rather than assuming, from a main-queue
    /// barrier, that GRDB has already fetched it (#533).
    private let newestYield = XLAwaitableState<Value?>(nil)

    var totalYieldCount: Int {
        state.withLock { $0.totalYieldCount }
    }

    /// Suspends until a value satisfying `isExpected` has been yielded into this mailbox.
    func waitForYield(satisfying isExpected: @escaping (Value) -> Bool) async {
        await newestYield.wait(until: { value in
            guard let value else { return false }
            return isExpected(value)
        })
    }

    // `@unchecked Sendable`, matching `FastPathOutcome`/`RegistrationOutcome` below: a bare
    // `(waiter: ..., value: Value)` tuple return type from `yield(_:)`'s `@Sendable` closure is itself
    // flagged as non-Sendable (since `Value` is), the same way those enums are.
    private struct Delivery: @unchecked Sendable {
        let waiter: CheckedContinuation<Value?, Error>
        let value: Value
    }

    func yield(_ value: Value) {
        // `OSAllocatedUnfairLock<State>: Sendable` holds its `withLock` closure parameter to
        // `@Sendable`, and `SingleSlotMailbox` itself opts into `@unchecked Sendable`, so capturing a
        // non-Sendable generic `Value` inside that closure is flagged under complete strict-concurrency
        // checking. A `nonisolated(unsafe)` shadow clears that specific capture. Empirically, though,
        // referencing the *original* `value` parameter a second time afterward, to feed
        // `resume(returning:)`'s own `sending` parameter, keeps warning regardless of `sending`,
        // `nonisolated(unsafe)`, or `consume` at that second call site -- something about a value
        // having already appeared inside this `@Sendable` closure keeps it "task-isolated" for any
        // later, separate use, even of a freshly shadowed copy of the same binding. The fix that does
        // work: never reference `value` a second time at all. Have the closure return the exact value
        // to resume with alongside the waiter -- extracted from the closure's return, exactly like
        // `waiter` itself already was as this file's very first prototype (before OSAllocatedUnfairLock)
        // -- rather than recombining it with the outer parameter after the fact.
        #if compiler(>=6.0)
        nonisolated(unsafe) let value = value
        #endif
        let delivery: Delivery? = state.withLock { state in
            // Termination wins over any value that arrives at or after it:
            // once finished, a mailbox never buffers or delivers a further
            // value, so a GRDB refresh racing with cancellation/completion
            // cannot resurrect delivery after the stream has ended.
            guard !state.isFinished else {
                return nil
            }
            state.totalYieldCount += 1
            if let waiter = state.waiter {
                state.waiter = nil
                return Delivery(waiter: waiter, value: value)
            }
            state.pendingValue = value
            return nil
        }
        // Resuming happens outside the lock, exactly like the previous
        // `NSLock`-based version: a continuation resumption can itself run
        // arbitrary downstream code, which must never happen while this
        // mailbox's own lock is held.
        if let delivery {
            newestYield.set(delivery.value)
            delivery.waiter.resume(returning: delivery.value)
        }
        else {
            newestYield.set(value)
        }
    }

    /// Ends the mailbox with the upstream source's own normal completion or
    /// terminal error -- NOT with consumer-initiated cancellation; use
    /// ``cancel()`` for that instead, which has different, stricter delivery
    /// semantics (see its documentation).
    ///
    /// Deliberately does NOT clear `pendingValue`: a value legitimately
    /// yielded before `finish()` is called (e.g. a source that emits one
    /// final value and completes immediately afterward) must still be
    /// delivered by the next `next()` call before iteration ends -- values
    /// then completion, in that order. Confirmed by #308's production use of
    /// this same policy: a `Just`-backed compatibility publisher's
    /// yield-then-finish happens synchronously within one callback chain, and
    /// discarding the buffered value here silently dropped it. `yield(_:)`'s
    /// own `isFinished` guard already prevents a value that arrives *after*
    /// `finish()`/`cancel()` from ever being buffered, which is the actual
    /// race this type must reject.
    func finish(throwing error: Error?) {
        let waiterResumption: (CheckedContinuation<Value?, Error>, Error?)? = state.withLock { state in
            guard !state.isFinished else {
                return nil
            }
            state.isFinished = true
            guard let waiter = state.waiter else {
                state.pendingError = error
                return nil
            }
            state.waiter = nil
            return (waiter, error)
        }
        guard let (waiter, error) = waiterResumption else {
            return
        }
        if let error {
            waiter.resume(throwing: error)
        }
        else {
            waiter.resume(returning: nil)
        }
    }

    /// Ends the mailbox because the *consumer* cancelled, not because the
    /// upstream source completed: every outstanding or future `next()` call
    /// resolves to `nil`, exactly like a normal, non-erroring end of
    /// iteration, and cancellation is never surfaced as a thrown
    /// `CancellationError` or a completion failure -- mirroring how
    /// cancelling a Combine subscription today never delivers a `.failure`
    /// completion.
    ///
    /// Unlike ``finish(throwing:)``, this also discards any value already
    /// buffered but not yet delivered: once the consumer has said it no
    /// longer wants delivery, a stale snapshot slipping through afterward
    /// would be a real cancellation-contract violation, not a legitimate
    /// "last value before normal completion." This is the distinction that
    /// makes ``finish(throwing:)`` and `cancel()` different operations rather
    /// than one delegating to the other.
    func cancel() {
        let waiterToResume: CheckedContinuation<Value?, Error>? = state.withLock { state in
            guard !state.isFinished else {
                return nil
            }
            state.isFinished = true
            state.pendingValue = nil
            state.pendingError = nil
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiterToResume?.resume(returning: nil)
    }

    // `@unchecked Sendable`: this enum only ever shuttles `Value` briefly out of `state`'s locked
    // closure (see `SingleSlotMailbox`'s own note on `@unchecked Sendable`) -- it never escapes
    // beyond `checkFastPath()`'s immediate caller.
    private enum FastPathOutcome: @unchecked Sendable {
        case value(Value)
        case error(Error)
        case finished
        case pending
    }

    /// All plain synchronous locked mutation is kept out of `next()`'s
    /// `async` body, matching the equivalent split already used elsewhere in
    /// this file: both the initial fast-path check and the re-check
    /// performed once a continuation is available live in plain, non-`async`
    /// helper methods instead.
    private func checkFastPath() -> FastPathOutcome {
        state.withLock { state in
            if let value = state.pendingValue {
                state.pendingValue = nil
                return .value(value)
            }
            if state.isFinished {
                if let pendingError = state.pendingError {
                    state.pendingError = nil
                    return .error(pendingError)
                }
                return .finished
            }
            return .pending
        }
    }

    // See `FastPathOutcome`'s note above -- identical reasoning.
    private enum RegistrationOutcome: @unchecked Sendable {
        case value(Value)
        case error(Error)
        case finished
        case registered
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
        let outcome: RegistrationOutcome = state.withLock { state in
            if let value = state.pendingValue {
                state.pendingValue = nil
                return .value(value)
            }
            if state.isFinished {
                let error = state.pendingError
                state.pendingError = nil
                if let error {
                    return .error(error)
                }
                return .finished
            }
            precondition(
                state.waiter == nil,
                "SingleSlotMailbox.next() called concurrently: a second caller "
                    + "would silently overwrite and leak/hang the first waiter."
            )
            state.waiter = continuation
            return .registered
        }
        switch outcome {
        case .value(let value):
            continuation.resume(returning: value)
        case .error(let error):
            continuation.resume(throwing: error)
        case .finished:
            continuation.resume(returning: nil)
        case .registered:
            break
        }
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

    private struct State {
        var didStart = false
        var cancellable: AnyDatabaseCancellable?

        /// Number of times this bridge has actually started the underlying
        /// GRDB observation. Must be 0 for a bridge whose stream is never
        /// iterated, and at most 1 for the lifetime of one bridge (one
        /// `stream()` call is one independent, single-consumer observation).
        var startCount = 0

        /// Set by `cancel()`, checked by `storeCancellable(_:)`: closes the
        /// race where `cancel()` runs after `startObservation(...)` returns a
        /// fresh `AnyDatabaseCancellable` but before `storeCancellable(_:)`
        /// stores it. Without this, `cancel()` would read `cancellable ==
        /// nil` and cancel nothing, while `storeCancellable(_:)` would then
        /// store the new observation anyway -- leaking a live GRDB
        /// observation nothing would ever cancel.
        var didCancel = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    private let mailbox = SingleSlotMailbox<Value>()

    private let startObservation: (
        @escaping (Error) -> Void,
        @escaping (Value) -> Void
    ) -> AnyDatabaseCancellable

    init(
        start: @escaping (
            @escaping (Error) -> Void,
            @escaping (Value) -> Void
        ) -> AnyDatabaseCancellable
    ) {
        self.startObservation = start
    }

    var totalYieldCount: Int { mailbox.totalYieldCount }

    /// Suspends until the underlying observation has produced a value satisfying `isExpected`,
    /// whether or not a consumer has pulled it yet.
    func waitForYield(satisfying isExpected: @escaping (Value) -> Bool) async {
        await mailbox.waitForYield(satisfying: isExpected)
    }

    var startCount: Int { state.withLock { $0.startCount } }

    /// Synchronous locked mutation kept out of `next()`'s `async` body (see
    /// the equivalent note on `SingleSlotMailbox`). Returns `true` exactly
    /// once, for the call that must actually start the GRDB observation.
    private func claimStart() -> Bool {
        state.withLock { state in
            guard !state.didStart else { return false }
            state.didStart = true
            state.startCount += 1
            return true
        }
    }

    /// Stores `newCancellable`, unless `cancel()` already ran and missed it
    /// (see `State.didCancel`), in which case this cancels `newCancellable`
    /// itself instead of storing it -- mirroring the identical check-after-
    /// store pattern the production `GRDBLiveQueryAsyncBridge` (#308) and
    /// `XLRequestPublisherAsyncBridge` (#309) use for the same race.
    // See the `nonisolated(unsafe)` shadow note on `SingleSlotMailbox.yield(_:)` above -- identical
    // reasoning, applied to a GRDB `AnyDatabaseCancellable` captured by this file's `@Sendable`
    // locked-state closure.
    private func storeCancellable(_ newCancellable: AnyDatabaseCancellable) {
        #if compiler(>=6.0)
        nonisolated(unsafe) let newCancellable = newCancellable
        #endif
        let alreadyCancelled: Bool = state.withLock { state in
            guard !state.didCancel else { return true }
            state.cancellable = newCancellable
            return false
        }
        if alreadyCancelled {
            newCancellable.cancel()
        }
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
        let existing: AnyDatabaseCancellable? = state.withLock { state in
            state.didStart = true
            state.didCancel = true
            let existing = state.cancellable
            state.cancellable = nil
            return existing
        }
        existing?.cancel()
        mailbox.cancel()
    }

    /// The publicly-shaped return type #308 must expose. Constructing this
    /// value performs no database work: only the first `next()` call (i.e.
    /// the first iteration attempt, whether via `for try await` or a manual
    /// `makeAsyncIterator().next()`) starts the GRDB observation.
    ///
    /// The closure captures `self` strongly, matching `GRDBLiveQueryAsyncBridge.stream()`. That is
    /// not incidental: `AsyncThrowingStream`'s own `unfolding` wrapper resolves to `nil` *without
    /// calling this closure* when the consuming task is already cancelled, and it releases the
    /// closure at the same time. For the production bridge that release is what tears the
    /// observation down -- the stream is the bridge's only owner, so the bridge deinits and its
    /// `AnyDatabaseCancellable` cancels on deinit. A `[weak self]` capture here broke that model:
    /// a cancellation landing *between* two `next()` calls never reached the bridge (the closure
    /// was never entered) and never released it either, so the observation kept fetching. That is
    /// issue #541, seen first as a 1-in-50 failure of
    /// `testCancellingTheConsumingTaskCancelsTheUnderlyingObservation`.
    ///
    /// No retain cycle: the bridge holds no reference back to the stream.
    func stream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(unfolding: {
            try await self.next()
        })
    }
}


/// Minimal demand-aware puller validating the #309 async-to-Combine demand
/// mapping: pulls from the bridge exactly once per unit of granted demand,
/// never ahead of demand, and never through a second unbounded queue.
private final class DemandDrivenPuller<Value>: @unchecked Sendable {

    private let bridge: LazyBufferedGRDBBridge<Value>

    private struct State {
        var remainingDemand = 0
        var isPulling = false
        var isFinished = false

        /// Set by an explicit `cancel()`, distinct from `isFinished` alone:
        /// lets an in-flight `pumpNext()` tell "the bridge legitimately
        /// completed or failed" apart from "this puller was cancelled," so
        /// cancellation never surfaces through `onFinish` -- mirroring how
        /// cancelling a Combine subscription never delivers a
        /// `.finished`/`.failure` completion.
        var wasCancelled = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

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
        let shouldStartPulling: Bool = state.withLock { state in
            guard !state.isFinished else {
                return false
            }
            state.remainingDemand += amount
            let shouldStart = !state.isPulling && state.remainingDemand > 0
            if shouldStart {
                state.isPulling = true
            }
            return shouldStart
        }
        if shouldStartPulling {
            pumpNext()
        }
    }

    func cancel() {
        state.withLock { state in
            state.isFinished = true
            state.wasCancelled = true
        }
        bridge.cancel()
    }

    private func pumpNext() {
        Task {
            do {
                guard let value = try await bridge.next() else {
                    if markFinished() {
                        onFinish(nil)
                    }
                    return
                }
                // `bridge.next()` can resolve with an already-in-flight value
                // at almost the same instant `cancel()` runs; re-check right
                // before delivery so that narrow race cannot hand a value to
                // a consumer that has already unsubscribed.
                guard isStillAcceptingDelivery() else {
                    return
                }
                onValue(value)
                if decrementDemandAndCheckWhetherToContinue() {
                    pumpNext()
                }
            }
            catch {
                if markFinished() {
                    onFinish(error)
                }
            }
        }
    }

    /// Synchronous locked mutation extracted out of the `async` `pumpNext`
    /// body, matching the equivalent split used elsewhere in this file.
    ///
    /// - Returns: `true` if `onFinish` should be delivered for this
    ///   termination, `false` if an explicit `cancel()` already fired (or
    ///   raced this call) and the completion must be suppressed.
    @discardableResult
    private func markFinished() -> Bool {
        state.withLock { state in
            let shouldDeliver = !state.wasCancelled
            state.isFinished = true
            state.isPulling = false
            return shouldDeliver
        }
    }

    /// Narrows, but cannot fully close, the window between `bridge.next()`
    /// resolving with a value and `onValue` being called: if `cancel()` won
    /// that race, this returns `false` so the value is dropped instead of
    /// reaching a consumer that already unsubscribed.
    private func isStillAcceptingDelivery() -> Bool {
        state.withLock { !$0.wasCancelled }
    }

    private func decrementDemandAndCheckWhetherToContinue() -> Bool {
        state.withLock { state in
            state.remainingDemand -= 1
            let shouldContinue = state.remainingDemand > 0 && !state.isFinished
            if !shouldContinue {
                state.isPulling = false
            }
            return shouldContinue
        }
    }
}


private final class LockedCounter: @unchecked Sendable {

    private let state = OSAllocatedUnfairLock(initialState: 0)

    @discardableResult
    func increment() -> Int {
        state.withLock { value in
            value += 1
            return value
        }
    }

    func read() -> Int {
        state.withLock { $0 }
    }
}


/// Backed by ``XLAwaitableState`` (`XLLiveQueryWaitSupport.swift`), so a test awaits the appends it
/// needs and is resumed by the append itself.
///
/// The previous version was polled by a `waitForCount` helper that created one `XCTestExpectation`
/// per attempt and waited on it with a 0.2s timeout, up to 200 times per call. Under load those
/// waits time out while the value is merely late, and the `asyncAfter` block that fulfils an
/// already-timed-out expectation is an XCTest API violation -- one of the two candidate mechanisms
/// for the `Index out of range` crash recorded on #533.
private final class LockedArray<Element>: @unchecked Sendable {

    private let state = XLAwaitableState<[Element]>([])

    func append(_ value: Element) {
        state.withValue { $0.append(value) }
    }

    func read() -> [Element] {
        state.read()
    }

    /// Suspends until at least `count` elements have been appended.
    func wait(untilCountIsAtLeast count: Int) async {
        await state.wait(untilCountIsAtLeast: count)
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

    /// Cancellation that lands *between* two `next()` calls must still stop the observation.
    ///
    /// The consumer parks in the loop body rather than inside `next()`, so this is the case
    /// `AsyncThrowingStream`'s `unfolding` wrapper short-circuits: it resolves the next iteration to
    /// `nil` without ever calling the bridge, so the bridge's own
    /// `withTaskCancellationHandler(onCancel:)` never fires. What stops the observation instead is
    /// the release of the unfolding closure -- the stream is the bridge's only owner, so the bridge
    /// deinits and its `AnyDatabaseCancellable` cancels. Issue #541: while the prototype's
    /// `stream()` captured `self` weakly, nothing tore it down on this path and the observation
    /// kept fetching, which is what made
    /// `testCancellingTheConsumingTaskCancelsTheUnderlyingObservation` fail roughly 1 run in 50.
    func testCancellationBetweenNextCallsStillCancelsTheObservation() async throws {
        let fetchCounter = LockedCounter()
        // The stream is deliberately the bridge's only owner, exactly as in production
        // (`GRDBRequest.stream()` hands its bridge straight to the returned stream).
        let stream = makeBridge(fetchProbe: { fetchCounter.increment() }).stream()
        let firstValue = XLAwaitableValue<Bool>()
        let resumeLoopBody = XLAwaitableValue<Bool>()
        let loopEnded = XLAwaitableValue<Bool>()

        let task = Task {
            do {
                for try await _ in stream {
                    firstValue.fulfill(true)
                    // Parking here, rather than inside `next()`, is the whole point of this test.
                    _ = await resumeLoopBody.wait()
                }
            }
            catch {
                XCTFail("Unexpected stream error: \(error)")
            }
            loopEnded.fulfill(true)
        }

        _ = await firstValue.wait()
        task.cancel()
        resumeLoopBody.fulfill(true)
        _ = await loopEnded.wait()

        let fetchCountAtCancel = fetchCounter.read()
        try insert("after-cancel-between-next", 99)
        await xlDrainMainQueue()
        XCTAssertEqual(
            fetchCounter.read(),
            fetchCountAtCancel,
            "A write after cancellation must not fetch, even when the cancellation landed between "
                + "two next() calls."
        )
        // Holds the stream -- and so the bridge -- past the assertion. Without this, ARC is free to
        // release it once the consuming task has ended, and the test would pass because the bridge
        // deallocated rather than because cancellation tore the observation down.
        withExtendedLifetime(stream) {}
    }

    func testCancellingTheConsumingTaskCancelsTheUnderlyingObservation() async throws {
        let fetchCounter = LockedCounter()
        // As in production, the stream owns the bridge (see `stream()`'s note): holding a separate
        // strong reference here would keep the observation alive past a cancellation that landed
        // between two `next()` calls, which is issue #541.
        let stream = makeBridge(fetchProbe: { fetchCounter.increment() }).stream()
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

        await seen.wait(untilCountIsAtLeast: 1)
        task.cancel()
        await fulfillment(of: [loopExpectation], timeout: 2)
        XCTAssertEqual(seen.read(), [0])

        let fetchCountAtCancel = fetchCounter.read()
        try insert("after-task-cancel", 99)
        await xlDrainMainQueue()
        XCTAssertEqual(
            fetchCounter.read(),
            fetchCountAtCancel,
            "Cancelling the consuming task must cancel the underlying GRDB observation."
        )
        // See the note in testCancellationBetweenNextCallsStillCancelsTheObservation: the stream
        // must outlive the assertion, or a pass proves deallocation rather than cancellation.
        withExtendedLifetime(stream) {}
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

    func testDemandDrivenPullerConsumesExactlyDemandedCountWithoutEagerDraining() async throws {
        let bridge = makeBridge()
        let delivered = LockedArray<Int>()
        let puller = DemandDrivenPuller(
            bridge: bridge,
            onValue: { delivered.append($0) },
            onFinish: { _ in }
        )

        // Zero demand: the puller must not touch the bridge at all.
        await xlDrainMainQueue()
        XCTAssertEqual(bridge.startCount, 0, "Zero demand must not start the observation.")
        XCTAssertEqual(delivered.read(), [])

        // Grant demand for exactly one value.
        puller.requestDemand(1)
        await delivered.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(delivered.read(), [0])

        // Multiple rapid writes while demand is exhausted (zero outstanding):
        // the puller must not pull ahead of demand. The bridge observes
        // `COUNT(*)`, so two inserts into this fresh table move the row
        // count from 0 to 2 (the `value` columns, 1 and 2, are unrelated to
        // the observed count).
        try insert("a", 1)
        try insert("b", 2)
        // Wait for the observation to have actually produced the state after
        // *both* commits. GRDB fetches on a reader queue and only then
        // dispatches to main, so a main-queue barrier says nothing about
        // whether the second commit has been fetched yet: under load it often
        // has not, the mailbox still holds the snapshot for the first insert,
        // and resuming demand correctly delivered `1` rather than `2` (#533).
        // How many fetches those two commits coalesce into is GRDB's business
        // and deliberately not asserted -- only that the newest value the
        // mailbox holds is the final one before demand resumes.
        await bridge.waitForYield(satisfying: { $0 == 2 })
        XCTAssertEqual(
            delivered.read(),
            [0],
            "With no demand outstanding, the puller must not deliver further values."
        )

        // Resuming demand delivers exactly one more value: the bridge's
        // single buffered "newest" snapshot, not a backlog of every write
        // that occurred while paused.
        puller.requestDemand(1)
        await delivered.wait(untilCountIsAtLeast: 2)
        XCTAssertEqual(delivered.read(), [0, 2])

        puller.cancel()
    }

    func testUnlimitedDemandDeliversAsValuesBecomeAvailableWithoutSpinningOrDoubleDelivery() async throws {
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
        await delivered.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(delivered.read(), [0])

        // The bridge observes `COUNT(*)`, so one insert into this fresh
        // table moves the row count from 0 to 1 (the inserted row's own
        // `value` column, 42, is unrelated to the observed count).
        try insert("x", 42)
        await delivered.wait(untilCountIsAtLeast: 2)
        XCTAssertEqual(delivered.read(), [0, 1])

        // No further writes: the puller must not spin, error, or duplicate
        // delivery while waiting for the next relevant commit.
        await xlDrainMainQueue()
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

}


private final class LockedValueBox<Value>: @unchecked Sendable {

    private let state: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        state = OSAllocatedUnfairLock(uncheckedState: value)
    }

    // See the `nonisolated(unsafe)` shadow note on `SingleSlotMailbox.yield(_:)` above -- identical
    // reasoning.
    func set(_ newValue: Value) {
        #if compiler(>=6.0)
        nonisolated(unsafe) let newValue = newValue
        #endif
        state.withLock { $0 = newValue }
    }

    // See the `ElementsBox` note on `LockedArray.read()` above -- identical reasoning.
    private struct ValueBox: @unchecked Sendable {
        let value: Value
    }

    func get() -> Value {
        state.withLock { ValueBox(value: $0) }.value
    }
}
