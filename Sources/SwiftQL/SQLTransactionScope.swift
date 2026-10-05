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
/// ## One thread
///
/// Use the scope only on the thread that runs `body`. The scope's connection
/// is lent to that thread until `body` returns. A conforming database should
/// refuse a statement run through the scope, or through a request made from
/// it, on any other thread with ``XLTransactionScopeError/scopeEscaped``
/// rather than share the connection, as ``GRDBDatabase`` does.
/// <doc:AdvancedUsage> gives the full rule for `GRDBDatabase`, including what
/// the compiler does not yet catch.
///
/// See <doc:AdvancedUsage> for the isolation and lifetime rules, and for
/// concrete examples of the durable-state guarantees this API makes.
/// <doc:GettingStarted> introduces the everyday spelling.
///
public protocol XLTransactionalDatabase: XLDatabase {

    ///
    /// Runs `body` against one pinned connection inside one real database
    /// transaction and returns its result.
    ///
    /// - Parameter body: Receives a database-shaped scope pinned to this
    ///   transaction's connection. Use it exactly like the enclosing
    ///   database — `makeRequest(with:)`, the v1 fetch/execute methods, and
    ///   any `@SQLQueries`-generated `Context` all work unchanged — but only
    ///   on the thread that runs `body`; see ``XLTransactionalDatabase``.
    /// - Returns: `body`'s result, after the transaction has committed.
    /// - Throws: The original error `body` threw (preparation, binding,
    ///   execution, decoding, or user-thrown) after rolling back every write
    ///   it performed; ``XLTransactionScopeError/nestedTransactionUnsupported``
    ///   if called again from inside an active `body`, before touching the
    ///   connection pool; or `CancellationError` if the calling task was
    ///   already cancelled before the transaction began.
    ///
    /// The result is discardable, so a body that only writes, such as one
    /// ending in `execute()`, which reports an `XLExecutionResult`, needs
    /// no `_ =` (issue #679).
    ///
    @discardableResult
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
    /// that body returned, or from a thread other than the one running the
    /// body, such as from a task created in the body. After the body returns,
    /// the connection is no longer pinned — the transaction already committed
    /// or rolled back — so continuing would silently operate on a connection
    /// reused for unrelated work. From another thread, the connection is still
    /// in use by the body on its own thread, and GRDB does not allow it to be
    /// shared.
    ///
    case scopeEscaped

    ///
    /// The original (root, unpinned) database was used from inside a scope
    /// that already holds one of its connections: `withTransaction(_:)` was
    /// called again from inside an active transaction body, the root database
    /// was used from inside a body instead of the pinned scope value it was
    /// given, or a second root read ran inside a result-set body -- each
    /// re-enters the same connection pool from the same flow of control. The v1 driver has no savepoint hook, so
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
            return "A transaction-scoped database, request, or write request was used after its 'withTransaction(_:)' body returned, or from another thread or task. Transaction-scoped values must not escape the closure's synchronous body."
        case .nestedTransactionUnsupported:
            return "The original (root) database was used from inside a scope that already holds one of its connections: 'withTransaction(_:)' was called again inside a transaction body, the root database was used instead of the pinned scope value the body was given, or a second root read ran inside a result-set body. Nested transactions and savepoints are not supported; inside a transaction, use the scope value the body receives, and inside a result set, finish reading before the next root read."
        case .liveQueriesUnsupportedInTransaction:
            return "Live-query 'publish()'/'publishOne()' is not supported inside a 'withTransaction(_:)' body. Fetch with 'fetchAll()'/'fetchOne()' instead, or observe outside the transaction."
        }
    }
}


/// `scopeEscaped` and `nestedTransactionUnsupported` are thrown before a
/// connection is lent, so a validated transaction rethrows them unchanged
/// rather than reporting a transaction failure. The third case,
/// `liveQueriesUnsupportedInTransaction`, is thrown before a live query
/// starts, never by a driver's transaction, so conforming the whole type
/// changes nothing for it.
extension XLTransactionScopeError: XLDriverScopeRefusal {}
