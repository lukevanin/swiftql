import Foundation
import XCTest

import SwiftQLCore


/// Issue #677: `resetPhysical(_:)` and `finalizePhysical(_:)` are connection
/// requirements with defaults, so a connection written before them keeps
/// compiling, and `warmUp(_:)` is the prepare-then-finalize lifecycle of a
/// caching connection.
final class StatementLifecycleDefaultsTests: XCTestCase {

    func testDefaultResetReturnsTheStatementUnchanged() throws {
        var connection = PlainConnection()

        XCTAssertEqual(try connection.resetPhysical("SELECT ?"), "SELECT ?")
    }

    func testDefaultFinalizeDoesNothing() {
        var connection = PlainConnection()

        connection.finalizePhysical("SELECT 1")

        XCTAssertEqual(connection.preparedSQL, [])
    }

    func testWarmUpPreparesAndFinalizesEachStatementInOrder() throws {
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

    func testWarmUpReportsAPrepareFailureAndStops() {
        var connection = RecordingCachingConnection(failingSQL: "SELECT broken")
        let manifest = ["SELECT broken", "SELECT 2"].map {
            connection.logicalStatement($0)
        }

        XCTAssertThrowsError(try connection.warmUp(manifest)) { error in
            guard case .prepareFailure = error as? XLDatabaseContractError else {
                return XCTFail("Expected a prepare failure, got \(error).")
            }
        }
        XCTAssertEqual(connection.events, [], "Nothing was prepared, so nothing is finalized.")
    }

    func testAConnectionsOwnWarmUpIsCalledThroughTheRefinement() throws {
        var connection = RecordingCachingConnection(warmsInBulk: true)
        let manifest = [connection.logicalStatement("SELECT 1")]

        try warmThroughRefinement(&connection, manifest)

        XCTAssertEqual(connection.events, ["bulk warm-up of 1"])
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

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        preparedSQL.append(statement.logicalStatement.sql)
        return statement.logicalStatement.sql
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        []
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        nil
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .write)
    }
}


/// A caching connection that records each lifecycle call, and counts every
/// preparation as a miss.
private struct RecordingCachingConnection: XLStatementCachingDriverConnection {

    struct PrepareFailure: Error {}

    let driverIdentifier = XLDriverIdentifier(rawValue: "recording-caching-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    var failingSQL: String?
    var warmsInBulk = false
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

    mutating func finalizePhysical(_ statement: String) {
        events.append("finalize \(statement)")
    }

    mutating func invalidatePreparedStatements() throws {
        statementCacheStatistics.invalidations += 1
    }

    mutating func warmUp<Manifest: Sequence>(
        _ manifest: Manifest
    ) throws where Manifest.Element == XLLogicalPreparedStatement {
        guard warmsInBulk else {
            for statement in manifest {
                finalizePhysical(try prepareValidated(statement))
            }
            return
        }
        events.append("bulk warm-up of \(Array(manifest).count)")
    }
}
