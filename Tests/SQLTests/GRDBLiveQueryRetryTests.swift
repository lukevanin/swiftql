#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif
import Foundation
import GRDB
import XCTest
@testable import SwiftQL


private enum RetryTestError: Error, Equatable {
    case permanent
}


private final class LockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func read() -> Value {
        withValue { $0 }
    }
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

    var scheduler: GRDBLiveQueryRetryScheduler {
        GRDBLiveQueryRetryScheduler { [weak self] delay in
            guard let self else {
                return Empty(completeImmediately: false).eraseToAnyPublisher()
            }
            let subject = PassthroughSubject<Void, Never>()
            let observer: ((TimeInterval) -> Void)?
            self.lock.lock()
            self.pending.append(PendingDelay(delay: delay, subject: subject))
            self.recorded.append(delay)
            if self.nextScheduledDelayObservers.isEmpty {
                observer = nil
            }
            else {
                observer = self.nextScheduledDelayObservers.removeFirst()
            }
            self.lock.unlock()
            observer?(delay)
            return subject.eraseToAnyPublisher()
        }
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


private struct InjectedBusyExpression: XLExpression {
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

    func testRetryPresetAcceptsOnlyPrimaryBusyCodesAndUsesExactDelays() {
        let primaryBusy = DatabaseError(resultCode: .SQLITE_BUSY)
        let extendedBusy = DatabaseError(resultCode: .SQLITE_BUSY_SNAPSHOT)

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
                after: DatabaseError(resultCode: .SQLITE_LOCKED),
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
            (completionErrors.read().first as? DatabaseError)?.resultCode,
            .SQLITE_BUSY
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
                        recoveredExpectation.fulfill()
                    }
                    else if rows == [
                        LiveQueryRetryRecord(id: "initial", value: 1),
                        LiveQueryRetryRecord(id: "updated", value: 2),
                    ] {
                        updateExpectation.fulfill()
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
            (completionErrors.read().first as? DatabaseError)?.resultCode,
            .SQLITE_BUSY
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
        XCTAssertTrue(scheduler.recordedDelays.isEmpty)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        XCTAssertEqual(
            fixture.functionState.invocationCount,
            1,
            "The permanent decode failure must terminate after one real query attempt."
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
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
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
                    configuration: configuration,
                    logger: nil,
                    liveQueryRetryPolicy: retryPolicy
                )
            }
            else {
                builder = try GRDBDatabaseBuilder(
                    url: databaseURL,
                    configuration: configuration,
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
