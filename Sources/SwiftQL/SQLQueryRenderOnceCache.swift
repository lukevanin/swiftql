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
/// Today there is a single dialect; keying on the dialect identifier rather than
/// assuming one means a second dialect renders into its own entry rather than
/// colliding with the first.
///
public struct XLPreparedQueryCacheKey: Hashable, Sendable {

    /// Identifies the database the cached request is bound to (per-instance in
    /// the GRDB adapter — a fresh identifier per driver init).
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
/// Retention trade-off: for the GRDB adapter, a cached `XLRequest` retains its
/// `GRDBInvocationExecutor` → `GRDBDatabaseDriver` → `DatabasePool` chain. Since
/// the macro emits one cache as a `static` peer per declaration, invoking a
/// declared query keeps that database pool alive for the process lifetime, even
/// if every other reference to the owning database is released. This mirrors an
/// accepted trade-off from the milestone #28 spike (long-lived databases pay
/// nothing extra; a short-lived database that only ever calls declared queries
/// once is retained longer than it otherwise would be). A per-instance store or
/// an eviction/weak-referencing scheme is future work if that trade-off proves
/// wrong for a real workload; there is no correctness issue today.
///
public final class XLRenderOnceCache<Row>: @unchecked Sendable {

    private let lock = NSLock()

    private var requests: [XLPreparedQueryCacheKey: any XLRequest<Row>] = [:]

    public init() {}

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
        lock.lock()
        defer { lock.unlock() }
        if let existing = requests[key] {
            return existing
        }
        let request = database.makeRequest(with: build())
        requests[key] = request
        return request
    }
}
