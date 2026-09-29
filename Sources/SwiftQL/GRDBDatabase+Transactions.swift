//
//  GRDBDatabase+Transactions.swift
//  SwiftQL
//
//  Running work against one pinned connection inside a transaction.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


/// `@unchecked Sendable` because sharing one value across threads and connections is this type's
/// whole purpose: `databasePool` hands any given call to whichever of several pooled physical
/// connections is idle, so every stored property is designed to be read concurrently from
/// multiple threads. The strict-concurrency checker cannot see that GRDB's own pool
/// synchronization already makes this safe.
extension GRDBDatabase: @unchecked Sendable {}


extension GRDBDatabase: XLTransactionScopeReporting {

    /// `true` for the pinned scope `withTransaction(_:)` hands its body, and
    /// still `true` after that body returns (issue #662). A generated
    /// `@SQLQueries` executor called on a scope runs on it rather than opening
    /// a nested transaction; an ended scope then throws `.scopeEscaped`.
    var isTransactionScope: Bool {
        driver.isPinned
    }
}


extension GRDBDatabase: XLTransactionalDatabase {

    /// Runs `body` against one pinned `DatabasePool` connection inside one
    /// real GRDB transaction (issue #284): the driver's
    /// `runTransaction(on:kind:_:)` opens the transaction on the pool's
    /// writer, hands `body` a `GRDBDatabase` pinned to that connection,
    /// commits when `body` returns normally, and rolls back — preserving the
    /// original error — when `body` throws. See ``XLTransactionalDatabase``
    /// for the full ordering, atomicity, and lifetime contract.
    ///
    /// Rejects two cases before any transaction work happens:
    /// - calling `withTransaction(_:)` again from inside an already-active
    ///   body on this database throws
    ///   ``XLTransactionScopeError/nestedTransactionUnsupported`` without
    ///   touching the pool;
    /// - a task that is already cancelled when this is called throws
    ///   `CancellationError` before opening the transaction. The body itself
    ///   runs synchronously to completion once started, so there is no later
    ///   cooperative cancellation point.
    @discardableResult
    public func withTransaction<Result>(
        _ body: (GRDBDatabase) throws -> Result
    ) throws -> Result {
        // Rejects reentry on the pinned scope itself (fast, value-level,
        // thread-independent) and reentry through the original, unpinned
        // database captured from inside an active body (see
        // `GRDBTransactionScopeTracker`). Both checks run before touching
        // the pool, because GRDB's own reentrant-write guard is
        // an uncatchable `fatalError`.
        guard !driver.isPinned else {
            throw XLTransactionScopeError.nestedTransactionUnsupported
        }
        try driver.preconditionNotRootReentrant(.write)
        if Task.isCancelled {
            throw CancellationError()
        }
        // The hold is taken inside the pool's write closure, not around it:
        // GRDB may run that closure on its own writer thread, and a hold is
        // kept per thread. A reentrant call from inside `body` runs in this
        // same synchronous extent, so it is what
        // `preconditionNotRootReentrant(_:)` observes. Once the transaction
        // has committed, only root writes stay rejected, so a GRDB
        // `databaseDidCommit` observer can read.
        return try databasePool.writeWithoutTransaction { database in
            try driver.runTransaction(on: database) {
                let box = GRDBPinnedConnectionBox(database)
                defer { box.invalidate() }
                let scope = GRDBDatabase(
                    pinnedDriver: driver.pinned(to: box),
                    pinnedFrom: self
                )
                return try body(scope)
            }
        }
    }
}
