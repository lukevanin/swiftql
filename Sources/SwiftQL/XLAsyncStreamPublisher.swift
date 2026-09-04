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


#if DEBUG
/// The lifecycle transitions of `XLAsyncStreamSubscription`'s consumer loop that a test can observe
/// through ``XLAsyncStreamSubscriptionTestHooks`` instead of polling or sleeping. Each case names a
/// point that already exists in the loop's control flow (issue #465) -- observing it changes nothing
/// about demand accounting, cancellation suppression, or delivery ordering.
enum XLAsyncStreamSubscriptionEvent: Sendable, Equatable {
    /// The consumer `Task` has started and passed its post-spawn cancellation re-check.
    case consumerTaskStarted
    /// `makeStream()` has been called and the iterator exists.
    case streamCreated
    /// `resolveDemandOrRegister` took the `.pending` path and registered a demand waiter.
    case demandWaiterRegistered
    /// A demand unit was consumed and the loop is about to call `next()`.
    case demandUnitConsumed
    /// `deliver(_:)` completed, including the downstream `receive(_:)` callback.
    case delivered
    /// `finish(error:)` ran: `forwarded` is `true` if it called `receive(completion:)`, `false` if it
    /// suppressed the outcome (already cancelled, already finished, or no downstream left).
    case finished(forwarded: Bool)
}

/// Test-only observation of every `XLAsyncStreamSubscription`'s lifecycle transitions, process-wide.
/// Not part of SwiftQL's public API: this type has no explicit access modifier, so it is `internal`
/// and reachable only via `@testable import SwiftQL`. `#if DEBUG`-gated, so it and every call site
/// that reports to it compile away entirely in a release build -- there is no synchronization for
/// production to pay when no observer is attached, and none of it exists at all outside DEBUG.
///
/// Global rather than per-instance because `Subscription` erases `XLAsyncStreamSubscription` behind
/// the `Combine.Subscription` existential the moment it is vended, so no test call site ever holds a
/// concrete reference to configure a hook on. Tests that care about ordering across multiple
/// concurrent subscriptions can still discriminate by the sequence/shape of events observed; tests
/// are responsible for calling ``reset()`` (e.g. in `tearDown`) so one test's observers don't leak
/// into the next.
final class XLAsyncStreamSubscriptionTestHooks: @unchecked Sendable {

    static let shared = XLAsyncStreamSubscriptionTestHooks()

    private let lock = NSLock()

    private var continuations: [UUID: AsyncStream<XLAsyncStreamSubscriptionEvent>.Continuation] = [:]

    private init() {}

    /// Vends a fresh `AsyncStream` of every subscription's lifecycle events from this call onward.
    func events() -> AsyncStream<XLAsyncStreamSubscriptionEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// Finishes every currently-vended stream and forgets all observers.
    func reset() {
        lock.lock()
        let pending = continuations
        continuations = [:]
        lock.unlock()
        for continuation in pending.values {
            continuation.finish()
        }
    }

    fileprivate func emit(_ event: XLAsyncStreamSubscriptionEvent) {
        lock.lock()
        let observers = Array(continuations.values)
        lock.unlock()
        for observer in observers {
            observer.yield(event)
        }
    }
}
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

    // Recursive, not plain `NSLock`: `deliver(_:)` and `finish(error:)` hold this
    // lock across the downstream `receive(_:)`/`receive(completion:)` call itself
    // (see their doc comments), and Combine subscribers are allowed to call
    // `cancel()` synchronously and reentrantly from inside that very callback --
    // exactly what `XLAsyncStreamPublisherTests` exercises. A plain `NSLock`
    // would deadlock that reentrant call; `NSRecursiveLock` lets the same thread
    // re-enter while still serializing genuinely concurrent (different-thread)
    // cancellation against delivery.
    private let lock = NSRecursiveLock()

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

    private func isCancelledNow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func runLoop() async {
        // `startConsumerTaskIfNeeded()` already checked `!isCancelled` before creating this
        // task, but creating a `Task` and that task's first statement actually running are
        // not atomic: `cancel()` can still land in between. Re-checking here, before calling
        // `makeStream()`, avoids doing real work -- for the production `makeStream` (backed
        // by `GRDBRequest.stream()`/`streamOne()`), that includes packet validation and
        // bridge construction -- for a subscription already known to be cancelled, rather
        // than only catching it one step later inside `waitForDemandUnit()`.
        guard !isCancelledNow() else {
            return
        }
        #if DEBUG
        XLAsyncStreamSubscriptionTestHooks.shared.emit(.consumerTaskStarted)
        #endif
        let stream = makeStream()
        var iterator = stream.makeAsyncIterator()
        #if DEBUG
        XLAsyncStreamSubscriptionTestHooks.shared.emit(.streamCreated)
        #endif
        while await waitForDemandUnit() {
            #if DEBUG
            XLAsyncStreamSubscriptionTestHooks.shared.emit(.demandUnitConsumed)
            #endif
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
        #if DEBUG
        XLAsyncStreamSubscriptionTestHooks.shared.emit(.demandWaiterRegistered)
        #endif
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
    ///
    /// Holds `lock` across `downstream.receive(_:)` itself, not just the state check before it: a plain
    /// check-then-unlock-then-call would leave a window where a `cancel()` racing in from another thread
    /// -- or even called synchronously and reentrantly from inside this very `receive(_:)` callback, as
    /// this type's own tests do -- could flip `isCancelled` in the gap and still let this value reach
    /// downstream. Serializing the whole call against `cancel()` (via the recursive lock) means either
    /// this delivery completes in full before `cancel()`'s state change takes effect, or `cancel()` has
    /// already taken effect before this delivery starts -- never a torn state in between.
    private func deliver(_ value: Downstream.Input) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, let downstream else {
            return
        }
        let additionalDemand = downstream.receive(value)
        #if DEBUG
        XLAsyncStreamSubscriptionTestHooks.shared.emit(.delivered)
        #endif
        guard !isCancelled, additionalDemand > .none else {
            return
        }
        remainingDemand += additionalDemand
    }

    /// Forwards the stream's terminal outcome exactly once -- unless this subscription's own
    /// `cancel()` is what caused the stream to end, in which case the completion is suppressed
    /// entirely. See this type's doc comment for why that is the one deliberate exception to
    /// "forward the stream's values, error, and completion exactly once."
    ///
    /// Holds `lock` across `downstream.receive(completion:)` for the same reason ``deliver(_:)`` holds
    /// it across `downstream.receive(_:)`: serializing delivery against a concurrent `cancel()` closes
    /// the same race for the terminal event.
    private func finish(error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, !didFinish, let downstream else {
            #if DEBUG
            XLAsyncStreamSubscriptionTestHooks.shared.emit(.finished(forwarded: false))
            #endif
            return
        }
        didFinish = true
        self.downstream = nil
        if let error {
            downstream.receive(completion: .failure(error))
        }
        else {
            downstream.receive(completion: .finished)
        }
        #if DEBUG
        XLAsyncStreamSubscriptionTestHooks.shared.emit(.finished(forwarded: true))
        #endif
    }
}
