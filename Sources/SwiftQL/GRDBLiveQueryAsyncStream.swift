#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import Foundation
import GRDB


/// Bridges a raw GRDB `ValueObservation` into SwiftQL's canonical,
/// lazily-started, single-slot ("newest wins") buffered async live-query
/// source (issue #308), implementing the buffering, cancellation, and
/// snapshot-ownership contract recorded at
/// `Sources/SwiftQL/SwiftQL.docc/LiveQueries.md`, "Buffering and
/// Resumed-Demand Semantics (#291)".
///
/// This is the type `GRDBRequest.stream()`/`streamOne()` (and their bindings
/// variants) build on. It intentionally does not use Combine, `AnyPublisher`,
/// or `.values` as its observation source — only GRDB's own
/// `ValueObservation.start(in:scheduling:onError:onChange:)`, the same
/// primitive ``GRDBLiveQueryRetryPolicy`` already uses for the Combine path.
///
/// Retry reuses ``GRDBLiveQueryRetryState`` (the exact generation-counter
/// cancellation-ownership design the Combine retry attempt runner in
/// `GRDBLiveQueryRetryPolicy.swift` already uses) and ``GRDBLiveQueryRetryScheduler``
/// (the exact delay seam that scheduler's deterministic tests already drive),
/// so this bridge does not fork a second retry engine, and any future adapter
/// (e.g. #309's Combine adapter) sharing this bridge inherits the identical
/// retry budget and delay semantics without reimplementing them.
///
/// Each bridge owns exactly one independent observation and one single-slot
/// buffer: constructing a bridge (or calling ``stream()`` on it) performs no
/// database work. Only the first consumer pull — the first `next()` call
/// reaching this bridge, whether through a manual iterator or a `for try
/// await` loop over the returned `AsyncThrowingStream` — starts the
/// underlying GRDB observation. This is verified explicitly by
/// `GRDBLiveQueryAsyncStreamTests.testUnusedStreamPerformsNoObservationOrFetch`.
final class GRDBLiveQueryAsyncBridge<Value>: @unchecked Sendable {

    typealias Start = (
        @escaping (Error) -> Void,
        @escaping (Value) -> Void
    ) -> AnyDatabaseCancellable

    private let lock = NSLock()

    private var didStart = false

    private var cancellable: AnyDatabaseCancellable?

    private var pendingDelayCancellable: AnyCancellable?

    private let buffer = XLSingleSlotAsyncBuffer<Value>()

    private let retryState: GRDBLiveQueryRetryState

    private let scheduler: GRDBLiveQueryRetryScheduler

    private let makeSource: Start

    init(
        policy: GRDBLiveQueryRetryPolicy,
        scheduler: GRDBLiveQueryRetryScheduler,
        makeSource: @escaping Start
    ) {
        self.retryState = GRDBLiveQueryRetryState(policy: policy)
        self.scheduler = scheduler
        self.makeSource = makeSource
    }

    /// Synchronous locked mutation kept out of `next()`'s `async` body (see
    /// the equivalent note on ``XLSingleSlotAsyncBuffer``). Returns `true`
    /// exactly once, for the call that must actually start the first GRDB
    /// observation attempt.
    private func claimStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didStart else { return false }
        didStart = true
        return true
    }

    private func storeCancellable(_ newCancellable: AnyDatabaseCancellable?) {
        lock.lock()
        cancellable = newCancellable
        lock.unlock()
    }

    private func storePendingDelay(_ newCancellable: AnyCancellable?) {
        lock.lock()
        pendingDelayCancellable = newCancellable
        lock.unlock()
    }

    func next() async throws -> Value? {
        // The start decision lives *inside* `operation`, not before this
        // call: if the consuming `Task` is already cancelled at this point,
        // Swift guarantees `onCancel` runs before `operation` starts
        // executing, so `cancel()` (and therefore `retryState.cancel()`)
        // completes first. `beginAttempt()` then correctly sees an already-
        // cancelled `retryState` and starts no observation at all, instead
        // of starting one and cancelling it a moment later.
        return try await withTaskCancellationHandler(
            operation: {
                if claimStart() {
                    beginAttempt()
                }
                return try await buffer.next()
            },
            onCancel: { [weak self] in self?.cancel() }
        )
    }

    /// Starts one fresh, protected GRDB observation attempt under a new
    /// retry generation. Reentrant via ``scheduleRetry(after:generation:)``
    /// below: a qualifying BUSY failure schedules another call to this
    /// method after the policy's backoff. Any callback from a superseded
    /// generation is dropped by `retryState`, so attempts never overlap.
    private func beginAttempt() {
        guard let generation = retryState.beginAttempt() else {
            // Cancelled before this attempt ever started (e.g. cancellation
            // raced the very first `next()` call, or arrived during backoff).
            buffer.cancel()
            return
        }
        let newCancellable = makeSource(
            { [weak self] error in self?.handleError(error, generation: generation) },
            { [weak self] value in self?.handleValue(value, generation: generation) }
        )
        storeCancellable(newCancellable)

        // `cancel()` may have run concurrently between `beginAttempt()`
        // succeeding above and `newCancellable` being stored — it would then
        // have read (and cleared) whatever was stored *before* this attempt,
        // never learning about this one. Re-checking the generation after
        // storing closes that race: if this attempt is already stale, cancel
        // what was just started and stored ourselves, mirroring the same
        // check-after-start pattern `GRDBOpenCombineValuePublisher.swift`
        // uses for the identical race on `request(_:)`.
        guard retryState.shouldDeliver(generation: generation) else {
            storeCancellable(nil)
            newCancellable.cancel()
            return
        }
    }

    private func handleValue(_ value: Value, generation: Int) {
        guard retryState.shouldDeliver(generation: generation) else { return }
        retryState.didDeliver(generation: generation)
        buffer.yield(value)
    }

    private func handleError(_ error: Error, generation: Int) {
        guard retryState.shouldDeliver(generation: generation) else { return }
        if let delay = retryState.retryDelay(after: error, generation: generation) {
            scheduleRetry(after: delay, generation: generation)
        }
        else {
            buffer.finish(throwing: error)
        }
    }

    /// Waits `delay` on the shared ``GRDBLiveQueryRetryScheduler`` seam
    /// before starting the next attempt. Cancelling the pending delay
    /// (`cancel()` below) stops this wait immediately rather than merely
    /// letting a fresh attempt no-op once the full delay eventually elapses,
    /// matching "cancelling during backoff cancels the pending delay and
    /// starts no new fetch."
    private func scheduleRetry(after delay: TimeInterval, generation: Int) {
        var delayCancellable: AnyCancellable?
        delayCancellable = scheduler.publisher(after: delay).sink(
            receiveCompletion: { [weak self] _ in
                self?.storePendingDelay(nil)
                self?.beginAttempt()
            },
            receiveValue: { _ in }
        )
        storePendingDelay(delayCancellable)

        // Same check-after-store race as `beginAttempt()`: `cancel()` may
        // have run between the guard in `handleError` and this store.
        guard retryState.shouldDeliver(generation: generation) else {
            storePendingDelay(nil)
            delayCancellable?.cancel()
            return
        }
    }

    /// Cancels the underlying GRDB observation, any pending retry backoff,
    /// and the buffer. Safe to call more than once, and safe to call whether
    /// or not `next()` was ever invoked.
    func cancel() {
        lock.lock()
        let existingObservation = cancellable
        let existingDelay = pendingDelayCancellable
        cancellable = nil
        pendingDelayCancellable = nil
        lock.unlock()

        retryState.cancel()
        existingDelay?.cancel()
        existingObservation?.cancel()
        buffer.cancel()
    }

    /// The publicly-shaped return type #308's methods must expose.
    /// Constructing this value performs no database work: only the first
    /// `next()` call (i.e. the first iteration attempt) starts the GRDB
    /// observation. Built with `AsyncThrowingStream`'s `unfolding:`
    /// initializer rather than its continuation-based
    /// `init(_:bufferingPolicy:_:)`, because that initializer runs its
    /// `build` closure eagerly at construction time — which would start GRDB
    /// observation before iteration begins.
    ///
    /// The `unfolding` closure captures `self` strongly, not weakly: this
    /// bridge is typically constructed and handed straight to `stream()`
    /// with no other owner (see `GRDBRequest.stream()`), so a weak capture
    /// would let it deallocate immediately after this call returns, before
    /// any consumer ever iterates — silently turning every stream into one
    /// that resolves to `nil` on its very first `next()`. The returned
    /// `AsyncThrowingStream` becomes this bridge's only owner from here on,
    /// and the bridge does not hold a reference back to the stream, so this
    /// creates no retain cycle: the bridge is released once the stream (and
    /// its iterator) are no longer referenced.
    func stream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(unfolding: {
            try await self.next()
        })
    }
}


/// Returns an `AsyncThrowingStream` that performs no work until its first
/// `next()` call, at which point it immediately throws `error` and finishes
/// -- unless the consuming `Task` is already cancelled, in which case it
/// resolves to `nil` instead, per the same cancellation contract every other
/// canonical stream honors: cancellation ends iteration with `nil`, never a
/// thrown error, `CancellationError` included. Used when a stream cannot be
/// constructed at all (an invalid invocation packet, a `RETURNING` request,
/// or a transaction-scoped driver with no pool to observe) — the
/// construction error must still be reported lazily, on first iteration, to
/// preserve "observation begins with iteration, not merely by constructing
/// an unused stream" for every code path, not only the successful one.
func xlFailingAsyncThrowingStream<Value>(_ error: Error) -> AsyncThrowingStream<Value, Error> {
    AsyncThrowingStream(unfolding: {
        guard !Task.isCancelled else {
            return nil
        }
        throw error
    })
}
