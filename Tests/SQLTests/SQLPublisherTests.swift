//
//  SQLPublisherTests.swift
//
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import Combine
import XCTest
import GRDB
import SwiftQL


struct InsertTest {
    
    private static let idParameter = XLNamedBindingReference<String>(name: "id")

    private static let valueParameter = XLNamedBindingReference<Int>(name: "value")

    private static func makeStatement() -> any XLInsertStatement<TestTable> {
        sqlInsert {
            let table = $0.table(TestTable.self)
            return insert(table).values(
                TestTable.MetaInsert(
                    id: idParameter,
                    value: valueParameter
                )
            )
        }
    }
    
    private let request: XLWriteRequest
    
    init(database: XLDatabase) {
        request = database.makeRequest(with: Self.makeStatement())
    }
    
    func execute(_ entity: TestTable) throws {
        var request = request
        request.set(Self.idParameter, entity.id)
        request.set(Self.valueParameter, entity.value)
        try request.execute()
    }
}


struct UpdateTest {
    
    private static let idParameter = XLNamedBindingReference<String>(name: "id")

    private static let valueParameter = XLNamedBindingReference<Int>(name: "value")

    private static func makeStatement() -> any XLUpdateStatement<TestTable> {
        sqlUpdate {
            let table = $0.into(TestTable.self)
            return update(table, set: TestTable.MetaUpdate(
                value: valueParameter
            ))
            .where(table.id == idParameter)
        }
    }
    
    private let request: XLWriteRequest
    
    init(database: XLDatabase) {
        request = database.makeRequest(with: Self.makeStatement())
    }
    
    func execute(id: String, value: Int) throws {
        var request = request
        request.set(Self.idParameter, id)
        request.set(Self.valueParameter, value)
        try request.execute()
    }
}


private final class PublisherLockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func read() -> Value {
        withValue { $0 }
    }
}


private final class ManualDemandSubscriber<Input>: Subscriber, @unchecked Sendable {

    typealias Failure = Error

    private let lock = NSLock()

    private var subscription: Subscription?

    private let receiveSubscriptionCallback: () -> Void

    private let receiveValueCallback: (Input) -> Void

    private let receiveAdditionalDemandCallback: (Input) -> Subscribers.Demand

    private let receiveCompletionCallback: (Subscribers.Completion<Error>) -> Void

    init(
        receiveSubscription: @escaping () -> Void,
        receiveValue: @escaping (Input) -> Void,
        receiveAdditionalDemand: @escaping (Input) -> Subscribers.Demand = { _ in .none },
        receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void
    ) {
        self.receiveSubscriptionCallback = receiveSubscription
        self.receiveValueCallback = receiveValue
        self.receiveAdditionalDemandCallback = receiveAdditionalDemand
        self.receiveCompletionCallback = receiveCompletion
    }

    func receive(subscription: Subscription) {
        lock.lock()
        self.subscription = subscription
        lock.unlock()
        receiveSubscriptionCallback()
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        receiveValueCallback(input)
        return receiveAdditionalDemandCallback(input)
    }

    func receive(completion: Subscribers.Completion<Error>) {
        receiveCompletionCallback(completion)
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
}


private struct BlockingObservationExpression: XLExpression {

    typealias T = Int

    static let functionName = "swiftql_test_blocking_observation"

    func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.functionName) { _ in }
    }
}


private enum ObservationTestError: Error {
    case rollback
}


private final class BlockingObservationFunctionState: @unchecked Sendable {

    private let releaseSemaphore = DispatchSemaphore(value: 0)

    private let onStart: @Sendable () -> Void

    private let onFinish: @Sendable () -> Void

    init(
        onStart: @escaping @Sendable () -> Void,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func invoke() -> Int {
        onStart()
        releaseSemaphore.wait()
        onFinish()
        return 1
    }

    func release() {
        releaseSemaphore.signal()
    }
}


final class XLPublisherTests: XCTestCase {

    private final class RecordingLogger: XLLogger {
        private let lock = NSLock()
        private var messages: [String] = []

        func log(level: XLLogLevel, message: String) {
            lock.lock()
            messages.append(message)
            lock.unlock()
        }

        func count(containing fragment: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return messages.filter { $0.contains(fragment) }.count
        }
    }

    private var formatter: XLiteFormatter!
    private var databaseDirectoryURL: URL!
    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!
    private var logger: RecordingLogger!

    private var insertTest: InsertTest!
    private var updateTest: UpdateTest!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appending(path: "primary.sqlite", directoryHint: .notDirectory)
        databasePool = try DatabasePool(path: fileURL.path)
        logger = RecordingLogger()
        database = try GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: logger)
        insertTest = InsertTest(database: database)
        updateTest = UpdateTest(database: database)
    }

    override func tearDown() {
        cancellables.removeAll()
        insertTest = nil
        updateTest = nil
        database = nil
        databasePool = nil
        logger = nil
        formatter = nil
        try? FileManager.default.removeItem(at: databaseDirectoryURL)
        databaseDirectoryURL = nil
    }

    func testPublishExistingEntities() throws {
        try createTestTable()
        try insertTest.execute(TestTable(id: "foo", value: 9000))
        try insertTest.execute(TestTable(id: "bar", value: 42))
        try insertTest.execute(TestTable(id: "baz", value: 100))

        let valueExpectation = expectation(description: "initial rows")
        var receivedRows: [TestTable]?
        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    guard receivedRows == nil else { return }
                    receivedRows = rows
                    valueExpectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [valueExpectation], timeout: 2)
        XCTAssertEqual(
            receivedRows,
            [
                TestTable(id: "bar", value: 42),
                TestTable(id: "baz", value: 100),
                TestTable(id: "foo", value: 9000),
            ]
        )
    }

    func testPublisherFetchesCurrentStateAtFirstDemand() throws {
        try createTestTable()
        let publisher = database.makeRequest(with: orderedStatement()).publish()
        try insertDirect(TestTable(id: "written-before-subscription", value: 1))

        let valueExpectation = expectation(description: "current initial value")
        var firstRows: [TestTable]?
        publisher
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    guard firstRows == nil else { return }
                    firstRows = rows
                    valueExpectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [valueExpectation], timeout: 2)
        XCTAssertEqual(firstRows, [TestTable(id: "written-before-subscription", value: 1)])
    }

    func testEachSubscriberReceivesFreshInitialValue() throws {
        try createTestTable()
        let publisher = database.makeRequest(with: orderedStatement()).publish()
        let firstInitialExpectation = expectation(description: "first subscriber initial value")
        let firstUpdatedExpectation = expectation(description: "first subscriber update")
        let firstSharedUpdateExpectation = expectation(description: "first subscriber shared update")
        var firstSawInitial = false
        var firstSawUpdate = false
        var firstSawSharedUpdate = false

        publisher
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    if !firstSawInitial {
                        firstSawInitial = true
                        XCTAssertEqual(rows, [])
                        firstInitialExpectation.fulfill()
                    }
                    else if rows == [TestTable(id: "foo", value: 7)] && !firstSawUpdate {
                        firstSawUpdate = true
                        firstUpdatedExpectation.fulfill()
                    }
                    else if rows == [TestTable(id: "foo", value: 8)] && !firstSawSharedUpdate {
                        firstSawSharedUpdate = true
                        firstSharedUpdateExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [firstInitialExpectation], timeout: 2)
        try insertTest.execute(TestTable(id: "foo", value: 7))
        wait(for: [firstUpdatedExpectation], timeout: 2)

        let secondInitialExpectation = expectation(description: "second subscriber current value")
        let secondSharedUpdateExpectation = expectation(description: "second subscriber shared update")
        var secondInitialRows: [TestTable]?
        var secondSawSharedUpdate = false
        publisher
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    if secondInitialRows == nil {
                        secondInitialRows = rows
                        secondInitialExpectation.fulfill()
                    }
                    else if rows == [TestTable(id: "foo", value: 8)] && !secondSawSharedUpdate {
                        secondSawSharedUpdate = true
                        secondSharedUpdateExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [secondInitialExpectation], timeout: 2)
        XCTAssertEqual(secondInitialRows, [TestTable(id: "foo", value: 7)])
        try updateTest.execute(id: "foo", value: 8)
        wait(
            for: [firstSharedUpdateExpectation, secondSharedUpdateExpectation],
            timeout: 2
        )
    }

    func testDirectWriteThroughObservedPoolPublishes() throws {
        try createTestTable()
        let initialExpectation = expectation(description: "initial value")
        let updateExpectation = expectation(description: "direct write update")
        var sawInitial = false
        var sawUpdate = false

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    if !sawInitial {
                        sawInitial = true
                        XCTAssertEqual(rows, [])
                        initialExpectation.fulfill()
                    }
                    else if rows == [TestTable(id: "direct", value: 42)] && !sawUpdate {
                        sawUpdate = true
                        updateExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try insertDirect(TestTable(id: "direct", value: 42))
        wait(for: [updateExpectation], timeout: 2)
    }

    func testIrrelevantTableWriteDoesNotChangeObservedSnapshot() throws {
        try createTestTable()
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE Other (id TEXT NOT NULL PRIMARY KEY)")
        }
        let initialExpectation = expectation(description: "initial observed snapshot")
        let livenessExpectation = expectation(description: "relevant commit liveness")
        let snapshots = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillInitial = PublisherLockedValue(false)
        let didFulfillLiveness = PublisherLockedValue(false)
        let finalRows = [TestTable(id: "relevant", value: 1)]

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    snapshots.withValue { $0.append(rows) }
                    if rows.isEmpty && didFulfillInitial.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        initialExpectation.fulfill()
                    }
                    if rows == finalRows && didFulfillLiveness.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        livenessExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try databasePool.write { database in
            try database.execute(sql: "INSERT INTO Other (id) VALUES ('irrelevant')")
        }
        try insertDirect(TestTable(id: "relevant", value: 1))
        wait(for: [livenessExpectation], timeout: 2)

        XCTAssertTrue(
            snapshots.read().allSatisfy { $0.isEmpty || $0 == finalRows },
            "An irrelevant-table commit must not create a different query snapshot."
        )
    }

    func testRolledBackWriteNeverAppearsBeforeCommittedLiveness() throws {
        try createTestTable()
        let initialExpectation = expectation(description: "initial durable snapshot")
        let livenessExpectation = expectation(description: "committed liveness snapshot")
        let snapshots = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillInitial = PublisherLockedValue(false)
        let didFulfillLiveness = PublisherLockedValue(false)
        let committedRows = [TestTable(id: "committed", value: 2)]

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    snapshots.withValue { $0.append(rows) }
                    if rows.isEmpty && didFulfillInitial.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        initialExpectation.fulfill()
                    }
                    if rows == committedRows && didFulfillLiveness.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        livenessExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        do {
            try databasePool.write { database in
                try database.execute(
                    sql: "INSERT INTO Test (id, value) VALUES (?, ?)",
                    arguments: ["rolled-back", 1]
                )
                throw ObservationTestError.rollback
            }
            XCTFail("Expected the injected transaction rollback.")
        }
        catch ObservationTestError.rollback {
            // The thrown error is the deterministic rollback trigger.
        }
        try insertDirect(TestTable(id: "committed", value: 2))
        wait(for: [livenessExpectation], timeout: 2)

        let observed = snapshots.read()
        XCTAssertFalse(observed.flatMap { $0 }.contains { $0.id == "rolled-back" })
        XCTAssertTrue(observed.allSatisfy { $0.isEmpty || $0 == committedRows })
    }

    func testMultipleWritesInOneTransactionPublishOnlyDurableState() throws {
        try createTestTable()
        let initialExpectation = expectation(description: "initial transaction snapshot")
        let finalExpectation = expectation(description: "durable transaction snapshot")
        let snapshots = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillInitial = PublisherLockedValue(false)
        let didFulfillFinal = PublisherLockedValue(false)
        let finalRows = [
            TestTable(id: "a", value: 3),
            TestTable(id: "b", value: 2),
        ]

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    snapshots.withValue { $0.append(rows) }
                    if rows.isEmpty && didFulfillInitial.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        initialExpectation.fulfill()
                    }
                    if rows == finalRows && didFulfillFinal.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        finalExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO Test (id, value) VALUES (?, ?)",
                arguments: ["a", 1]
            )
            try database.execute(
                sql: "INSERT INTO Test (id, value) VALUES (?, ?)",
                arguments: ["b", 2]
            )
            try database.execute(
                sql: "UPDATE Test SET value = ? WHERE id = ?",
                arguments: [3, "a"]
            )
        }
        wait(for: [finalExpectation], timeout: 2)

        XCTAssertTrue(
            snapshots.read().allSatisfy { $0.isEmpty || $0 == finalRows },
            "One transaction may coalesce, but no intermediate durable state may escape."
        )
    }

    func testZeroDemandStartsNoFetchAndFirstDemandReadsCurrentState() throws {
        try createTestTable()
        let subscriptionExpectation = expectation(description: "zero-demand subscription")
        let currentValueExpectation = expectation(description: "first demanded current value")
        let values = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillCurrentValue = PublisherLockedValue(false)
        let currentRows = [TestTable(id: "before-demand", value: 1)]
        let subscriber = ManualDemandSubscriber<[TestTable]>(
            receiveSubscription: {
                subscriptionExpectation.fulfill()
            },
            receiveValue: { rows in
                values.withValue { $0.append(rows) }
                if rows == currentRows && didFulfillCurrentValue.withValue({ value in
                    guard !value else { return false }
                    value = true
                    return true
                }) {
                    currentValueExpectation.fulfill()
                }
            },
            receiveCompletion: { completion in
                XCTFail("Unexpected zero-demand publisher completion: \(completion)")
            }
        )

        database.makeRequest(with: orderedStatement()).publish().subscribe(subscriber)
        wait(for: [subscriptionExpectation], timeout: 2)
        XCTAssertEqual(logger.count(containing: "fetchAll:"), 0)
        try insertDirect(TestTable(id: "before-demand", value: 1))
        drainMainQueue(description: "zero-demand write barrier")
        XCTAssertTrue(values.read().isEmpty)
        XCTAssertEqual(logger.count(containing: "fetchAll:"), 0)

        subscriber.request(.max(1))
        wait(for: [currentValueExpectation], timeout: 2)
        XCTAssertEqual(values.read(), [currentRows])
        subscriber.cancel()
    }

    func testIncrementalDemandBoundsDeliveryUntilLaterCommitReachesCurrentState() throws {
        try createTestTable()
        try insertTest.execute(TestTable(id: "initial", value: 1))
        let subscriptionExpectation = expectation(description: "incremental-demand subscription")
        let initialExpectation = expectation(description: "first demanded snapshot")
        let finalExpectation = expectation(description: "later demanded current snapshot")
        let values = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillInitial = PublisherLockedValue(false)
        let didFulfillFinal = PublisherLockedValue(false)
        let didGrantIntermediateDemand = PublisherLockedValue(false)
        let initialRows = [TestTable(id: "initial", value: 1)]
        let intermediateRows = [
            TestTable(id: "initial", value: 1),
            TestTable(id: "undemanded", value: 2),
        ]
        let finalRows = [
            TestTable(id: "demanded", value: 3),
            TestTable(id: "initial", value: 1),
            TestTable(id: "undemanded", value: 2),
        ]
        let subscriber = ManualDemandSubscriber<[TestTable]>(
            receiveSubscription: {
                subscriptionExpectation.fulfill()
            },
            receiveValue: { rows in
                values.withValue { $0.append(rows) }
                if rows == initialRows && didFulfillInitial.withValue({ value in
                    guard !value else { return false }
                    value = true
                    return true
                }) {
                    initialExpectation.fulfill()
                }
                if rows == finalRows && didFulfillFinal.withValue({ value in
                    guard !value else { return false }
                    value = true
                    return true
                }) {
                    finalExpectation.fulfill()
                }
            },
            receiveAdditionalDemand: { rows in
                // A refresh that was already in flight when demand ran out may
                // consume newly requested demand. Replenish exactly once so
                // the later liveness commit can still publish current state
                // without turning finite demand into an open-ended loop.
                guard rows == intermediateRows else { return .none }
                return didGrantIntermediateDemand.withValue { didGrant in
                    guard !didGrant else { return .none }
                    didGrant = true
                    return .max(1)
                }
            },
            receiveCompletion: { completion in
                XCTFail("Unexpected incremental-demand publisher completion: \(completion)")
            }
        )

        database.makeRequest(with: orderedStatement()).publish().subscribe(subscriber)
        wait(for: [subscriptionExpectation], timeout: 2)
        subscriber.request(.max(1))
        wait(for: [initialExpectation], timeout: 2)
        let initialFetchCount = logger.count(containing: "fetchAll:")
        XCTAssertGreaterThan(initialFetchCount, 0)

        try insertDirect(TestTable(id: "undemanded", value: 2))
        waitForFetchCount(atLeast: initialFetchCount + 1, containing: "fetchAll:")
        drainMainQueue(description: "finite-demand delivery barrier")
        XCTAssertEqual(values.read(), [initialRows])

        subscriber.request(.max(1))
        try insertDirect(TestTable(id: "demanded", value: 3))
        wait(for: [finalExpectation], timeout: 2)
        let observed = values.read()
        XCTAssertTrue(
            observed == [initialRows, finalRows]
                || observed == [initialRows, intermediateRows, finalRows],
            "Unexpected incremental-demand snapshots: \(observed)"
        )
        subscriber.cancel()
    }

    func testCancellationBeforeDemandStartsNoFetch() throws {
        try createTestTable()
        let subscriptionExpectation = expectation(description: "cancel-before-demand subscription")
        let freshLivenessExpectation = expectation(description: "fresh subscriber after cancellation")
        let values = PublisherLockedValue<[[TestTable]]>([])
        let subscriber = ManualDemandSubscriber<[TestTable]>(
            receiveSubscription: {
                subscriptionExpectation.fulfill()
            },
            receiveValue: { rows in
                values.withValue { $0.append(rows) }
            },
            receiveCompletion: { completion in
                XCTFail("Unexpected cancel-before-demand completion: \(completion)")
            }
        )

        database.makeRequest(with: orderedStatement()).publish().subscribe(subscriber)
        wait(for: [subscriptionExpectation], timeout: 2)
        subscriber.cancel()
        try insertDirect(TestTable(id: "after-zero-demand-cancel", value: 1))
        drainMainQueue(description: "cancel-before-demand write barrier")
        XCTAssertTrue(values.read().isEmpty)
        XCTAssertEqual(logger.count(containing: "fetchAll:"), 0)

        var freshDidFulfill = false
        let freshCancellable = database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected fresh publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    if rows == [TestTable(id: "after-zero-demand-cancel", value: 1)]
                        && !freshDidFulfill {
                        freshDidFulfill = true
                        freshLivenessExpectation.fulfill()
                    }
                }
            )
        wait(for: [freshLivenessExpectation], timeout: 2)
        drainMainQueue(description: "cancel-before-demand callback barrier")
        XCTAssertTrue(values.read().isEmpty)
        freshCancellable.cancel()
    }

    func testCancellationDuringInFlightSQLiteWorkSuppressesDelivery() throws {
        let startedExpectation = expectation(description: "SQLite fetch entered blocking function")
        let finishedExpectation = expectation(description: "SQLite fetch left blocking function")
        let freshLivenessExpectation = expectation(description: "fresh publisher after in-flight cancellation")
        let functionState = BlockingObservationFunctionState(
            onStart: {
                startedExpectation.fulfill()
            },
            onFinish: {
                finishedExpectation.fulfill()
            }
        )
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    BlockingObservationExpression.functionName,
                    argumentCount: 0
                ) { _ in
                    functionState.invoke()
                }
            )
        }
        let blockingURL = databaseDirectoryURL
            .appending(path: "blocking.sqlite", directoryHint: .notDirectory)
        let blockingPool = try DatabasePool(
            path: blockingURL.path,
            configuration: configuration
        )
        let blockingDatabase = try GRDBDatabase(
            databasePool: blockingPool,
            formatter: formatter,
            logger: nil
        )
        try createTestTable(in: blockingPool)
        try insertDirect(TestTable(id: "initial", value: 1), in: blockingPool)
        let cancelledValues = PublisherLockedValue<[[TestTable]]>([])

        let cancelledCancellable = blockingDatabase
            .makeRequest(with: blockingStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected in-flight publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    cancelledValues.withValue { $0.append(rows) }
                }
            )

        wait(for: [startedExpectation], timeout: 2)
        cancelledCancellable.cancel()
        functionState.release()
        wait(for: [finishedExpectation], timeout: 2)
        try insertDirect(TestTable(id: "after-cancel", value: 2), in: blockingPool)

        var freshDidFulfill = false
        let freshCancellable = blockingDatabase
            .makeRequest(with: orderedStatement())
            .publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected fresh publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    if rows == [
                        TestTable(id: "after-cancel", value: 2),
                        TestTable(id: "initial", value: 1),
                    ] && !freshDidFulfill {
                        freshDidFulfill = true
                        freshLivenessExpectation.fulfill()
                    }
                }
            )
        wait(for: [freshLivenessExpectation], timeout: 2)
        drainMainQueue(description: "in-flight cancellation callback barrier")
        XCTAssertTrue(cancelledValues.read().isEmpty)
        freshCancellable.cancel()
    }

    func testDistinctDatabasePoolsDoNotCrossTrigger() throws {
        try createTestTable()
        let secondaryURL = databaseDirectoryURL.appending(path: "secondary.sqlite", directoryHint: .notDirectory)
        let secondaryPool = try DatabasePool(path: secondaryURL.path)
        let unrelatedSecondaryPool = try DatabasePool(path: secondaryURL.path)
        let secondaryDatabase = try GRDBDatabase(
            databasePool: secondaryPool,
            formatter: formatter,
            logger: nil
        )
        try createTestTable(in: secondaryPool)

        let primaryInitial = expectation(description: "primary initial value")
        let secondaryInitial = expectation(description: "secondary initial value")
        let primaryUpdate = expectation(description: "primary update")
        let secondaryLiveness = expectation(description: "secondary observed-pool liveness")
        let primarySnapshots = PublisherLockedValue<[[TestTable]]>([])
        let secondarySnapshots = PublisherLockedValue<[[TestTable]]>([])
        let didFulfillPrimaryUpdate = PublisherLockedValue(false)
        let didFulfillSecondaryLiveness = PublisherLockedValue(false)

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected primary publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    let count = primarySnapshots.withValue { snapshots in
                        snapshots.append(rows)
                        return snapshots.count
                    }
                    if count == 1 {
                        XCTAssertEqual(rows, [])
                        primaryInitial.fulfill()
                    }
                    if rows == [TestTable(id: "primary", value: 1)]
                        && didFulfillPrimaryUpdate.withValue({ value in
                            guard !value else { return false }
                            value = true
                            return true
                        }) {
                        primaryUpdate.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        secondaryDatabase.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected secondary publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    let count = secondarySnapshots.withValue { snapshots in
                        snapshots.append(rows)
                        return snapshots.count
                    }
                    if count == 1 {
                        XCTAssertEqual(rows, [])
                        secondaryInitial.fulfill()
                    }
                    if rows == [
                        TestTable(id: "hidden-secondary", value: 2),
                        TestTable(id: "observed-secondary", value: 3),
                    ] && didFulfillSecondaryLiveness.withValue({ value in
                        guard !value else { return false }
                        value = true
                        return true
                    }) {
                        secondaryLiveness.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [primaryInitial, secondaryInitial], timeout: 2)
        try insertDirect(
            TestTable(id: "hidden-secondary", value: 2),
            in: unrelatedSecondaryPool
        )
        try insertTest.execute(TestTable(id: "primary", value: 1))
        wait(for: [primaryUpdate], timeout: 2)
        try insertDirect(
            TestTable(id: "observed-secondary", value: 3),
            in: secondaryPool
        )
        wait(for: [secondaryLiveness], timeout: 2)

        XCTAssertTrue(
            primarySnapshots.read().allSatisfy {
                $0 == [] || $0 == [TestTable(id: "primary", value: 1)]
            }
        )
        XCTAssertTrue(
            secondarySnapshots.read().allSatisfy {
                $0 == [] || $0 == [
                    TestTable(id: "hidden-secondary", value: 2),
                    TestTable(id: "observed-secondary", value: 3),
                ]
            },
            "An external writer must not publish a hidden-only snapshot through another pool."
        )
    }

    func testRapidWritesPublishSerializedMonotonicValuesOnMainQueue() throws {
        try createTestTable()
        try insertTest.execute(TestTable(id: "counter", value: 0))
        let initialExpectation = expectation(description: "initial counter")
        let finalExpectation = expectation(description: "final counter")
        let livenessExpectation = expectation(description: "post-final liveness snapshot")
        let lock = NSLock()
        var observedValues: [Int] = []
        var allCallbacksOnMainThread = true
        var sawInitial = false
        var sawFinal = false
        var sawLiveness = false

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    lock.lock()
                    allCallbacksOnMainThread = allCallbacksOnMainThread && Thread.isMainThread
                    let value = rows.first(where: { $0.id == "counter" })?.value
                    if let value {
                        observedValues.append(value)
                    }
                    let isInitial: Bool
                    let isFinal: Bool
                    switch value {
                    case .some(0):
                        isInitial = !sawInitial
                        isFinal = false
                    case .some(25):
                        isInitial = false
                        isFinal = !sawFinal
                    default:
                        isInitial = false
                        isFinal = false
                    }
                    let isLiveness = rows.contains(where: { $0.id == "zz-liveness" }) && !sawLiveness
                    if isInitial {
                        sawInitial = true
                    }
                    if isFinal {
                        sawFinal = true
                    }
                    if isLiveness {
                        sawLiveness = true
                    }
                    lock.unlock()

                    if isInitial {
                        initialExpectation.fulfill()
                    }
                    if isFinal {
                        finalExpectation.fulfill()
                    }
                    if isLiveness {
                        livenessExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        for value in 1...25 {
            try updateTest.execute(id: "counter", value: value)
        }
        wait(for: [finalExpectation], timeout: 2)
        try insertTest.execute(TestTable(id: "zz-liveness", value: 999))
        wait(for: [livenessExpectation], timeout: 2)

        lock.lock()
        let values = observedValues
        let callbacksWereOnMain = allCallbacksOnMainThread
        lock.unlock()
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy(<=))
        XCTAssertEqual(values.last, 25)
        XCTAssertTrue(callbacksWereOnMain)
    }

    func testCancellationStopsObservationFetchesAndValues() throws {
        try createTestTable()
        let initialExpectation = expectation(description: "initial value")
        let freshSubscriberExpectation = expectation(description: "fresh subscriber liveness")
        let cancelledSnapshots = PublisherLockedValue<[[TestTable]]>([])

        let cancellable = database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected publisher completion before cancellation: \(completion)")
                },
                receiveValue: { rows in
                    let count = cancelledSnapshots.withValue { snapshots in
                        snapshots.append(rows)
                        return snapshots.count
                    }
                    if count == 1 {
                        XCTAssertEqual(rows, [])
                        initialExpectation.fulfill()
                    }
                }
            )

        wait(for: [initialExpectation], timeout: 2)
        cancellable.cancel()
        try insertDirect(TestTable(id: "after-cancel", value: 1))

        var freshDidFulfill = false
        let freshCancellable = database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected fresh publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    if rows == [TestTable(id: "after-cancel", value: 1)] && !freshDidFulfill {
                        freshDidFulfill = true
                        freshSubscriberExpectation.fulfill()
                    }
                }
            )
        wait(for: [freshSubscriberExpectation], timeout: 2)
        drainMainQueue(description: "post-cancellation callback barrier")

        XCTAssertEqual(cancelledSnapshots.read(), [[]])
        freshCancellable.cancel()
    }

    func testPublishOneObservesDirectWrites() throws {
        try createTestTable()
        let initialExpectation = expectation(description: "initial nil")
        let updateExpectation = expectation(description: "first row")
        var sawInitial = false
        var sawUpdate = false

        database.makeRequest(with: orderedStatement()).publishOne()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { row in
                    if !sawInitial {
                        sawInitial = true
                        XCTAssertNil(row)
                        initialExpectation.fulfill()
                    }
                    else if row == TestTable(id: "first", value: 1) && !sawUpdate {
                        sawUpdate = true
                        updateExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try insertDirect(TestTable(id: "first", value: 1))
        wait(for: [updateExpectation], timeout: 2)
    }

    // MARK: - Helpers

    private func orderedStatement() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    private func blockingStatement() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(BlockingObservationExpression() == 1)
            OrderBy(table.id.ascending())
        }
    }

    private func createTestTable(in pool: DatabasePool? = nil) throws {
        try (pool ?? databasePool).write { database in
            try database.execute(
                literal: """
                    CREATE TABLE Test (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }
    }

    private func insertDirect(_ row: TestTable, in pool: DatabasePool? = nil) throws {
        try (pool ?? databasePool).write { database in
            try database.execute(
                sql: "INSERT INTO Test (id, value) VALUES (?, ?)",
                arguments: [row.id, row.value]
            )
        }
    }

    private func drainMainQueue(description: String) {
        let barrier = expectation(description: description)
        DispatchQueue.main.async {
            barrier.fulfill()
        }
        wait(for: [barrier], timeout: 2)
    }

    private func waitForFetchCount(atLeast minimumCount: Int, containing fragment: String) {
        for attempt in 1...200 {
            if logger.count(containing: fragment) >= minimumCount {
                return
            }
            let poll = expectation(description: "positive fetch-count poll \(attempt)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                poll.fulfill()
            }
            wait(for: [poll], timeout: 1)
        }
        XCTFail(
            "Expected at least \(minimumCount) log entries containing '\(fragment)'; "
                + "received \(logger.count(containing: fragment))."
        )
    }
}
