import Foundation
import XCTest

import SwiftQLCore
import SwiftQLTestSupport


/// Runs the asynchronous driver-scope contract (issue #676) against a driver
/// that shares nothing with GRDB, and checks that the suite itself notices a
/// driver that breaks it.
final class AsyncDriverContractTests: XCTestCase {

    func testNonGRDBDoublePassesEveryContractClause() async {
        for clause in DriverContractClause.allCases {
            do {
                try await DriverContractSuite.check(clause, MarkerFixture())
            }
            catch {
                XCTFail("\(clause): \(error)")
            }
        }
    }

    func testSuiteReportsADriverThatCommitsAFailedTransaction() async {
        await assertSuite(
            reports: .transactionRollsBackWhenTheOperationThrows,
            for: .commitsWhenTheOperationThrows
        )
    }

    func testSuiteReportsADriverThatLendsAConnectionToACancelledTask() async {
        await assertSuite(
            reports: .cancelledTaskIsNotLentAConnection,
            for: .ignoresCancellation
        )
    }

    func testSuiteReportsADriverThatAcceptsAnyTransactionKind() async {
        await assertSuite(
            reports: .unsupportedTransactionKindIsRejectedBeforeTheOperationRuns,
            for: .acceptsAnyTransactionKind
        )
    }

    func testSuiteReportsADriverThatReplacesTheOperationError() async {
        await assertSuite(
            reports: .transactionRollsBackWhenTheOperationThrows,
            for: .replacesTheOperationError
        )
    }

    private func assertSuite(
        reports clause: DriverContractClause,
        for defect: MarkerDriver.Defect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await DriverContractSuite.check(clause, MarkerFixture(defect: defect))
            XCTFail("The suite accepted a driver that \(defect).", file: file, line: line)
        }
        catch let violation as DriverContractViolation {
            XCTAssertEqual(violation.clause, clause, file: file, line: line)
        }
        catch {
            XCTFail("Expected a contract violation, got \(error).", file: file, line: line)
        }
    }
}


/// Writes and counts markers through prepared logical statements, so the
/// fixture exercises the connection contract rather than reaching into the
/// double.
private struct MarkerFixture: DriverContractFixture {

    var defect: MarkerDriver.Defect?

    var supportedTransactionKinds: [XLTransactionKind] {
        MarkerDriver.supportedTransactionKinds
    }

    func makeDriver() async throws -> MarkerDriver {
        MarkerDriver(defect: defect)
    }

    func insertMarker(on connection: inout MarkerConnection) throws {
        let statement = try connection.prepareValidated(
            logicalStatement(MarkerConnection.insertSQL, on: connection)
        )
        try connection.executeValidated(statement)
    }

    func markerCount(on connection: inout MarkerConnection) throws -> Int {
        let statement = try connection.prepareValidated(
            logicalStatement(MarkerConnection.countSQL, on: connection)
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

    private func logicalStatement(
        _ sql: String,
        on connection: MarkerConnection
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: connection.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }
}


///
/// An in-memory driver whose only state is a count of marker rows.
///
/// An actor owns the committed count and serializes every write scope, the
/// way a database serializes its writer, without blocking a thread. A read
/// scope takes a snapshot of the committed count. A write scope keeps its
/// inserts whether or not the operation throws; a transaction keeps them only
/// when the operation returns.
///
private struct MarkerDriver: XLDatabaseDriver {

    /// A deliberate contract violation, for checking that the suite notices.
    enum Defect: Sendable, CustomStringConvertible {
        case commitsWhenTheOperationThrows
        case ignoresCancellation
        case acceptsAnyTransactionKind
        case replacesTheOperationError

        var description: String {
            switch self {
            case .commitsWhenTheOperationThrows:
                return "commits a transaction whose operation threw"
            case .ignoresCancellation:
                return "lends a connection to a cancelled task"
            case .acceptsAnyTransactionKind:
                return "accepts a transaction kind it does not know"
            case .replacesTheOperationError:
                return "replaces the error a transaction's operation threw"
            }
        }
    }

    struct ReplacedError: Error {}

    static let supportedTransactionKinds: [XLTransactionKind] = [.deferred, .immediate, .exclusive]

    let driverIdentifier = XLDriverIdentifier(rawValue: "marker-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect(
        version: XLDialectVersion(3, 46),
        capabilities: XLSQLiteDialect.standardCapabilities
    )
    let defect: Defect?
    private let store = MarkerStore()

    init(defect: Defect?) {
        self.defect = defect
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        try checkCancellation()
        var connection = makeConnection(count: await store.committedCount)
        return try operation(&connection)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        try checkCancellation()
        return try await store.write(
            makeConnection(count: 0),
            keepsWritesOnThrow: true,
            operation
        )
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        if !Self.supportedTransactionKinds.contains(kind), defect != .acceptsAnyTransactionKind {
            throw XLDatabaseContractError.unsupportedTransactionKind(
                driver: driverIdentifier,
                kind: kind
            )
        }
        try checkCancellation()
        do {
            return try await store.write(
                makeConnection(count: 0),
                keepsWritesOnThrow: defect == .commitsWhenTheOperationThrows,
                operation
            )
        }
        catch where defect == .replacesTheOperationError {
            throw ReplacedError()
        }
    }

    private func checkCancellation() throws {
        if defect != .ignoresCancellation {
            try Task.checkCancellation()
        }
    }

    private func makeConnection(count: Int) -> MarkerConnection {
        MarkerConnection(
            driverIdentifier: driverIdentifier,
            databaseIdentifier: databaseIdentifier,
            dialect: dialect,
            count: count
        )
    }
}


private actor MarkerStore {

    private(set) var committedCount = 0

    /// Runs `operation` on a connection that sees the committed count, then
    /// commits the connection's count when `operation` returns, or when it
    /// throws and `keepsWritesOnThrow` is set.
    func write<Result: Sendable>(
        _ template: MarkerConnection,
        keepsWritesOnThrow: Bool,
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) throws -> Result {
        var connection = template
        connection.count = committedCount
        do {
            let result = try operation(&connection)
            committedCount = connection.count
            return result
        }
        catch {
            if keepsWritesOnThrow {
                committedCount = connection.count
            }
            throw error
        }
    }
}


private struct MarkerConnection: XLDatabaseDriverConnection, Sendable {

    static let insertSQL = "INSERT marker"
    static let countSQL = "COUNT marker"

    struct Statement {
        let sql: String
    }

    let driverIdentifier: XLDriverIdentifier
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect: XLSQLiteDialect
    var count: Int

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> Statement {
        let sql = statement.logicalStatement.sql
        guard sql == Self.insertSQL || sql == Self.countSQL else {
            throw XLDatabaseContractError.prepareFailure(
                driver: driverIdentifier,
                message: "unknown statement \(sql)"
            )
        }
        return Statement(sql: sql)
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: Statement
    ) throws -> Statement {
        throw XLDatabaseContractError.bindFailure(
            driver: driverIdentifier,
            key: key,
            message: "marker statements take no parameters"
        )
    }

    mutating func fetchAll(_ statement: Statement) throws -> [[XLSQLiteValue]] {
        try fetchOne(statement).map { [$0] } ?? []
    }

    mutating func fetchOne(_ statement: Statement) throws -> [XLSQLiteValue]? {
        guard statement.sql == Self.countSQL else {
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: "\(statement.sql) returns no rows"
            )
        }
        return [.integer(Int64(count))]
    }

    mutating func execute(_ statement: Statement) throws {
        guard statement.sql == Self.insertSQL else {
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: "\(statement.sql) is not a write"
            )
        }
        count += 1
    }
}
