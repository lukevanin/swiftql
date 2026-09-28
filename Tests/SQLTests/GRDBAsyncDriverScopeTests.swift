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
                    statements.withValue { $0.append(statement.sql) }
                }
            }
        }

        for kind in [XLTransactionKind.deferred, .immediate, .exclusive] {
            try await driver.withTransaction(kind) { _ in }
        }
        try await driver.withTransaction { _ in }

        XCTAssertEqual(
            statements.read().filter { $0.hasPrefix("BEGIN") },
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
    /// database for a write must throw, and inside a transaction so must a
    /// read, which would miss the uncommitted writes. Without the guard, a nested write asks GRDB for
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
                try driver.withBlockingWriteConnection { _ in }
            }
        }
        await assertNestedTransactionUnsupported {
            try await driver.withTransaction { _ in
                try driver.withBlockingReadConnection { _ in }
            }
        }

        // Outside a transaction nothing is uncommitted, and GRDB serves the
        // read from a reader.
        let readInsideWrite = try await driver.withWriteConnection { _ in
            try driver.withBlockingReadConnection { _ in true }
        }
        XCTAssertTrue(readInsideWrite)

        let value = try await driver.withTransaction { _ in 5 }
        XCTAssertEqual(value, 5, "The guard must clear when the scope returns.")
    }

    /// A read scope holds one reader. A nested root read would ask GRDB for a
    /// second reader from the same thread, which GRDB stops with "Database
    /// methods are not reentrant", so it throws. A nested root write uses
    /// GRDB's separate writer, which GRDB allows, so it still runs.
    func testReadScopeOperationRejectsANestedRootReadButAllowsAWrite() async throws {
        let database = try fixtures.makeDatabase()
        let driver = database.driver

        await assertNestedTransactionUnsupported {
            try await driver.withReadConnection { _ in
                try driver.withBlockingReadConnection { _ in }
            }
        }

        let wrote = try await driver.withReadConnection { _ in
            try database.withTransaction { _ in true }
        }
        XCTAssertTrue(wrote)
    }

    /// A reader or writer hold is about GRDB's same-thread rule, not about a
    /// transaction. A task created inside such a scope runs on another
    /// thread with its own connection, so its root access is allowed even
    /// while the scope is still running.
    func testTaskCreatedInsideAReadOrWriteScopeIsNotRejected() async throws {
        let database = try fixtures.makeDatabase()
        let driver = database.driver

        for scope in ["read", "write"] {
            let child = LockedValue<Task<Int, Error>?>(nil)
            let body: @Sendable (inout GRDBDatabaseDriverConnection) throws -> Void = { _ in
                let started = DispatchSemaphore(value: 0)
                let task = Task {
                    defer { started.signal() }
                    return try await driver.withReadConnection { _ in 13 }
                }
                child.withValue { $0 = task }
                // Keep the scope open until the child has finished, so the
                // child's access happens while the parent still holds.
                guard started.wait(timeout: .now() + 10) == .success else {
                    throw ChildTimedOut()
                }
            }
            if scope == "read" {
                try await driver.withReadConnection(body)
            }
            else {
                try await driver.withWriteConnection(body)
            }
            let value = try await XCTUnwrap(child.read()).value
            XCTAssertEqual(value, 13, "A task created inside a \(scope) scope was rejected.")
        }
    }

    /// The blocking scopes of the v1 request layer hold the same way. A
    /// nested root access that GRDB would stop on the same thread now throws
    /// instead, and so does a root read inside a transaction. The nestings
    /// GRDB serves on a separate connection still run.
    func testBlockingScopesRejectWhatGRDBForbidsOrATransactionWouldMiss() throws {
        let database = try fixtures.makeDatabase()
        let driver = database.driver

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { _ in
                try driver.withBlockingReadConnection { _ in }
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }
        XCTAssertThrowsError(
            try driver.withBlockingTransaction { _ in
                try driver.withBlockingWriteConnection { _ in }
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }

        let wroteInsideRead = try driver.withBlockingReadConnection { _ in
            try driver.withBlockingWriteConnection { _ in true }
        }
        XCTAssertTrue(wroteInsideRead)
        let readInsideWrite = try driver.withBlockingWriteConnection { _ in
            try driver.withBlockingReadConnection { _ in true }
        }
        XCTAssertTrue(readInsideWrite)

        // Inside a transaction a root read would miss the uncommitted writes.
        XCTAssertThrowsError(
            try driver.withBlockingTransaction { _ in
                try driver.withBlockingReadConnection { _ in }
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }
    }

    /// A transaction held across suspension points, as an asynchronous
    /// transaction body will be (#681), keeps rejecting root access from its
    /// own task wherever the task resumes. The thread-local holds of the
    /// synchronous scopes cannot express that, and the thread dictionary the
    /// guard used before could not be read from asynchronous code at all.
    /// A task created inside the transaction is separate work and is not
    /// rejected.
    func testAsyncTransactionHoldSurvivesSuspensionPointsInItsOwnTask() async throws {
        let database = try fixtures.makeDatabase()
        let driver = database.driver
        let otherDriver = try await fixtures.makeDriver()
        let tracker = GRDBTransactionScopeTracker.shared

        try await tracker.withAsyncTransaction(on: try XCTUnwrap(driver.databasePool)) {
            await Task.yield()
            try await Task.sleep(nanoseconds: 1_000_000)

            await assertNestedTransactionUnsupported {
                try await driver.withReadConnection { _ in }
            }
            await assertNestedTransactionUnsupported {
                try await driver.withTransaction { _ in }
            }
            XCTAssertThrowsError(try database.withTransaction { _ in }) { error in
                XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
            }

            let otherValue = try await otherDriver.withReadConnection { _ in 3 }
            XCTAssertEqual(otherValue, 3, "The hold names one database.")

            let childValue = try await Task {
                try await driver.withReadConnection { _ in 7 }
            }.value
            XCTAssertEqual(childValue, 7, "A task created inside the hold is not rejected.")
        }

        let value = try await driver.withReadConnection { _ in 9 }
        XCTAssertEqual(value, 9, "The hold must clear when its scope returns.")
    }

    /// A task created by a synchronous transaction body is concurrent work.
    /// Its root write waits for the writer and runs after the commit, and
    /// its root read sees committed data, so neither is rejected.
    ///
    /// The body runs on a dispatch thread, not the test's task, so blocking
    /// it while the child runs cannot starve the cooperative pool.
    func testTaskCreatedByATransactionBodyIsNotRejected() async throws {
        let database = try fixtures.makeDatabase()

        let childOutcome = try await onDispatchThread {
            try database.withTransaction { _ -> String in
                let finished = DispatchSemaphore(value: 0)
                let recorded = LockedValue<String?>(nil)
                Task {
                    let outcome: String
                    do {
                        outcome = try await database.driver.withReadConnection { _ in "read" }
                    }
                    catch {
                        outcome = "threw \(error)"
                    }
                    recorded.withValue { $0 = outcome }
                    finished.signal()
                }
                guard finished.wait(timeout: .now() + 10) == .success else {
                    throw ChildTimedOut()
                }
                return try XCTUnwrap(recorded.read())
            }
        }

        XCTAssertEqual(childOutcome, "read")
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
                // Finishing the stream on every exit keeps the wait below
                // from hanging if the operation throws before it yields.
                defer { startedContinuation.finish() }
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
            let unknown = XLTransactionKind(rawValue: "unknown")
            try await pinnedDriver.withTransaction(unknown) { _ in }
            XCTFail("A pinned driver has no asynchronous scope.")
        }
        catch {
            XCTAssertEqual(
                error as? XLTransactionScopeError,
                .scopeEscaped,
                "The scope check runs before the kind check."
            )
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
        let opened = opened.withValue { opened in
            defer { opened = [] }
            return opened
        }
        for fixture in opened {
            fixture.tearDown()
        }
    }

    private func makePool() throws -> DatabasePool {
        let fixture = try TemporaryDatabaseFixture.make(named: "grdb-async-driver-scope")
        opened.withValue { $0.append(fixture) }
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
