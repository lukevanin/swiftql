//
//  SQLQueryRenderOnceCache.swift
//  SwiftQL
//
//  Render-once caching for `@SQLQuery` / `@SQLQueries` macro-generated
//  executors (issues #18/#26, ported from the milestone #28 spike on
//  `experiment/sqlquery-peer-macro`).
//
//  The generated executor renders its value-free statement to SQL once per
//  declaration and reuses that request on every call, so per-call work is only
//  packet construction plus execution. Because the SQL text is identical across
//  invocations (parameters are placeholders, not inline literals), GRDB's
//  per-connection `cachedStatement(sql:)` reuses the physical prepared
//  statement. This is the runtime seam the macro emits a cache against.
//

import Foundation


///
/// Identity that scopes a render-once cache entry.
///
/// Rendering a statement to SQL depends only on the **dialect**, so the dialect
/// identifier is the render-relevant component. The **database identifier** is
/// included so a cache shared across databases (the macro emits the cache as a
/// per-declaration `static`) never hands one database's request to another:
/// each database renders into its own entry, while repeated calls on the same
/// database reuse one rendered request. In the GRDB adapter the identifier is a
/// fresh value per `GRDBDatabase` (its driver assigns one per init), so the
/// scope is per-instance — two `GRDBDatabase` values wrapping the same
/// `DatabasePool` render independently rather than sharing an entry.
///
/// A transaction scope is not a separate database for this key (issue #642).
/// `GRDBDatabase.preparedQueryCacheKey` returns the key of the database the
/// scope was opened on, so a scope adds no entry, however many transactions
/// call a declared query. See ``XLRenderOnceCache`` for how the shared entry
/// reaches the scope's connection.
///
/// Today there is a single dialect; keying on the dialect identifier rather than
/// assuming one means a second dialect renders into its own entry rather than
/// colliding with the first.
///
public struct XLPreparedQueryCacheKey: Hashable, Sendable {

    /// Identifies the database that owns the entry (per-instance in the GRDB
    /// adapter — a fresh identifier per driver init). A transaction scope uses
    /// the identifier of the database it was opened on.
    public let databaseIdentifier: XLDatabaseIdentifier

    /// Identifies the dialect the SQL was rendered for.
    public let dialectIdentifier: XLDialectIdentifier

    public init(
        databaseIdentifier: XLDatabaseIdentifier,
        dialectIdentifier: XLDialectIdentifier
    ) {
        self.databaseIdentifier = databaseIdentifier
        self.dialectIdentifier = dialectIdentifier
    }
}


///
/// A lazily-populated, thread-safe cache of one rendered request per
/// declaration, scoped by ``XLPreparedQueryCacheKey``.
///
/// The macro emits one instance per query specification as a `static` peer, so
/// the rendered request is shared across every invocation of that declaration.
/// The first call for a given key renders the statement (building the request
/// through the database's existing `makeRequest(with:)` path) while holding the
/// lock, so concurrent first callers render exactly once; later calls read the
/// cached request. The cached request is value-free — parameters are bound per
/// call through an immutable invocation packet — so reusing it across threads is
/// safe.
///
/// One entry also serves every transaction scope opened on a database (issue
/// #642). A request closes over one connection, so an adapter whose requests do
/// that conforms to `XLRenderOnceRequestBinding`. The cache then stores each
/// entry bound to the database itself -- even when a transaction scope renders
/// it first -- and binds the entry to the calling database or scope before it
/// returns it. Binding reuses the rendered SQL and row reader and renders
/// nothing, so a declared query called inside any number of transactions still
/// renders once per database and adds no entry beyond the database's own. A
/// call on the database returns the stored request as is; a call on a scope
/// gets a copy bound to the scope's connection.
///
/// Retention trade-off: for the GRDB adapter, a cached `XLRequest` retains its
/// `GRDBInvocationExecutor` → `GRDBDatabaseDriver` → `DatabasePool` chain. Since
/// the macro emits one cache as a `static` peer per declaration, invoking a
/// declared query keeps that database pool alive for the process lifetime, even
/// if every other reference to the owning database is released. This mirrors an
/// accepted trade-off from the milestone #28 spike (long-lived databases pay
/// nothing extra; a short-lived database that only ever calls declared queries
/// once is retained longer than it otherwise would be). A per-instance store or
/// an eviction/weak-referencing scheme is future work if that trade-off proves
/// wrong for a real workload; there is no correctness issue today. A request
/// first rendered inside a transaction is stored bound to the database's pool
/// driver, not to the scope, so an entry never retains a scope's invalidated
/// connection (issue #642).
///
public final class XLRenderOnceCache<Row: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var requests: [XLPreparedQueryCacheKey: any XLRequest<Row>] = [:]

    public init() {}

    /// How many entries this cache holds. Tests read it to pin that
    /// transaction scopes add no entries; nothing in the library reads it.
    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    /// The stored entry for `key`, before it is bound to any caller. Tests
    /// read it to pin what an entry retains; nothing in the library reads it.
    func cachedEntry(for key: XLPreparedQueryCacheKey) -> (any XLRequest<Row>)? {
        lock.lock()
        defer { lock.unlock() }
        return requests[key]
    }

    ///
    /// Returns the request for `database`, rendering the statement built by
    /// `build` on first use and reusing it afterward.
    ///
    /// - Parameter database: The database the request is prepared against; its
    ///   ``XLDatabase/preparedQueryCacheKey`` scopes the cache entry.
    /// - Parameter build: Builds the value-free statement. Invoked at most once
    ///   per key — never on a cache hit.
    ///
    public func request(
        for database: some XLDatabase,
        statement build: () -> any XLQueryStatement<Row>
    ) -> any XLRequest<Row> {
        guard let key = database.preparedQueryCacheKey else {
            // The adapter opts out of render-once caching, so render per call
            // exactly as the un-cached executor did.
            return database.makeRequest(with: build())
        }
        let request = cachedRequest(for: key, database: database, statement: build)
        // One entry serves a database and every transaction scope opened on it
        // (issue #642), and the stored request is bound to the database, so bind
        // it to the caller -- a scope gets its own connection -- before returning.
        guard let binding = database as? any XLRenderOnceRequestBinding else {
            return request
        }
        return binding.bindRenderOnceRequest(request)
    }

    /// The entry for `key`, rendered under the lock on first use so concurrent
    /// first callers render exactly once.
    private func cachedRequest(
        for key: XLPreparedQueryCacheKey,
        database: some XLDatabase,
        statement build: () -> any XLQueryStatement<Row>
    ) -> any XLRequest<Row> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = requests[key] {
            return existing
        }
        let rendered = database.makeRequest(with: build())
        // Store the entry bound to the database itself, even when a transaction
        // scope renders it first, so the entry never keeps an ended scope's
        // connection and a call on the database never has to rebind it.
        let request = (database as? any XLRenderOnceRequestBinding)?
            .storableRenderOnceRequest(rendered) ?? rendered
        requests[key] = request
        return request
    }
}


///
/// Binds a render-once cache entry to the database that is calling (issue
/// #642).
///
/// Internal. An adapter whose cached requests close over one connection
/// conforms, so a transaction scope can share its database's entry without
/// the entry ever running on the wrong connection. ``XLRenderOnceCache`` calls
/// it on every request it returns; an adapter that does not conform gets the
/// cached request unchanged.
///
protocol XLRenderOnceRequestBinding {

    /// `request`, bound to this database. Must render nothing.
    func bindRenderOnceRequest<Row: Sendable>(_ request: any XLRequest<Row>) -> any XLRequest<Row>

    /// `request` as the cache should store it: bound to the database that owns
    /// the cache key, even when this is a transaction scope that rendered it.
    /// Called once per entry, under the cache's lock. Must render nothing.
    func storableRenderOnceRequest<Row: Sendable>(_ request: any XLRequest<Row>) -> any XLRequest<Row>
}
