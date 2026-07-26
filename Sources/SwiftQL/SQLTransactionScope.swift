//
//  SQLTransactionScope.swift
//  SwiftQL
//
//  Typed multi-statement transaction scopes (issue #284): a database that
//  lends one pinned connection to an ordered sequence of typed
//  `XLRequest`/`XLWriteRequest` invocations, committing only after the whole
//  body succeeds and rolling back every write on any failure. Built on the
//  `XLDatabase` contract that issues #18/#26 already generate `Context`
//  executors against, so a `@SQLQueries` declaration composes with
//  `withTransaction(_:)` without a second query or binding runtime.
//

import Foundation


///
/// A database capable of running an ordered sequence of typed requests as one
/// atomic transaction on a single pinned connection.
///
/// `withTransaction(_:)` is the typed, adapter-neutral multi-statement
/// executor required by issue #284. It differs from calling
/// `XLDatabaseDriver.withTransaction` directly in three ways:
///
/// - the body receives another value of `Self` — an ordinary `XLDatabase` —
///   instead of a driver connection, so it composes with `makeRequest(with:)`,
///   `execute()`, `fetchAll()`, and every other typed v1 request API, and
///   with a `@SQLQueries`-generated `Context`;
/// - no adapter connection, statement handle, or pool type is ever exposed;
/// - the scope is invalidated the instant `body` returns, so a request or
///   scope value that escapes the closure fails predictably instead of
///   touching a connection that may already be reused for other work.
///
/// ## Ordering, atomicity, and results
///
/// Every request `body` executes runs, in source order, against the same
/// physical connection `withTransaction(_:)` pinned for this call. Because
/// Swift closures execute their statements in program order, an ordinary
/// local variable is enough to carry one operation's typed result to a later
/// one, or out to the transaction's own return value — no extra plumbing is
/// required.
///
/// The whole body is one commit unit: `withTransaction(_:)` commits only
/// after `body` returns normally, and rolls back every write `body` performed
/// — preparation, binding, execution, decoding, and user-thrown failures
/// alike — before rethrowing the original, unmodified error.
///
/// ## Unsupported: nesting, savepoints, and mid-flight cancellation
///
/// Calling `withTransaction(_:)` again from inside an active body throws
/// ``XLTransactionScopeError/nestedTransactionUnsupported`` before any nested
/// work runs — the v1 driver has no savepoint hook, so a nested call cannot
/// prove correct partial-rollback semantics, and re-entering the root
/// connection pool from inside an open transaction can deadlock or hand two
/// operations different connections. Cancellation is checked only once, at
/// the very start of `withTransaction(_:)`, because the body itself runs
/// synchronously to completion and has no cooperative cancellation point
/// while committed or rolled-back writes are underway.
///
/// See <doc:GettingStarted> for the isolation and lifetime rules, and for
/// concrete examples of the durable-state guarantees this API makes.
///
public protocol XLTransactionalDatabase: XLDatabase {

    ///
    /// Runs `body` against one pinned connection inside one real database
    /// transaction and returns its result.
    ///
    /// - Parameter body: Receives a database-shaped scope pinned to this
    ///   transaction's connection. Use it exactly like the enclosing
    ///   database — `makeRequest(with:)`, the v1 fetch/execute methods, and
    ///   any `@SQLQueries`-generated `Context` all work unchanged.
    /// - Returns: `body`'s result, after the transaction has committed.
    /// - Throws: The original error `body` threw (preparation, binding,
    ///   execution, decoding, or user-thrown) after rolling back every write
    ///   it performed; ``XLTransactionScopeError/nestedTransactionUnsupported``
    ///   if called again from inside an active `body`, before touching the
    ///   connection pool; or `CancellationError` if the calling task was
    ///   already cancelled before the transaction began.
    ///
    func withTransaction<Result>(
        _ body: (Self) throws -> Result
    ) throws -> Result
}


///
/// Failures at the transaction-scope boundary itself, distinct from errors a
/// scoped operation's preparation, binding, execution, or decoding raises.
///
public enum XLTransactionScopeError: Error, Equatable, Sendable, LocalizedError {

    ///
    /// A request, write request, or scope value created inside a
    /// ``XLTransactionalDatabase/withTransaction(_:)`` body was used after
    /// that body returned. The body's connection is no longer pinned by the
    /// time this is thrown — the transaction already committed or rolled
    /// back — so continuing would silently operate on a connection reused
    /// for unrelated work instead of the one the caller believed it still
    /// held.
    ///
    case scopeEscaped

    ///
    /// Either `withTransaction(_:)` was called again from inside an
    /// already-active transaction body, or the original (root, unpinned)
    /// database was used from inside an active body instead of the pinned
    /// scope value it was given -- both re-enter the same connection pool
    /// while a transaction is open. The v1 driver has no savepoint hook, so
    /// a nested call cannot commit or roll back only its own writes; pool
    /// re-entry can also deadlock or hand two operations different
    /// connections. Rejected before any nested work runs, so no partial
    /// state exists to roll back.
    ///
    case nestedTransactionUnsupported

    ///
    /// A request's live-query `publish()`/`publishOne()` was called on a
    /// transaction-scoped database. Live observation tracks a connection
    /// pool across commits over time; a transaction-scoped connection is
    /// invalidated the instant the body returns, so there is no stable pool
    /// to observe.
    ///
    case liveQueriesUnsupportedInTransaction

    public var errorDescription: String? {
        switch self {
        case .scopeEscaped:
            return "A transaction-scoped database, request, or write request was used after its 'withTransaction(_:)' body returned. Transaction-scoped values must not escape the closure."
        case .nestedTransactionUnsupported:
            return "'withTransaction(_:)' was called again from inside an active transaction body, or the original (root) database was used instead of the pinned scope value the body was given -- both re-enter the connection pool while a transaction is open. Nested transactions and savepoints are not supported; perform every operation in one body using the scope value it receives instead."
        case .liveQueriesUnsupportedInTransaction:
            return "Live-query 'publish()'/'publishOne()' is not supported inside a 'withTransaction(_:)' body. Fetch with 'fetchAll()'/'fetchOne()' instead, or observe outside the transaction."
        }
    }
}
