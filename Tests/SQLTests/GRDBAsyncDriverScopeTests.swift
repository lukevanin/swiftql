import Foundation
import GRDB
import SwiftQLTestSupport
import XCTest
@testable import SwiftQL


/// The GRDB adapter's asynchronous driver scopes (issue #676): the shared
/// contract suite over a real `DatabasePool`, the reentrancy guard across a
/// suspension point, and the pinned-scope boundary.
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
        let recorder = StatementRecorder()
        // Transactions run on the writer connection, so tracing it sees every
        // `BEGIN`. The fixture closes the database, which ends the trace.
        let pool = try XCTUnwrap(driver.databasePool)
        try await pool.writeWithoutTransaction { database in
            database.trace { event in
                if case .statement(let statement) = event {
                    recorder.append(statement.sql)
                }
            }
        }

        for kind in [XLTransactionKind.deferred, .immediate, .exclusive] {
            try await driver.withTransaction(kind) { _ in }
        }
        try await driver.withTransaction { _ in }

        XCTAssertEqual(
            recorder.statements.filter { $0.hasPrefix("BEGIN") },
            [
                "BEGIN DEFERRED TRANSACTION",
                "BEGIN IMMEDIATE TRANSACTION",
                "BEGIN EXCLUSIVE TRANSACTION",
                "BEGIN IMMEDIATE TRANSACTION",
            ]
        )
    }

    // MARK: - Reentrancy

    /// The marker is read after two suspension points, from which the task
    /// may resume on another thread. The thread dictionary this guard used
    /// before keyed the marker to a thread, and Swift 6 does not allow
    /// `Thread.current` in asynchronous code at all.
    func testReentrancyGuardHoldsAcrossASuspensionPoint() async throws {
        let driver = try await fixtures.makeDriver()
        let tracker = GRDBTransactionScopeTracker.shared

        try await tracker.withActive(driver.databaseIdentifier) {
            await Task.yield()
            try await Task.sleep(nanoseconds: 1_000_000)
            XCTAssertTrue(tracker.isActive(driver.databaseIdentifier))

            await assertNestedTransactionUnsupported {
                try await driver.withReadConnection { _ in }
            }
            await assertNestedTransactionUnsupported {
                try await driver.withWriteConnection { _ in }
            }
            await assertNestedTransactionUnsupported {
                try await driver.withTransaction { _ in }
            }
        }

        XCTAssertFalse(tracker.isActive(driver.databaseIdentifier))
        let value = try await driver.withReadConnection { _ in 7 }
        XCTAssertEqual(value, 7, "The guard must clear when the scope returns.")
    }

    func testReentrancyGuardIsScopedToOneDatabase() async throws {
        let driver = try await fixtures.makeDriver()
        let other = try await fixtures.makeDriver()

        try await GRDBTransactionScopeTracker.shared.withActive(driver.databaseIdentifier) {
            await Task.yield()
            let value = try await other.withReadConnection { _ in 3 }
            XCTAssertEqual(value, 3)
        }
    }

    func testTaskCreatedInsideAnActiveScopeIsRejectedWhileTheScopeRuns() async throws {
        let driver = try await fixtures.makeDriver()

        try await GRDBTransactionScopeTracker.shared.withActive(driver.databaseIdentifier) {
            let child = Task {
                try await driver.withReadConnection { _ in }
            }
            await assertNestedTransactionUnsupported {
                try await child.value
            }
        }
    }

    /// A task created inside a transaction body inherits the task-local
    /// marker. Once the body has returned the transaction is over, so the
    /// inherited marker must not reject that task's later access.
    func testTaskCreatedInsideATransactionBodyIsNotRejectedAfterTheBodyReturns() async throws {
        let pool = try fixtures.makePool()
        let database = try GRDBDatabase(
            databasePool: pool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
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

    // MARK: - Pinned scope

    func testPinnedScopeRejectsAsynchronousAccess() async throws {
        let pool = try fixtures.makePool()
        let database = try GRDBDatabase(
            databasePool: pool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
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
}


/// A contract fixture over real temporary SQLite databases. Every database it
/// opens is closed and removed by `tearDown()`.
private final class GRDBMarkerFixture: DriverContractFixture, @unchecked Sendable {

    private let lock = NSLock()
    private var opened: [TemporaryDatabaseFixture] = []

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

    func makePool() throws -> DatabasePool {
        let fixture = try TemporaryDatabaseFixture.make(named: "grdb-async-driver-scope")
        lock.lock()
        opened.append(fixture)
        lock.unlock()
        return fixture.pool
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
        lock.lock()
        let opened = opened
        self.opened = []
        lock.unlock()
        for fixture in opened {
            fixture.tearDown()
        }
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


private final class StatementRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [String] = []

    func append(_ statement: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(statement)
    }

    var statements: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
