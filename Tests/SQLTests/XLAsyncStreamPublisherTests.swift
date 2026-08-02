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

/// How a stream created by ``ControllableStreamSource`` ended.
private enum StreamTermination: Equatable {
    /// The consumer `Task` was cancelled, or the consumer loop exited and dropped its iterator.
    case cancelled
    /// This source finished the stream itself, with or without an error.
    case finished
}


/// A hand-controlled `AsyncThrowingStream` factory used to drive
/// ``XLAsyncStreamPublisher`` deterministically, without a real GRDB database. Every call to
/// ``makeStream()`` produces one fresh, independent stream and records its own continuation, so a
/// test can drive several concurrent subscriptions (each created its own call to `makeStream`)
/// completely independently -- exactly the "never share a stream/iterator/snapshot across
/// subscribers" contract issue #309 requires of the production adapter.
private final class ControllableStreamSource<Value>: @unchecked Sendable {

    private let lock = NSLock()

    /// One entry per `makeStream()` call, in order. A slot is appended as `nil` and filled in by
    /// `AsyncThrowingStream`'s `build` closure; `makeStreamCallCount` is published only once the
    /// slot holds its continuation, so a `nil` slot is never reachable through `callCount` (#464).
    private var continuations: [AsyncThrowingStream<Value, Error>.Continuation?] = []

    private var makeStreamCallCount = 0

    private var cancelledContinuationCount = 0

    /// How each stream ended, by index, once its `onTermination` has fired.
    private var terminations: [Int: StreamTermination] = [:]

    /// Callers parked in ``waitForTermination(ofStream:)`` for a stream that has not ended yet.
    private var terminationWaiters: [Int: [CheckedContinuation<StreamTermination, Never>]] = [:]

    func makeStream() -> AsyncThrowingStream<Value, Error> {
        lock.lock()
        let index = continuations.count
        continuations.append(nil)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuations[index] = continuation
            // Only becomes visible to `callCount` once the continuation this index needs is
            // actually stored -- issue #464's "publish race": incrementing before the continuation
            // was stored let a concurrent observer of `callCount` race ahead of this closure and
            // call `yield`/`finish` against a still-`nil` slot, which silently dropped the value
            // instead of failing.
            self.makeStreamCallCount += 1
            self.lock.unlock()
            continuation.onTermination = { [weak self] termination in
                guard let self else { return }
                let kind: StreamTermination
                if case .cancelled = termination {
                    kind = .cancelled
                }
                else {
                    kind = .finished
                }
                self.lock.lock()
                if kind == .cancelled {
                    self.cancelledContinuationCount += 1
                }
                self.terminations[index] = kind
                let waiters = self.terminationWaiters.removeValue(forKey: index) ?? []
                self.lock.unlock()
                for waiter in waiters {
                    waiter.resume(returning: kind)
                }
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

    /// Suspends until the `streamIndex`-th stream has ended, and reports how.
    ///
    /// This is the harness-side counterpart of ``XLAsyncStreamSubscriptionTestHooks``' subscription
    /// events, and the thing that makes "nothing else was delivered" provable rather than a race
    /// against a sleep: once a stream reports `.cancelled`, the consumer loop that owned it has
    /// either been cancelled mid-`next()` or exited and dropped its iterator, so it can never
    /// deliver another value. Suspends via a continuation, so waiting costs no polling and no
    /// wall-clock deadline decides the outcome.
    ///
    /// An index no `makeStream()` call has reached yet fails the test immediately, naming the index,
    /// rather than parking forever on a stream that may never exist -- the same "a harness misuse
    /// must fail where it happened" rule `yield`/`finish` follow. The value it returns in that case
    /// is meaningless; the `XCTFail` is the outcome.
    func waitForTermination(
        ofStream streamIndex: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> StreamTermination {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let termination = terminations[streamIndex] {
                lock.unlock()
                continuation.resume(returning: termination)
                return
            }
            guard streamIndex >= 0, streamIndex < continuations.count else {
                let createdCount = continuations.count
                lock.unlock()
                XCTFail(
                    "ControllableStreamSource.waitForTermination(ofStream: \(streamIndex)) called "
                        + "with an out-of-range stream index (only \(createdCount) stream(s) created "
                        + "so far). Wait for callCount to reach \(streamIndex + 1) first.",
                    file: file,
                    line: line
                )
                continuation.resume(returning: .finished)
                return
            }
            terminationWaiters[streamIndex, default: []].append(continuation)
            lock.unlock()
        }
    }

    /// Yields `value` on the stream constructed by the `streamIndex`-th `makeStream()` call
    /// (defaulting to the first/only one a test cares about).
    ///
    /// See the matching note on `XLSingleSlotAsyncBuffer.yield(_:)`: `sending` (Swift 6.0+ only) marks
    /// this call as `value`'s last use, matching `AsyncThrowingStream.Continuation.yield(_:)`'s own
    /// `sending` parameter.
    // The whole declaration is duplicated per branch: splitting only the signature across #if/#else
    // and sharing one body does not parse -- each active branch's opening brace must be matched by a
    // closing brace within that same branch.
    #if compiler(>=6.0)
    func yield(
        _ value: sending Value,
        toStream streamIndex: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let continuation = continuation(at: streamIndex, calledFrom: "yield", file: file, line: line) else {
            return
        }
        continuation.yield(value)
    }
    #else
    func yield(
        _ value: Value,
        toStream streamIndex: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let continuation = continuation(at: streamIndex, calledFrom: "yield", file: file, line: line) else {
            return
        }
        continuation.yield(value)
    }
    #endif

    func finish(
        throwing error: Error? = nil,
        stream streamIndex: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let continuation = continuation(at: streamIndex, calledFrom: "finish", file: file, line: line) else {
            return
        }
        if let error {
            continuation.finish(throwing: error)
        }
        else {
            continuation.finish()
        }
    }

    /// Looks up the continuation for `streamIndex`, failing the current test loudly (naming the
    /// stream index) rather than silently dropping the caller's value/completion when it is not yet
    /// stored, or trapping on an out-of-range subscript. With the `makeStreamCallCount` ordering
    /// above, a missing continuation here means a caller drove this source ahead of `callCount`
    /// actually reaching `streamIndex + 1` -- a harness bug, not a timing fluke to paper over.
    /// `XCTFail` (rather than `preconditionFailure`) keeps this recoverable, so a negative-control
    /// test can drive this path with `XCTExpectFailure` and observe it fire.
    private func continuation(
        at streamIndex: Int,
        calledFrom caller: StaticString,
        file: StaticString,
        line: UInt
    ) -> AsyncThrowingStream<Value, Error>.Continuation? {
        // The lookup is resolved to a value under the lock and reported afterwards: `yield`/`finish`
        // are called from background queues in this suite, and calling into XCTest (which takes its
        // own locks, and can run arbitrary observer code) while holding this one is how test
        // harnesses acquire deadlocks.
        let lookup = lookUpContinuation(at: streamIndex)
        switch lookup {
        case .found(let continuation):
            return continuation
        case .outOfRange(let createdCount):
            XCTFail(
                "ControllableStreamSource.\(caller)(toStream: \(streamIndex)) called with an "
                    + "out-of-range stream index (only \(createdCount) stream(s) created so far).",
                file: file,
                line: line
            )
            return nil
        case .notStoredYet:
            XCTFail(
                "ControllableStreamSource.\(caller)(toStream: \(streamIndex)) called before that "
                    + "stream's continuation was stored. Wait for callCount to reach "
                    + "\(streamIndex + 1) first.",
                file: file,
                line: line
            )
            return nil
        }
    }

    private enum ContinuationLookup {
        case found(AsyncThrowingStream<Value, Error>.Continuation)
        case outOfRange(createdCount: Int)
        case notStoredYet
    }

    private func lookUpContinuation(at streamIndex: Int) -> ContinuationLookup {
        lock.lock()
        defer { lock.unlock() }
        guard streamIndex >= 0, streamIndex < continuations.count else {
            return .outOfRange(createdCount: continuations.count)
        }
        guard let continuation = continuations[streamIndex] else {
            return .notStoredYet
        }
        return .found(continuation)
    }
}


// The deterministic waiting primitives this suite runs on -- `XLSubscriptionEventRecorder` (the
// #465 subscription seam) and `XLAwaitableValue` -- live in `XLLiveQueryWaitSupport.swift`, shared
// with `XLObservableLiveQueryTests` and `GRDBLiveQueryAsyncStreamTests` (#467).


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

    /// Observes the subscription seam for the duration of one test. Recreated per test, and the
    /// shared hooks are reset on both sides of the test so no observer leaks into the next one.
    private var events: XLSubscriptionEventRecorder!

    override func setUp() {
        super.setUp()
        XLAsyncStreamSubscriptionTestHooks.shared.reset()
        events = XLSubscriptionEventRecorder()
    }

    override func tearDown() {
        events?.stop()
        events = nil
        XLAsyncStreamSubscriptionTestHooks.shared.reset()
        super.tearDown()
    }

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
        // Nothing to await on the subject itself -- the claim is that it never starts a consumer
        // task at all. A canary subscription created *after* it runs a full start-to-delivery round
        // trip, so the assertion below is made at a point where the runtime demonstrably got around
        // to starting consumer tasks and delivering values, rather than after a fixed sleep.
        await runCanaryRoundTrip(value: 61)

        XCTAssertEqual(source.callCount, 0, "Zero demand must not start the consumer task.")
        XCTAssertTrue(subscriber.recordedValues.isEmpty)
        subscriber.cancel()
    }

    func testFirstPositiveDemandStartsExactlyOneStream() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        await startConsuming(publisher, with: subscriber)
        XCTAssertEqual(source.callCount, 1, "One subscriber must produce exactly one stream.")

        source.yield(1)
        await events.wait(for: .delivered)

        XCTAssertEqual(subscriber.recordedValues, [1])
        XCTAssertEqual(source.callCount, 1)
        subscriber.cancel()
    }

    // MARK: - Demand mapping (#291's "Async-to-Combine demand mapping")

    func testOneAtATimeDemandDeliversExactlyRequestedCountWithoutEagerDraining() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        await startConsuming(publisher, with: subscriber)

        // Yield three values while only one unit of demand is outstanding: only the first may be
        // delivered; the rest must sit in the stream's own buffer, untouched, until more demand
        // is granted -- the adapter must never call next() ahead of demand.
        source.yield(1)
        source.yield(2)
        source.yield(3)
        await events.wait(for: .delivered)
        // `.demandWaiterRegistered` is the proof that the consumer loop came back around, found no
        // demand left, and parked. An adapter that drained eagerly would have delivered 2 and 3
        // before reaching this same point, so the assertion below can fail rather than merely
        // racing a sleep.
        await events.wait(for: .demandWaiterRegistered)
        XCTAssertEqual(subscriber.recordedValues, [1], "Must not pull ahead of granted demand.")

        subscriber.requestMore(.max(1))
        await events.wait(for: .delivered)
        await events.wait(for: .demandWaiterRegistered)
        XCTAssertEqual(subscriber.recordedValues, [1, 2])

        subscriber.requestMore(.max(1))
        await events.wait(for: .delivered)
        await events.wait(for: .demandWaiterRegistered)
        XCTAssertEqual(subscriber.recordedValues, [1, 2, 3])
        subscriber.cancel()
    }

    func testUnlimitedDemandDeliversValuesAsTheyArrive() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)

        for value in 1...5 {
            source.yield(value)
        }
        for _ in 1...5 {
            await events.wait(for: .delivered)
        }

        XCTAssertEqual(subscriber.recordedValues, [1, 2, 3, 4, 5])
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

        await startConsuming(publisher, with: subscriber)

        for value in 1...3 {
            source.yield(value)
            await events.wait(for: .delivered)
            XCTAssertEqual(subscriber.recordedValues.last, value)
        }
        XCTAssertEqual(subscriber.recordedValues, [1, 2, 3])
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
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .consumerTaskStarted)
        await events.wait(for: .streamCreated)
        await events.wait(for: .streamCreated)
        XCTAssertEqual(source.callCount, 2)

        source.yield(100, toStream: 0)
        await events.wait(for: .delivered)
        let ownerOf100 = first.recordedValues == [100] ? first : second
        let otherSubscriber = ownerOf100 === first ? second : first
        XCTAssertTrue(
            otherSubscriber.recordedValues.isEmpty,
            "A value yielded to one stream must not reach the other subscription."
        )

        source.yield(200, toStream: 1)
        await events.wait(for: .delivered)
        XCTAssertEqual(
            ownerOf100.recordedValues,
            [100],
            "A later value on the other stream must not leak into this subscription."
        )
        XCTAssertEqual(otherSubscriber.recordedValues, [200])

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
        // As in the zero-demand test: the claim is that nothing starts, so the canary's full
        // start-to-delivery round trip is what proves the runtime had the opportunity.
        await runCanaryRoundTrip(value: 62)

        XCTAssertEqual(source.callCount, 0)
        XCTAssertTrue(subscriber.recordedValues.isEmpty)
        XCTAssertTrue(subscriber.recordedCompletions.isEmpty)
    }

    func testCancellationDuringActiveIterationPropagatesToTheUnderlyingStream() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        source.yield(1)
        await events.wait(for: .delivered)

        subscriber.cancel()
        let termination = await source.waitForTermination()

        XCTAssertEqual(
            termination,
            .cancelled,
            "Cancelling the subscription must tear down the underlying stream, not leave it running."
        )
        XCTAssertEqual(source.cancelledCount, 1)
    }

    func testSelfInflictedCancellationDoesNotDeliverASpuriousCompletion() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        await consumeStartupDemandUnit()
        source.yield(1)
        await events.wait(for: .delivered)
        // Waiting for the *next* demand unit to be consumed puts the consumer loop provably inside
        // `next()` before cancelling, which is the case under test: cancellation resolves `next()`
        // to nil, and a naive bridge would forward that as `.finished`. The startup unit consumed
        // above is what makes this wait refer to that second pull rather than resolving against the
        // first one, still buffered in the recorder.
        await events.wait(for: .demandUnitConsumed)

        subscriber.cancel()
        // The positive event that proves the opposite outcome had its opportunity: `finish(error:)`
        // ran and *decided*. `waitForFinish()` matches either decision, so the wrong one fails this
        // test rather than hanging it.
        let forwarded = await events.waitForFinish()

        XCTAssertFalse(
            forwarded,
            "A completion produced by this subscription's own cancel() must be suppressed, not "
                + "forwarded."
        )
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

        await startConsuming(publisher, with: subscriber)
        source.yield(1)
        source.yield(2)
        await events.wait(for: .delivered)
        XCTAssertTrue(cancelledDuringReceive.isSet)

        // The positive event: the stream is torn down, which happens only once the consumer loop has
        // either been cancelled inside `next()` or exited and dropped its iterator. Either way it
        // has had -- and used up -- every opportunity to deliver the second value, so the assertion
        // below no longer races a fixed sleep.
        let termination = await source.waitForTermination()

        XCTAssertEqual(termination, .cancelled)
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

        await startConsuming(publisher, with: subscriber)
        source.finish(throwing: XLAsyncStreamPublisherTestError.terminal)

        let forwarded = await events.waitForFinish()
        _ = await source.waitForTermination()

        XCTAssertTrue(forwarded, "A stream that failed on its own must forward its failure.")
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

        await startConsuming(publisher, with: subscriber)
        source.yield(1)
        await events.wait(for: .delivered)

        // The stream ends on its own, with no cancel() ever called: this is NOT the self-inflicted
        // case, so it must be forwarded normally as `.finished`.
        source.finish()

        let forwarded = await events.waitForFinish()

        XCTAssertTrue(forwarded, "A completion nobody cancelled for must be forwarded downstream.")
        XCTAssertEqual(subscriber.recordedCompletions.count, 1)
        guard case .finished = subscriber.recordedCompletions[0] else {
            return XCTFail("Expected a normal `.finished` completion, not a self-inflicted suppression.")
        }
    }

    // MARK: - Main-queue delivery default (`xlLiveQueryPublisher`)

    func testXlLiveQueryPublisherDeliversOnTheMainQueueByDefault() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = xlLiveQueryPublisher(makeStream: source.makeStream)
        let deliveryOnMainQueue = XLAwaitableValue<Bool>()
        let completionOnMainQueue = XLAwaitableValue<Bool>()

        let cancellable = publisher.sink(
            receiveCompletion: { _ in
                completionOnMainQueue.fulfill(Thread.isMainThread)
            },
            receiveValue: { _ in
                deliveryOnMainQueue.fulfill(Thread.isMainThread)
            }
        )

        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        // Yield from a background queue: the adapter itself is thread-agnostic, so this proves the
        // main-queue delivery comes from `.receive(on: DispatchQueue.main)`, not from whichever
        // thread produced the value.
        DispatchQueue.global().async {
            source.yield(1)
        }
        // Awaiting the delivery itself -- rather than a flag that is only set on the main queue --
        // means a delivery on the wrong thread fails this test instead of hanging it.
        let deliveredOnMainQueue = await deliveryOnMainQueue.wait()
        XCTAssertTrue(deliveredOnMainQueue, "Values must be delivered on the main queue by default.")

        source.finish()
        let completedOnMainQueue = await completionOnMainQueue.wait()
        XCTAssertTrue(completedOnMainQueue, "Completions must be delivered on the main queue too.")
        withExtendedLifetime(cancellable) {}
    }

    // MARK: - Deterministic repeated stress (no sleeps as synchronization)

    func testRepeatedSubscribeYieldCancelCycleLeavesNoDanglingState() async throws {
        // 25 rounds by default; issue #466 asks for at least 250 during review, and #463's repeat-run
        // evidence re-runs this file under load. Raise it in place with
        // `SWIFTQL_PUBLISHER_CYCLE_ROUNDS=250 swift test --filter XLAsyncStreamPublisherTests`
        // rather than editing the file, so the review run is reproducible from the command alone.
        let rounds = ProcessInfo.processInfo.environment["SWIFTQL_PUBLISHER_CYCLE_ROUNDS"]
            .flatMap(Int.init) ?? 25
        for round in 0 ..< rounds {
            let source = ControllableStreamSource<Int>()
            let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
            let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

            // `startConsuming` fences on this round's own `.consumerTaskStarted`, so a previous
            // round's last event can never be mistaken for one of this round's.
            await startConsuming(publisher, with: subscriber)
            source.yield(round)
            await events.wait(for: .delivered)
            XCTAssertEqual(subscriber.recordedValues, [round])

            subscriber.cancel()
            let termination = await source.waitForTermination()

            XCTAssertEqual(termination, .cancelled, "Round \(round) left the stream running.")
            XCTAssertTrue(subscriber.recordedCompletions.isEmpty)
        }
    }

    // MARK: - Negative controls
    //
    // One per rewritten test above. Each drives the same wait sequence in a scenario where the
    // guarded behaviour does *not* hold, and asserts that the paired test's own predicate is false
    // at exactly the point that test asserts it -- so a rewritten test cannot pass vacuously, and
    // its waits are shown to resume early enough to see the wrong outcome.
    //
    // Every control uses values and demands decoupled from its paired test's constants (the 9xx
    // range, and different demand counts), so it cannot pass merely by sharing them.
    //
    // The broken world is produced through legal use of the publisher -- granting different demand,
    // finishing instead of cancelling, subscribing twice -- rather than by mutating the subscription
    // under test, so these controls exercise the real adapter rather than a stub of it.

    func testNegativeControlZeroDemandNoWorkAssertionCanFail() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // The broken world: a subscription that *does* start a stream. If zero demand ever started
        // one, this is the state the two "performs no work" tests would find.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        await startConsuming(publisher, with: subscriber)

        assertGuardedPredicateFails(
            source.callCount == 0,
            "`callCount == 0` must be able to fail once a stream really is created."
        )
        subscriber.cancel()
    }

    func testNegativeControlFirstPositiveDemandStartsExactlyOneStreamAssertionCanFail() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let first = RecordingSubscriber<Int>(initialDemand: .max(1))
        let second = RecordingSubscriber<Int>(initialDemand: .max(1))

        publisher.receive(subscriber: first)
        publisher.receive(subscriber: second)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .consumerTaskStarted)
        await events.wait(for: .streamCreated)
        await events.wait(for: .streamCreated)

        assertGuardedPredicateFails(
            source.callCount == 1,
            "`callCount == 1` must be able to fail when more than one stream is created."
        )
        first.cancel()
        second.cancel()
    }

    func testNegativeControlEagerDrainingWouldBeVisibleAtTheSameWaitPoint() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // Three units of demand rather than one: the adapter legitimately delivers all three, which
        // is exactly the observable state an eagerly-draining adapter would produce.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(3))

        await startConsuming(publisher, with: subscriber)
        source.yield(901)
        source.yield(902)
        source.yield(903)
        await events.wait(for: .delivered)
        await events.wait(for: .demandWaiterRegistered)

        assertGuardedPredicateFails(
            subscriber.recordedValues == [901],
            "The one-at-a-time assertion must be able to see values delivered beyond the first by "
                + "the time the consumer loop parks."
        )
        XCTAssertEqual(subscriber.recordedValues, [901, 902, 903])
        subscriber.cancel()
    }

    func testNegativeControlUnderDeliveryWouldBeVisibleAtTheSameWaitPoint() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // Two units of demand for four values: the observable state an adapter that stopped pulling
        // early under unlimited demand would produce.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(2))

        await startConsuming(publisher, with: subscriber)
        for value in 911...914 {
            source.yield(value)
        }
        await events.wait(for: .delivered)
        await events.wait(for: .delivered)
        await events.wait(for: .demandWaiterRegistered)

        assertGuardedPredicateFails(
            subscriber.recordedValues == [911, 912, 913, 914],
            "The unlimited-demand assertion must be able to fail when values are missing."
        )
        XCTAssertEqual(subscriber.recordedValues, [911, 912])
        subscriber.cancel()
    }

    func testNegativeControlAStalledPullStaysStalledWithoutAdditionalDemand() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // The broken world for "additional demand from receive(_:) resumes the pull": a subscriber
        // that grants none, so the second value must never arrive.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(1))

        await startConsuming(publisher, with: subscriber)
        source.yield(921)
        source.yield(922)
        await events.wait(for: .delivered)
        await events.wait(for: .demandWaiterRegistered)

        assertGuardedPredicateFails(
            subscriber.recordedValues.last == 922,
            "The resumed-pull assertion must be able to fail when no additional demand is granted."
        )
        XCTAssertEqual(subscriber.recordedValues, [921])
        subscriber.cancel()
    }

    func testNegativeControlCrossStreamLeakWouldBeVisible() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let first = RecordingSubscriber<Int>(initialDemand: .unlimited)
        let second = RecordingSubscriber<Int>(initialDemand: .unlimited)

        publisher.receive(subscriber: first)
        publisher.receive(subscriber: second)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .consumerTaskStarted)
        await events.wait(for: .streamCreated)
        await events.wait(for: .streamCreated)

        // Yield the same value to *both* streams: the observable state a leak between subscriptions
        // would produce, reached here without one.
        source.yield(931, toStream: 0)
        await events.wait(for: .delivered)
        source.yield(931, toStream: 1)
        await events.wait(for: .delivered)

        assertGuardedPredicateFails(
            first.recordedValues.isEmpty || second.recordedValues.isEmpty,
            "The independence assertion must be able to fail when both subscribers hold the value."
        )
        XCTAssertEqual(first.recordedValues, [931])
        XCTAssertEqual(second.recordedValues, [931])
        first.cancel()
        second.cancel()
    }

    func testNegativeControlANormallyEndedStreamIsNotReportedAsCancelled() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        source.yield(941)
        await events.wait(for: .delivered)
        // Ending the stream from the source rather than cancelling: the termination signal the
        // cancellation test asserts on must discriminate between the two.
        source.finish()
        let termination = await source.waitForTermination()

        assertGuardedPredicateFails(
            termination == .cancelled && source.cancelledCount == 1,
            "The cancellation-propagation assertion must be able to fail when nothing cancelled."
        )
        XCTAssertEqual(termination, .finished)
        XCTAssertEqual(source.cancelledCount, 0)
        subscriber.cancel()
    }

    func testNegativeControlAForwardedCompletionIsVisibleToTheSuppressionAssertion() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        await consumeStartupDemandUnit()
        source.yield(951)
        await events.wait(for: .delivered)
        await events.wait(for: .demandUnitConsumed)
        // No cancel: the stream ends on its own, so the completion *is* forwarded -- exactly what
        // the self-inflicted-cancellation test claims never happens in its scenario.
        source.finish()
        let forwarded = await events.waitForFinish()

        assertGuardedPredicateFails(
            !forwarded && subscriber.recordedCompletions.isEmpty,
            "The suppression assertion must be able to see a completion that really was forwarded."
        )
        XCTAssertTrue(forwarded)
        XCTAssertEqual(subscriber.recordedCompletions.count, 1)
        subscriber.cancel()
    }

    func testNegativeControlASecondBufferedValueIsVisibleWhenNothingCancels() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // Same shape as the concurrent-cancellation test, minus the cancel inside receive(_:): both
        // buffered values are delivered, which is what that test asserts must not happen.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .max(2))

        await startConsuming(publisher, with: subscriber)
        source.yield(961)
        source.yield(962)
        await events.wait(for: .delivered)
        await events.wait(for: .delivered)

        subscriber.cancel()
        let termination = await source.waitForTermination()

        XCTAssertEqual(termination, .cancelled)
        assertGuardedPredicateFails(
            subscriber.recordedValues == [961],
            "The post-cancel suppression assertion must be able to see a second delivered value at "
                + "the same wait point."
        )
        XCTAssertEqual(subscriber.recordedValues, [961, 962])
    }

    func testNegativeControlANormalCompletionIsNotAFailure() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        // Finishing without an error, where the terminal-error test finishes with one.
        source.finish()
        _ = await events.waitForFinish()

        var carriesTheTerminalError = false
        if let completion = subscriber.recordedCompletions.first,
            case .failure(let error) = completion {
            carriesTheTerminalError = (error as? XLAsyncStreamPublisherTestError) == .terminal
        }
        assertGuardedPredicateFails(
            carriesTheTerminalError,
            "The terminal-error assertion must be able to fail when the stream ended without one."
        )
        XCTAssertEqual(subscriber.recordedCompletions.count, 1)
    }

    func testNegativeControlASuppressedCompletionIsVisibleToTheForwardingAssertion() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        await consumeStartupDemandUnit()
        source.yield(971)
        await events.wait(for: .delivered)
        await events.wait(for: .demandUnitConsumed)
        // Cancelling first makes the completion self-inflicted, so it is suppressed -- the opposite
        // of what the normal-completion test asserts.
        subscriber.cancel()
        let forwarded = await events.waitForFinish()

        assertGuardedPredicateFails(
            forwarded && !subscriber.recordedCompletions.isEmpty,
            "The forwarding assertion must be able to fail when the completion was suppressed."
        )
        XCTAssertFalse(forwarded)
        XCTAssertTrue(subscriber.recordedCompletions.isEmpty)
    }

    func testNegativeControlDeliveryOffTheMainQueueIsVisible() async throws {
        let source = ControllableStreamSource<Int>()
        // The raw publisher, without `xlLiveQueryPublisher`'s `.receive(on: DispatchQueue.main)`:
        // its consumer `Task` runs on the cooperative pool, never the main thread.
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        let deliveryOnMainQueue = XLAwaitableValue<Bool>()
        let subscriber = RecordingSubscriber<Int>(
            initialDemand: .unlimited,
            additionalDemand: { _ in
                deliveryOnMainQueue.fulfill(Thread.isMainThread)
                return .none
            }
        )

        await startConsuming(publisher, with: subscriber)
        DispatchQueue.global().async {
            source.yield(981)
        }
        let deliveredOnMainQueue = await deliveryOnMainQueue.wait()

        assertGuardedPredicateFails(
            deliveredOnMainQueue,
            "The main-queue delivery assertion must be able to fail when delivery is off-main."
        )
        subscriber.cancel()
    }

    func testNegativeControlADanglingCompletionAfterCancelWouldBeVisible() async throws {
        let source = ControllableStreamSource<Int>()
        let publisher = XLAsyncStreamPublisher(makeStream: source.makeStream)
        // Unlimited demand, so the consumer loop is provably inside `next()` when the stream ends and
        // the completion really is forwarded rather than left unobserved behind a demand wait.
        let subscriber = RecordingSubscriber<Int>(initialDemand: .unlimited)

        await startConsuming(publisher, with: subscriber)
        await consumeStartupDemandUnit()
        source.yield(991)
        await events.wait(for: .delivered)
        await events.wait(for: .demandUnitConsumed)
        // Ending the stream before cancelling leaves a completion recorded -- the dangling state the
        // repeat-cycle test asserts each round never leaves behind.
        source.finish()
        _ = await events.waitForFinish()
        subscriber.cancel()

        assertGuardedPredicateFails(
            subscriber.recordedCompletions.isEmpty,
            "The repeat-cycle assertion must be able to see a completion left behind by a round."
        )
    }

    // MARK: - Harness self-test (negative controls for #464)

    // `XCTExpectFailure` has no equivalent in swift-corelibs-xctest (the pinned Swift 5.9 Linux
    // cell), and intercepting a recorded failure is the only way to prove `XCTFail` fired, so these
    // two are Darwin-only. Every other control in this file is portable and runs on every cell.
    #if canImport(Darwin)
    /// Proves `ControllableStreamSource` fails the test explicitly, rather than silently dropping
    /// the value and letting a caller time out somewhere unrelated, when driven ahead of a stream
    /// that does not exist yet.
    func testYieldBeforeAnyStreamExistsFailsExplicitlyInsteadOfDroppingSilently() {
        let source = ControllableStreamSource<Int>()

        XCTExpectFailure("Yielding to a stream index that was never created must fail loudly.") {
            source.yield(1)
        }

        XCTAssertEqual(
            source.callCount,
            0,
            "The failed yield must not fabricate a stream that was never created."
        )
    }

    /// Same failure path, for `finish(throwing:stream:)`.
    func testFinishBeforeAnyStreamExistsFailsExplicitlyInsteadOfDroppingSilently() {
        let source = ControllableStreamSource<Int>()

        XCTExpectFailure("Finishing a stream index that was never created must fail loudly.") {
            source.finish()
        }

        XCTAssertEqual(source.callCount, 0)
    }

    /// Same rule for the termination signal this PR adds: a stream index nothing ever created fails
    /// where the mistake was made, instead of parking the caller forever.
    func testWaitingForTerminationOfAStreamThatWasNeverCreatedFailsInsteadOfHanging() async {
        let source = ControllableStreamSource<Int>()

        // The block form of `XCTExpectFailure` takes a synchronous closure, so the whole-test form
        // is used here: the awaited call is what must record the failure.
        XCTExpectFailure("Awaiting termination of a stream that was never created must fail loudly.")
        _ = await source.waitForTermination()

        XCTAssertEqual(source.callCount, 0)
    }
    #endif

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

    /// Subscribes `subscriber` and returns once its consumer task has started and its stream exists.
    ///
    /// Both waits are load-bearing. `fenceOnConsumerTaskStart()` gives this test its own event
    /// epoch, and `.streamCreated` is the point from which `source.yield(_:)` is guaranteed to find
    /// a stored continuation rather than fail (#464's ordering).
    private func startConsuming<Value>(
        _ publisher: XLAsyncStreamPublisher<Value>,
        with subscriber: RecordingSubscriber<Value>
    ) async {
        publisher.receive(subscriber: subscriber)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
    }

    /// Consumes the demand unit the consumer loop takes at startup, before any value exists.
    ///
    /// A subscriber with demand outstanding at subscribe time makes the loop consume a unit and call
    /// `next()` immediately, so `.demandUnitConsumed` is already in the recorder before the test
    /// yields anything. Consuming it here is what lets a later `.demandUnitConsumed` wait mean "the
    /// loop went back around and re-entered `next()`" rather than resolving against that first one.
    private func consumeStartupDemandUnit() async {
        await events.wait(for: .demandUnitConsumed)
    }

    /// Runs an independent subscription all the way from subscribing to a delivered value.
    ///
    /// Used by the two "performs no work" tests, whose claim is that a subscription never starts at
    /// all: there is no event of their own to await, so this canary -- created *after* the subject,
    /// and observed through the same seam -- is what proves the runtime reached the point of
    /// starting consumer tasks and delivering values before those tests assert nothing happened.
    private func runCanaryRoundTrip(
        value: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let canarySource = ControllableStreamSource<Int>()
        let canaryPublisher = XLAsyncStreamPublisher(makeStream: canarySource.makeStream)
        let canary = RecordingSubscriber<Int>(initialDemand: .max(1))

        await startConsuming(canaryPublisher, with: canary)
        canarySource.yield(value)
        await events.wait(for: .delivered)

        XCTAssertEqual(canary.recordedValues, [value], file: file, line: line)
        canary.cancel()
        _ = await canarySource.waitForTermination()
    }

    /// Asserts that `predicate` -- written to be the same predicate its paired test asserts -- does
    /// *not* hold in a deliberately-broken scenario. That is what makes the paired test falsifiable:
    /// its wait resumes early enough, and its assertion is specific enough, to catch the wrong
    /// outcome rather than passing vacuously.
    private func assertGuardedPredicateFails(
        _ predicate: @autoclosure () -> Bool,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(predicate(), "Negative control: \(description)", file: file, line: line)
    }
}
