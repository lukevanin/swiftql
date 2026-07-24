//
//  SQLQueryRenderOnceCacheTests.swift
//  SwiftQL
//
//  Runtime tests for the render-once cache (#361): the generated executor
//  renders its value-free statement to SQL once per declaration and reuses the
//  request across calls, binding parameter values per call through an immutable
//  invocation packet. The rendered SQL is byte-identical across calls (parameters
//  are placeholders, not inline literals), and concurrent first use renders once.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


///
/// Lock-guarded shared state for the concurrent first-use test. The database is
/// not `Sendable`, so it is reached only through this holder, which vouches for
/// its own thread safety.
///
private final class ConcurrentRenderProbe: @unchecked Sendable {

    let cache = XLRenderOnceCache<TestTable>()

    let database: GRDBDatabase

    private let lock = NSLock()
    private var count = 0

    init(database: GRDBDatabase) {
        self.database = database
    }

    func recordBuild() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var buildCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}


final class XLQueryRenderOnceCacheTests: XCTestCase {

    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        )
        (databasePool, database) = Self.makeDatabase()
    }

    override func tearDown() {
        encoder = nil
        databasePool = nil
        database = nil
    }

    private static func makeDatabase() -> (DatabasePool, GRDBDatabase) {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        let pool = try! DatabasePool(path: fileURL.path)
        let database = try! GRDBDatabase(databasePool: pool, formatter: formatter, logger: nil)
        return (pool, database)
    }


    // MARK: - Render-once

    ///
    /// The render-once premise: the value-free statement is rendered exactly
    /// once per declaration and reused, regardless of how many times the query
    /// is invoked. The build closure — which constructs the statement the cache
    /// renders — runs only on the first call. Render count is the allocation
    /// anchor: rendering a statement is a fixed allocation set, so one render for
    /// N calls amortizes that cost to zero per call.
    ///
    func testCacheBuildsStatementExactlyOnceAcrossManyCalls() {
        let cache = XLRenderOnceCache<TestTable>()
        var buildCount = 0
        for _ in 0 ..< 1_000 {
            _ = cache.request(for: database) {
                buildCount += 1
                return database.rowsMatchingIDStatement()
            }
        }
        XCTAssertEqual(
            buildCount,
            1,
            "the render-once cache must render the statement exactly once"
        )
    }

    ///
    /// A cache hit returns the previously rendered request without rebuilding.
    ///
    func testCacheReturnsSameRequestWithoutRebuildingOnHit() {
        let cache = XLRenderOnceCache<TestTable>()
        _ = cache.request(for: database) { database.rowsMatchingIDStatement() }
        _ = cache.request(for: database) {
            XCTFail("a cache hit must not rebuild the statement")
            return database.rowsMatchingIDStatement()
        }
    }


    // MARK: - Concurrent first use (cache race)

    ///
    /// Many threads racing on the first use of one declaration must render
    /// exactly once. The cache renders under its lock, so concurrent first
    /// callers block until the single render completes, then reuse it.
    ///
    func testConcurrentFirstUseBuildsExactlyOnce() {
        // The shared state crosses a `@Sendable` concurrent closure, so it is
        // routed through one lock-guarded holder rather than capturing `self`
        // or the non-Sendable database directly.
        let probe = ConcurrentRenderProbe(database: database)
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            let request = probe.cache.request(for: probe.database) {
                probe.recordBuild()
                return probe.database.rowsMatchingIDStatement()
            }
            // Every racing caller receives a usable request with the layout.
            XCTAssertEqual(request.parameterLayout.slots.map(\.key), [.named("id")])
        }
        XCTAssertEqual(
            probe.buildCount,
            1,
            "concurrent first use must render the statement exactly once"
        )
    }


    // MARK: - Stable placeholder SQL across calls with different values

    ///
    /// One rendered request serves every parameter value: the cached executor
    /// returns the rows for each distinct argument, proving the SQL binds a
    /// placeholder rather than freezing the first call's value as an inline
    /// literal. The rendered SQL is byte-identical and value-free.
    ///
    func testCachedExecutorServesDifferentArgumentsWithStablePlaceholderSQL() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        // Different values through the same rendered request → different rows.
        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "alpha"),
            [TestTable(id: "alpha", value: 1)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 2)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "alpha"),
            [TestTable(id: "alpha", value: 1)]
        )

        // The rendered SQL carries a named placeholder and no inline literal,
        // and is byte-identical across renders — the property the cache reuses.
        let first = encoder.makeSQL(database.rowsMatchingIDStatement())
        let second = encoder.makeSQL(database.rowsMatchingIDStatement())
        XCTAssertEqual(first.sql, second.sql)
        XCTAssertTrue(first.sql.contains(":id"))
        XCTAssertFalse(first.sql.contains("'"))
    }


    // MARK: - Cache keying

    ///
    /// The cache key includes the database identity, so a per-declaration
    /// `static` cache shared across databases never binds one database's request
    /// to another: two distinct `GRDBDatabase` instances render independently,
    /// while the same database reuses its rendered request.
    ///
    func testDistinctDatabasesRenderIndependentlyAndSameDatabaseReuses() {
        let cache = XLRenderOnceCache<TestTable>()
        let (poolA, databaseA) = Self.makeDatabase()
        let (poolB, databaseB) = Self.makeDatabase()
        withExtendedLifetime((poolA, poolB)) {
            var buildCount = 0
            _ = cache.request(for: databaseA) {
                buildCount += 1
                return databaseA.rowsMatchingIDStatement()
            }
            _ = cache.request(for: databaseB) {
                buildCount += 1
                return databaseB.rowsMatchingIDStatement()
            }
            XCTAssertEqual(
                buildCount,
                2,
                "distinct databases must not share one cached request"
            )
            // The first database reuses its entry rather than rendering again.
            _ = cache.request(for: databaseA) {
                buildCount += 1
                return databaseA.rowsMatchingIDStatement()
            }
            XCTAssertEqual(buildCount, 2)
        }
    }

    ///
    /// The keys of the two databases differ in their database identifier and
    /// agree on the dialect identifier — the documented keying decision.
    ///
    func testCacheKeyScopesByDatabaseAndDialect() {
        let (poolA, databaseA) = Self.makeDatabase()
        let (poolB, databaseB) = Self.makeDatabase()
        withExtendedLifetime((poolA, poolB)) {
            guard let keyA = databaseA.preparedQueryCacheKey,
                  let keyB = databaseB.preparedQueryCacheKey else {
                return XCTFail("the GRDB adapter opts into render-once caching")
            }
            XCTAssertNotEqual(keyA, keyB)
            XCTAssertNotEqual(keyA.databaseIdentifier, keyB.databaseIdentifier)
            XCTAssertEqual(keyA.dialectIdentifier, keyB.dialectIdentifier)
        }
    }


    // MARK: - Benchmark (allocation-anchored)

    ///
    /// Micro-benchmark: render-once reuse vs. per-call rebuild. The conclusion
    /// is anchored on the deterministic render count (render-once renders once
    /// for N calls; per-call renders N times) rather than the wall-clock delta,
    /// which is unreliable on a noisy machine. The timing is printed as
    /// corroborating evidence only.
    ///
    func testRenderOnceVsPerCallRebuildBenchmark() {
        // Kept small so the benchmark doesn't add noticeable wall-clock time to
        // the unit-test suite on slower CI runners. The deterministic anchor
        // (render count) is exact at any iteration count; a few thousand calls
        // is already enough for the per-call rebuild cost to dominate visibly
        // in the corroborating timing.
        let iterations = 3_000

        // Deterministic anchor: render-once renders exactly once for N calls.
        let cache = XLRenderOnceCache<TestTable>()
        var renderOnceBuildCount = 0
        let renderOnceStart = DispatchTime.now()
        for _ in 0 ..< iterations {
            _ = cache.request(for: database) {
                renderOnceBuildCount += 1
                return database.rowsMatchingIDStatement()
            }
        }
        let renderOnceElapsed = elapsedSeconds(since: renderOnceStart)

        // Per-call rebuild renders on every call (the pre-cache behavior).
        var perCallBuildCount = 0
        let perCallStart = DispatchTime.now()
        for _ in 0 ..< iterations {
            perCallBuildCount += 1
            _ = database.makeRequest(with: database.rowsMatchingIDStatement())
        }
        let perCallElapsed = elapsedSeconds(since: perCallStart)

        XCTAssertEqual(renderOnceBuildCount, 1)
        XCTAssertEqual(perCallBuildCount, iterations)

        let ratio = perCallElapsed / max(renderOnceElapsed, .leastNonzeroMagnitude)
        print(
            """
            [render-once benchmark] iterations=\(iterations)
              render-once: renders=1        wall=\(String(format: "%.4f", renderOnceElapsed))s
              per-call:    renders=\(iterations)  wall=\(String(format: "%.4f", perCallElapsed))s
              wall-clock speedup (noisy, corroborating only): \(String(format: "%.1f", ratio))x
              allocation anchor: render-once avoids \(iterations - 1) of \(iterations) renders
            """
        )
    }

    private func elapsedSeconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }


    // MARK: - Helpers

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
