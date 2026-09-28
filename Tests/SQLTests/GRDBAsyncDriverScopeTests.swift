import Foundation
import GRDB
import SwiftQLTestSupport
import XCTest
@testable import SwiftQL


/// The GRDB adapter's asynchronous driver scopes (issue #676): the shared
/// contract suite over a real `DatabasePool`, the reentrancy guard, mid-run
/// cancellation, and the pinned-scope boundary.
final class GRDBAsyncDriverScopeTests: XCTestCase {

    private var fixtures: GRDBMarkerFixture!

    override func setUp() {
        super.setUp()
        fixtures = GRDBMarkerFixture()
    }

    override func tearDown() {
        fixtures.tearDown()
        fixtures = nil
        super.tearDown()
    }

    // MARK: - Contract

    func testGRDBDriverPassesEveryContractClause() async {
        for clause in DriverContractClause.allCases {
            do {
                try await DriverContractSuite.check(clause, fixtures!)
            }
            catch {
                XCTFail("\(clause): \(error)")
            }
        }
    }

    func testTransactionKindRendersAsTheMatchingBeginStatement() async throws {
        let driver = try await fixtures.makeDriver()
        let statements = LockedValue<[String]>([])
        // Transactions run on the writer connection, so tracing it sees every
        // `BEGIN`. The fixture closes the database, which ends the trace.
        let pool = try XCTUnwrap(driver.databasePool)
        try await pool.writeWithoutTransaction { database in
            database.trace { event in
                if case .statement(let statement) = event {
                    statements.withLock { $0.append(statement.sql) }
                }
            }
        }

        for kind in [XLTransactionKind.deferred, .immediate, .exclusive] {
            try await driver.withTransaction(kind) { _ in }
        }
        try await driver.withTransaction { _ in }

        XCTAssertEqual(
            statements.value.filter { $0.hasPrefix("BEGIN") },
            [
                "BEGIN DEFERRED TRANSACTION",
                "BEGIN IMMEDIATE TRANSACTION",
                "BEGIN EXCLUSIVE TRANSACTION",
                "BEGIN IMMEDIATE TRANSACTION",
            ]
        )
    }

    // MARK: - Reentrancy

    /// An operation that holds GRDB's writer and calls back into the root
    /// database must throw. Without the guard, the nested call asks GRDB for
    /// the writer it already holds, and GRDB stops the process with
    /// "Database methods are not reentrant".
    func testWriterScopeOperationThatReentersTheRootDatabaseThrows() async throws {
        let database = try fixtures.makeDatabase()
        let driver = database.driver

        await assertNestedTransactionUnsupported {
            try await driver.withTransaction { _ in
                try database.withTransaction { _ in }
            }
        }
        await assertNestedTransactionUnsupported {
            try await driver.withTransaction(.deferred) { _ in
                try driver.withBlockingWriteConnection { _ in }
            }
        }
        await assertNestedTransactionUnsupported {
            try await driver.withWriteConnection { _ in
                try driver.withBlockingReadConnection { _ in }
            }
        }

        let value = try await driver.withTransaction { _ in 5 }
        XCTAssertEqual(value, 5, "The guard must clear when the scope returns.")
    }

    /// A task created by a transaction body inherits the task-local marker.
    /// It reaches the root database only after two suspension points, from
    /// which it may resume on another thread, and is still rejected. The
    /// thread dictionary this guard used before keyed the marker to a thread,
    /// and Swift 6 does not allow `Thread.current` in asynchronous code.
    ///
    /// The body runs on a dispatch thread, not the test's task, so blocking
    /// it while the child runs cannot starve the cooperative pool.
    func testTaskCreatedByATransactionBodyIsRejectedAcrossASuspensionPoint() async throws {
        let database = try fixtures.makeDatabase()
        let otherDriver = try await fixtures.makeDriver()

        let outcome = try await onDispatchThread {
            try database.withTransaction { _ -> ChildOutcome in
                let finished = DispatchSemaphore(value: 0)
                let recorded = LockedValue<ChildOutcome?>(nil)
                Task {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    var outcome = ChildOutcome()
                    do {
                        try await database.driver.withReadConnection { _ in }
                    }
                    catch {
                        outcome.sameDatabaseError = error as? XLTransactionScopeError
                    }
                    outcome.otherDatabaseValue = try? await otherDriver.withReadConnection { _ in 3 }
                    recorded.withLock { $0 = outcome }
                    finished.signal()
                }
                guard finished.wait(timeout: .now() + 10) == .success else {
                    throw ChildTimedOut()
                }
                return try XCTUnwrap(recorded.value)
            }
        }

        XCTAssertEqual(outcome.sameDatabaseError, .nestedTransactionUnsupported)
        XCTAssertEqual(
            outcome.otherDatabaseValue,
            3,
            "The marker names one database; another database stays usable."
        )
    }

    /// Once the body has returned the transaction is over, so a marker a
    /// task inherited from it must not reject that task's later access.
    func testTaskCreatedInsideATransactionBodyIsNotRejectedAfterTheBodyReturns() async throws {
        let database = try fixtures.makeDatabase()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()

        let child = try database.withTransaction { _ in
            Task {
                for await _ in release {
                    break
                }
                return try await database.driver.withReadConnection { _ in 11 }
            }
        }
        releaseContinuation.yield()
        releaseContinuation.finish()

        let value = try await child.value
        XCTAssertEqual(value, 11)
    }

    // MARK: - Cancellation

    /// GRDB 7 cancels the database when the task is cancelled mid-operation.
    /// The next statement throws, and the transaction rolls back.
    func testCancellingTheTaskInterruptsARunningTransactionAndRollsBack() async throws {
        let driver = try await fixtures.makeDriver()
        let fixtures = fixtures!
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()

        let task = Task {
            try await driver.withTransaction { connection in
                try fixtures.insertMarker(on: &connection)
                startedContinuation.yield()
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline {
                    _ = try fixtures.markerCount(on: &connection)
                }
            }
        }
        for await _ in started {
            break
        }
        task.cancel()

        switch await task.result {
        case .success:
            XCTFail("The operation ran to its deadline instead of being interrupted.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Threw \(error).")
        }
        let count = try await driver.withReadConnection { connection in
            try fixtures.markerCount(on: &connection)
        }
        XCTAssertEqual(count, 0, "The interrupted transaction must roll back.")
    }

    // MARK: - Pinned scope

    func testPinnedScopeRejectsAsynchronousAccess() async throws {
        let database = try fixtures.makeDatabase()
        let pinnedDriver = try database.withTransaction { scope in
            scope.driver
        }

        do {
            try await pinnedDriver.withReadConnection { _ in }
            XCTFail("A pinned driver has no asynchronous scope.")
        }
        catch {
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }

        do {
            try await pinnedDriver.withValidatedTransaction { _ in }
            XCTFail("A pinned driver has no asynchronous scope.")
        }
        catch {
            XCTAssertEqual(
                error as? XLTransactionScopeError,
                .scopeEscaped,
                "A validated transaction must rethrow the typed refusal, not a transaction failure."
            )
        }
    }

    private func assertNestedTransactionUnsupported(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected nestedTransactionUnsupported.", file: file, line: line)
        }
        catch {
            XCTAssertEqual(
                error as? XLTransactionScopeError,
                .nestedTransactionUnsupported,
                file: file,
                line: line
            )
        }
    }

    /// Runs `body` on a dispatch thread, outside any task, and resumes with
    /// its result.
    private func onDispatchThread<Result: Sendable>(
        _ body: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Swift.Result { try body() })
            }
        }
    }
}


private struct ChildOutcome: Sendable {
    var sameDatabaseError: XLTransactionScopeError?
    var otherDatabaseValue: Int?
}


private struct ChildTimedOut: Error {}


/// A contract fixture over real temporary SQLite databases. Every database it
/// opens is closed and removed by `tearDown()`.
private final class GRDBMarkerFixture: DriverContractFixture, @unchecked Sendable {

    private let opened = LockedValue<[TemporaryDatabaseFixture]>([])

    var supportedTransactionKinds: [XLTransactionKind] {
        [.deferred, .immediate, .exclusive]
    }

    func makeDriver() async throws -> GRDBDatabaseDriver {
        let pool = try makePool()
        try await pool.write { database in
            try database.execute(sql: "CREATE TABLE contract_marker (id INTEGER PRIMARY KEY)")
        }
        return GRDBDatabaseDriver(databasePool: pool, dialect: XLSQLiteDialect())
    }

    func makeDatabase() throws -> GRDBDatabase {
        try GRDBDatabase(
            databasePool: makePool(),
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
    }

    func insertMarker(on connection: inout GRDBDatabaseDriverConnection) throws {
        let statement = try connection.prepareValidated(
            logicalStatement("INSERT INTO contract_marker DEFAULT VALUES", on: connection)
        )
        try connection.executeValidated(statement)
    }

    func markerCount(on connection: inout GRDBDatabaseDriverConnection) throws -> Int {
        let statement = try connection.prepareValidated(
            logicalStatement("SELECT COUNT(*) FROM contract_marker", on: connection)
        )
        guard case .integer(let count)? = try connection.fetchOneValidated(statement)?.first else {
            throw XLDatabaseContractError.decodeFailure(
                dialect: XLSQLiteDialect.identity,
                column: 0,
                message: "expected one integer count"
            )
        }
        return Int(count)
    }

    func tearDown() {
        let opened = opened.withLock { opened in
            defer { opened = [] }
            return opened
        }
        for fixture in opened {
            fixture.tearDown()
        }
    }

    private func makePool() throws -> DatabasePool {
        let fixture = try TemporaryDatabaseFixture.make(named: "grdb-async-driver-scope")
        opened.withLock { $0.append(fixture) }
        return fixture.pool
    }

    private func logicalStatement(
        _ sql: String,
        on connection: GRDBDatabaseDriverConnection
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: connection.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }
}
