//
//  SQLStatementLifecycle.swift
//  SwiftQLCore
//
//  The statement lifecycle a connection's statement cache needs (issue #677):
//  finalize on every connection, and, for a connection that caches
//  statements, reset, warm-up, schema invalidation, and cache statistics.
//
//  A statement goes through these calls, all on one connection access:
//
//      prepare → bind… → run → finalize
//
//  A caller that runs a cached statement more than once resets it between
//  runs:
//
//      prepare → bind… → run → (reset → bind… → run)… → finalize
//
//  Warm-up is the same lifecycle without the binds and runs:
//
//      prepare → finalize
//

import Foundation


extension XLDatabaseDriverConnection {

    /// Does nothing: the connection releases a statement when its last
    /// reference goes.
    public mutating func finalizePhysical(_ statement: PhysicalStatement) {}
}


/// A connection that keeps prepared statements in a cache that SwiftQL can
/// observe, warm, and invalidate (issue #677).
///
/// A connection does not have to cache statements. One that does conforms to
/// this refinement, so that the core can count what its cache does, prepare a
/// set of statements before they are needed, and discard statements a schema
/// change has made stale. A connection that does not cache does not conform,
/// rather than reporting an empty cache.
///
/// The cache follows the statement lifecycle every connection has:
///
/// - ``XLDatabaseDriverConnection/preparePhysical(_:)`` lends a cached
///   statement for the SQL when one is free, and counts a hit. Otherwise it
///   prepares a new statement, caches it, and counts a miss. It never lends
///   a statement that is still in use, that is, prepared and not yet
///   finalized. A request nested inside a row callback can prepare the same
///   SQL while the outer request's statement is stepping, and gets a
///   separate statement.
/// - ``XLDatabaseDriverConnection/finalizePhysical(_:)`` returns the
///   statement to the cache, reset and with no values bound, unless the
///   cache was invalidated while the statement was in use or the statement
///   cannot be reset, in which case it is discarded. A caching connection
///   must implement it: the default of `XLDatabaseDriverConnection` does
///   nothing, so a statement would never come back to the cache.
///
/// A cached statement belongs to the physical connection that prepared it.
/// It is never lent to another connection, and it never leaves the
/// connection access it is lent to.
///
/// A cached statement must not run against a schema other than the one it
/// was prepared for. The connection invalidates its cache when a statement it
/// runs changes the schema. A schema change it cannot see, such as one made
/// through another connection, is reported to it through
/// ``invalidatePreparedStatements()``.
public protocol XLStatementCachingDriverConnection: XLDatabaseDriverConnection {

    /// Returns a statement that has run to its prepared state, so that it
    /// can be bound and run again on this connection.
    ///
    /// A caller that runs one statement more than once calls this between
    /// the runs, then binds every parameter again. The returned statement has
    /// no open cursor and no bound values, and it stays in use until it is
    /// finalized. SwiftQL's requests prepare a statement for each run, so
    /// they finalize it rather than reset it.
    ///
    /// - Throws: The error the database reports for the reset. The statement
    ///   must then not run again; finalize it, and the cache discards it.
    mutating func resetPhysical(_ statement: PhysicalStatement) throws -> PhysicalStatement

    /// What this connection's statement cache has done since the physical
    /// connection opened.
    var statementCacheStatistics: XLStatementCacheStatistics { get }

    /// Discards every cached statement, so that the next preparation of each
    /// SQL text prepares it again against the current schema.
    ///
    /// This reaches only this connection's cache. A driver with several
    /// connections reports a schema change to each of them.
    ///
    /// A statement in use keeps running, and is discarded rather than
    /// cached again when it is finalized. Each statement discarded counts in
    /// ``XLStatementCacheStatistics/invalidations``.
    ///
    /// - Throws: An error releasing a statement, such as a network failure
    ///   closing a server-side one. The connection must still never lend a
    ///   statement it cached before this call, whether or not it throws.
    mutating func invalidatePreparedStatements() throws

    /// Prepares every statement in `manifest` without running it, so that
    /// the first run of each on this connection is a cache hit, unless the
    /// cache evicts it first.
    ///
    /// The default implementation prepares each statement with
    /// ``XLDatabaseDriverConnection/prepare(_:)``, as a request does, and
    /// finalizes it.
    /// A connection that can prepare a manifest more cheaply, such as in
    /// bulk, implements this, and must leave the same statements cached.
    mutating func warmUp<Manifest: Sequence>(
        _ manifest: Manifest
    ) throws where Manifest.Element == XLLogicalPreparedStatement
}


extension XLStatementCachingDriverConnection {

    /// Prepares every statement in `manifest` without running it, so that
    /// the first run of each on this connection is a cache hit (issue #677).
    ///
    /// A cache smaller than the manifest, or later work on the connection,
    /// can evict a warmed statement before it runs, and its first run is
    /// then a miss.
    ///
    /// Each statement is prepared as a request prepares it, with
    /// ``XLDatabaseDriverConnection/prepare(_:)``: it is checked against the
    /// connection's database and dialect, and the functions it calls are
    /// installed. It is then finalized without being bound or run, which
    /// leaves it in the cache.
    /// Nothing executes, so a statement that writes changes nothing.
    ///
    /// Warm-up fills only this connection's cache. Warming every connection
    /// of a pool, including ones it opens later, is the driver's to arrange,
    /// for example when it opens each connection.
    ///
    /// - Parameter manifest: The statements to prepare, such as the declared
    ///   queries an application runs. A statement already cached and free
    ///   counts as a hit and stays cached. One in use, such as when warm-up
    ///   runs inside a row callback for the same SQL, counts as a miss, as
    ///   any preparation of it would.
    /// - Throws: The error of the first statement that fails to prepare.
    ///   The statements before it stay cached, and the ones after it are not
    ///   prepared.
    public mutating func warmUp<Manifest: Sequence>(
        _ manifest: Manifest
    ) throws where Manifest.Element == XLLogicalPreparedStatement {
        for statement in manifest {
            let physicalStatement = try prepare(statement)
            finalizePhysical(physicalStatement)
        }
    }
}


/// What a connection's statement cache has done since the physical
/// connection opened (issue #677).
///
/// The counters, every member but ``cachedStatementCount``, only grow.
/// Subtract two readings of a counter to measure a span of work.
/// ``cachedStatementCount`` is how many statements the cache holds when it is
/// read.
public struct XLStatementCacheStatistics: Hashable, Sendable {

    /// Preparations the cache served with a statement it already held.
    public var hits: Int

    /// Preparations that prepared a new statement, including those a
    /// warm-up made.
    public var misses: Int

    /// Statements the cache discarded to stay within its capacity.
    public var evictions: Int

    /// Statements the cache discarded because the schema changed, whether
    /// the connection saw the change or was told of it through
    /// ``XLStatementCachingDriverConnection/invalidatePreparedStatements()``.
    public var invalidations: Int

    /// The statements the cache holds now, in use or free.
    public var cachedStatementCount: Int

    public init(
        hits: Int = 0,
        misses: Int = 0,
        evictions: Int = 0,
        invalidations: Int = 0,
        cachedStatementCount: Int = 0
    ) {
        self.hits = hits
        self.misses = misses
        self.evictions = evictions
        self.invalidations = invalidations
        self.cachedStatementCount = cachedStatementCount
    }
}
