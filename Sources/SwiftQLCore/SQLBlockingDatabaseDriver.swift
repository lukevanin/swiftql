//
//  SQLBlockingDatabaseDriver.swift
//  SwiftQLCore
//
//  The synchronous scopes a driver offers for SwiftQL's synchronous request
//  members (issue #682).
//


/// A driver that can also lend a connection to the calling thread, for
/// SwiftQL's synchronous request members, such as `fetchAll()` and
/// `execute()` (issue #682).
///
/// ``XLDatabaseDriver``'s scopes are asynchronous, and SwiftQL never blocks a
/// thread waiting on them (`Research/AsyncDriverContractFeasibility.md`). A
/// synchronous request needs a driver that can wait for a connection itself,
/// so each scope here blocks the calling thread until a connection is
/// available, then runs `operation` on it and returns its result. The
/// connection primitives are the same ones the asynchronous scopes lend.
///
/// The rules for each scope follow its asynchronous counterpart:
///
/// - ``withBlockingReadConnection(_:)`` lends a connection that reads a
///   consistent snapshot.
/// - ``withBlockingWriteConnection(_:)`` lends the connection that writes,
///   outside a transaction.
/// - ``withBlockingTransaction(_:)`` runs `operation` in one transaction of
///   the driver's ``XLDatabaseDriver/defaultTransactionKind`` on the
///   connection that writes. The transaction commits when `operation`
///   returns, and rolls back when it throws, and the error it threw is
///   rethrown unchanged.
///
/// `operation` is not `@Sendable`, because a blocking scope runs it while the
/// calling thread waits, so it may capture the caller's non-`Sendable` state.
/// A driver that runs it on another thread must not let it run concurrently
/// with the caller.
public protocol XLBlockingDatabaseDriver: XLDatabaseDriver {

    /// Runs `operation` on a connection that reads a consistent snapshot,
    /// blocking the calling thread until it returns.
    func withBlockingReadConnection<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result

    /// Runs `operation` on the connection that writes, outside a transaction,
    /// blocking the calling thread until it returns.
    func withBlockingWriteConnection<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result

    /// Runs `operation` inside one transaction of the driver's
    /// ``XLDatabaseDriver/defaultTransactionKind``, on the connection that
    /// writes, blocking the calling thread until it commits or rolls back.
    func withBlockingTransaction<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result
}
