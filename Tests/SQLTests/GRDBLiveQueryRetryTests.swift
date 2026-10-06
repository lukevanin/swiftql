#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif
import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@_spi(GRDB) @testable import SwiftQL


private enum RetryTestError: Error, Equatable {
    case permanent
}


private final class ManualRetryScheduler: @unchecked Sendable {

    private struct PendingDelay {
        let delay: TimeInterval
        let subject: PassthroughSubject<Void, Never>
    }

    private let lock = NSLock()

    private var pending: [PendingDelay] = []

    private var recorded: [TimeInterval] = []

    private var nextScheduledDelayObservers: [(TimeInterval) -> Void] = []

    /// The scheduling seam handed to the bridge.
    ///
    /// A delay becomes pending, and its observer runs, only once the bridge has subscribed to the
    /// returned publisher. `GRDBLiveQueryAsyncBridge.scheduleRetry(after:)` subscribes after this
    /// closure returns, and `runNext()` sends into a `PassthroughSubject`, which drops a value sent
    /// before anyone subscribes -- the retry would then never start. While GRDB delivered errors on
    /// the main queue, the test's own main-thread `runNext()` could not land in that window. As of
    /// #652, errors arrive on the bridge's private queue. The window therefore has to be closed
    /// here, the same way `AsyncStreamManualRetryScheduler` closes it.
    var scheduler: GRDBLiveQueryRetryScheduler {
        GRDBLiveQueryRetryScheduler { [weak self] delay in
            guard let self else {
                return Empty(completeImmediately: false).eraseToAnyPublisher()
            }
            let subject = PassthroughSubject<Void, Never>()
            self.lock.lock()
            self.recorded.append(delay)
            self.lock.unlock()
            return subject
                .handleEvents(receiveSubscription: { [weak self] _ in
                    self?.didSubscribe(to: PendingDelay(delay: delay, subject: subject))
                })
                .eraseToAnyPublisher()
        }
    }

    private func didSubscribe(to pendingDelay: PendingDelay) {
        let observer: ((TimeInterval) -> Void)?
        lock.lock()
        pending.append(pendingDelay)
        if nextScheduledDelayObservers.isEmpty {
            observer = nil
        }
        else {
            observer = nextScheduledDelayObservers.removeFirst()
        }
        lock.unlock()
        observer?(pendingDelay.delay)
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

    func observeNextScheduledDelay(
        _ observer: @escaping (TimeInterval) -> Void
    ) {
        lock.lock()
        nextScheduledDelayObservers.append(observer)
        lock.unlock()
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


@SQLTable(name: "LiveQueryRetryRecord")
private struct LiveQueryRetryRecord: Equatable {
    let id: String
    let value: Int
}


private struct InjectedBusyExpression: XLSQLiteExpression {
    typealias T = Int

    static let functionName = "swiftql_test_injected_busy"

    func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.functionName) { _ in }
    }
}


private final class InjectedBusyFunctionState: @unchecked Sendable {

    enum Behavior {
        case succeed
        case failOnce
        case failAlways
    }

    private let lock = NSLock()

    private let behavior: Behavior

    private var invocationCountValue = 0

    init(behavior: Behavior = .failOnce) {
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


/// Issue #309 removed `makeGRDBLiveQueryRetryPublisher`/`makeGRDBLiveQueryRetryAttempt` (the
/// Combine-only retry-attempt runner `publisher<T>(fetch:)` used to wrap) once `publish()`/
/// `publishOne()` stopped calling them: `GRDBRequest.stream()`/`streamOne()` are the only callers of
/// the shared `GRDBLiveQueryRetryState`/`GRDBLiveQueryRetryScheduler` engine now, and `publish()`
/// inherits that engine for free by adapting `stream()` rather than owning a second one. The direct
/// unit tests that drove `makeGRDBLiveQueryRetryPublisher` against synthetic `PassthroughSubject`
/// sources (attempt serialization, budget reset, cancellation suppressing late events, independent
/// per-subscriber budgets) were removed along with it; the same `GRDBLiveQueryRetryState` state
/// machine keeps equivalent coverage through the async-native path in
/// `Tests/SQLTests/GRDBLiveQueryAsyncStreamTests.swift`. What remains below are the tests that assert
/// the *observable* `publish()` contract end-to-end against a real GRDB database, which must -- and
/// do -- keep passing unchanged now that `publish()` is a Combine adapter over `stream()`.
final class XLGRDBLiveQueryRetryTests: XCTestCase {

    /// Issue #679: a statement reports the portable `XLDatabaseError`, and the
    /// policy classifies it by its portable code, not by a GRDB type.
    func testRetryPresetClassifiesThePortableBusyCode() {
        func portable(_ code: XLDatabaseErrorCode, native: Int32) -> XLDatabaseError {
            XLDatabaseError(
                code: code,
                nativeCode: native,
                message: nil,
                sql: nil,
                driver: XLDriverIdentifier(rawValue: "grdb"),
                underlying: CancellationError()
            )
        }

        XCTAssertEqual(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: portable(.busy, native: 5),
                retryNumber: 0
            ),
            0.1
        )
        XCTAssertEqual(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: portable(.busy, native: 517),
                retryNumber: 1
            ),
            0.2
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: portable(.locked, native: 6),
                retryNumber: 0
            )
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.terminal.retryDelay(
                after: portable(.busy, native: 5),
                retryNumber: 0
            )
        )
    }

    /// Issue #679: GRDB can fail while it starts an observation, outside any
    /// SwiftQL statement. The stream still ends with the portable error.
    func testStreamReportsAFailureGRDBRaisesItselfAsThePortableError() async {
        let bridge = GRDBLiveQueryAsyncBridge<Int>(
            policy: .terminal,
            scheduler: .queue(DispatchQueue(label: "SwiftQL.RetryTests.raw")),
            makeSource: { onError, _ in
                onError(DatabaseError(resultCode: .SQLITE_BUSY, message: "observation start"))
                return AnyDatabaseCancellable(cancel: {})
            }
        )

        do {
            _ = try await bridge.next()
            XCTFail("The observation failed to start.")
        }
        catch {
            guard let error = error as? XLDatabaseError else {
                return XCTFail("Expected an XLDatabaseError, received \(error).")
            }
            XCTAssertEqual(error.code, .busy)
            XCTAssertEqual(error.message, "observation start")
            XCTAssertTrue(error.underlying is DatabaseError)
        }
    }

    /// A BUSY failure GRDB raises itself is retried like a statement's, and
    /// the stream ends with the portable error once the retries run out.
    func testRetryBusyRetriesAFailureGRDBRaisesItself() async {
        let attempts = LockedValue(0)
        let scheduler = GRDBLiveQueryRetryScheduler { _ in
            Just(()).eraseToAnyPublisher()
        }
        let bridge = GRDBLiveQueryAsyncBridge<Int>(
            policy: .retryBusy,
            scheduler: scheduler,
            makeSource: { onError, _ in
                attempts.withValue { $0 += 1 }
                onError(DatabaseError(resultCode: .SQLITE_BUSY_SNAPSHOT))
                return AnyDatabaseCancellable(cancel: {})
            }
        )

        do {
            _ = try await bridge.next()
            XCTFail("Every attempt failed.")
        }
        catch {
            XCTAssertEqual((error as? XLDatabaseError)?.code, .busy, "\(error)")
        }
        XCTAssertEqual(attempts.read(), 4, "One attempt and three retries.")
    }

    func testRetryPresetAcceptsOnlyPrimaryBusyCodesAndUsesExactDelays() {
        let primaryBusy = XLDatabaseError(DatabaseError(resultCode: .SQLITE_BUSY), driver: .grdb)
        let extendedBusy = XLDatabaseError(DatabaseError(resultCode: .SQLITE_BUSY_SNAPSHOT), driver: .grdb)

        XCTAssertEqual(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: primaryBusy,
                retryNumber: 0
            ),
            0.1
        )
        XCTAssertEqual(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: extendedBusy,
                retryNumber: 1
            ),
            0.2
        )
        XCTAssertEqual(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: primaryBusy,
                retryNumber: 2
            ),
            0.4
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: primaryBusy,
                retryNumber: 3
            )
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.terminal.retryDelay(
                after: primaryBusy,
                retryNumber: 0
            )
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: XLDatabaseError(DatabaseError(resultCode: .SQLITE_LOCKED), driver: .grdb),
                retryNumber: 0
            )
        )
        XCTAssertNil(
            GRDBLiveQueryRetryPolicy.retryBusy.retryDelay(
                after: RetryTestError.permanent,
                retryNumber: 0
            )
        )
    }

    func testDefaultDatabasePolicyTerminatesOnBusyWithoutRetry() throws {
        let fixture = try makeIntegrationFixture(retryPolicy: nil)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let completionExpectation = expectation(description: "terminal busy failure")
        let receivedValues = LockedValue<[[LiveQueryRetryRecord]]>([])
        let completionErrors = LockedValue<[Error]>([])

        let cancellable = fixture.database
            .makeRequest(with: integrationStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        completionErrors.withValue { $0.append(error) }
                        completionExpectation.fulfill()
                    }
                },
                receiveValue: { value in
                    receivedValues.withValue { $0.append(value) }
                }
            )

        wait(for: [completionExpectation], timeout: 2)
        XCTAssertTrue(receivedValues.read().isEmpty)
        XCTAssertEqual(completionErrors.read().count, 1)
        XCTAssertEqual(
            (completionErrors.read().first as? XLDatabaseError)?.code,
            .busy
        )
        XCTAssertEqual(fixture.functionState.invocationCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRealGRDBObservationRecoversFromInjectedBusyAndKeepsObserving() throws {
        let fixture = try makeIntegrationFixture(retryPolicy: .retryBusy)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let recoveredExpectation = expectation(description: "fresh observation after busy")
        let updateExpectation = expectation(description: "continued observation after recovery")
        let completionErrors = LockedValue<[Error]>([])
        let values = LockedValue<[[LiveQueryRetryRecord]]>([])
        // Each state fulfils its expectation once. A delivery may repeat the
        // state already seen -- GRDB notifies the same value twice when it
        // cannot tell whether a change touched the observed value, on any
        // platform -- and fulfilling twice is an XCTest API violation.
        let didRecover = LockedValue<Bool>(false)
        let didUpdate = LockedValue<Bool>(false)

        let cancellable = fixture.database
            .makeRequest(with: integrationStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        completionErrors.withValue { $0.append(error) }
                    }
                },
                receiveValue: { rows in
                    values.withValue { $0.append(rows) }
                    if rows == [LiveQueryRetryRecord(id: "initial", value: 1)] {
                        let isFirst = didRecover.withValue { didRecover -> Bool in
                            defer { didRecover = true }
                            return !didRecover
                        }
                        if isFirst {
                            recoveredExpectation.fulfill()
                        }
                    }
                    else if rows == [
                        LiveQueryRetryRecord(id: "initial", value: 1),
                        LiveQueryRetryRecord(id: "updated", value: 2),
                    ] {
                        let isFirst = didUpdate.withValue { didUpdate -> Bool in
                            defer { didUpdate = true }
                            return !didUpdate
                        }
                        if isFirst {
                            updateExpectation.fulfill()
                        }
                    }
                }
            )

        wait(for: [recoveredExpectation], timeout: 2)
        XCTAssertGreaterThanOrEqual(fixture.functionState.invocationCount, 2)
        try fixture.database.databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO LiveQueryRetryRecord (id, value) VALUES (?, ?)",
                arguments: ["updated", 2]
            )
        }
        wait(for: [updateExpectation], timeout: 2)

        XCTAssertTrue(completionErrors.read().isEmpty)
        XCTAssertEqual(values.read().last, [
            LiveQueryRetryRecord(id: "initial", value: 1),
            LiveQueryRetryRecord(id: "updated", value: 2),
        ])
        XCTAssertGreaterThanOrEqual(fixture.functionState.invocationCount, 3)
        cancellable.cancel()
    }

    func testRealGRDBObservationExhaustsAlwaysBusyRetriesWithManualScheduler() throws {
        let scheduler = ManualRetryScheduler()
        let fixture = try makeIntegrationFixture(
            retryPolicy: .retryBusy,
            retryScheduler: scheduler.scheduler,
            busyBehavior: .failAlways
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let completionExpectation = expectation(description: "terminal busy after retry exhaustion")
        let receivedValues = LockedValue<[[LiveQueryRetryRecord]]>([])
        let completionErrors = LockedValue<[Error]>([])
        let firstDelayExpectation = expectation(description: "first BUSY retry delay scheduled")
        scheduler.observeNextScheduledDelay { delay in
            XCTAssertEqual(delay, 0.1)
            firstDelayExpectation.fulfill()
        }

        let cancellable = fixture.database
            .makeRequest(with: integrationStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        completionErrors.withValue { $0.append(error) }
                    case .finished:
                        XCTFail("An always-BUSY observation must not finish successfully.")
                    }
                    completionExpectation.fulfill()
                },
                receiveValue: { rows in
                    receivedValues.withValue { $0.append(rows) }
                }
            )

        wait(for: [firstDelayExpectation], timeout: 2)
        XCTAssertEqual(scheduler.pendingDelays, [0.1])
        XCTAssertEqual(fixture.functionState.invocationCount, 1)

        let secondDelayExpectation = expectation(description: "second BUSY retry delay scheduled")
        scheduler.observeNextScheduledDelay { delay in
            XCTAssertEqual(delay, 0.2)
            secondDelayExpectation.fulfill()
        }
        XCTAssertTrue(scheduler.runNext())
        wait(for: [secondDelayExpectation], timeout: 2)
        XCTAssertEqual(scheduler.pendingDelays, [0.2])
        XCTAssertEqual(fixture.functionState.invocationCount, 2)

        let thirdDelayExpectation = expectation(description: "third BUSY retry delay scheduled")
        scheduler.observeNextScheduledDelay { delay in
            XCTAssertEqual(delay, 0.4)
            thirdDelayExpectation.fulfill()
        }
        XCTAssertTrue(scheduler.runNext())
        wait(for: [thirdDelayExpectation], timeout: 2)
        XCTAssertEqual(scheduler.pendingDelays, [0.4])
        XCTAssertEqual(fixture.functionState.invocationCount, 3)

        XCTAssertTrue(scheduler.runNext())
        wait(for: [completionExpectation], timeout: 2)

        XCTAssertTrue(receivedValues.read().isEmpty)
        XCTAssertEqual(fixture.functionState.invocationCount, 4)
        XCTAssertEqual(scheduler.recordedDelays, [0.1, 0.2, 0.4])
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        XCTAssertEqual(completionErrors.read().count, 1)
        XCTAssertEqual(
            (completionErrors.read().first as? XLDatabaseError)?.code,
            .busy
        )
        withExtendedLifetime(cancellable) {}
    }

    func testRealGRDBObservationTreatsDecodeFailureAsPermanentUnderRetryBusy() throws {
        let scheduler = ManualRetryScheduler()
        let fixture = try makeIntegrationFixture(
            retryPolicy: .retryBusy,
            retryScheduler: scheduler.scheduler,
            busyBehavior: .succeed,
            initialValue: nil
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let completionExpectation = expectation(description: "terminal row decode failure")
        let receivedValues = LockedValue<[[LiveQueryRetryRecord]]>([])
        let completionErrors = LockedValue<[Error]>([])

        let cancellable = fixture.database
            .makeRequest(with: integrationStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        completionErrors.withValue { $0.append(error) }
                    case .finished:
                        XCTFail("A row-decoding failure must not finish successfully.")
                    }
                    completionExpectation.fulfill()
                },
                receiveValue: { rows in
                    receivedValues.withValue { $0.append(rows) }
                }
            )

        wait(for: [completionExpectation], timeout: 2)

        XCTAssertTrue(receivedValues.read().isEmpty)
        XCTAssertEqual(completionErrors.read().count, 1)
        XCTAssertEqual(
            completionErrors.read().first as? XLColumnReadError,
            XLColumnReadError(
                index: 1,
                expectedType: "Int",
                failure: .nullValue
            )
        )
        // No retry was scheduled: the decode failure ended the only attempt.
        XCTAssertTrue(scheduler.recordedDelays.isEmpty)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        // That one attempt can run the query twice. Where SQLite has no WAL
        // snapshots, as on Linux, GRDB fetches on a reader, decodes that
        // value on its reduce queue, and meanwhile fetches again on the writer
        // to start observing. The decode failure cancels the observation, and
        // whether the writer's fetch ran first is a race.
        XCTAssertTrue(
            (1...2).contains(fixture.functionState.invocationCount),
            "The permanent decode failure must terminate the one query attempt; "
                + "ran \(fixture.functionState.invocationCount) fetches."
        )
        withExtendedLifetime(cancellable) {}
    }

    private struct IntegrationFixture {
        let database: GRDBDatabase
        let directoryURL: URL
        let functionState: InjectedBusyFunctionState
    }

    private func makeIntegrationFixture(
        retryPolicy: GRDBLiveQueryRetryPolicy?,
        retryScheduler: GRDBLiveQueryRetryScheduler? = nil,
        busyBehavior: InjectedBusyFunctionState.Behavior = .failOnce,
        initialValue: Int? = 1
    ) throws -> IntegrationFixture {
        let directoryURL = try makeTemporaryDirectory(named: "live-query-retry")
        let databaseURL = directoryURL
            .appendingPathComponent("retry.sqlite", isDirectory: false)
        let functionState = InjectedBusyFunctionState(behavior: busyBehavior)
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    InjectedBusyExpression.functionName,
                    argumentCount: 0
                ) { _ in
                    try functionState.invoke()
                }
            )
        }

        let database: GRDBDatabase
        if let retryScheduler {
            let databasePool = try DatabasePool(
                path: databaseURL.path,
                configuration: configuration
            )
            database = try GRDBDatabase(
                databasePool: databasePool,
                formatter: XLiteFormatter(),
                logger: nil,
                liveQueryRetryPolicy: retryPolicy ?? .terminal,
                liveQueryRetryScheduler: retryScheduler
            )
        }
        else {
            let builder: GRDBDatabaseBuilder
            if let retryPolicy {
                builder = try GRDBDatabaseBuilder(
                    url: databaseURL,
                    grdbConfiguration: configuration,
                    logger: nil,
                    liveQueryRetryPolicy: retryPolicy
                )
            }
            else {
                builder = try GRDBDatabaseBuilder(
                    url: databaseURL,
                    grdbConfiguration: configuration,
                    logger: nil
                )
            }
            database = try builder.build()
        }
        try database.databasePool.write { database in
            let valueConstraint = initialValue == nil ? "" : " NOT NULL"
            try database.execute(
                sql: """
                    CREATE TABLE LiveQueryRetryRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT\(valueConstraint)
                    )
                    """
            )
            try database.execute(
                sql: "INSERT INTO LiveQueryRetryRecord (id, value) VALUES (?, ?)",
                arguments: ["initial", initialValue]
            )
        }
        return IntegrationFixture(
            database: database,
            directoryURL: directoryURL,
            functionState: functionState
        )
    }

    private func integrationStatement() -> any XLQueryStatement<LiveQueryRetryRecord> {
        sql { schema in
            let table = schema.table(LiveQueryRetryRecord.self)
            Select(table)
            From(table)
            Where(InjectedBusyExpression() == 1)
            OrderBy(table.id.ascending())
        }
    }
}
