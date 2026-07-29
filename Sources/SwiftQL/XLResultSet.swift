//
//  XLResultSet.swift
//

import Foundation


/// Failures produced by ``XLResultSet`` iteration itself, distinct from the
/// original SQLite or decode error that ended a result set's iteration.
public enum XLResultSetError: Error, Equatable, Sendable, LocalizedError {

    /// This result set can no longer step or decode a row.
    ///
    /// A fresh call to `next()` after the query legitimately runs out of
    /// matching rows is **not** this error -- that keeps returning `nil`
    /// forever, exactly like any other exhausted iteration. This error only
    /// fires once the result set can no longer safely touch its underlying
    /// cursor or connection at all: after an explicit ``XLResultSet/close()``,
    /// after a prior SQLite step or row-decode error already terminated
    /// iteration, or after the ``XLRequest/withResultSet(_:)`` /
    /// ``XLRequest/withResultSet(bindings:_:)`` scope that owned this result
    /// set has already returned.
    case closed

    public var errorDescription: String? {
        switch self {
        case .closed:
            return "This XLResultSet is closed. It was either closed explicitly, terminated by an earlier SQLite or decode error, or its withResultSet(_:) scope has already returned; request a fresh result set instead of retaining this one."
        }
    }
}


///
/// A single-pass, connection-scoped, lazily-decoded query result.
///
/// `next()` performs at most one additional SQLite step and typed decode per
/// call. No row is fetched or decoded before the first call to `next()`, and
/// stopping early -- an early `return`, `break`, or thrown error from the
/// ``XLRequest/withResultSet(_:)`` callback -- means every later row is never
/// stepped or decoded. There is no read-ahead and no buffering: the cost of
/// producing rows scales with rows actually requested, not with the query's
/// total cardinality.
///
/// ### Reference semantics, not a collection
///
/// `XLResultSet` is deliberately a `final class`, not a `struct`, and it does
/// not conform to `Sequence`, `IteratorProtocol`, or `Collection`. Those
/// abstractions promise replayable, copyable value semantics that a live
/// SQLite cursor cannot honor -- copying a value that wraps a one-shot cursor
/// would either alias the same cursor from two places or silently require
/// buffering rows to fake independent iteration. `next() throws -> Row?` is
/// deliberately the entire surface instead, so every step can throw the
/// original SQLite or decode error directly, rather than a
/// `Sequence`/`IteratorProtocol` conformance swallowing it (`Sequence`'s
/// `next()` cannot throw).
///
/// `XLResultSet` is intentionally **not** `Sendable`. It wraps a cursor bound
/// to one specific database connection or snapshot; never capture it across
/// threads, tasks, actors, or database queues, and never use it outside the
/// callback that received it.
///
/// ### Scope lifetime and connection occupancy
///
/// An `XLResultSet` is valid only for the dynamic extent of the
/// ``XLRequest/withResultSet(_:)`` (or ``XLRequest/withResultSet(bindings:_:)``)
/// callback that receives it. That callback owns the underlying database read
/// access -- a pooled connection, or the pinned connection of an enclosing
/// transaction -- for its *entire* duration, not just while a `next()` call is
/// in flight. Avoid slow, unrelated work between `next()` calls, since it
/// keeps that connection or snapshot occupied the whole time. The owning
/// scope closes the result set with `defer` before returning or throwing, so
/// this happens whether the callback returns normally, returns early, or
/// throws.
///
/// A reference retained past that callback's return no longer has a live
/// cursor to step: every later `next()` throws ``XLResultSetError/closed``
/// instead of touching a cursor or connection that may already have been
/// released back to the pool or reused for unrelated work.
///
/// ### Partial progress and early termination
///
/// Rows already returned by earlier, successful `next()` calls remain valid,
/// independent decoded values even if a later row fails to step or decode --
/// unlike `fetchAll()`, which is atomic and returns either a complete array
/// or no array at all. Once `next()` throws -- a genuine SQLite step failure
/// or a row-decode failure -- the result set becomes terminal: it does not
/// retry, does not skip the failing row, and every subsequent call throws
/// ``XLResultSetError/closed`` rather than re-throwing the original error or
/// attempting to step further. That original SQLite or decode error is only
/// ever delivered once, from the `next()` call that produced it.
///
/// Natural exhaustion is different from all of the above: once the query
/// legitimately runs out of matching rows, `next()` keeps returning `nil`
/// rather than throwing, so callers may safely call `next()` again after
/// exhaustion without special-casing "the last call."
///
/// ### When to use `fetchAll()` instead
///
/// Reach for `fetchAll()` when the caller wants a complete, retained,
/// randomly-indexable `[Row]` -- to sort, count, `map`, `filter`, encode, or
/// hand to code that expects an ordinary Swift collection -- and the full
/// result comfortably fits in memory. `fetchAll()` also gives atomic,
/// all-or-nothing failure semantics: if any row fails, the caller gets either
/// the complete array or the error, never a partially populated one.
///
/// Reach for `withResultSet(_:)` and `next()` when the result may be large,
/// when the caller may stop before consuming every row, or when the cost of
/// decoding rows nobody ends up using should scale with rows actually
/// requested rather than total query cardinality.
///
/// ### Why synchronous, scoped iteration is the v1.5 baseline
///
/// This API is deliberately synchronous and scoped to one callback rather
/// than an `async`/`await` row sequence. Swift 5.9's ownership and
/// actor-isolation model has no way to let a live SQLite cursor -- tied to
/// one specific pooled connection, or to one pinned transaction connection --
/// safely survive an arbitrary `await` suspension point between rows, short
/// of either unsafely widening its lifetime past the access that owns it, or
/// silently reintroducing the buffering this API exists to avoid. A
/// synchronous callback keeps the cursor's lifetime exactly as long as the
/// database access that owns it, which the compiler can check; an
/// `async` row sequence's lifetime is not something Swift 5.9 can check the
/// same way.
///
/// Demand-driven async row iteration is real, separate follow-up work,
/// planned for once the package's minimum Swift version and concurrency
/// story can support it safely. It is also unrelated to issue #308's
/// `AsyncThrowingStream` of complete, eagerly-decoded live-query snapshots --
/// that stream re-emits a fresh `fetchAll()`-equivalent array every time the
/// observed database region changes; it does not stream the individual rows
/// of one execution incrementally the way `XLResultSet` does.
///
public final class XLResultSet<Row> {

    /// One remaining row step, or `nil` once this result set can no longer
    /// step or decode a row (explicitly closed, terminated by a SQLite step
    /// or decode error, or invalidated because its owning scope returned).
    ///
    /// Distinct from ``isExhausted``: exhaustion is a stable, non-throwing
    /// terminal state reached by the underlying cursor legitimately running
    /// out of rows, not by an error or an explicit close.
    private var stepper: (() throws -> Row?)?

    /// `true` once the underlying cursor has legitimately run out of rows.
    /// `next()` keeps returning `nil` in this state instead of throwing,
    /// distinguishing "no more rows" from "closed."
    private var isExhausted = false

    /// Creates a result set backed by one row-stepping closure.
    ///
    /// - Parameter stepper: Performs at most one SQLite step and typed
    ///   decode per call, returning `nil` once the underlying cursor is
    ///   exhausted. Must only be invoked from inside the database access
    ///   that owns whatever cursor it closes over, and must stop being
    ///   invoked no later than when that access returns.
    init(stepper: @escaping () throws -> Row?) {
        self.stepper = stepper
    }

    ///
    /// Fetches and decodes the next row, performing at most one additional
    /// SQLite step and typed decode.
    ///
    /// Returns `nil` once the query is exhausted; further calls after
    /// exhaustion keep returning `nil`. Throws the original SQLite or decode
    /// error the instant either fails, and the result set becomes terminal:
    /// every later call throws ``XLResultSetError/closed`` instead of
    /// retrying, skipping the failing row, or re-throwing the original error
    /// again. Throws ``XLResultSetError/closed`` immediately if this result
    /// set was already closed, already terminated by an earlier error, or
    /// retained past its owning `withResultSet` scope.
    ///
    /// - Throws: The original query-execution or row-decoding error, or
    ///   ``XLResultSetError/closed``.
    ///
    public func next() throws -> Row? {
        if isExhausted {
            return nil
        }
        guard let stepper else {
            throw XLResultSetError.closed
        }
        do {
            guard let row = try stepper() else {
                isExhausted = true
                self.stepper = nil
                return nil
            }
            return row
        }
        catch {
            self.stepper = nil
            throw error
        }
    }

    ///
    /// Closes this result set, releasing its row-stepping closure (and
    /// anything it captures, such as a GRDB cursor) immediately instead of
    /// waiting for the owning scope to return.
    ///
    /// Idempotent: closing an already-closed or already-terminated result
    /// set has no additional effect. After `close()`, every `next()` throws
    /// ``XLResultSetError/closed`` -- including when the result set was
    /// already exhausted, since an explicit close is a stronger, deliberate
    /// signal that this reference is done, not just that its query ran out
    /// of rows.
    ///
    public func close() {
        isExhausted = false
        stepper = nil
    }
}
