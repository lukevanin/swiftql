//
//  XLExecutionTests.swift
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

    func testPublisherFetchesAtSubscriptionTime() throws {
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
        var firstSawInitial = false
        var firstSawUpdate = false

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
                }
            )
            .store(in: &cancellables)

        wait(for: [firstInitialExpectation], timeout: 2)
        try insertTest.execute(TestTable(id: "foo", value: 7))
        wait(for: [firstUpdatedExpectation], timeout: 2)

        let secondInitialExpectation = expectation(description: "second subscriber current value")
        var secondInitialRows: [TestTable]?
        publisher
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    guard secondInitialRows == nil else { return }
                    secondInitialRows = rows
                    secondInitialExpectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [secondInitialExpectation], timeout: 2)
        XCTAssertEqual(secondInitialRows, [TestTable(id: "foo", value: 7)])
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
        let unexpectedSecondaryUpdate = expectation(description: "no secondary cross-trigger")
        unexpectedSecondaryUpdate.isInverted = true
        var primarySawInitial = false
        var primarySawUpdate = false
        var secondarySawInitial = false

        database.makeRequest(with: orderedStatement()).publish()
            .removeDuplicates()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected primary publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    if !primarySawInitial {
                        primarySawInitial = true
                        primaryInitial.fulfill()
                    }
                    else if rows == [TestTable(id: "primary", value: 1)] && !primarySawUpdate {
                        primarySawUpdate = true
                        primaryUpdate.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        secondaryDatabase.makeRequest(with: orderedStatement()).publish()
            .removeDuplicates()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected secondary publisher completion: \(completion)")
                },
                receiveValue: { rows in
                    if !secondarySawInitial {
                        secondarySawInitial = true
                        XCTAssertEqual(rows, [])
                        secondaryInitial.fulfill()
                    }
                    else if rows == [TestTable(id: "hidden-secondary", value: 2)] {
                        unexpectedSecondaryUpdate.fulfill()
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
        wait(for: [primaryUpdate, unexpectedSecondaryUpdate], timeout: 0.5)
    }

    func testRapidWritesPublishSerializedMonotonicValuesOnMainQueue() throws {
        try createTestTable()
        try insertTest.execute(TestTable(id: "counter", value: 0))
        let initialExpectation = expectation(description: "initial counter")
        let finalExpectation = expectation(description: "final counter")
        let staleAfterFinalExpectation = expectation(description: "no stale value after final state")
        staleAfterFinalExpectation.isInverted = true
        let lock = NSLock()
        var observedValues: [Int] = []
        var allCallbacksOnMainThread = true
        var sawFinal = false

        database.makeRequest(with: orderedStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    guard let value = rows.first?.value else { return }
                    lock.lock()
                    allCallbacksOnMainThread = allCallbacksOnMainThread && Thread.isMainThread
                    observedValues.append(value)
                    let isInitial = observedValues.count == 1 && value == 0
                    let isStaleAfterFinal = sawFinal && value < 25
                    let isFinal = value == 25 && !sawFinal
                    if isFinal {
                        sawFinal = true
                    }
                    lock.unlock()

                    if isInitial {
                        initialExpectation.fulfill()
                    }
                    if isFinal {
                        finalExpectation.fulfill()
                    }
                    if isStaleAfterFinal {
                        staleAfterFinalExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        for value in 1...25 {
            try updateTest.execute(id: "counter", value: value)
        }
        wait(for: [finalExpectation], timeout: 2)
        wait(for: [staleAfterFinalExpectation], timeout: 0.5)

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
        let unexpectedValue = expectation(description: "no value after cancellation")
        unexpectedValue.isInverted = true
        var sawInitial = false

        let cancellable = database.makeRequest(with: orderedStatement()).publish()
            .removeDuplicates()
            .sink(
                receiveCompletion: { completion in
                    XCTFail("Unexpected publisher completion before cancellation: \(completion)")
                },
                receiveValue: { _ in
                    if !sawInitial {
                        sawInitial = true
                        initialExpectation.fulfill()
                    }
                    else {
                        unexpectedValue.fulfill()
                    }
                }
            )

        wait(for: [initialExpectation], timeout: 2)
        let fetchCountBeforeCancellation = waitForFetchCountToSettle(containing: "fetchAll:")
        XCTAssertGreaterThan(fetchCountBeforeCancellation, 0)
        cancellable.cancel()
        try insertDirect(TestTable(id: "after-cancel", value: 1))
        wait(for: [unexpectedValue], timeout: 0.5)
        XCTAssertEqual(logger.count(containing: "fetchAll:"), fetchCountBeforeCancellation)
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

    private func waitForFetchCountToSettle(containing fragment: String) -> Int {
        var previousCount = logger.count(containing: fragment)
        var stableSamples = 0

        for sample in 1...20 {
            let interval = expectation(description: "fetch count settle interval \(sample)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                interval.fulfill()
            }
            wait(for: [interval], timeout: 1)

            let currentCount = logger.count(containing: fragment)
            if currentCount == previousCount {
                stableSamples += 1
                if stableSamples == 2 {
                    return currentCount
                }
            }
            else {
                previousCount = currentCount
                stableSamples = 0
            }
        }

        XCTFail("Observation fetch count did not settle.")
        return previousCount
    }
}
