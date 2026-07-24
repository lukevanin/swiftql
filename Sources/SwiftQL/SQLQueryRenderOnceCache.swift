//
//  SQLQueryRenderOnceCache.swift
//  SwiftQL
//
//  Spike (#361): render-once caching for `@SQLQuery` macro-generated executors.
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


extension XLDatabase {

    ///
    /// The identity a render-once cache keys on, or `nil` to opt out of caching.
    ///
    /// The default opts out: an adapter that does not render SQL
    /// deterministically per dialect returns `nil`, and the executor renders on
    /// every call exactly as before. Adapters that do render deterministically
    /// (the GRDB adapter) override this to return a stable key.
    ///
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        nil
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
