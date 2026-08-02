//
//  XLResultSetTests.swift
//
//  Issue #249: a typed, connection-scoped `XLResultSet` that lazily fetches
//  and decodes one row at a time over the streaming execution seam delivered
//  by issue #248 (`XLStreamingDatabaseDriverConnection.forEachRow`).
//
//  These tests exercise the real GRDB-backed adapter against a real temporary
//  SQLite database (no mocks), and use a custom SQLite scalar-function probe
//  -- the same technique `GRDBDriverContractTests` and
//  `SQLColumnReadErrorTests` already use -- to prove SQLite itself never
//  steps rows beyond what `next()` actually requested.
//

#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import Foundation
import GRDB
import SwiftQL
import XCTest


/// Records one invocation per row SQLite actually evaluates through
/// `XLResultSetStreamStepProbe.functionName`, independent of anything the
/// Swift decode path does. A thrown Swift error from `observe(_:)` becomes a
/// genuine SQLite-level (step) failure, distinct from a row-decode failure
/// that only happens after a row's values are already in hand.
private final class XLResultSetStreamStepProbe: @unchecked Sendable {

    static let functionName = "swiftql_result_set_stream_probe"

    /// A row whose raw value equals this sentinel makes `observe(_:)` throw,
    /// simulating a SQLite step failure (as opposed to a Swift-side decode
    /// failure) at that row.
    static let stepFailureSentinel: Int64 = -1

    private let lock = NSLock()
    private var invocationCountValue = 0

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCountValue
    }

    func observe(_ value: DatabaseValue) throws -> Int64? {
        lock.lock()
        invocationCountValue += 1
        lock.unlock()
        let intValue = Int64.fromDatabaseValue(value)
        if intValue == Self.stepFailureSentinel {
            throw XLResultSetTestStepFailure.simulated
        }
        return intValue
    }
}


private enum XLResultSetTestStepFailure: Error, Equatable {
    case simulated
}


final class XLResultSetTests: XCTestCase {

    private var database: GRDBDatabase!
    private var databasePool: DatabasePool!
    private var databaseDirectoryURL: URL!
    private var probe: XLResultSetStreamStepProbe!

    override func setUpWithError() throws {
        probe = XLResultSetStreamStepProbe()
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "database.sqlite",
            isDirectory: false
        )
        var configuration = Configuration()
        let probe = try XCTUnwrap(probe)
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    XLResultSetStreamStepProbe.functionName,
                    argumentCount: 1
                ) { values in
                    try probe.observe(values[0])
                }
            )
        }
        database = try GRDBDatabase(
            url: fileURL,
            configuration: configuration,
            logger: nil
        )
        databasePool = database.databasePool
    }

    override func tearDown() {
        databasePool = nil
        database = nil
        probe = nil
        if let databaseDirectoryURL {
            try? FileManager.default.removeItem(at: databaseDirectoryURL)
        }
        databaseDirectoryURL = nil
    }

    // MARK: - Fixtures

    /// Creates the backing table and a `Test` view whose `value` column
    /// routes through the step probe, then inserts `rows` in the given
    /// order. `Test` is the table name `TestTable` (see `Tables/TestTable.swift`)
    /// is declared against, so `probedTableStatement()` below decodes through
    /// the ordinary `@SQLTable` machinery.
    private func createProbedTable(rows: [(id: String, value: Int?)]) throws {
        try databasePool.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE TestStorage (
                        id TEXT PRIMARY KEY,
                        value INTEGER
                    )
                    """
            )
            for row in rows {
                try database.execute(
                    sql: "INSERT INTO TestStorage (id, value) VALUES (?, ?)",
                    arguments: [row.id, row.value]
                )
            }
            try database.execute(
                sql: """
                    CREATE VIEW Test AS
                    SELECT
                        id,
                        \(XLResultSetStreamStepProbe.functionName)(value) AS value
                    FROM TestStorage
                    """
            )
        }
    }

    private func probedTableStatement() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    /// A trivial read used to prove the pool's connections are still usable
    /// (not leaked, not deadlocked) after a `withResultSet` scope returns.
    private func assertPoolStillUsable(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(
            try databasePool.read { database in
                try Int.fetchOne(database, sql: "SELECT 42")
            },
            42,
            "The database pool must remain usable after a withResultSet scope returns.",
            file: file,
            line: line
        )
    }

    // MARK: - Empty result

    func testEmptyResultSetReturnsNilImmediatelyWithoutStepping() throws {
        try createProbedTable(rows: [])

        var callCount = 0
        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            callCount += 1
            XCTAssertNil(try results.next())
            XCTAssertNil(try results.next(), "Repeated next() on an empty result must stay nil.")
        }
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(probe.invocationCount, 0)
        try assertPoolStillUsable()
    }

    // MARK: - Lazy stepping and decoding

    func testNoRowIsSteppedOrDecodedBeforeFirstNext() throws {
        try createProbedTable(rows: [
            ("1", 1), ("2", 2), ("3", 3),
        ])

        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            XCTAssertEqual(self.probe.invocationCount, 0, "No row may be stepped before the first next() call.")
            _ = try results.next()
            XCTAssertEqual(self.probe.invocationCount, 1)
        }
    }

    func testExactlyOneRowDecodedPerSuccessfulNext() throws {
        try createProbedTable(rows: [
            ("1", 1), ("2", 2), ("3", 3),
        ])

        var decoded: [TestTable] = []
        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            for expectedCount in 1 ... 3 {
                guard let row = try results.next() else {
                    return XCTFail("Expected a row.")
                }
                decoded.append(row)
                XCTAssertEqual(
                    self.probe.invocationCount,
                    expectedCount,
                    "Each successful next() must step and decode exactly one row."
                )
            }
            // Exhaustion: SQLite must not evaluate a fourth, nonexistent row.
            XCTAssertNil(try results.next())
            XCTAssertEqual(self.probe.invocationCount, 3)
        }
        XCTAssertEqual(decoded, [
            TestTable(id: "1", value: 1),
            TestTable(id: "2", value: 2),
            TestTable(id: "3", value: 3),
        ])
        try assertPoolStillUsable()
    }

    func testStoppingAfterNRowsDoesNotStepOrDecodeRemainingRows() throws {
        try createProbedTable(rows: [
            ("1", 1), ("2", 2), ("3", 3), ("4", 4), ("5", 5),
        ])

        var decoded: [TestTable] = []
        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            decoded.append(try XCTUnwrap(results.next()))
            decoded.append(try XCTUnwrap(results.next()))
            // Deliberately stop early: rows 3, 4, 5 must never be evaluated.
        }
        XCTAssertEqual(decoded, [
            TestTable(id: "1", value: 1),
            TestTable(id: "2", value: 2),
        ])
        XCTAssertEqual(
            probe.invocationCount,
            2,
            "Early termination must not step or decode the remaining rows."
        )
        try assertPoolStillUsable()
    }

    func testRepeatedNextAfterNaturalExhaustionReturnsNilStably() throws {
        try createProbedTable(rows: [("1", 1), ("2", 2)])

        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            XCTAssertNotNil(try results.next())
            XCTAssertNotNil(try results.next())
            XCTAssertNil(try results.next(), "The result set is exhausted after the second row.")
            XCTAssertNil(try results.next(), "Exhaustion must be stable, not an error.")
            XCTAssertNil(try results.next(), "Exhaustion must remain stable across repeated calls.")
        }
        XCTAssertEqual(probe.invocationCount, 2)
    }

    // MARK: - close() and scope-exit semantics

    func testCloseIsIdempotentAndNextThrowsClosedAfterExplicitClose() throws {
        try createProbedTable(rows: [("1", 1), ("2", 2)])

        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            XCTAssertNotNil(try results.next())
            results.close()
            results.close() // Idempotent: must not crash or throw.

            XCTAssertThrowsError(try results.next()) { error in
                XCTAssertEqual(error as? XLResultSetError, .closed)
            }
            results.close() // Still idempotent once terminated.
            XCTAssertThrowsError(try results.next()) { error in
                XCTAssertEqual(error as? XLResultSetError, .closed)
            }
        }
        XCTAssertEqual(
            probe.invocationCount,
            1,
            "Closing early must not step the remaining row."
        )
        try assertPoolStillUsable()
    }

    func testRetainedResultSetThrowsClosedAfterScopeExits() throws {
        try createProbedTable(rows: [("1", 1), ("2", 2), ("3", 3)])

        var escaped: XLResultSet<TestTable>!
        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            XCTAssertNotNil(try results.next())
            escaped = results
        }

        XCTAssertThrowsError(try escaped.next()) { error in
            XCTAssertEqual(
                error as? XLResultSetError,
                .closed,
                "A retained XLResultSet must throw .closed once its withResultSet scope has returned."
            )
        }
        // Repeated post-scope access must keep throwing the same error.
        XCTAssertThrowsError(try escaped.next()) { error in
            XCTAssertEqual(error as? XLResultSetError, .closed)
        }
        XCTAssertEqual(
            probe.invocationCount,
            1,
            "A result set escaping its scope must not be able to step further rows."
        )
        try assertPoolStillUsable()
    }

    func testRetainedResultSetThatWasAlreadyExhaustedStillThrowsClosedAfterScopeExits() throws {
        try createProbedTable(rows: [("1", 1)])

        var escaped: XLResultSet<TestTable>!
        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            XCTAssertNotNil(try results.next())
            XCTAssertNil(try results.next()) // Naturally exhausted inside the scope.
            escaped = results
        }

        // Outside the scope, even an already-exhausted reference must report
        // the stronger, deterministic "closed" state rather than looking
        // like it could still be validly re-queried.
        XCTAssertThrowsError(try escaped.next()) { error in
            XCTAssertEqual(error as? XLResultSetError, .closed)
        }
    }

    // MARK: - Consumer-thrown errors

    private struct ConsumerError: Error, Equatable {}

    func testConsumerThrownErrorPropagatesAndClosesResultSet() throws {
        try createProbedTable(rows: [("1", 1), ("2", 2), ("3", 3)])

        var escaped: XLResultSet<TestTable>!
        XCTAssertThrowsError(
            try database.makeRequest(with: probedTableStatement()).withResultSet { results in
                _ = try results.next()
                escaped = results
                throw ConsumerError()
            }
        ) { error in
            XCTAssertEqual(error as? ConsumerError, ConsumerError())
        }

        XCTAssertEqual(
            probe.invocationCount,
            1,
            "A consumer-thrown error must not step further rows."
        )
        XCTAssertThrowsError(try escaped.next()) { error in
            XCTAssertEqual(error as? XLResultSetError, .closed)
        }
        try assertPoolStillUsable()
    }

    // MARK: - Decode failure (Swift-side, after a value is already fetched)

    func testDecodeErrorMidStreamPreservesOriginalErrorAndStopsStepping() throws {
        try createProbedTable(rows: [
            ("1-valid", 1),
            ("2-invalid", nil),
            ("3-must-not-step", 3),
        ])

        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            let first = try XCTUnwrap(results.next())
            XCTAssertEqual(first, TestTable(id: "1-valid", value: 1))

            XCTAssertThrowsError(try results.next()) { error in
                XCTAssertEqual(
                    error as? XLColumnReadError,
                    XLColumnReadError(index: 1, expectedType: "Int", failure: .nullValue)
                )
            }

            // The original decode error is delivered exactly once; every
            // later call is the deterministic terminal error instead.
            XCTAssertThrowsError(try results.next()) { error in
                XCTAssertEqual(error as? XLResultSetError, .closed)
            }
        }
        XCTAssertEqual(
            probe.invocationCount,
            2,
            "A decode failure at row 2 must stop before SQLite steps row 3."
        )
        try assertPoolStillUsable()
    }

    // MARK: - SQLite step failure (distinct from a Swift-side decode failure)

    func testSQLiteStepFailurePreservesOriginalErrorAndStopsStepping() throws {
        try createProbedTable(rows: [
            ("1-valid", 1),
            ("2-step-failure", Int(XLResultSetStreamStepProbe.stepFailureSentinel)),
            ("3-must-not-step", 3),
        ])

        try database.makeRequest(with: probedTableStatement()).withResultSet { results in
            let first = try XCTUnwrap(results.next())
            XCTAssertEqual(first, TestTable(id: "1-valid", value: 1))

            XCTAssertThrowsError(try results.next()) { error in
                // The probe's thrown Swift error surfaces as a SQLite-level
                // failure raised while stepping row 2, before any typed
                // decode of that row's values is attempted.
                XCTAssertFalse(error is XLColumnReadError)
                XCTAssertFalse(error is XLResultSetError)
            }

            XCTAssertThrowsError(try results.next()) { error in
                XCTAssertEqual(error as? XLResultSetError, .closed)
            }
        }
        XCTAssertEqual(
            probe.invocationCount,
            2,
            "A SQLite step failure at row 2 must stop before SQLite steps row 3."
        )
        try assertPoolStillUsable()
    }

    // MARK: - RETURNING statements decode eagerly to protect write completeness

    /// `RETURNING` rows are produced as SQLite steps through the
    /// data-changing statement itself, so lazily stopping partway through
    /// them would leave the underlying `UPDATE` only partially applied.
    /// `GRDBRequest.withResultSet(bindings:_:)` decodes `RETURNING` results
    /// eagerly for exactly this reason -- confirm the write is always fully
    /// applied even when the consumer stops after the first `next()` call.
    func testReturningStatementCommitsCompleteWriteEvenWhenConsumerStopsEarly() throws {
        try databasePool.write { database in
            try database.execute(
                sql: "CREATE TABLE Test (id TEXT PRIMARY KEY, value INTEGER NOT NULL)"
            )
            try database.execute(
                sql: "INSERT INTO Test (id, value) VALUES ('a', 1), ('b', 2), ('c', 3)"
            )
        }

        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let statement = update(t)
            .set { row in row.value = 99 }
            .where(t.id != "does-not-exist")
            .returning(projection)

        var decoded: [TestTable] = []
        try database.makeRequest(with: statement).withResultSet { results in
            // Stop after the first row on purpose.
            decoded.append(try XCTUnwrap(results.next()))
        }
        XCTAssertEqual(decoded, [TestTable(id: "a", value: 99)])

        let allRowsStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: allRowsStatement).fetchAll(),
            [
                TestTable(id: "a", value: 99),
                TestTable(id: "b", value: 99),
                TestTable(id: "c", value: 99),
            ],
            "Stopping withResultSet early must never leave a RETURNING write partially applied."
        )
    }

    // MARK: - Compatibility default (adapters that predate XLResultSet)

    func testCompatibilityDefaultServesEagerlyFetchedRowsThroughNext() throws {
        let request = XLResultSetLegacyRequest(rows: [10, 20, 30])

        var decoded: [Int] = []
        try request.withResultSet { results in
            while let value = try results.next() {
                decoded.append(value)
            }
            XCTAssertNil(try results.next(), "Exhaustion must remain stable for the eager fallback too.")
        }
        XCTAssertEqual(decoded, [10, 20, 30])
        XCTAssertEqual(request.fetchAllCallCount, 1)
    }

    func testCompatibilityDefaultRetainedResultSetThrowsClosedAfterScopeExits() throws {
        let request = XLResultSetLegacyRequest(rows: [1])

        var escaped: XLResultSet<Int>!
        try request.withResultSet { results in
            escaped = results
        }
        XCTAssertThrowsError(try escaped.next()) { error in
            XCTAssertEqual(error as? XLResultSetError, .closed)
        }
    }
}


/// A thread-unsafe call counter is fine here: these tests never call
/// `fetchAll()` concurrently. A reference type lets a non-mutating
/// `fetchAll()` (the protocol's exact requirement) still record invocations.
private final class XLResultSetLegacyRequestCallCounter {
    private(set) var fetchAllCallCount = 0

    func recordFetchAll() {
        fetchAllCallCount += 1
    }
}


/// A minimal `XLRequest` conformer that predates `XLResultSet`, mirroring
/// `LegacyReadRequest` in `SQLRequestCompatibilityTests.swift`. It implements
/// none of the `withResultSet` requirements itself, relying entirely on the
/// protocol's eager compatibility default.
private struct XLResultSetLegacyRequest: XLRequest {

    let rows: [Int]

    private let callCounter = XLResultSetLegacyRequestCallCounter()

    var fetchAllCallCount: Int { callCounter.fetchAllCallCount }

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {}

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {}

    func fetchAll() throws -> [Int] {
        callCounter.recordFetchAll()
        return rows
    }

    func fetchOne() throws -> Int? {
        rows.first
    }

    func publish() -> AnyPublisher<[Int], Error> {
        Just(rows).setFailureType(to: Error.self).eraseToAnyPublisher()
    }

    func publishOne() -> AnyPublisher<Int?, Error> {
        Just(rows.first).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}
