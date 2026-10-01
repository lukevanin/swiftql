//
//  XLRequestCombineDefaultsTests.swift
//
//  Issue #684: the publish members are SwiftQL's own, built on a request's
//  stream members, and a request adapter needs no Combine to conform.
//
//  `XLAsyncStreamPublisherTests` proves the stream-to-publisher adapter's
//  demand mapping in depth. These tests prove that every request's publish
//  members are wired to that adapter, one stream per subscriber, through the
//  conformers in `SwiftQLStreamOnlyRequestFixture`, which import no Combine.
//  They also cover the publisher-to-stream bridge, `XLPublisherAsyncBridge`.
//

#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import Foundation
import SwiftQLStreamOnlyRequestFixture
import SwiftQLTestSupport
import XCTest
@testable import SwiftQL


final class XLRequestCombineDefaultsTests: XCTestCase {

    /// Observes the stream-to-publisher subscription seam for one test.
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

    // MARK: - The fixture needs no Combine

    /// The fixture target compiling is the proof that a conformer needs no Combine, so it must
    /// never import Combine or OpenCombine, or check whether it can.
    func testStreamOnlyFixtureNeverImportsCombine() throws {
        let fixtureDirectory = try swiftQLRepositoryRootURL()
            .appendingPathComponent("Tests/SwiftQLStreamOnlyRequestFixture")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: fixtureDirectory, includingPropertiesForKeys: nil)
        )
        let combineReference = try NSRegularExpression(
            pattern: #"^\s*(@\w+(\([^)]*\))?\s+)*import\s+((class|enum|func|let|protocol|struct|typealias|var)\s+)?(Open)?Combine\w*\b|canImport\s*\(\s*(Open)?Combine\w*\b"#,
            options: [.anchorsMatchLines]
        )
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            XCTAssertNil(
                combineReference.firstMatch(in: source, range: range),
                "\(url.lastPathComponent) must not import Combine or OpenCombine."
            )
        }
        XCTAssertGreaterThan(scanned, 0, "The fixture target has no Swift sources to check.")

        // The detector itself must notice each form it guards against.
        for line in [
            "import Combine",
            "@preconcurrency import OpenCombine",
            "import struct Combine.AnyPublisher",
            "#if canImport(Combine)",
            "import OpenCombineDispatch",
            "#elseif canImport(OpenCombineFoundation)",
        ] {
            let range = NSRange(line.startIndex..., in: line)
            XCTAssertNotNil(combineReference.firstMatch(in: line, range: range), line)
        }
    }

    // MARK: - Lazy start and independent observations

    func testZeroDemandStartsNoStreamUntilPositiveDemand() async throws {
        let request = StreamOnlyRequest()
        let subscriber = DemandSubscriber<[Int]>(initialDemand: .none)

        request.publish().subscribe(subscriber)
        // `.receive(on: DispatchQueue.main)` hands the subscription over on the main queue, so the
        // subscriber can request demand only once it has arrived.
        await subscriber.waitUntilSubscribed()
        // A canary subscription that runs from subscribing to a delivered value proves the runtime
        // got around to starting consumer tasks before the zero-demand assertion.
        await runCanaryRoundTrip()
        XCTAssertEqual(request.rows.startedCount, 0, "Zero demand must not call stream().")

        subscriber.request(.max(1))
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        XCTAssertEqual(request.rows.startedCount, 1, "Positive demand starts one stream.")

        request.rows.send([1])
        await subscriber.values.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(subscriber.values.read(), [[1]])
        subscriber.cancel()
    }

    func testEachSubscriberOwnsAnIndependentStream() async throws {
        let request = StreamOnlyRequest()
        let first = DemandSubscriber<Int?>(initialDemand: .unlimited)
        let second = DemandSubscriber<Int?>(initialDemand: .unlimited)

        let publisher = request.publishOne()
        publisher.subscribe(first)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        publisher.subscribe(second)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)

        XCTAssertEqual(request.row.startedCount, 2, "One streamOne() call per subscriber.")
        XCTAssertEqual(request.rows.startedCount, 0)

        request.row.send(7)
        await first.values.wait(untilCountIsAtLeast: 1)
        await second.values.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(first.values.read(), [7])
        XCTAssertEqual(second.values.read(), [7])

        first.cancel()
        _ = await events.waitForFinish()
        XCTAssertEqual(request.row.endedCount, 1, "Cancelling one subscriber ends only its stream.")
        second.cancel()
    }

    // MARK: - Delivery, failure, and cancellation

    func testValuesAndCompletionArriveOnTheMainQueue() async throws {
        let request = StreamOnlyRequest()
        let valueOnMain = XLAwaitableValue<Bool>()
        let completionOnMain = XLAwaitableValue<Bool>()
        let cancellable = request.publish().sink(
            receiveCompletion: { _ in completionOnMain.fulfill(Thread.isMainThread) },
            receiveValue: { _ in valueOnMain.fulfill(Thread.isMainThread) }
        )
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)

        let rows = request.rows
        DispatchQueue.global().async {
            rows.send([1, 2])
        }
        let deliveredOnMain = await valueOnMain.wait()
        XCTAssertTrue(deliveredOnMain)

        request.rows.finish()
        let completedOnMain = await completionOnMain.wait()
        XCTAssertTrue(completedOnMain)
        withExtendedLifetime(cancellable) {}
    }

    func testAStreamErrorFailsThePublisherWithThatError() async throws {
        struct ObservationFailure: Error, Equatable {}
        let request = StreamOnlyRequest()
        let subscriber = DemandSubscriber<Int?>(initialDemand: .unlimited)

        request.publishOne().subscribe(subscriber)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        request.row.finish(throwing: ObservationFailure())

        let completion = await subscriber.firstCompletion()
        guard case .failure(let error) = completion else {
            return XCTFail("Expected a failure, got \(completion).")
        }
        XCTAssertEqual(error as? ObservationFailure, ObservationFailure())
        XCTAssertTrue(subscriber.values.read().isEmpty)
    }

    func testCancellingTheSubscriptionEndsTheStream() async throws {
        let request = StreamOnlyRequest()
        let subscriber = DemandSubscriber<[Int]>(initialDemand: .unlimited)

        request.publish().subscribe(subscriber)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        request.rows.send([1])
        await subscriber.values.wait(untilCountIsAtLeast: 1)

        subscriber.cancel()
        let forwarded = await events.waitForFinish()

        XCTAssertFalse(forwarded, "Cancelling must not complete the subscriber.")
        XCTAssertEqual(request.rows.endedCount, 1, "Cancelling must end the stream.")
        XCTAssertTrue(subscriber.completions.read().isEmpty)
    }

    // MARK: - Bindings

    func testBindingsPublishersObserveThroughTheBindingsStreams() async throws {
        let request = StreamOnlyRequest()
        let packet = try Self.packet(binding: 5)
        let rows = DemandSubscriber<[Int]>(initialDemand: .unlimited)
        let row = DemandSubscriber<Int?>(initialDemand: .unlimited)

        request.publish(bindings: packet).subscribe(rows)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        request.publishOne(bindings: packet).subscribe(row)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)

        XCTAssertEqual(request.receivedBindingCounts, [1, 1], "Each packet reaches its stream member.")
        request.rows.send([5])
        request.row.send(5)
        await rows.values.wait(untilCountIsAtLeast: 1)
        await row.values.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(rows.values.read(), [[5]])
        XCTAssertEqual(row.values.read(), [5])
        rows.cancel()
        row.cancel()
    }

    /// A conformer that implements only `stream()` and `streamOne()` gets the `bindings:` stream
    /// defaults, so an empty packet observes and a nonempty one fails the publisher.
    func testMinimalConformerPublishBindingsUsesTheCompatibilityDefaults() async throws {
        let request = MinimalStreamOnlyRequest()
        let accepted = DemandSubscriber<[Int]>(initialDemand: .unlimited)
        request.publish(bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty)).subscribe(accepted)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        request.rows.send([3])
        await accepted.values.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(accepted.values.read(), [[3]])
        accepted.cancel()

        let rejected = DemandSubscriber<Int?>(initialDemand: .unlimited)
        request.publishOne(bindings: try Self.packet(binding: 1)).subscribe(rejected)
        let completion = await rejected.firstCompletion()
        guard case .failure(let error) = completion,
              case .unsupportedInvocationBindings(let requestType, _)? = error as? XLRequestBindingError
        else {
            return XCTFail("Expected unsupportedInvocationBindings, got \(completion).")
        }
        XCTAssertTrue(requestType.contains("MinimalStreamOnlyRequest"))
        XCTAssertEqual(request.row.startedCount, 0, "A rejected packet must not start the adapter's stream.")
    }

    // MARK: - XLPublisherAsyncBridge

    func testBridgeMakesThePublisherOnlyOnFirstIteration() async throws {
        let subject = WatchedSubject<Int>()
        let made = LockedValue(0)
        let stream = XLPublisherAsyncBridge(makePublisher: { () -> WatchedSubject<Int> in
            made.withValue { $0 += 1 }
            return subject
        }).stream()
        XCTAssertEqual(made.read(), 0, "Making the stream must not make the publisher.")

        let iterator = BridgeIterator(stream)
        let first = Task { try await iterator.next() }
        await subject.waitUntilSubscribed()
        XCTAssertEqual(made.read(), 1)

        subject.send(1)
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)

        subject.send(completion: .finished)
        let end = try await iterator.next()
        XCTAssertNil(end, "A finished publisher ends the stream.")
        XCTAssertEqual(made.read(), 1, "The publisher is made once.")
    }

    func testBridgeBuffersOnlyTheNewestUndeliveredValue() async throws {
        let subject = WatchedSubject<Int>()
        let iterator = BridgeIterator(XLPublisherAsyncBridge(makePublisher: { subject }).stream())
        let first = Task { try await iterator.next() }
        await subject.waitUntilSubscribed()
        subject.send(1)
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)

        subject.send(2)
        subject.send(3)
        let newest = try await iterator.next()
        XCTAssertEqual(newest, 3, "A newer value replaces one the consumer has not asked for.")
    }

    func testBridgeThrowsAFailureAndThenEnds() async throws {
        struct PublisherFailure: Error, Equatable {}
        let subject = WatchedSubject<Int>()
        let iterator = BridgeIterator(XLPublisherAsyncBridge(makePublisher: { subject }).stream())
        let first = Task { try await iterator.next() }
        await subject.waitUntilSubscribed()
        subject.send(completion: .failure(PublisherFailure()))

        do {
            _ = try await first.value
            XCTFail("The failure must be thrown.")
        }
        catch {
            XCTAssertEqual(error as? PublisherFailure, PublisherFailure())
        }
        let end = try await iterator.next()
        XCTAssertNil(end)
    }

    func testCancellingTheConsumingTaskCancelsTheSubscription() async throws {
        let subject = WatchedSubject<Int>()
        let stream = XLPublisherAsyncBridge(makePublisher: { subject }).stream()
        let ended = XLAwaitableValue<Bool>()
        let seen = XLAwaitableState<[Int]>([])

        let task = Task {
            do {
                for try await value in stream {
                    seen.withValue { $0.append(value) }
                }
                ended.fulfill(true)
            }
            catch {
                ended.fulfill(false)
            }
        }
        await subject.waitUntilSubscribed()
        subject.send(1)
        await seen.wait(untilCountIsAtLeast: 1)

        task.cancel()
        let endedWithNil = await ended.wait()
        XCTAssertTrue(endedWithNil, "Cancellation ends iteration with nil, not an error.")
        await subject.waitUntilCancelled()
    }

    /// The two bridges compose: a conformer that only has a publisher implements its streams with
    /// `XLPublisherAsyncBridge`, and its publish members, built on those streams, deliver its
    /// values and cancel its publisher.
    func testPublisherOnlyConformerRoundTripsThroughBothBridges() async throws {
        let request = SubjectBridgedRequest()
        let values = XLAwaitableState<[[Int]]>([])
        let cancellable = request.publish().sink(
            receiveCompletion: { _ in },
            receiveValue: { rows in values.withValue { $0.append(rows) } }
        )
        await request.subject.waitUntilSubscribed()

        request.subject.send([4, 2])
        await values.wait(untilCountIsAtLeast: 1)
        XCTAssertEqual(values.read(), [[4, 2]])

        cancellable.cancel()
        await request.subject.waitUntilCancelled()
    }

    // MARK: - Helpers

    private static func packet(binding value: Int64) throws -> XLInvocationBindings<XLSQLiteValue> {
        let slot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("value"),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(site: .parameter, path: XLValueCodingPath("value"))
        )
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: try XLParameterLayout(slots: [slot]),
            bindings: [try XLInvocationBinding(slot: slot, value: .integer(value))]
        )
    }

    /// Runs an independent subscription from subscribing to a delivered value, so a "no work"
    /// assertion is made after the runtime has demonstrably started consumer tasks.
    private func runCanaryRoundTrip() async {
        let canary = StreamOnlyRequest()
        let subscriber = DemandSubscriber<[Int]>(initialDemand: .max(1))
        canary.publish().subscribe(subscriber)
        await events.fenceOnConsumerTaskStart()
        await events.wait(for: .streamCreated)
        canary.rows.send([0])
        await subscriber.values.wait(untilCountIsAtLeast: 1)
        // The canary's demand is spent, so its consumer is waiting for more rather than in the
        // stream: cancelling it ends the loop without a `.finished` event to await. The next
        // `fenceOnConsumerTaskStart()` discards whatever it left behind.
        subscriber.cancel()
    }
}


/// A conformer with only a Combine publisher, implementing its streams with the one-line bridge.
private struct SubjectBridgedRequest: XLRequest, @unchecked Sendable {

    let subject = WatchedSubject<[Int]>()

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {}

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {}

    func fetchAll() throws -> [Int] {
        []
    }

    func fetchOne() throws -> Int? {
        nil
    }

    func stream() -> AsyncThrowingStream<[Int], Error> {
        XLPublisherAsyncBridge(makePublisher: { subject }).stream()
    }

    func streamOne() -> AsyncThrowingStream<Int?, Error> {
        XLPublisherAsyncBridge(makePublisher: { subject.map(\.first) }).stream()
    }
}


/// A `PassthroughSubject` a test can await: a subscriber that has received its subscription, and
/// so has already requested its demand, and a subscription cancelled.
private final class WatchedSubject<Output>: Publisher, @unchecked Sendable {

    typealias Failure = Error

    private let subject = PassthroughSubject<Output, Error>()

    private let subscriptions = XLAwaitableState(0)

    private let cancellations = XLAwaitableState(0)

    func receive<S>(subscriber: S) where S: Subscriber, S.Input == Output, S.Failure == Error {
        let subscriptions = subscriptions
        let cancellations = cancellations
        subject
            .handleEvents(receiveCancel: { cancellations.withValue { $0 += 1 } })
            .receive(subscriber: AnnouncingSubscriber(downstream: subscriber) {
                subscriptions.withValue { $0 += 1 }
            })
    }

    func send(_ value: Output) {
        subject.send(value)
    }

    func send(completion: Subscribers.Completion<Error>) {
        subject.send(completion: completion)
    }

    /// Suspends until a subscriber can receive what this subject sends.
    func waitUntilSubscribed() async {
        await subscriptions.wait(until: { $0 >= 1 })
    }

    /// Suspends until a subscription has been cancelled.
    func waitUntilCancelled() async {
        await cancellations.wait(until: { $0 >= 1 })
    }
}


/// Announces a subscription only after the downstream subscriber has received it, which is when
/// a sink has already requested its demand, so a value sent after the announcement is not dropped.
private struct AnnouncingSubscriber<Downstream: Subscriber>: Subscriber {

    typealias Input = Downstream.Input

    typealias Failure = Downstream.Failure

    let combineIdentifier = CombineIdentifier()

    let downstream: Downstream

    let announce: () -> Void

    init(downstream: Downstream, announce: @escaping () -> Void) {
        self.downstream = downstream
        self.announce = announce
    }

    func receive(subscription: Subscription) {
        downstream.receive(subscription: subscription)
        announce()
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        downstream.receive(input)
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        downstream.receive(completion: completion)
    }
}


/// A subscriber whose demand the test grants, recording what it receives in awaitable state.
private final class DemandSubscriber<Input>: Subscriber, @unchecked Sendable {

    typealias Failure = Error

    let values = XLAwaitableState<[Input]>([])

    let completions = XLAwaitableState<[Subscribers.Completion<Error>]>([])

    private let subscribed = XLAwaitableState(false)

    private let lock = NSLock()

    private var subscription: Subscription?

    private let initialDemand: Subscribers.Demand

    init(initialDemand: Subscribers.Demand) {
        self.initialDemand = initialDemand
    }

    func receive(subscription: Subscription) {
        lock.lock()
        self.subscription = subscription
        lock.unlock()
        subscription.request(initialDemand)
        subscribed.set(true)
    }

    /// Suspends until the subscriber has its subscription, so ``request(_:)`` reaches it.
    func waitUntilSubscribed() async {
        await subscribed.wait(for: true)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        values.withValue { $0.append(input) }
        return .none
    }

    func receive(completion: Subscribers.Completion<Error>) {
        completions.withValue { $0.append(completion) }
    }

    func request(_ demand: Subscribers.Demand) {
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

    /// Suspends until the subscriber completes, and returns the completion.
    func firstCompletion() async -> Subscribers.Completion<Error> {
        await completions.wait(untilCountIsAtLeast: 1)
        return completions.read()[0]
    }
}


/// Holds one stream's iterator across awaits, so a test can start a `next()` call in a task and
/// make the following one itself.
private final class BridgeIterator: @unchecked Sendable {

    private var iterator: AsyncThrowingStream<Int, Error>.AsyncIterator

    init(_ stream: AsyncThrowingStream<Int, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Int? {
        try await iterator.next()
    }
}
