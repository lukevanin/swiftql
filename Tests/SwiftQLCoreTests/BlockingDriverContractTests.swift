import Foundation
import XCTest

import SwiftQLCore
import SwiftQLTestSupport


/// Runs the blocking driver-scope contract (issue #682) against a driver that
/// shares nothing with GRDB, and checks that the suite itself notices a driver
/// that breaks it.
final class BlockingDriverContractTests: XCTestCase {

    func testNonGRDBDoublePassesEveryBlockingContractClause() async {
        for clause in BlockingDriverContractClause.allCases {
            do {
                try await BlockingDriverContractSuite.check(clause, BlockingMarkerFixture())
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

    func testSuiteReportsADriverThatReplacesTheOperationError() async {
        await assertSuite(
            reports: .transactionRollsBackWhenTheOperationThrows,
            for: .replacesTheOperationError
        )
    }

    func testSuiteReportsADriverWhoseWriteScopeDropsWrites() async {
        await assertSuite(
            reports: .writeScopeWritesOutsideATransaction,
            for: .dropsWriteScopeWrites
        )
    }

    private func assertSuite(
        reports clause: BlockingDriverContractClause,
        for defect: BlockingMarkerDriver.Defect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await BlockingDriverContractSuite.check(clause, BlockingMarkerFixture(defect: defect))
            XCTFail("The suite accepted a driver that \(defect).", file: file, line: line)
        }
        catch let violation as BlockingDriverContractViolation {
            XCTAssertEqual(violation.clause, clause, file: file, line: line)
        }
        catch {
            XCTFail("Expected a contract violation, got \(error).", file: file, line: line)
        }
    }
}


/// Writes and counts markers through prepared logical statements, as the
/// asynchronous suite's `MarkerFixture` does.
private struct BlockingMarkerFixture: DriverContractFixture {

    var defect: BlockingMarkerDriver.Defect?

    var supportedTransactionKinds: [XLTransactionKind] {
        [.immediate]
    }

    func makeDriver() async throws -> BlockingMarkerDriver {
        BlockingMarkerDriver(defect: defect)
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
/// An in-memory blocking driver whose only state is a count of marker rows.
///
/// A lock serializes every scope, the way a database serializes its writer.
/// A read scope sees the committed count. A write scope keeps its inserts; a
/// transaction keeps them only when the operation returns. Its asynchronous
/// scopes run the blocking ones, which is enough for a double.
///
private struct BlockingMarkerDriver: XLBlockingDatabaseDriver {

    /// A deliberate contract violation, for checking that the suite notices.
    enum Defect: Sendable, CustomStringConvertible {
        case commitsWhenTheOperationThrows
        case replacesTheOperationError
        case dropsWriteScopeWrites

        var description: String {
            switch self {
            case .commitsWhenTheOperationThrows:
                return "commits a blocking transaction whose operation threw"
            case .replacesTheOperationError:
                return "replaces the error a blocking transaction's operation threw"
            case .dropsWriteScopeWrites:
                return "drops what the blocking write scope wrote"
            }
        }
    }

    struct ReplacedError: Error {}

    let driverIdentifier = XLDriverIdentifier(rawValue: "blocking-marker-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let defaultTransactionKind = XLTransactionKind.immediate
    let defect: Defect?
    private let store = BlockingMarkerStore()

    init(defect: Defect?) {
        self.defect = defect
    }

    func withBlockingReadConnection<Result>(
        _ operation: (inout MarkerConnection) throws -> Result
    ) throws -> Result {
        try store.locked { committed in
            var connection = makeConnection(count: committed)
            return try operation(&connection)
        }
    }

    func withBlockingWriteConnection<Result>(
        _ operation: (inout MarkerConnection) throws -> Result
    ) throws -> Result {
        try store.locked { committed in
            var connection = makeConnection(count: committed)
            defer {
                if defect != .dropsWriteScopeWrites {
                    committed = connection.count
                }
            }
            return try operation(&connection)
        }
    }

    func withBlockingTransaction<Result>(
        _ operation: (inout MarkerConnection) throws -> Result
    ) throws -> Result {
        try store.locked { committed in
            var connection = makeConnection(count: committed)
            do {
                let result = try operation(&connection)
                committed = connection.count
                return result
            }
            catch {
                if defect == .commitsWhenTheOperationThrows {
                    committed = connection.count
                }
                if defect == .replacesTheOperationError {
                    throw ReplacedError()
                }
                throw error
            }
        }
    }

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        return try withBlockingReadConnection(operation)
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        return try withBlockingWriteConnection(operation)
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout MarkerConnection) throws -> Result
    ) async throws -> Result {
        guard kind == .immediate else {
            throw XLDatabaseContractError.unsupportedTransactionKind(driver: driverIdentifier, kind: kind)
        }
        try Task.checkCancellation()
        return try withBlockingTransaction(operation)
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


/// The committed marker count, behind a lock every scope holds while its
/// operation runs.
private final class BlockingMarkerStore: @unchecked Sendable {

    private let lock = NSRecursiveLock()

    private var committed = 0

    func locked<Result>(_ body: (inout Int) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&committed)
    }
}
