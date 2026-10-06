//
//  SQLTransactionScopeQueueTests.swift
//  SwiftQL
//
//  A transaction scope used from a block that another dispatch queue runs on
//  the body's own thread (issue #816).
//

import Foundation
import Dispatch
import SwiftQLTestSupport
import XCTest
import GRDB
@_spi(GRDB) import SwiftQL


/// GRDB confines the pinned connection to its writer's dispatch queue, not to
/// a thread. A block that another queue runs on the body's thread passes a
/// thread check, and GRDB then stops the process with "Database was not used
/// on the correct thread". For a database SwiftQL opens, every such use
/// throws `scopeEscaped` instead (issue #816).
///
/// Each test asserts that the other queue's block ran on the body's thread,
/// so the refusal comes from the queue check and not from the thread check
/// before it. Without the queue check, each of these tests stops the process
/// in GRDB.
final class SQLTransactionScopeQueueTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
    }

    // MARK: - Helpers

    private func databaseURL(_ name: String = "database") -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("sqlite")
    }

    /// Opens a database the way an application does, so SwiftQL opens and
    /// configures the pool.
    private func makeDatabase(
        url: URL? = nil,
        configuration: GRDBDatabaseConfiguration = GRDBDatabaseConfiguration()
    ) throws -> GRDBDatabase {
        let database = try GRDBDatabase(
            url: url ?? databaseURL(),
            configuration: configuration,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
        addTeardownBlock {
            try? database.databasePool.close()
        }
        return database
    }

    private func createTestTable(in database: GRDBDatabase) throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func selectAllTestRows() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
        }
    }

    private func rows(in database: GRDBDatabase) throws -> [TestTable] {
        try database.makeRequest(with: selectAllTestRows()).fetchAll()
            .sorted { $0.id < $1.id }
    }

    /// Runs a statement through each of the scope's main entry points, and
    /// reports what each one did. Called from the other queue's block.
    private static func outcomes(of scope: GRDBDatabase) -> [String] {
        func outcome(_ entryPoint: String, _ work: () throws -> Void) -> String {
            do {
                try work()
                return "\(entryPoint): ran"
            }
            catch let error as XLTransactionScopeError {
                return "\(entryPoint): \(error)"
            }
            catch {
                return "\(entryPoint): \(type(of: error)): \(error)"
            }
        }
        let select = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
        }
        return [
            outcome("fetchAll()") {
                _ = try scope.makeRequest(with: select).fetchAll()
            },
            outcome("withResultSet(_:)") {
                _ = try scope.makeRequest(with: select).withResultSet { try $0.next() }
            },
            outcome("execute()") {
                try scope.makeRequest(with: sqlInsert(TestTable(id: "beta", value: 2))).execute()
            },
            outcome("insert(contentsOf:)") {
                try scope.insert(contentsOf: [TestTable(id: "gamma", value: 3)])
            },
        ]
    }

    private static let refused = [
        "fetchAll(): scopeEscaped",
        "withResultSet(_:): scopeEscaped",
        "execute(): scopeEscaped",
        "insert(contentsOf:): scopeEscaped",
    ]

    /// Runs `block` on `queue` with `sync` from inside a transaction body,
    /// and checks that every statement it ran through the scope was refused,
    /// that it ran on the body's thread, that the body could still use the
    /// scope afterwards, and that only the body's own writes committed.
    private func assertSyncBlockIsRefused(
        on queue: DispatchQueue,
        database: GRDBDatabase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try createTestTable(in: database)

        let (ranOnTheBodysThread, outcomes) = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            let bodyThread = pthread_self()
            let result = queue.sync {
                (pthread_equal(bodyThread, pthread_self()) != 0, Self.outcomes(of: scope))
            }
            try scope.makeRequest(with: sqlInsert(TestTable(id: "delta", value: 4))).execute()
            return result
        }

        XCTAssertTrue(ranOnTheBodysThread, "the block did not run on the body's thread", file: file, line: line)
        XCTAssertEqual(outcomes, Self.refused, file: file, line: line)
        XCTAssertEqual(
            try rows(in: database),
            [TestTable(id: "alpha", value: 1), TestTable(id: "delta", value: 4)],
            file: file,
            line: line
        )
    }

    // MARK: - A `sync` call onto another queue

    /// The first case in issue #816.
    func testASyncBlockOnAGlobalQueueInTheBodyThrowsScopeEscaped() throws {
        try assertSyncBlockIsRefused(on: .global(), database: makeDatabase())
    }

    func testASyncBlockOnASerialQueueInTheBodyThrowsScopeEscaped() throws {
        try assertSyncBlockIsRefused(
            on: DispatchQueue(label: "SQLTransactionScopeQueueTests.serial"),
            database: makeDatabase()
        )
    }

    /// A read-only pool's writer runs on the readers' target queue rather than
    /// the writer's, so SwiftQL marks that queue instead.
    func testASyncBlockInTheBodyOfAReadOnlyDatabaseThrowsScopeEscaped() throws {
        let url = databaseURL()
        let writable = try makeDatabase(url: url)
        try createTestTable(in: writable)
        try writable.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()

        let database = try makeDatabase(
            url: url,
            configuration: GRDBDatabaseConfiguration(readonly: true)
        )
        let (ranOnTheBodysThread, outcome) = try database.withTransaction { scope in
            let bodyThread = pthread_self()
            let result = DispatchQueue.global().sync {
                () -> (Bool, Result<[TestTable], Error>) in
                let fetched = Result { try scope.makeRequest(with: self.selectAllTestRows()).fetchAll() }
                return (pthread_equal(bodyThread, pthread_self()) != 0, fetched)
            }
            // The scope still works on the body's own queue.
            XCTAssertEqual(
                try scope.makeRequest(with: selectAllTestRows()).fetchAll(),
                [TestTable(id: "alpha", value: 1)]
            )
            return result
        }

        XCTAssertTrue(ranOnTheBodysThread)
        XCTAssertThrowsError(try outcome.get()) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }
    }

    /// Opens a database through the GRDB escape hatch's builder, with a
    /// target queue of the caller's own that has a quality of service other
    /// than GRDB's default.
    private func makeDatabase(
        targetedAt callerQueue: DispatchQueue,
        readonly: Bool = false,
        url: URL? = nil
    ) throws -> GRDBDatabase {
        var configuration = Configuration()
        configuration.readonly = readonly
        configuration.targetQueue = callerQueue
        let database = try GRDBDatabaseBuilder(
            url: url ?? databaseURL(),
            grdbConfiguration: configuration,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        ).build()
        addTeardownBlock {
            try? database.databasePool.close()
        }
        return database
    }

    private func makeCallerQueue(key: DispatchSpecificKey<String>) -> DispatchQueue {
        let callerQueue = DispatchQueue(
            label: "SQLTransactionScopeQueueTests.caller",
            qos: .utility,
            attributes: .concurrent
        )
        callerQueue.setSpecific(key: key, value: "caller")
        return callerQueue
    }

    /// The queue SwiftQL marks targets a target queue the caller set in a
    /// GRDB configuration, so that queue keeps applying, with its quality of
    /// service, and the scope is still refused on another queue.
    func testACallersTargetQueueStillAppliesAndTheScopeIsStillRefusedOnAnotherQueue() throws {
        let callerKey = DispatchSpecificKey<String>()
        let callerQueue = makeCallerQueue(key: callerKey)
        let database = try makeDatabase(targetedAt: callerQueue)

        let callerQueueValue = try database.withTransaction { _ in
            DispatchQueue.getSpecific(key: callerKey)
        }
        XCTAssertEqual(callerQueueValue, "caller")
        XCTAssertEqual(database.databasePool.configuration.writeQoS, .utility)
        XCTAssertEqual(database.databasePool.configuration.readQoS, .utility)

        try assertSyncBlockIsRefused(on: .global(), database: database)
    }

    /// A read-only pool's marked queue is its readers' target too, so they
    /// keep the caller's queue and its quality of service.
    func testAReadOnlyDatabaseKeepsACallersTargetQueue() throws {
        let url = databaseURL()
        try createTestTable(in: makeDatabase(url: url))
        let callerKey = DispatchSpecificKey<String>()
        let database = try makeDatabase(targetedAt: makeCallerQueue(key: callerKey), readonly: true, url: url)

        let callerQueueValues = try database.withTransaction { _ in
            DispatchQueue.getSpecific(key: callerKey)
        }
        XCTAssertEqual(callerQueueValues, "caller")
        XCTAssertEqual(
            try database.databasePool.read { _ in DispatchQueue.getSpecific(key: callerKey) },
            "caller"
        )
        XCTAssertEqual(database.databasePool.configuration.readQoS, .utility)
        XCTAssertEqual(try rows(in: database), [])
    }

    /// With no target queue configured, the writer keeps the quality of
    /// service GRDB would have given it.
    func testTheWriterKeepsItsQualityOfService() throws {
        let database = try makeDatabase()
        XCTAssertEqual(database.databasePool.configuration.writeQoS, Configuration().qos)
        XCTAssertEqual(database.databasePool.configuration.readQoS, Configuration().qos)
    }

    /// GRDB allows the connection on another database's queue when that
    /// database's access was opened from inside the body. The mark cannot
    /// tell that from an access opened elsewhere on the body's thread, which
    /// GRDB stops, so both are refused.
    func testAScopeUsedInsideAnotherDatabasesAccessThrowsScopeEscaped() throws {
        let database = try makeDatabase()
        try createTestTable(in: database)
        let other = try makeDatabase(url: databaseURL("other"))
        try createTestTable(in: other)
        try other.makeRequest(with: sqlInsert(TestTable(id: "other", value: 0))).execute()

        let outcomes = try database.withTransaction { scope in
            try other.makeRequest(with: selectAllTestRows()).withResultSet { _ in
                Self.outcomes(of: scope)
            }
        }

        XCTAssertEqual(outcomes, Self.refused)
        XCTAssertEqual(try rows(in: database), [])
    }

    /// A database that wraps a pool its caller opened has no mark, so only
    /// the thread is checked. Its scope still works inside an access to a
    /// SwiftQL-opened database opened from the body, which GRDB allows, as it
    /// did before the queue check.
    func testAScopeOfAWrappedPoolStillRunsInsideAnotherDatabasesAccess() throws {
        let wrappedPool = try DatabasePool(path: databaseURL("wrapped").path)
        addTeardownBlock {
            try? wrappedPool.close()
        }
        let wrapped = try GRDBDatabase(
            databasePool: wrappedPool,
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            logger: nil
        )
        try createTestTable(in: wrapped)
        let other = try makeDatabase()
        try createTestTable(in: other)

        try wrapped.withTransaction { scope in
            try other.withTransaction { _ in
                try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            }
        }

        XCTAssertEqual(try rows(in: wrapped), [TestTable(id: "alpha", value: 1)])
    }

    // MARK: - Main-queue work run by a run loop the body spins

    /// Spins the current run loop until `isDone` returns `true`, for at most
    /// ten seconds.
    private func spinRunLoop(until isDone: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !isDone(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    /// The second case in issue #816: a main-thread body spins the run loop,
    /// which runs a main-queue block that uses the scope.
    func testMainQueueWorkThatARunLoopInAMainThreadBodyRunsThrowsScopeEscaped() throws {
        guard Thread.isMainThread else {
            throw XCTSkip("needs a test method that runs on the main thread")
        }
        let database = try makeDatabase()
        try createTestTable(in: database)

        let (bodyRanOnTheMainThread, outcomes) = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            let outcomes = LockedValue<[String]?>(nil)
            DispatchQueue.main.async {
                outcomes.withValue { $0 = Self.outcomes(of: scope) }
            }
            spinRunLoop { outcomes.read() != nil }
            return (Thread.isMainThread, outcomes.read())
        }

        XCTAssertTrue(bodyRanOnTheMainThread)
        XCTAssertEqual(outcomes, Self.refused)
        XCTAssertEqual(try rows(in: database), [TestTable(id: "alpha", value: 1)])
    }

    #if canImport(Darwin)
    /// A main-actor task is main-queue work too. A main-thread body that
    /// spins the run loop runs it during the body.
    ///
    /// Darwin only: the main actor's executor is the main dispatch queue
    /// there, which the run loop drains. Elsewhere the main executor may be
    /// one this run loop does not drive.
    func testAMainActorTaskThatARunLoopInAMainThreadBodyRunsThrowsScopeEscaped() throws {
        guard Thread.isMainThread else {
            throw XCTSkip("needs a test method that runs on the main thread")
        }
        let database = try makeDatabase()
        try createTestTable(in: database)

        let outcomes = try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
            let outcomes = LockedValue<[String]?>(nil)
            Task { @MainActor in
                outcomes.withValue { $0 = Self.outcomes(of: scope) }
            }
            spinRunLoop { outcomes.read() != nil }
            return outcomes.read()
        }

        XCTAssertEqual(outcomes, Self.refused)
        XCTAssertEqual(try rows(in: database), [TestTable(id: "alpha", value: 1)])
    }
    #endif

    // MARK: - What still works

    /// The scope still works when the body runs on the main thread, and a
    /// `DispatchQueue.main.sync` call from a body on another thread runs on
    /// the main thread, where the thread check refuses it as before.
    func testAMainThreadBodyCanUseTheScopeAndMainQueueSyncIsStillRefused() throws {
        guard Thread.isMainThread else {
            throw XCTSkip("needs a test method that runs on the main thread")
        }
        let database = try makeDatabase()
        try createTestTable(in: database)

        try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(TestTable(id: "alpha", value: 1))).execute()
        }
        XCTAssertEqual(try rows(in: database), [TestTable(id: "alpha", value: 1)])

        let outcomes = LockedValue<[String]?>(nil)
        DispatchQueue.global().async {
            do {
                try database.withTransaction { scope in
                    let refused = DispatchQueue.main.sync { Self.outcomes(of: scope) }
                    outcomes.withValue { $0 = refused }
                }
            }
            catch {
                outcomes.withValue { $0 = ["withTransaction: \(error)"] }
            }
        }
        spinRunLoop { outcomes.read() != nil }
        XCTAssertEqual(outcomes.read(), Self.refused)
    }
}
