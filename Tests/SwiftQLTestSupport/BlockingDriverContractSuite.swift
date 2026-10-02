//
//  BlockingDriverContractSuite.swift
//  SwiftQLTestSupport
//
//  The blocking driver-scope contract, as a suite any driver can run
//  (issue #682): the rules `XLBlockingDatabaseDriver` states for the scopes
//  SwiftQL's synchronous request members run on.
//
//  It follows `DriverContractSuite`, the asynchronous suite (issue #676), and
//  takes the same fixture, so the non-GRDB double in `SwiftQLCoreTests` and the
//  GRDB adapter in `SQLTests` run the same clauses. A clause reports a failure
//  by throwing `BlockingDriverContractViolation`.
//

import Foundation
import SwiftQLCore


/// One broken clause of the blocking driver contract.
public struct BlockingDriverContractViolation: Error, CustomStringConvertible {

    public let clause: BlockingDriverContractClause

    public let detail: String

    public var description: String {
        "\(clause): \(detail)"
    }
}


/// The clauses of the blocking driver-scope contract.
public enum BlockingDriverContractClause: String, CaseIterable, Sendable, CustomStringConvertible {

    /// The blocking read scope lends a connection for the driver's own
    /// database and dialect, and returns what the operation returned.
    case readScopeLendsTheDriversConnection

    /// A write made through the blocking write scope is visible to a later
    /// read.
    case writeScopeWritesOutsideATransaction

    /// A blocking transaction commits when its operation returns, and returns
    /// what the operation returned.
    case transactionCommitsWhenTheOperationReturns

    /// A blocking transaction rolls back when its operation throws, and
    /// rethrows that error unchanged.
    case transactionRollsBackWhenTheOperationThrows

    public var description: String {
        rawValue
    }
}


/// Runs the blocking driver-scope contract against a fixture.
public enum BlockingDriverContractSuite {

    /// Checks one clause against a fresh driver from `fixture`.
    ///
    /// - Throws: ``BlockingDriverContractViolation`` when the driver breaks the
    ///   clause, or whatever the fixture threw while setting up.
    public static func check<Fixture: DriverContractFixture>(
        _ clause: BlockingDriverContractClause,
        _ fixture: Fixture
    ) async throws where Fixture.Driver: XLBlockingDatabaseDriver {
        let driver = try await fixture.makeDriver()
        let check = BlockingClauseCheck(clause: clause, fixture: fixture, driver: driver)
        switch clause {
        case .readScopeLendsTheDriversConnection:
            try check.readScopeLendsTheDriversConnection()
        case .writeScopeWritesOutsideATransaction:
            try check.writeScopeWritesOutsideATransaction()
        case .transactionCommitsWhenTheOperationReturns:
            try check.transactionCommitsWhenTheOperationReturns()
        case .transactionRollsBackWhenTheOperationThrows:
            try check.transactionRollsBackWhenTheOperationThrows()
        }
    }
}


/// The error the suite's own operations throw, so a rethrown error can be
/// told apart from anything the driver produced.
private struct BlockingContractSentinel: Error, Equatable {
    let tag: String
}


private struct BlockingClauseCheck<Fixture: DriverContractFixture>
    where Fixture.Driver: XLBlockingDatabaseDriver
{

    typealias Driver = Fixture.Driver

    let clause: BlockingDriverContractClause
    let fixture: Fixture
    let driver: Driver

    func readScopeLendsTheDriversConnection() throws {
        let lent = try driver.withBlockingReadConnection { connection in
            (
                connection.driverIdentifier,
                connection.databaseIdentifier,
                connection.dialect.descriptor.identity
            )
        }
        try expect(lent.0 == driver.driverIdentifier, "lent driver \(lent.0), expected \(driver.driverIdentifier)")
        try expect(lent.1 == driver.databaseIdentifier, "lent database \(lent.1), expected \(driver.databaseIdentifier)")
        try expect(
            lent.2 == driver.dialect.descriptor.identity,
            "lent dialect \(lent.2), expected \(driver.dialect.descriptor.identity)"
        )

        let returned = try driver.withBlockingReadConnection { _ in "returned" }
        try expect(returned == "returned", "the blocking read scope returned \(returned)")
    }

    func writeScopeWritesOutsideATransaction() throws {
        try driver.withBlockingWriteConnection { connection in
            try fixture.insertMarker(on: &connection)
        }
        try expectMarkerCount(1, "after one blocking write-scope insert")
    }

    func transactionCommitsWhenTheOperationReturns() throws {
        let returned = try driver.withBlockingTransaction { connection in
            try fixture.insertMarker(on: &connection)
            return "committed"
        }
        try expect(returned == "committed", "the blocking transaction returned \(returned)")
        try expectMarkerCount(1, "after a committed blocking transaction")
    }

    func transactionRollsBackWhenTheOperationThrows() throws {
        let sentinel = BlockingContractSentinel(tag: "blocking-rollback")
        do {
            try driver.withBlockingTransaction { connection in
                try fixture.insertMarker(on: &connection)
                throw sentinel
            }
            throw violation("a blocking transaction whose operation threw returned normally")
        }
        catch let error as BlockingContractSentinel {
            try expect(error == sentinel, "the blocking transaction rethrew \(error)")
        }
        catch let error as BlockingDriverContractViolation {
            throw error
        }
        catch {
            throw violation("the blocking transaction threw \(error) instead of the operation's error")
        }
        try expectMarkerCount(0, "after a rolled-back blocking transaction")
    }

    private func expectMarkerCount(_ expected: Int, _ context: String) throws {
        let count = try driver.withBlockingReadConnection { connection in
            try fixture.markerCount(on: &connection)
        }
        try expect(count == expected, "counted \(count) markers \(context), expected \(expected)")
    }

    private func expect(_ condition: Bool, _ detail: @autoclosure () -> String) throws {
        if !condition {
            throw violation(detail())
        }
    }

    private func violation(_ detail: String) -> BlockingDriverContractViolation {
        BlockingDriverContractViolation(clause: clause, detail: detail)
    }
}
