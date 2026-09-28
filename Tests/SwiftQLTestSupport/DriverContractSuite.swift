//
//  DriverContractSuite.swift
//  SwiftQLTestSupport
//
//  The asynchronous driver-scope contract, as a suite any driver can run
//  (issue #676).
//
//  `Research/AsyncDriverContractFeasibility.md` names this suite. It lives
//  here, free of XCTest, so the non-GRDB double in `SwiftQLCoreTests` and the
//  GRDB adapter in `SQLTests` run the same clauses rather than two copies that
//  can drift. A clause reports a failure by throwing
//  `DriverContractViolation`; the test target turns that into an XCTest
//  failure.
//

import Foundation
import SwiftQLCore


///
/// What the contract suite needs from a driver beyond the driver itself: a
/// fresh database, and one driver-specific way to write and count a marker
/// row through a lent connection.
///
public protocol DriverContractFixture: Sendable {

    associatedtype Driver: XLDatabaseDriver

    /// Transaction kinds the driver honours. Every clause that opens a
    /// transaction runs once for each.
    var supportedTransactionKinds: [XLTransactionKind] { get }

    /// A driver over a new, empty database, whose marker count is zero.
    func makeDriver() async throws -> Driver

    /// Writes one marker row through `connection`.
    func insertMarker(on connection: inout Driver.Connection) throws

    /// Counts the marker rows `connection` can see.
    func markerCount(on connection: inout Driver.Connection) throws -> Int
}


/// One broken clause of the driver contract.
public struct DriverContractViolation: Error, CustomStringConvertible {

    public let clause: DriverContractClause

    public let detail: String

    public var description: String {
        "\(clause): \(detail)"
    }
}


/// The clauses of the asynchronous driver-scope contract.
public enum DriverContractClause: String, CaseIterable, Sendable, CustomStringConvertible {

    /// A read scope lends a connection for the driver's own database and
    /// dialect, and returns what the operation returned.
    case readScopeLendsTheDriversConnection

    /// A write made through the write scope is visible to a later read.
    case writeScopeWritesOutsideATransaction

    /// A transaction commits when its operation returns.
    case transactionCommitsWhenTheOperationReturns

    /// A transaction rolls back when its operation throws, and rethrows that
    /// error unchanged.
    case transactionRollsBackWhenTheOperationThrows

    /// A validated transaction rethrows its operation's error unchanged.
    case validatedTransactionPreservesTheOperationError

    /// A kind the driver cannot honour is rejected with a structured error
    /// before any connection is lent.
    case unsupportedTransactionKindIsRejectedBeforeTheOperationRuns

    /// A task that is already cancelled gets `CancellationError` from every
    /// scope, a validated transaction included, and no operation runs.
    case cancelledTaskIsNotLentAConnection

    /// One driver value serves many concurrent tasks, and every write lands
    /// exactly once.
    case sharedDriverServesConcurrentTasks

    public var description: String {
        rawValue
    }
}


/// Runs the asynchronous driver-scope contract against a fixture.
public enum DriverContractSuite {

    /// Checks one clause against a fresh driver from `fixture`.
    ///
    /// - Throws: ``DriverContractViolation`` when the driver breaks the
    ///   clause, or whatever the fixture threw while setting up.
    public static func check<Fixture: DriverContractFixture>(
        _ clause: DriverContractClause,
        _ fixture: Fixture
    ) async throws {
        let driver = try await fixture.makeDriver()
        let check = ClauseCheck(clause: clause, fixture: fixture, driver: driver)
        switch clause {
        case .readScopeLendsTheDriversConnection:
            try await check.readScopeLendsTheDriversConnection()
        case .writeScopeWritesOutsideATransaction:
            try await check.writeScopeWritesOutsideATransaction()
        case .transactionCommitsWhenTheOperationReturns:
            try await check.transactionCommitsWhenTheOperationReturns()
        case .transactionRollsBackWhenTheOperationThrows:
            try await check.transactionRollsBackWhenTheOperationThrows()
        case .validatedTransactionPreservesTheOperationError:
            try await check.validatedTransactionPreservesTheOperationError()
        case .unsupportedTransactionKindIsRejectedBeforeTheOperationRuns:
            try await check.unsupportedTransactionKindIsRejectedBeforeTheOperationRuns()
        case .cancelledTaskIsNotLentAConnection:
            try await check.cancelledTaskIsNotLentAConnection()
        case .sharedDriverServesConcurrentTasks:
            try await check.sharedDriverServesConcurrentTasks()
        }
    }
}


/// The error the suite's own operations throw, so a rethrown error can be
/// told apart from anything the driver produced.
private struct ContractSentinel: Error, Equatable {
    let tag: String
}


/// Counts how many times an operation ran. Operations are `@Sendable` and
/// may run on the driver's executor, so the count is locked rather than
/// captured.
private typealias OperationProbe = LockedValue<Int>


extension LockedValue where Value == Int {

    fileprivate func record() {
        withValue { $0 += 1 }
    }

    fileprivate var runCount: Int {
        read()
    }
}


private struct ClauseCheck<Fixture: DriverContractFixture>: Sendable {

    typealias Driver = Fixture.Driver

    let clause: DriverContractClause
    let fixture: Fixture
    let driver: Driver

    func readScopeLendsTheDriversConnection() async throws {
        let expected = (
            driver.driverIdentifier,
            driver.databaseIdentifier,
            driver.dialect.descriptor.identity
        )
        let lent = try await driver.withReadConnection { connection in
            (
                connection.driverIdentifier,
                connection.databaseIdentifier,
                connection.dialect.descriptor.identity
            )
        }
        try expect(lent.0 == expected.0, "lent driver \(lent.0), expected \(expected.0)")
        try expect(lent.1 == expected.1, "lent database \(lent.1), expected \(expected.1)")
        try expect(lent.2 == expected.2, "lent dialect \(lent.2), expected \(expected.2)")

        let returned = try await driver.withReadConnection { _ in "returned" }
        try expect(returned == "returned", "the read scope returned \(returned)")
    }

    func writeScopeWritesOutsideATransaction() async throws {
        let fixture = fixture
        try await driver.withWriteConnection { connection in
            try fixture.insertMarker(on: &connection)
        }
        try await expectMarkerCount(1, "after one write-scope insert")
    }

    func transactionCommitsWhenTheOperationReturns() async throws {
        let fixture = fixture
        var expected = 0
        for kind in fixture.supportedTransactionKinds {
            let returned = try await driver.withTransaction(kind) { connection in
                try fixture.insertMarker(on: &connection)
                return kind.rawValue
            }
            expected += 1
            try expect(returned == kind.rawValue, "a \(kind) transaction returned \(returned)")
            try await expectMarkerCount(expected, "after a committed \(kind) transaction")
        }
    }

    func transactionRollsBackWhenTheOperationThrows() async throws {
        let fixture = fixture
        for kind in fixture.supportedTransactionKinds {
            let sentinel = ContractSentinel(tag: "rollback-\(kind)")
            do {
                try await driver.withTransaction(kind) { connection in
                    try fixture.insertMarker(on: &connection)
                    throw sentinel
                }
                throw violation("a \(kind) transaction whose operation threw returned normally")
            }
            catch let error as ContractSentinel {
                try expect(error == sentinel, "a \(kind) transaction rethrew \(error)")
            }
            catch let error as DriverContractViolation {
                throw error
            }
            catch {
                throw violation("a \(kind) transaction threw \(error) instead of the operation's error")
            }
            try await expectMarkerCount(0, "after a rolled-back \(kind) transaction")
        }
    }

    func validatedTransactionPreservesTheOperationError() async throws {
        for kind in fixture.supportedTransactionKinds {
            let sentinel = ContractSentinel(tag: "validated-\(kind)")
            do {
                _ = try await driver.withValidatedTransaction(kind) { _ -> Int in
                    throw sentinel
                }
                throw violation("a validated \(kind) transaction whose operation threw returned normally")
            }
            catch let error as ContractSentinel {
                try expect(error == sentinel, "a validated \(kind) transaction rethrew \(error)")
            }
            catch let error as DriverContractViolation {
                throw error
            }
            catch {
                throw violation(
                    "a validated \(kind) transaction threw \(error) instead of the operation's error"
                )
            }
        }
    }

    func unsupportedTransactionKindIsRejectedBeforeTheOperationRuns() async throws {
        let kind = XLTransactionKind(rawValue: "swiftql-contract-suite-unsupported")
        let expected = XLDatabaseContractError.unsupportedTransactionKind(
            driver: driver.driverIdentifier,
            kind: kind
        )
        let probe = OperationProbe(0)

        do {
            try await driver.withTransaction(kind) { _ in probe.record() }
            throw violation("an unsupported transaction kind was accepted")
        }
        catch let error as XLDatabaseContractError {
            try expect(error == expected, "an unsupported kind threw \(error)")
        }
        catch let error as DriverContractViolation {
            throw error
        }
        catch {
            throw violation("an unsupported kind threw \(error), not a contract error")
        }

        do {
            try await driver.withValidatedTransaction(kind) { _ in probe.record() }
            throw violation("a validated transaction accepted an unsupported kind")
        }
        catch let error as XLDatabaseContractError {
            try expect(error == expected, "a validated transaction threw \(error)")
        }
        catch let error as DriverContractViolation {
            throw error
        }
        catch {
            throw violation("a validated transaction threw \(error) for an unsupported kind")
        }

        try expect(probe.runCount == 0, "the operation ran \(probe.runCount) time(s)")
    }

    func cancelledTaskIsNotLentAConnection() async throws {
        let driver = driver
        let probe = OperationProbe(0)
        let scopes: [(String, @Sendable () async throws -> Void)] = [
            ("read", { try await driver.withReadConnection { _ in probe.record() } }),
            ("write", { try await driver.withWriteConnection { _ in probe.record() } }),
            ("transaction", { try await driver.withTransaction { _ in probe.record() } }),
            (
                "validated transaction",
                { try await driver.withValidatedTransaction { _ in probe.record() } }
            ),
        ]
        for (name, scope) in scopes {
            let task = Task {
                // Wait for the cancellation below, so the scope is entered by
                // a task that is already cancelled.
                while !Task.isCancelled {
                    await Task.yield()
                }
                try await scope()
            }
            task.cancel()
            switch await task.result {
            case .success:
                throw violation("the \(name) scope ran for a cancelled task")
            case .failure(let error):
                try expect(
                    error is CancellationError,
                    "the \(name) scope threw \(error) for a cancelled task"
                )
            }
        }
        try expect(probe.runCount == 0, "an operation ran \(probe.runCount) time(s)")
    }

    func sharedDriverServesConcurrentTasks() async throws {
        let driver = driver
        let fixture = fixture
        let writers = 8
        let readers = 8
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<writers {
                group.addTask {
                    try await driver.withTransaction { connection in
                        try fixture.insertMarker(on: &connection)
                    }
                }
            }
            for _ in 0..<readers {
                group.addTask {
                    let count = try await driver.withReadConnection { connection in
                        try fixture.markerCount(on: &connection)
                    }
                    guard (0...writers).contains(count) else {
                        throw violation("a concurrent read counted \(count) markers")
                    }
                }
            }
            try await group.waitForAll()
        }
        try await expectMarkerCount(writers, "after \(writers) concurrent transactions")
    }

    private func expectMarkerCount(_ expected: Int, _ context: String) async throws {
        let fixture = fixture
        let count = try await driver.withReadConnection { connection in
            try fixture.markerCount(on: &connection)
        }
        try expect(count == expected, "counted \(count) markers \(context), expected \(expected)")
    }

    private func expect(_ condition: Bool, _ detail: @autoclosure () -> String) throws {
        if !condition {
            throw violation(detail())
        }
    }

    private func violation(_ detail: String) -> DriverContractViolation {
        DriverContractViolation(clause: clause, detail: detail)
    }
}
