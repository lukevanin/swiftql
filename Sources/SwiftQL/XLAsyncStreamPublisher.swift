//
//  XLAsyncStreamPublisher.swift
//

import Dispatch
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif


/// Combine convenience adapter over SwiftQL's canonical async live-query streams (issue #308),
/// selected for `XLRequest.publish()`/`publishOne()` (and their `bindings:` variants) by issue #309.
///
/// Combine owns only subscription, demand accounting, delivery, completion, and cancellation
/// adaptation here. Database observation, immutable-packet capture, retry, decoding, and buffering
/// (issue #291's bound-1 "newest wins" policy) all come from the `AsyncThrowingStream` `makeStream`
/// produces -- in production, `GRDBRequest.stream()`/`streamOne()` (or their `bindings:` variants).
/// This type never calls `ValueObservation.publisher(in:)`, never owns a Combine-side retry pipeline,
/// and never shares one stream, iterator, or buffered snapshot across subscribers.
///
/// `makeStream` is invoked exactly once per `Subscription` -- once per Combine subscriber -- and only
/// the first time that subscriber grants positive demand: never at `Publisher` construction, and never
/// merely because something subscribed. This mirrors #308's "observation begins with iteration" rule:
/// building this publisher, and even subscribing to it with zero demand, performs no database work.
struct XLAsyncStreamPublisher<Value>: Publisher {

    typealias Output = Value

    typealias Failure = Error

    private let makeStream: () -> AsyncThrowingStream<Value, Error>

    init(makeStream: @escaping () -> AsyncThrowingStream<Value, Error>) {
        self.makeStream = makeStream
    }

    func receive<S>(subscriber: S) where S: Subscriber, S.Input == Value, S.Failure == Error {
        let subscription = XLAsyncStreamSubscription(downstream: subscriber, makeStream: makeStream)
        subscriber.receive(subscription: subscription)
    }
}


/// Wraps `makeStream` as an `AnyPublisher` with SwiftQL's documented main-queue delivery default
/// (`Sources/SwiftQL/SwiftQL.docc/LiveQueries.md`, "Observation Semantics"): "Initial and updated
/// values are delivered asynchronously on the main dispatch queue by default."
///
/// Composing the stock `.receive(on:)` operator on top of ``XLAsyncStreamPublisher`` is deliberate --
/// it reuses Combine's own, already-correct demand-preserving scheduling instead of reimplementing
/// queue-hopping inside the subscription itself, which would need to duplicate `.receive(on:)`'s
/// backpressure bookkeeping for no benefit. ``XLAsyncStreamSubscription`` therefore stays thread-
/// agnostic: it delivers on whatever thread its consumer `Task` runs on, and `.receive(on:)` is the
/// only thing that reschedules delivery onto the main queue.
func xlLiveQueryPublisher<Value>(
    makeStream: @escaping () -> AsyncThrowingStream<Value, Error>
) -> AnyPublisher<Value, Error> {
    XLAsyncStreamPublisher(makeStream: makeStream)
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}


/// The `Subscription` half of ``XLAsyncStreamPublisher``: owns one demand-gated consumer `Task` that
/// pulls from one independently-constructed `AsyncThrowingStream`, translating Combine's pull-based
/// demand model into calls to the stream's `next()`. See #291's "Async-to-Combine demand mapping"
/// contract (`Sources/SwiftQL/SwiftQL.docc/LiveQueries.md`), which this implements:
///
/// - **Zero demand**: the consumer `Task` is not started. `request(_:)` starts it lazily, and only
///   once, on the first call that raises demand above zero.
/// - **Incremental demand**: the consumer task calls the stream iterator's `next()` exactly once per
///   unit of granted demand, decrementing `remainingDemand` immediately before each call. It never
///   calls `next()` ahead of outstanding demand, and never buffers read-ahead of its own on top of
///   whatever buffering the stream itself already does.
/// - **Unlimited demand**: the loop never runs out of demand to consume, so it pulls as fast as the
///   stream can produce -- rate-limited by the stream's own bounded buffer and fetch cadence, not by a
///   second unbounded queue here.
/// - **Demand granted from `receive(_:)`**: added directly to `remainingDemand`; no separate mechanism
///   is needed, since the next loop iteration (or a currently-suspended wait) simply observes it.
///
/// Cancellation is the one place this type deliberately behaves differently from a plain forward-
/// everything bridge:
/// - `cancel()` sets `isCancelled` (and releases the stored `downstream` reference) *before* cancelling
///   the consumer `Task`. If that task is currently suspended inside the stream's own `next()`, the
///   cancellation reaches the stream's own cancellation handling (see `GRDBLiveQueryAsyncBridge`/
///   `XLSingleSlotAsyncBuffer`, or `AsyncThrowingStream`'s own continuation-based cancellation), which
///   resolves `next()` to `nil` -- ordinarily indistinguishable from a real, non-cancelled end of
///   iteration. `finish(error:)` below checks `isCancelled` and suppresses the completion in exactly
///   that self-inflicted case, so cancelling a subscription never manifests as a spurious
///   `.finished`/`.failure` completion to the downstream subscriber.
/// - This is unrelated to, and does not change, the stream's own #291 buffering rule that a value
///   legitimately produced and buffered before termination must still be delivered before iteration
///   ends. If such a value races ahead of cancellation and the stream's `next()` still returns it to
///   this subscription, ``deliver(_:)`` independently checks `isCancelled` first and drops it, because
///   Combine's own contract is that nothing may reach a subscriber after it calls `cancel()` --
///   regardless of what the underlying stream still yields afterward.
private final class XLAsyncStreamSubscription<Downstream>: Subscription, @unchecked Sendable
where Downstream: Subscriber, Downstream.Failure == Error {

    private let lock = NSLock()

    private var downstream: Downstream?

    private let makeStream: () -> AsyncThrowingStream<Downstream.Input, Error>

    private var task: Task<Void, Never>?

    private var remainingDemand: Subscribers.Demand = .none

    private var demandWaiter: CheckedContinuation<Bool, Never>?

    private var isCancelled = false

    private var didFinish = false

    init(
        downstream: Downstream,
        makeStream: @escaping () -> AsyncThrowingStream<Downstream.Input, Error>
    ) {
        self.downstream = downstream
        self.makeStream = makeStream
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        remainingDemand += demand
        // Handing off to a stalled waiter consumes exactly one unit of the demand just granted --
        // mirroring `resolveDemandOrRegister(_:)`'s own immediate-availability branch -- so the waiter
        // resumes having *already* accounted for the pull it is about to make. Forgetting this
        // decrement here previously left `remainingDemand` one unit too high, letting the next loop
        // iteration's fast path grant a second, unrequested pull immediately afterward.
        var waiterToResume: CheckedContinuation<Bool, Never>?
        if let waiter = demandWaiter, remainingDemand > .none {
            remainingDemand -= 1
            demandWaiter = nil
            waiterToResume = waiter
        }
        let needsStart = task == nil
        lock.unlock()

        waiterToResume?.resume(returning: true)
        if needsStart {
            startConsumerTaskIfNeeded()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        downstream = nil
        let waiter = demandWaiter
        demandWaiter = nil
        let existingTask = task
        lock.unlock()

        // Resume a stalled demand wait with `false` (no `next()` was ever pending on the stream for
        // it), then cancel the consumer task so any `next()` call it *is* currently suspended in tears
        // down the underlying observation promptly.
        waiter?.resume(returning: false)
        existingTask?.cancel()
    }

    private func startConsumerTaskIfNeeded() {
        lock.lock()
        guard task == nil, !isCancelled else {
            lock.unlock()
            return
        }
        let newTask = Task {
            await self.runLoop()
        }
        task = newTask
        lock.unlock()
    }

    private func runLoop() async {
        let stream = makeStream()
        var iterator = stream.makeAsyncIterator()
        while await waitForDemandUnit() {
            do {
                guard let value = try await iterator.next() else {
                    finish(error: nil)
                    return
                }
                deliver(value)
            }
            catch {
                finish(error: error)
                return
            }
        }
        // `waitForDemandUnit()` returned `false`: this subscription was cancelled while waiting for
        // demand, before calling `next()` again. No completion is forwarded here -- `cancel()` already
        // released `downstream`, and any completion produced by cancelling mid-`next()` is separately
        // suppressed by `finish(error:)`'s own `isCancelled` check.
    }

    private enum DemandFastPathOutcome {
        case proceed
        case cancelled
        case pending
    }

    /// Locked, non-`async` fast-path check, kept out of `waitForDemandUnit()`'s `async` body: recent
    /// Foundation marks `NSLock.lock()`/`unlock()` unavailable directly inside an asynchronous context
    /// (an error under the Swift 6 language mode), matching the same split already used by
    /// ``XLSingleSlotAsyncBuffer``.
    private func checkDemandFastPath() -> DemandFastPathOutcome {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            return .cancelled
        }
        if remainingDemand > .none {
            remainingDemand -= 1
            return .proceed
        }
        return .pending
    }

    /// Re-checks and, if still pending, registers the continuation as the single outstanding waiter,
    /// all inside one locked critical section. This must not be split into a separate check-then-
    /// register pair of locked calls: demand granted from another thread in the gap between them would
    /// otherwise be lost, exactly like the equivalent note on
    /// ``XLSingleSlotAsyncBuffer/resolveImmediatelyOrRegister(_:)``.
    private func resolveDemandOrRegister(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(returning: false)
            return
        }
        if remainingDemand > .none {
            remainingDemand -= 1
            lock.unlock()
            continuation.resume(returning: true)
            return
        }
        precondition(
            demandWaiter == nil,
            "XLAsyncStreamSubscription's consumer loop must be single-threaded: a second concurrent "
                + "wait would silently overwrite and leak/hang the first waiter."
        )
        demandWaiter = continuation
        lock.unlock()
    }

    /// Suspends until either one unit of demand is available (consuming it and returning `true`) or
    /// this subscription is cancelled (returning `false`). Never itself calls the stream's `next()` --
    /// pulling exactly once per unit of granted demand is `runLoop()`'s job.
    private func waitForDemandUnit() async -> Bool {
        switch checkDemandFastPath() {
        case .proceed:
            return true
        case .cancelled:
            return false
        case .pending:
            return await withCheckedContinuation { continuation in
                resolveDemandOrRegister(continuation)
            }
        }
    }

    /// Forwards one value downstream, honoring Combine's "nothing after `cancel()`" contract even if
    /// the value raced ahead of a concurrent cancellation and the stream still handed it to `runLoop()`.
    private func deliver(_ value: Downstream.Input) {
        lock.lock()
        guard !isCancelled, let downstream else {
            lock.unlock()
            return
        }
        lock.unlock()

        let additionalDemand = downstream.receive(value)
        guard additionalDemand > .none else { return }

        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        remainingDemand += additionalDemand
        lock.unlock()
    }

    /// Forwards the stream's terminal outcome exactly once -- unless this subscription's own
    /// `cancel()` is what caused the stream to end, in which case the completion is suppressed
    /// entirely. See this type's doc comment for why that is the one deliberate exception to
    /// "forward the stream's values, error, and completion exactly once."
    private func finish(error: Error?) {
        lock.lock()
        guard !isCancelled, !didFinish, let downstream else {
            lock.unlock()
            return
        }
        didFinish = true
        self.downstream = nil
        lock.unlock()

        if let error {
            downstream.receive(completion: .failure(error))
        }
        else {
            downstream.receive(completion: .finished)
        }
    }
}
