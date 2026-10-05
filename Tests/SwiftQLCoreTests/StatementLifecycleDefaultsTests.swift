import Foundation
import XCTest

import SwiftQLCore


/// Issue #677: `finalizePhysical(_:)` is a connection requirement with a
/// default, so a connection written before it keeps compiling, and the
/// default `warmUp(_:)` of a caching connection is the prepare-then-finalize
/// lifecycle.
final class StatementLifecycleDefaultsTests: XCTestCase {

    func testDefaultFinalizeLeavesTheConnectionAsItWas() throws {
        var connection = PlainConnection()
        let statement = try connection.prepare(connection.logicalStatement("SELECT 1"))

        connection.finalizePhysical(statement)

        XCTAssertEqual(connection.preparedSQL, ["SELECT 1"])
        XCTAssertEqual(try connection.fetchAll(statement), [[.integer(1)]])
    }

    func testDefaultWarmUpPreparesAndFinalizesEachStatementInOrder() throws {
        var connection = RecordingCachingConnection()
        let manifest = ["SELECT 1", "INSERT INTO t VALUES (1)"].map {
            connection.logicalStatement($0)
        }

        try connection.warmUp(manifest)

        XCTAssertEqual(connection.events, [
            "prepare SELECT 1", "finalize SELECT 1",
            "prepare INSERT INTO t VALUES (1)", "finalize INSERT INTO t VALUES (1)",
        ])
        XCTAssertEqual(connection.statementCacheStatistics.misses, 2)
    }

    /// Warm-up prepares as a request does, so a prepare failure reaches the
    /// caller as the connection threw it.
    func testDefaultWarmUpStopsAtTheFirstPrepareFailure() {
        var connection = RecordingCachingConnection(failingSQL: "SELECT broken")
        let manifest = ["SELECT 1", "SELECT broken", "SELECT 2"].map {
            connection.logicalStatement($0)
        }

        XCTAssertThrowsError(try connection.warmUp(manifest)) { error in
            XCTAssertTrue(error is RecordingCachingConnection.PrepareFailure, "\(error)")
        }
        XCTAssertEqual(connection.events, ["prepare SELECT 1", "finalize SELECT 1"])
    }

    func testAConnectionsOwnWarmUpIsCalledThroughTheRefinement() throws {
        var connection = BulkWarmingConnection()
        let manifest = [connection.recording.logicalStatement("SELECT 1")]

        try warmThroughRefinement(&connection, manifest)

        XCTAssertEqual(connection.recording.events, ["bulk warm-up of 1"])
    }

    func testStatisticsDefaultToZero() {
        XCTAssertEqual(
            XLStatementCacheStatistics(),
            XLStatementCacheStatistics(
                hits: 0,
                misses: 0,
                evictions: 0,
                invalidations: 0,
                cachedStatementCount: 0
            )
        )
    }
}


/// Warms `connection` through generic code that knows only the refinement.
private func warmThroughRefinement<Connection: XLStatementCachingDriverConnection>(
    _ connection: inout Connection,
    _ manifest: [XLLogicalPreparedStatement]
) throws {
    try connection.warmUp(manifest)
}


/// A connection that implements only the required members.
private struct PlainConnection: XLDatabaseDriverConnection {

    let driverIdentifier = XLDriverIdentifier(rawValue: "plain-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    var preparedSQL: [String] = []

    func logicalStatement(_ sql: String) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        preparedSQL.append(statement.logicalStatement.sql)
        return statement.logicalStatement.sql
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        [[.integer(1)]]
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        try fetchAll(statement).first
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .write)
    }
}


/// A caching connection that records each lifecycle call, counts every
/// preparation as a miss, and keeps the default warm-up.
private struct RecordingCachingConnection: XLStatementCachingDriverConnection {

    struct PrepareFailure: Error {}

    let driverIdentifier = XLDriverIdentifier(rawValue: "recording-caching-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    var failingSQL: String?
    var events: [String] = []
    var statementCacheStatistics = XLStatementCacheStatistics()

    func logicalStatement(_ sql: String) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        let sql = statement.logicalStatement.sql
        if sql == failingSQL {
            throw PrepareFailure()
        }
        events.append("prepare \(sql)")
        statementCacheStatistics.misses += 1
        return sql
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        events.append("bind \(statement)")
        return statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        events.append("fetch \(statement)")
        return []
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        events.append("fetch \(statement)")
        return nil
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        events.append("execute \(statement)")
        return XLExecutionResult(rowsAffected: 0, access: .write)
    }

    mutating func resetPhysical(_ statement: String) throws -> String {
        events.append("reset \(statement)")
        return statement
    }

    mutating func finalizePhysical(_ statement: String) {
        events.append("finalize \(statement)")
    }

    mutating func invalidatePreparedStatements() throws {
        statementCacheStatistics.invalidations += 1
    }
}


/// A caching connection with its own warm-up, which prepares a manifest in
/// one step.
private struct BulkWarmingConnection: XLStatementCachingDriverConnection {

    var recording = RecordingCachingConnection()

    var driverIdentifier: XLDriverIdentifier { recording.driverIdentifier }
    var databaseIdentifier: XLDatabaseIdentifier { recording.databaseIdentifier }
    var dialect: XLSQLiteDialect { recording.dialect }
    var statementCacheStatistics: XLStatementCacheStatistics { recording.statementCacheStatistics }

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        try recording.preparePhysical(statement)
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        try recording.bind(value, to: key, in: statement)
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        try recording.fetchAll(statement)
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        try recording.fetchOne(statement)
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        try recording.execute(statement)
    }

    mutating func resetPhysical(_ statement: String) throws -> String {
        try recording.resetPhysical(statement)
    }

    mutating func invalidatePreparedStatements() throws {
        try recording.invalidatePreparedStatements()
    }

    mutating func warmUp<Manifest: Sequence>(
        _ manifest: Manifest
    ) throws where Manifest.Element == XLLogicalPreparedStatement {
        recording.events.append("bulk warm-up of \(Array(manifest).count)")
    }
}
