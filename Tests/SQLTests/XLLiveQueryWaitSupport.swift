//
//  XLLiveQueryWaitSupport.swift
//
//  Shared deterministic waiting for the live-query async suites (issue #467).
//
//  Before this file, three suites carried their own copy of the same `waitUntil` helper: a 5ms (or
//  10ms) poll loop against a 3s wall-clock cap, failing with `Condition not met within 3.0s` --
//  a message that named neither the condition nor the suite. Under load the cap expired while the
//  code under test was merely slow, which is the failure class issue #463 exists to remove.
//
//  What replaces it:
//
//  - ``XLAwaitableState`` -- a lock-protected value whose *mutations* resume waiters. A test waits
//    for the state it needs and is resumed by the write that produces it, so load can delay a test
//    but cannot change its verdict.
//  - ``XLAwaitableValue`` -- the one-shot form, for a callback that fires once.
//  - ``XLSubscriptionEventRecorder`` -- buffers `XLAsyncStreamSubscription`'s own lifecycle events
//    (the `#if DEBUG` seam from #465) so a test can await a named transition of the subject itself.
//  - ``xlWaitUntil(describing:)`` -- the deliberately-bounded fallback, for the one class of
//    condition nothing can signal: an object being deallocated. Its failure names the condition.
//

import Foundation
import XCTest
#if canImport(Observation) && canImport(Darwin)
import Observation
#endif
@testable import SwiftQL


// MARK: - Awaitable state

/// A lock-protected value that callers await rather than poll.
///
/// `wait(until:)` suspends on a continuation and is resumed by the very mutation that satisfies its
/// predicate, so nothing sleeps and nothing samples on a timer. Predicates are evaluated inside the
/// lock, against the value as it stands at that instant, so a state that is reached and then left
/// again between two polls -- the classic reason a polling wait misses an event -- cannot be missed
/// here.
final class XLAwaitableState<Value>: @unchecked Sendable {

    private struct Waiter {
        let id: UUID
        let isSatisfied: (Value) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()

    private var value: Value

    private var waiters: [Waiter] = []

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Mutates the value and resumes every waiter the new value satisfies.
    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        let result = body(&value)
        let satisfied = waiters.filter { $0.isSatisfied(value) }
        let satisfiedIDs = Set(satisfied.map(\.id))
        waiters.removeAll { satisfiedIDs.contains($0.id) }
        lock.unlock()
        // Resumed outside the lock: a resumed test task usually goes straight back into the code
        // under test, which may take this same lock again through another mutation.
        for waiter in satisfied {
            waiter.continuation.resume()
        }
        return result
    }

    func set(_ newValue: Value) {
        withValue { $0 = newValue }
    }

    /// Suspends until the value satisfies `isSatisfied`, returning immediately if it already does.
    func wait(until isSatisfied: @escaping (Value) -> Bool) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isSatisfied(value) {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(Waiter(id: UUID(), isSatisfied: isSatisfied, continuation: continuation))
            lock.unlock()
        }
    }
}


extension XLAwaitableState where Value: Equatable {

    /// Suspends until the value equals `expected`.
    func wait(for expected: Value) async {
        await wait(until: { $0 == expected })
    }
}


extension XLAwaitableState {

    /// Suspends until the collection holds at least `count` elements.
    func wait<Element>(untilCountIsAtLeast count: Int) async where Value == [Element] {
        await wait(until: { $0.count >= count })
    }
}


/// A value produced exactly once, which callers await.
///
/// Used where the observable thing is a single callback -- a completion handler, a delivery on a
/// particular queue -- rather than evolving state. Awaiting the callback *itself* and then asserting
/// on what it carried keeps the wrong outcome a test failure rather than a hang, which is not true
/// of waiting for a flag that is only set when the outcome is already the expected one.
final class XLAwaitableValue<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value?

    private var waiters: [CheckedContinuation<Value, Never>] = []

    /// Records the first value only. Later calls are ignored, so a test reading "the" value cannot be
    /// confused by a second one arriving mid-assertion.
    func fulfill(_ newValue: Value) {
        lock.lock()
        guard value == nil else {
            lock.unlock()
            return
        }
        value = newValue
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending {
            waiter.resume(returning: newValue)
        }
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}


// MARK: - Subscription lifecycle events

#if DEBUG
/// Buffers every `XLAsyncStreamSubscription` lifecycle event the `#if DEBUG` seam from issue #465
/// emits, and lets a test await a *named* one instead of polling a predicate against a wall-clock
/// deadline.
///
/// Waiting this way is what makes runner load unable to change a verdict: every wait here resumes
/// because the subscription reached a specific point in its own control flow, so load can only make
/// a test take longer, never make it assert against a state the subscription has not reached yet.
/// There is deliberately no timeout: a bounded wait is a wall-clock deadline wearing a different
/// hat, and the failure it produces under load is exactly the one these suites are being fixed for.
///
/// Each wait consumes the earliest *matching* buffered event, and parks on a continuation if none
/// has arrived yet. Non-matching events are not skipped past and discarded: they stay buffered in
/// arrival order, so a later wait for one of them still finds it. A wait therefore never has to
/// step over -- or block on -- an event the test does not care about.
final class XLSubscriptionEventRecorder: @unchecked Sendable {

    private struct RecordedEvent {
        let sequence: Int
        let event: XLAsyncStreamSubscriptionEvent
    }

    private struct Waiter {
        let matches: (XLAsyncStreamSubscriptionEvent) -> Bool
        let continuation: CheckedContinuation<RecordedEvent, Never>
    }

    private let lock = NSLock()

    private var buffered: [RecordedEvent] = []

    private var waiter: Waiter?

    private var nextSequence = 0

    private var pump: Task<Void, Never>?

    init() {
        // `events()` registers its observer synchronously inside `AsyncStream`'s build closure, and
        // that stream buffers without bound, so no event emitted after this line can be missed --
        // including events emitted before `pump` gets its first chance to run.
        let stream = XLAsyncStreamSubscriptionTestHooks.shared.events()
        pump = Task { [weak self] in
            for await event in stream {
                self?.ingest(event)
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }

    private func ingest(_ event: XLAsyncStreamSubscriptionEvent) {
        lock.lock()
        let recorded = RecordedEvent(sequence: nextSequence, event: event)
        nextSequence += 1
        if let waiter, waiter.matches(event) {
            self.waiter = nil
            lock.unlock()
            // Resumed outside the lock: the resumed test task goes on to call into the subscription
            // (cancel, request more demand), which takes the subscription's own lock.
            waiter.continuation.resume(returning: recorded)
            return
        }
        buffered.append(recorded)
        lock.unlock()
    }

    private func wait(
        matching matches: @escaping (XLAsyncStreamSubscriptionEvent) -> Bool
    ) async -> RecordedEvent {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let index = buffered.firstIndex(where: { matches($0.event) }) {
                let match = buffered.remove(at: index)
                lock.unlock()
                continuation.resume(returning: match)
                return
            }
            precondition(
                waiter == nil,
                "XLSubscriptionEventRecorder serves one wait at a time: a test that awaits two events "
                    + "concurrently would silently overwrite and hang the first waiter."
            )
            waiter = Waiter(matches: matches, continuation: continuation)
            lock.unlock()
        }
    }

    /// Awaits (and consumes) the next occurrence of `event`.
    func wait(for event: XLAsyncStreamSubscriptionEvent) async {
        _ = await wait(matching: { $0 == event })
    }

    /// Awaits `finish(error:)` running and reports whether it forwarded the completion downstream or
    /// suppressed it as self-inflicted.
    ///
    /// Matching *either* outcome is deliberate. A test that waited only for the outcome it expects
    /// would hang -- rather than fail -- in the world where the subscription made the opposite
    /// decision, which is the world the test exists to detect.
    func waitForFinish() async -> Bool {
        let match = await wait(matching: { event in
            if case .finished = event {
                return true
            }
            return false
        })
        guard case .finished(let forwarded) = match.event else {
            preconditionFailure("wait(matching:) resumed with a non-`.finished` event.")
        }
        return forwarded
    }

    /// Awaits the next consumer task starting, and forgets everything emitted before it.
    ///
    /// The seam is process-global -- `Publisher.receive(subscriber:)` erases the concrete
    /// `XLAsyncStreamSubscription` behind Combine's `Subscription` existential the moment it is
    /// vended, so no test ever holds a handle to hook per-instance. That means a previous test's
    /// (or previous round's) still-unwinding subscription can in principle emit one last event into
    /// this recorder. `.consumerTaskStarted` can only come from a consumer task starting *now*, so
    /// fencing on it and dropping everything with a lower sequence number gives each test a clean
    /// epoch, without polling for quiescence.
    func fenceOnConsumerTaskStart() async {
        let match = await wait(matching: { $0 == .consumerTaskStarted })
        discardEvents(before: match.sequence)
    }

    /// Locked, non-`async` half of ``fenceOnConsumerTaskStart()``: recent Foundation marks
    /// `NSLock.lock()`/`unlock()` unavailable directly inside an asynchronous context (an error in
    /// the Swift 6 language mode), the same split `XLAsyncStreamSubscription` itself uses.
    private func discardEvents(before sequence: Int) {
        lock.lock()
        buffered.removeAll { $0.sequence < sequence }
        lock.unlock()
    }
}
#endif


// MARK: - Observation-native waiting

#if canImport(Observation) && canImport(Darwin)
/// Suspends until `isSatisfied` holds for main-actor `@Observable` state, resumed by Observation's
/// own change notification rather than by a poll.
///
/// Each round evaluates `isSatisfied` inside `withObservationTracking`, so the properties it reads
/// are exactly the ones whose next mutation resumes the wait -- there is no window between checking
/// and subscribing in which a change could be missed. `onChange` fires just *before* the new value
/// is visible, so the loop yields the main actor once and re-evaluates afterwards. That is an await
/// on a scheduling hop, not on a duration: under load the loop simply takes more turns, and it can
/// never conclude anything early.
@available(iOS 17, macOS 14, *)
@MainActor
func xlWaitForObservedState(_ isSatisfied: @escaping @MainActor () -> Bool) async {
    while true {
        let changed = XLAwaitableValue<Void>()
        let isSatisfiedNow = withObservationTracking {
            isSatisfied()
        } onChange: {
            changed.fulfill(())
        }
        if isSatisfiedNow {
            return
        }
        await changed.wait()
        await Task.yield()
    }
}
#endif


// MARK: - Bounded fallback

/// Bounded wait for a condition nothing can signal -- in practice, only "this object has been
/// deallocated," where no seam exists to be notified.
///
/// Every other wait in these suites is event-driven and unbounded. This one keeps a deadline because
/// an unobservable condition that never becomes true would otherwise hang forever with no diagnosis
/// at all. `describing` is mandatory, so the failure says what was being waited for instead of
/// issue #463's anonymous `Condition not met within 3.0s`.
///
/// `@MainActor`, matching its call sites: a condition closure formed inside a `@MainActor` test
/// method is itself main-actor-isolated, and a nonisolated helper would have to *send* it (and
/// everything it captures) across an actor boundary just to receive it as a parameter.
@MainActor
func xlWaitUntil(
    describing description: String,
    timeout: TimeInterval = 3,
    pollInterval: UInt64 = 10_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async throws {
    let maximumAttempts = max(Int((timeout * 1_000_000_000) / Double(pollInterval)), 1)
    for _ in 0 ..< maximumAttempts {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    XCTFail(
        "Timed out after \(timeout)s waiting for: \(description)",
        file: file,
        line: line
    )
}


/// Suspends until every block already enqueued on the main queue has run.
///
/// A barrier, not a deadline: it resumes when the main queue reaches the block it enqueued, however
/// long that takes. Valid only where the main queue genuinely is the delivery path being drained --
/// GRDB's `ValueObservation` scheduling and Combine's `.receive(on: DispatchQueue.main)` -- and
/// never as a stand-in for "let the cooperative pool settle," which it says nothing about.
func xlDrainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
