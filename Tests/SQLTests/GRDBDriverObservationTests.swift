//
//  GRDBDriverObservationTests.swift
//
//  The GRDB driver as an `XLObservingDatabaseDriver` (issue #684): it re-runs
//  a fetch on its own connection after a write to a table the statement
//  reads, and not after a write to any other table.
//
//  GRDB fetches an observation's initial value from a pool reader, and may
//  fetch again when it first takes the writer, so a test here never counts on
//  exactly one initial fetch or one initial value. See <doc:LiveQueries>, "A
//  live query may deliver the same value twice".
//

import Foundation
import GRDB
import SwiftQLTestSupport
import XCTest
@testable import SwiftQL


final class GRDBDriverObservationTests: XCTestCase {

    private var fixture: TemporaryDatabaseFixture!

    private var driver: GRDBDatabaseDriver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try TemporaryDatabaseFixture.make(named: "GRDBDriverObservationTests")
        driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: XLSQLiteDialect())
        try fixture.pool.write { database in
            try database.execute(sql: "CREATE TABLE Tracked (id INTEGER PRIMARY KEY)")
            try database.execute(sql: "CREATE TABLE Untracked (id INTEGER PRIMARY KEY)")
        }
    }

    override func tearDown() {
        driver = nil
        fixture?.tearDown()
        fixture = nil
        super.tearDown()
    }

    // MARK: - Tracked and untracked writes

    func testWriteToATrackedTableRefetchesOnTheDriversConnection() async throws {
        let fetches = FetchCounter()
        let iterator = ObservationIterator(observeTrackedCount(counting: fetches))

        try await iterator.next(until: 0)
        try insert(into: "Tracked", id: 1)
        try await iterator.next(until: 1)
        try insert(into: "Tracked", id: 2)
        try await iterator.next(until: 2)

        XCTAssertGreaterThanOrEqual(fetches.count, 3, "Each delivered count needs its own fetch.")
    }

    func testWriteToAnUntrackedTableDoesNotRefetch() async throws {
        let fetches = FetchCounter()
        let iterator = ObservationIterator(observeTrackedCount(counting: fetches))
        try await iterator.next(until: 0)

        // A tracked write the observation reports is the fence: GRDB has
        // installed the observation on the writer, and its initial fetches,
        // one or two, are behind it.
        try insert(into: "Tracked", id: 1)
        try await iterator.next(until: 1)
        let fetchesAfterFence = fetches.count

        try insert(into: "Untracked", id: 1)
        try insert(into: "Tracked", id: 2)
        try await iterator.next(until: 2)

        XCTAssertEqual(
            fetches.count,
            fetchesAfterFence + 1,
            "Only the tracked write may refetch; the untracked write must not."
        )
    }

    /// The driver observes the tables SQLite reports the statement reads, so a
    /// view's base table is tracked although the statement names only the view.
    func testWriteToTheBaseTableOfAViewRefetches() async throws {
        try await fixture.pool.write { database in
            try database.execute(sql: "CREATE VIEW TrackedView AS SELECT id FROM Tracked")
        }
        let statement = logicalStatement(
            sql: "SELECT COUNT(*) FROM TrackedView",
            entities: ["TrackedView"]
        )
        let iterator = ObservationIterator(
            driver.observe(statement, fetch: countFetch(statement, counting: FetchCounter()))
        )

        try await iterator.next(until: 0)
        try insert(into: "Tracked", id: 1)
        try await iterator.next(until: 1)
    }

    // MARK: - Errors

    func testAnErrorThrownByFetchEndsTheStreamWithThatError() async throws {
        struct FetchFailure: Error, Equatable {}
        let statement = trackedCountStatement()
        var iterator = driver.observe(statement, fetch: { _ -> Int in
            throw FetchFailure()
        }).makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("The fetch error must end the stream.")
        }
        catch {
            XCTAssertEqual(error as? FetchFailure, FetchFailure())
        }
        let afterFailure = try await iterator.next()
        XCTAssertNil(afterFailure, "A failed observation ends; it does not resume.")
    }

    func testADatabaseErrorIsReportedAsAnXLDatabaseError() async throws {
        let statement = logicalStatement(sql: "SELECT COUNT(*) FROM Missing", entities: ["Missing"])
        var iterator = driver.observe(
            statement,
            fetch: countFetch(statement, counting: FetchCounter())
        ).makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("Preparing a statement for a missing table must fail.")
        }
        catch {
            XCTAssertNotNil(error as? XLDatabaseError, "Unexpected error: \(error)")
        }
    }

    func testAStatementForAnotherDatabaseFailsLazilyWithoutFetching() async throws {
        let fetches = FetchCounter()
        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: XLDatabaseIdentifier(rawValue: UUID()),
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: "SELECT COUNT(*) FROM Tracked",
            entities: ["Tracked"]
        )
        let stream = driver.observe(statement, fetch: countFetch(statement, counting: fetches))
        var iterator = stream.makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("A statement for another database must not be observed.")
        }
        catch let error as XLDatabaseContractError {
            guard case .driverMismatch(let expected, let actual, let driverIdentifier) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(expected, statement.databaseIdentifier)
            XCTAssertEqual(actual, driver.databaseIdentifier)
            XCTAssertEqual(driverIdentifier, .grdb)
        }
        XCTAssertEqual(fetches.count, 0)
    }

    // MARK: - Laziness and cancellation

    func testConstructingTheStreamDoesNotFetch() async throws {
        let fetches = FetchCounter()
        let stream = observeTrackedCount(counting: fetches)

        // A second observation of the same table, iterated to a write, is the
        // fence: had the first one started, its initial fetch would have run
        // long before this one sees a committed write.
        let fence = ObservationIterator(observeTrackedCount(counting: FetchCounter()))
        try await fence.next(until: 0)
        try insert(into: "Tracked", id: 1)
        try await fence.next(until: 1)

        XCTAssertEqual(fetches.count, 0, "Observation begins with iteration.")
        withExtendedLifetime(stream) {}
    }

    func testCancellingTheConsumingTaskEndsWithNilAndStopsFetching() async throws {
        let fetches = FetchCounter()
        let stream = observeTrackedCount(counting: fetches)
        let seen = XLAwaitableState<[Int]>([])
        let ended = XLAwaitableValue<Bool>()

        let task = Task {
            do {
                for try await count in stream {
                    seen.withValue { $0.append(count) }
                }
                ended.fulfill(true)
            }
            catch {
                XCTFail("Cancellation must end iteration with nil, not \(error).")
                ended.fulfill(false)
            }
        }
        await seen.wait(untilCountIsAtLeast: 1)
        task.cancel()
        let endedWithNil = await ended.wait()
        XCTAssertTrue(endedWithNil)
        let fetchesAtCancel = fetches.count

        // Another observation that sees the next write is the fence: the
        // write was committed and reported to every observation still
        // installed.
        let fence = ObservationIterator(observeTrackedCount(counting: FetchCounter()))
        try await fence.next(until: 0)
        try insert(into: "Tracked", id: 1)
        try await fence.next(until: 1)

        XCTAssertEqual(
            fetches.count,
            fetchesAtCancel,
            "A cancelled observation must not fetch again."
        )
        XCTAssertEqual(xlDistinctStates(seen.read()), [0])
        withExtendedLifetime(stream) {}
    }

    // MARK: - Helpers

    private func observeTrackedCount(
        counting fetches: FetchCounter
    ) -> AsyncThrowingStream<Int, Error> {
        let statement = trackedCountStatement()
        return driver.observe(statement, fetch: countFetch(statement, counting: fetches))
    }

    private func trackedCountStatement() -> XLLogicalPreparedStatement {
        logicalStatement(sql: "SELECT COUNT(*) FROM Tracked", entities: ["Tracked"])
    }

    private func logicalStatement(sql: String, entities: Set<String>) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql,
            entities: entities
        )
    }

    /// Runs `statement` through the connection contract on whatever
    /// connection the driver lends, as a request adapter would.
    private func countFetch(
        _ statement: XLLogicalPreparedStatement,
        counting fetches: FetchCounter
    ) -> @Sendable (inout GRDBDatabaseDriverConnection) throws -> Int {
        { connection in
            fetches.increment()
            let prepared = try connection.prepare(statement)
            guard case .integer(let count)? = try connection.fetchOne(prepared)?.first else {
                throw XLDatabaseContractError.decodeFailure(
                    dialect: XLSQLiteDialect.identity,
                    column: 0,
                    message: "expected one integer count"
                )
            }
            return Int(count)
        }
    }

    private func insert(into table: String, id: Int) throws {
        try fixture.pool.write { database in
            try database.execute(sql: "INSERT INTO \(table) (id) VALUES (?)", arguments: [id])
        }
    }
}


/// Counts how many times a fetch ran. Locked, because GRDB runs a fetch on a
/// pool reader or the writer.
private final class FetchCounter: @unchecked Sendable {

    private let lock = NSLock()

    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}


/// Holds one stream's iterator across awaits, and skips the repeated values
/// GRDB may deliver while it waits for the one a test expects.
private final class ObservationIterator: @unchecked Sendable {

    private var iterator: AsyncThrowingStream<Int, Error>.AsyncIterator

    init(_ stream: AsyncThrowingStream<Int, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    /// Iterates until the stream yields `expected`. Fails the test if it ends
    /// first.
    func next(
        until expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        while let value = try await iterator.next() {
            if value == expected {
                return
            }
        }
        XCTFail("The stream ended before it yielded \(expected).", file: file, line: line)
    }
}
