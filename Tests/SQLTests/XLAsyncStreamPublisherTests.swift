//
//  XLAsyncStreamPublisherTests.swift
//

#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif
import Foundation
import XCTest
@testable import SwiftQL


// MARK: - Deterministic, GRDB-independent stream source

/// A hand-controlled `AsyncThrowingStream` factory used to drive
/// ``XLAsyncStreamPublisher`` deterministically, without a real GRDB database. Every call to
/// ``makeStream()`` produces one fresh, independent stream and records its own continuation, so a
/// test can drive several concurrent subscriptions (each created its own call to `makeStream`)
/// completely independently -- exactly the "never share a stream/iterator/snapshot across
/// subscribers" contract issue #309 requires of the production adapter.
private final class ControllableStreamSource<Value>: @unchecked Sendable {

    private let lock = NSLock()

    /// One entry per `makeStream()` call, in order. `AsyncThrowingStream`'s `build` closure runs
    /// synchronously inside `init`, so the continuation for index `n` is always populated before
    /// `makeStream()` returns -- no caller can observe a `nil` entry it just created.
    private var continuations: [AsyncThrowingStream<Value, Error>.Continuation?] = []

    private var makeStreamCallCount = 0

    private var cancelledContinuationCount = 0

    func makeStream() -> AsyncThrowingStream<Value, Error> {
        lock.lock()
        makeStreamCallCount += 1
        let index = continuations.count
        continuations.append(nil)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuations[index] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] termination in
                guard let self, case .cancelled = termination else { return }
                self.lock.lock()
                self.cancelledContinuationCount += 1
                self.lock.unlock()
            }
        }
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return makeStreamCallCount
    }

    var cancelledCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelledContinuationCount
    }

    /// Yields `value` on the stream constructed by the `streamIndex`-th `makeStream()` call
    /// (defaulting to the first/only one a test cares about).
    func yield(_ value: Value, toStream streamIndex: Int = 0) {
        lock.lock()
        let continuation = continuations[streamIndex]
        lock.unlock()
        continuation?.yield(value)
    }

    func finish(throwing error: Error? = nil, stream streamIndex: Int = 0) {
        lock.lock()
        let continuation = continuations[streamIndex]
        lock.unlock()
        if let error {
            continuation?.finish(throwing: error)
        }
        else {
            continuation?.finish()
        }
    }
}


private enum XLAsyncStreamPublisherTestError: Error, Equatable {
    case terminal
}


/// Records every value/completion a `Subscriber` receives, plus the demand granted at subscription
/// time and from every subsequent `receive(_:)` call, so tests can assert Combine's contract
/// precisely without needing `sink`'s fixed unlimited-demand behavior.
private final class RecordingSubscriber<Input>: Subscriber, @unchecked Sendable {

    typealias Failure = Error

    private let lock = NSLock()

    private var values: [Input] = []

    private var completions: [Subscribers.Completion<Error>] = []

    private var subscription: Subscription?

    private let initialDemand: Subscribers.Demand

    private let additionalDemand: (Input) -> Subscribers.Demand

    init(
        initialDemand: Subscribers.Demand,
        additionalDemand: @escaping (Input) -> Subscribers.Demand = { _ in .none }
    ) {
        self.initialDemand = initialDemand
        self.additionalDemand = additionalDemand
    }

    var recordedValues: [Input] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    var recordedCompletions: [Subscribers.Completion<Error>] {
        lock.lock()
        defer { lock.unlock() }
        return completions
    }

    func requestMore(_ demand: Subscribers.Demand) {
        lock.lock()
        let subscription = subscription
        lock.unlock()
        subscription?.request(demand)
    }

    func cancel() {
        lock.lock()
        let subscription = subscription
        self.subscription = nil
        lock.unlock()
        subscription?.cancel()
    }

    func receive(subscription: Subscription) {
        lock.lock()
        self.subscription = subscription
        lock.unlock()
        subscription.request(initialDemand)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        lock.lock()
        values.append(input)
        lock.unlock()
        return additionalDemand(input)
    }

    func receive(completion: Subscribers.Completion<Error>) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }
}


final class XLAsyncStreamPublisherTests: XCTestCase {

    // MARK: - Lazy start

    func testConstructingThePublisherPerformsNoWork() throws {
        let source = ControllableStreamSource<Int>()
        _ = XLAsyncStreamPublisher(makeStream: source.makeStream)

        XCTAssertEqual(source.callCount, 0, "Building the publisher must not call makeStream.")
    }

    func testSubscribingWithZeroDemandPerformsNoWork() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .none)

        publisher.receive(subscriber: subscriber)
        await drainCurrentThread()

        XCTAssertEqual(source.callCount, 0, "Zero demand must not start the consumer task.")
        subscriber.cancel()
    }

    func testFirstPositiveDemandStartsExactlyOneStream() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }

        source.yield(1)
        try await waitUntil { subscriber.recordedValues == [1] }
        subscriber.cancel()
    }

    // MARK: - Demand mapping (#291's "Async-to-Combine demand mapping")

    func testOneAtATimeDemandDeliversExactlyRequestedCountWithoutEagerDraining() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }

        // Yield three values while only one unit of demand is outstanding: only the first may be
        // delivered; the rest must sit in the stream's own buffer, untouched, until more demand
        // is granted -- the adapter must never call next() ahead of demand.
        source.yield(1)
        source.yield(2)
        source.yield(3)
        try await waitUntil { subscriber.recordedValues == [1] }
        await drainCurrentThread()
        XCTAssertEqual(subscriber.recordedValues, [1], "Must not pull ahead of granted demand.")

        subscriber.requestMore(.max(1))
        try await waitUntil { subscriber.recordedValues == [1, 2] }
        await drainCurrentThread()
        XCTAssertEqual(subscriber.recordedValues, [1, 2])

        subscriber.requestMore(.max(1))
        try await waitUntil { subscriber.recordedValues == [1, 2, 3] }
        subscriber.cancel()
    }

    func testUnlimitedDemandDeliversValuesAsTheyArrive() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }

        for value in 1...5 {
            source.yield(value)
        }
        try await waitUntil { subscriber.recordedValues == [1, 2, 3, 4, 5] }
        subscriber.cancel()
    }

    func testAdditionalDemandGrantedFromReceiveResumesAStalledPull() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // Each delivered value grants exactly one more unit of demand from inside receive(_:),
        // so the pull loop should keep going indefinitely without any external request() call.
        let subscriber = RecordingSubscriber<Int>(
            initialDemand: .max(1),
            additionalDemand: { _ in .max(1) }
        )

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }

        for value in 1...3 {
            source.yield(value)
            try await waitUntil { subscriber.recordedValues.last == value }
        }
        subscriber.cancel()
    }

    // MARK: - Independent subscriptions

    func testEachSubscriptionGetsAnIndependentStreamNeverSharingState() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let first = RecordingSubscriber<Int>(initialDemand: .unlimited)
        let second = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: first)
        publisher.receive(subscriber: second)
        // `first`'s and `second`'s consumer tasks each call `makeStream()` from their own
        // independently-scheduled `Task`, so there is no guarantee *which* of the two calls lands at
        // index 0 versus index 1 -- only that there are two distinct, independent streams. The
        // assertions below deliberately never assume a fixed index-to-subscriber mapping.
        try await waitUntil { source.callCount == 2 }

        source.yield(100, toStream: 0)
        try await waitUntil { first.recordedValues == [100] || second.recordedValues == [100] }
        await drainCurrentThread()
        let ownerOf100 = first.recordedValues == [100] ? first : second
        let otherSubscriber = ownerOf100 === first ? second : first
        XCTAssertTrue(
            otherSubscriber.recordedValues.isEmpty,
            "A value yielded to one stream must not reach the other subscription."
        )

        source.yield(200, toStream: 1)
        try await waitUntil { otherSubscriber.recordedValues == [200] }
        await drainCurrentThread()
        XCTAssertEqual(
            ownerOf100.recordedValues,
            [100],
            "A later value on the other stream must not leak into this subscription."
        )

        first.cancel()
        second.cancel()
    }

    // MARK: - Cancellation

    func testCancellationBeforeAnyDemandPerformsNoWorkEvenIfDemandArrivesLater() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .none)

        publisher.receive(subscriber: subscriber)
        subscriber.cancel()
        subscriber.requestMore(.unlimited)
        await drainCurrentThread()

        XCTAssertEqual(source.callCount, 0)
        XCTAssertTrue(subscriber.recordedValues.isEmpty)
        XCTAssertTrue(subscriber.recordedCompletions.isEmpty)
    }

    func testCancellationDuringActiveIterationPropagatesToTheUnderlyingStream() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }
        source.yield(1)
        try await waitUntil { subscriber.recordedValues == [1] }

        subscriber.cancel()
        try await waitUntil { source.cancelledCount == 1 }
    }

    func testSelfInflictedCancellationDoesNotDeliverASpuriousCompletion() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }
        source.yield(1)
        try await waitUntil { subscriber.recordedValues == [1] }

        subscriber.cancel()
        // Give the cancelled consumer task every opportunity to (incorrectly) resolve next() to
        // nil and forward it as `.finished` before asserting it never did.
        try await waitUntil { source.cancelledCount == 1 }
        await drainCurrentThread()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(
            subscriber.recordedCompletions.isEmpty,
            "Cancelling must never manifest as a completion, matching Combine's own contract that "
                + "nothing is delivered to a subscriber after it calls cancel()."
        )
    }

    func testValueDeliveredConcurrentlyWithCancellationIsNeverForwarded() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let cancelledDuringReceive = LockedFlag()
        var capturedSubscriber: RecordingSubscriber<Int>!
        let subscriber = RecordingSubscriber<Int>(
            initialDemand: .max(2),
            additionalDemand: { value in
                // Cancel from *inside* delivery of the first value, with a second value already
                // sitting in the stream's own buffer (both values are yielded below, after
                // subscribing, before this callback ever cancels). This exercises the same
                // end-to-end guarantee as
                // `SQLPublisherTests.testCancellationDuringInFlightSQLiteWorkSuppressesDelivery`'s
                // real-GRDB scenario (a value produced concurrently with cancel() must never reach
                // the subscriber) without needing a real database: whether the second value is
                // rejected by `waitForDemandUnit()`'s cancellation check before ever calling
                // `next()` again, or by `deliver(_:)`'s own pre-`receive` check for a value that
                // raced further ahead, is an implementation detail -- what must hold either way is
                // that nothing reaches the subscriber after `cancel()`.
                if value == 1 {
                    cancelledDuringReceive.set()
                    capturedSubscriber.cancel()
                }
                return .none
            }
        )
        capturedSubscriber = subscriber

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }
        source.yield(1)
        source.yield(2)
        try await waitUntil { cancelledDuringReceive.isSet }
        await drainCurrentThread()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(
            subscriber.recordedValues,
            [1],
            "A value already buffered in the stream when cancel() was called must never reach the "
                + "subscriber -- Combine's contract is that nothing is delivered after cancel(), "
                + "regardless of what the underlying stream still yields."
        )
    }

    // MARK: - Terminal outcomes

    func testTerminalErrorIsForwardedExactlyOnce() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }
        source.finish(throwing: XLAsyncStreamPublisherTestError.terminal)

        try await waitUntil { !subscriber.recordedCompletions.isEmpty }
        await drainCurrentThread()

        XCTAssertEqual(subscriber.recordedCompletions.count, 1)
        guard case .failure(let error) = subscriber.recordedCompletions[0] else {
            return XCTFail("Expected a failure completion.")
        }
        XCTAssertEqual(error as? XLAsyncStreamPublisherTestError, .terminal)
    }

    func testNormalCompletionNotCausedByCancellationIsForwarded() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: subscriber)
        try await waitUntil { source.callCount == 1 }
        source.yield(1)
        try await waitUntil { subscriber.recordedValues == [1] }

        // The stream ends on its own, with no cancel() ever called: this is NOT the self-inflicted
        // case, so it must be forwarded normally as `.finished`.
        source.finish()

        try await waitUntil { !subscriber.recordedCompletions.isEmpty }
        XCTAssertEqual(subscriber.recordedCompletions.count, 1)
        guard case .finished = subscriber.recordedCompletions[0] else {
            return XCTFail("Expected a normal `.finished` completion, not a self-inflicted suppression.")
        }
    }

    // MARK: - Main-queue delivery default (`xlLiveQueryPublisher`)

    func testXlLiveQueryPublisherDeliversOnTheMainQueueByDefault() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = xlLiveQueryPublisher(makeStream: source.makeStream)
        let deliveredOnMain = LockedFlag()
        let completedOnMain = LockedFlag()

        let cancellable = publisher.sink(
            receiveCompletion: { _ in
                if Thread.isMainThread { completedOnMain.set() }
            },
            receiveValue: { _ in
                if Thread.isMainThread { deliveredOnMain.set() }
            }
        )

        try await waitUntil { source.callCount == 1 }
        // Yield from a background queue: the adapter itself is thread-agnostic, so this proves the
        // main-queue delivery comes from `.receive(on: DispatchQueue.main)`, not from whichever
        // thread produced the value.
        DispatchQueue.global().async {
            source.yield(1)
        }
        try await waitUntil { deliveredOnMain.isSet }

        source.finish()
        try await waitUntil { completedOnMain.isSet }
        withExtendedLifetime(cancellable) {}
    }

    // MARK: - Deterministic repeated stress (no sleeps as synchronization)

    func testRepeatedSubscribeYieldCancelCycleLeavesNoDanglingState() async throws {
        for round in 0 ..< 25 {
            let source = ControllableStreamSource<Int>()
            let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
            let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

            publisher.receive(subscriber: subscriber)
            try await waitUntil { source.callCount == 1 }
            source.yield(round)
            try await waitUntil { subscriber.recordedValues == [round] }
            subscriber.cancel()
            try await waitUntil { source.cancelledCount == 1 }

            XCTAssertTrue(subscriber.recordedCompletions.isEmpty)
        }
    }

    // MARK: - Helpers

    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false

        func set() {
            lock.lock()
            flag = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }
    }

    /// Lets any already-scheduled asynchronous work (Task hops, `DispatchQueue.main` blocks already
    /// enqueued) finish before an assertion, without asserting anything about timing itself.
    ///
    /// This suspends via a checked continuation rather than XCTest's synchronous `wait(for:timeout:)`
    /// deliberately: every call site runs inside an `async throws` test method, which executes on
    /// Swift concurrency's cooperative thread pool. Blocking one of those threads synchronously (as
    /// `wait(for:timeout:)` does) can starve the pool of the thread this test's own consumer `Task`
    /// needs to make progress, causing a self-inflicted hang -- exactly the failure mode this helper
    /// exists to avoid.
    private func drainCurrentThread() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    /// Bounded, deterministic polling: checks `condition` repeatedly instead of sleeping blindly,
    /// matching #308's own async test suite style (`GRDBLiveQueryAsyncStreamTests.waitUntil`).
    private func waitUntil(
        timeout: TimeInterval = 3,
        pollInterval: UInt64 = 5_000_000,
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
}
