//
//  StatementCachingConnectionTests.swift
//  SQLTests
//
//  Issue #677: the statement lifecycle hooks are enough for a connection to
//  cache statements that SwiftQL can observe, warm, and invalidate. The
//  connection here caches real SQLite statements, prepared through GRDB
//  without GRDB's own cache, and SwiftQL's request path runs on it.
//

import Foundation
import GRDB
import XCTest
@testable import SwiftQL


final class StatementCachingConnectionTests: XCTestCase {

    // MARK: - Warm-up

    func testWarmUpPreparesAManifestWithoutExecutingIt() throws {
        let driver = try makeDriver()
        let select = driver.logicalStatement("SELECT name FROM item ORDER BY id")
        let insert = driver.logicalStatement("INSERT INTO item (name) VALUES ('warm')")

        let statistics = try driver.withBlockingWriteConnection { connection in
            try connection.warmUp([select, insert])
            return connection.statementCacheStatistics
        }

        XCTAssertEqual(
            statistics,
            XLStatementCacheStatistics(misses: 2, cachedStatementCount: 2)
        )
        XCTAssertEqual(try driver.itemCount(), 0, "Warm-up must not run the INSERT.")

        try XLInvocationExecutor(driver: driver, logicalStatement: insert)
            .execute(bindings: noBindings)
        let names = try XLInvocationExecutor(driver: driver, logicalStatement: select)
            .fetchAll(bindings: noBindings)

        XCTAssertEqual(names, [[.text("warm")]])
        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(hits: 2, misses: 2, cachedStatementCount: 2),
            "Each warmed statement's first run is a cache hit."
        )
    }

    func testWarmUpChecksEachStatementBeforePreparingIt() throws {
        let driver = try makeDriver()
        let foreign = XLLogicalPreparedStatement(
            databaseIdentifier: XLDatabaseIdentifier(rawValue: UUID()),
            dialectRequirement: driver.requirement,
            sql: "SELECT 1"
        )

        XCTAssertThrowsError(
            try driver.withBlockingWriteConnection { connection in
                try connection.warmUp([driver.logicalStatement("SELECT 2"), foreign])
            }
        ) { error in
            guard case .driverMismatch = error as? XLDatabaseContractError else {
                return XCTFail("Expected a driver mismatch, got \(error).")
            }
        }

        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(misses: 1, cachedStatementCount: 1),
            "The statement before the failure stays cached; the failing one is never prepared."
        )
    }

    // MARK: - Statistics

    func testRepeatedRequestsHitTheCacheBecauseSwiftQLFinalizesEachStatement() throws {
        let driver = try makeDriver()
        let select = XLInvocationExecutor(
            driver: driver,
            logicalStatement: driver.logicalStatement("SELECT count(*) FROM item")
        )

        for _ in 0 ..< 3 {
            _ = try select.fetchAll(bindings: noBindings)
        }
        _ = try select.fetchOne(bindings: noBindings)
        try select.forEachRow(bindings: noBindings) { _ in .stop }

        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(hits: 4, misses: 1, cachedStatementCount: 1)
        )
    }

    func testTheCacheCountsEvictions() throws {
        let driver = try makeDriver(capacity: 2)
        let statements = ["SELECT 1", "SELECT 2", "SELECT 3", "SELECT 1"].map {
            XLInvocationExecutor(driver: driver, logicalStatement: driver.logicalStatement($0))
        }

        for statement in statements {
            _ = try statement.fetchAll(bindings: noBindings)
        }

        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(misses: 4, evictions: 2, cachedStatementCount: 2),
            "`SELECT 1` is evicted for `SELECT 3`, so its second run prepares it again."
        )
    }

    // MARK: - Schema invalidation

    func testASchemaChangeInvalidatesTheCacheAndTheNextRunPreparesAgain() throws {
        let driver = try makeDriver()
        try driver.queue.write { database in
            try database.execute(sql: "INSERT INTO item (name) VALUES ('pen')")
        }
        let select = XLInvocationExecutor(
            driver: driver,
            logicalStatement: driver.logicalStatement("SELECT * FROM item")
        )
        XCTAssertEqual(try select.fetchAll(bindings: noBindings), [[.integer(1), .text("pen")]])
        XCTAssertEqual(try select.fetchAll(bindings: noBindings), [[.integer(1), .text("pen")]])
        XCTAssertEqual(driver.statistics.hits, 1)

        try XLInvocationExecutor(
            driver: driver,
            logicalStatement: driver.logicalStatement(
                "ALTER TABLE item ADD COLUMN price REAL NOT NULL DEFAULT 1.5"
            )
        )
        .execute(bindings: noBindings)

        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(hits: 1, misses: 2, invalidations: 2),
            "The ALTER TABLE discards both cached statements, itself included."
        )
        XCTAssertEqual(
            try select.fetchAll(bindings: noBindings),
            [[.integer(1), .text("pen"), .real(1.5)]],
            "The SELECT is prepared again, against the new schema."
        )
        XCTAssertEqual(
            driver.statistics,
            XLStatementCacheStatistics(hits: 1, misses: 3, invalidations: 2, cachedStatementCount: 1)
        )
    }

    /// A schema change the connection cannot see, such as one made through
    /// another connection, reaches it through `invalidatePreparedStatements()`.
    /// A statement in use when that happens finishes its run, and is
    /// discarded rather than cached again.
    func testInvalidatingWhileAStatementIsInUseLetsItFinish() throws {
        let driver = try makeDriver()
        try driver.queue.write { database in
            try database.execute(sql: "INSERT INTO item (name) VALUES ('ink'), ('nib')")
        }
        let select = driver.logicalStatement("SELECT name FROM item ORDER BY id")

        let (names, statistics) = try driver.withBlockingWriteConnection { connection in
            let statement = try connection.prepare(select)
            // The same physical connection, as a row callback would reach it.
            var sameConnection = connection
            var names: [[XLSQLiteValue]] = []
            try connection.forEachRow(statement) { row in
                names.append(row)
                try sameConnection.invalidatePreparedStatements()
                return .advance
            }
            connection.finalizePhysical(statement)
            return (names, connection.statementCacheStatistics)
        }

        XCTAssertEqual(names, [[.text("ink")], [.text("nib")]])
        XCTAssertEqual(
            statistics,
            XLStatementCacheStatistics(misses: 1, invalidations: 1),
            "The invalidated statement is not returned to the cache when it is finalized."
        )
        _ = try XLInvocationExecutor(driver: driver, logicalStatement: select)
            .fetchAll(bindings: noBindings)
        XCTAssertEqual(driver.statistics.misses, 2, "The next run prepares the statement again.")
    }

    // MARK: - Helpers

    private var noBindings: XLInvocationBindings<XLSQLiteValue> {
        XLInvocationBindings(layout: .empty)
    }

    private func makeDriver(capacity: Int = 8) throws -> CachingSQLiteDriver {
        let queue = try DatabaseQueue()
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE item (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
        }
        return CachingSQLiteDriver(queue: queue, cache: SQLiteStatementCache(capacity: capacity))
    }
}


// MARK: - A caching connection

/// A bounded cache of SQLite statements for one physical connection. It holds
/// at most one statement per SQL text, and evicts the least recently lent
/// free statement when it is full.
///
/// Only the connection's serialized database accesses touch it.
final class SQLiteStatementCache: @unchecked Sendable {

    private struct Entry {
        let statement: Statement
        var isInUse: Bool
    }

    let capacity: Int

    private var entries: [String: Entry] = [:]

    /// The cached SQL texts, least recently lent first.
    private var recency: [String] = []

    /// Bumped by every invalidation, so that a statement lent before it is
    /// not cached again.
    private(set) var generation = 0

    private var counters = XLStatementCacheStatistics()

    init(capacity: Int) {
        self.capacity = capacity
    }

    var statistics: XLStatementCacheStatistics {
        var statistics = counters
        statistics.cachedStatementCount = entries.count
        return statistics
    }

    /// Lends the cached statement for `sql` when it is free, and otherwise
    /// prepares one. Returns whether the statement belongs to the cache.
    func checkOut(sql: String, in database: Database) throws -> (Statement, isCached: Bool) {
        if var entry = entries[sql] {
            if !entry.isInUse {
                counters.hits += 1
                entry.isInUse = true
                entries[sql] = entry
                touch(sql)
                return (entry.statement, true)
            }
            // A nested request runs the same SQL while the cached statement
            // is stepping: lend it a statement of its own.
            counters.misses += 1
            return (try database.makeStatement(sql: sql), false)
        }
        counters.misses += 1
        let statement = try database.makeStatement(sql: sql)
        entries[sql] = Entry(statement: statement, isInUse: true)
        touch(sql)
        evictIfFull()
        return (statement, true)
    }

    func checkIn(sql: String, generation lentGeneration: Int) {
        guard lentGeneration == generation, var entry = entries[sql] else {
            return
        }
        entry.isInUse = false
        entries[sql] = entry
    }

    func invalidate() {
        counters.invalidations += entries.count
        entries.removeAll()
        recency.removeAll()
        generation += 1
    }

    private func touch(_ sql: String) {
        recency.removeAll { $0 == sql }
        recency.append(sql)
    }

    private func evictIfFull() {
        while entries.count > capacity,
              let victim = recency.first(where: { entries[$0]?.isInUse == false }) {
            entries[victim] = nil
            recency.removeAll { $0 == victim }
            counters.evictions += 1
        }
    }
}


struct CachingSQLiteStatement {
    let sql: String
    let statement: Statement
    let isCached: Bool
    let generation: Int
    var bindings: [XLBindingKey: XLSQLiteValue] = [:]
}


/// A connection that caches real SQLite statements, and invalidates its
/// cache when a statement it runs changes the schema.
struct CachingSQLiteConnection: XLStatementCachingDriverConnection {

    typealias Dialect = XLSQLiteDialect

    typealias PhysicalStatement = CachingSQLiteStatement

    let driverIdentifier: XLDriverIdentifier
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect = XLSQLiteDialect()
    let database: Database
    let cache: SQLiteStatementCache

    var statementCacheStatistics: XLStatementCacheStatistics {
        cache.statistics
    }

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> CachingSQLiteStatement {
        let sql = statement.logicalStatement.sql
        let generation = cache.generation
        let (prepared, isCached) = try cache.checkOut(sql: sql, in: database)
        return CachingSQLiteStatement(
            sql: sql,
            statement: prepared,
            isCached: isCached,
            generation: generation
        )
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: CachingSQLiteStatement
    ) throws -> CachingSQLiteStatement {
        var bound = statement
        bound.bindings[key] = value
        return bound
    }

    mutating func fetchAll(_ statement: CachingSQLiteStatement) throws -> [[XLSQLiteValue]] {
        try Row.fetchAll(statement.statement, arguments: arguments(statement)).map { row in
            row.databaseValues.map(\.sqliteDialectValue)
        }
    }

    mutating func fetchOne(_ statement: CachingSQLiteStatement) throws -> [XLSQLiteValue]? {
        try Row.fetchOne(statement.statement, arguments: arguments(statement))
            .map { row in row.databaseValues.map(\.sqliteDialectValue) }
    }

    mutating func forEachRow(
        _ statement: CachingSQLiteStatement,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        let cursor = try Row.fetchCursor(statement.statement, arguments: arguments(statement))
        while let row = try cursor.next() {
            if try body(row.databaseValues.map(\.sqliteDialectValue)) == .stop {
                return
            }
        }
    }

    mutating func execute(_ statement: CachingSQLiteStatement) throws -> XLExecutionResult {
        let schemaVersion = try database.schemaVersion()
        try statement.statement.execute(arguments: arguments(statement))
        if try database.schemaVersion() != schemaVersion {
            try invalidatePreparedStatements()
        }
        return XLExecutionResult(rowsAffected: database.changesCount, access: .write)
    }

    mutating func resetPhysical(_ statement: CachingSQLiteStatement) throws -> CachingSQLiteStatement {
        var reset = statement
        reset.bindings = [:]
        return reset
    }

    mutating func finalizePhysical(_ statement: CachingSQLiteStatement) {
        if statement.isCached {
            cache.checkIn(sql: statement.sql, generation: statement.generation)
        }
    }

    mutating func invalidatePreparedStatements() throws {
        cache.invalidate()
    }

    private func arguments(_ statement: CachingSQLiteStatement) -> StatementArguments {
        var named: [String: (any DatabaseValueConvertible)?] = [:]
        for (key, value) in statement.bindings {
            if case .named(let name) = key {
                named[name] = value.databaseValue
            }
        }
        return StatementArguments(named)
    }
}


/// A blocking driver over one in-memory queue, whose connection caches
/// statements across accesses.
struct CachingSQLiteDriver: XLBlockingDatabaseDriver {

    typealias Dialect = XLSQLiteDialect

    typealias Connection = CachingSQLiteConnection

    let driverIdentifier = XLDriverIdentifier(rawValue: "caching-sqlite-fixture")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let defaultTransactionKind = XLTransactionKind.immediate
    let queue: DatabaseQueue
    let cache: SQLiteStatementCache

    var requirement: XLDialectRequirement {
        XLDialectRequirement(identity: XLSQLiteDialect.identity, capabilities: [.namedBindings])
    }

    var statistics: XLStatementCacheStatistics {
        queue.inDatabase { _ in cache.statistics }
    }

    func logicalStatement(_ sql: String) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: requirement,
            sql: sql
        )
    }

    func itemCount() throws -> Int {
        try queue.read { database in
            try Int.fetchOne(database, sql: "SELECT count(*) FROM item") ?? 0
        }
    }

    func withBlockingReadConnection<Result>(
        _ operation: (inout CachingSQLiteConnection) throws -> Result
    ) throws -> Result {
        try queue.inDatabase { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    func withBlockingWriteConnection<Result>(
        _ operation: (inout CachingSQLiteConnection) throws -> Result
    ) throws -> Result {
        try queue.inDatabase { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    func withBlockingTransaction<Result>(
        _ operation: (inout CachingSQLiteConnection) throws -> Result
    ) throws -> Result {
        try queue.inDatabase { database in
            var result: Result?
            try database.inTransaction(.immediate) {
                var connection = makeConnection(database)
                result = try operation(&connection)
                return .commit
            }
            return result!
        }
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout CachingSQLiteConnection) throws -> Result
    ) async throws -> Result {
        try withBlockingReadConnection(operation)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout CachingSQLiteConnection) throws -> Result
    ) async throws -> Result {
        try withBlockingWriteConnection(operation)
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout CachingSQLiteConnection) throws -> Result
    ) async throws -> Result {
        try withBlockingTransaction(operation)
    }

    private func makeConnection(_ database: Database) -> CachingSQLiteConnection {
        CachingSQLiteConnection(
            driverIdentifier: driverIdentifier,
            databaseIdentifier: databaseIdentifier,
            database: database,
            cache: cache
        )
    }
}
