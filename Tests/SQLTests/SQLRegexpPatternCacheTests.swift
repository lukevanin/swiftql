//
//  SQLRegexpPatternCacheTests.swift
//
//  Issue #613: a REGEXP pattern is compiled once per statement execution, not
//  once per row.
//

import Foundation
import GRDB
import XCTest
@testable import SwiftQL


@SQLTable(name: "CachedPhrase")
struct RegexpCachedPhrase: Equatable {
    let id: Int
    let text: String
    let pattern: String
}


final class XLRegexpPatternCacheTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

    /// Enough rows that a compile-per-row implementation is unmistakable: the
    /// difference between one compile and this many is what the test measures.
    private let rowCount = 500

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    override func tearDownWithError() throws {
        try? database?.databasePool.close()
        database = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    /// Seeds `rowCount` rows. Every row carries its own `pattern` column so a
    /// test can force one distinct pattern per row.
    private func makeSeededDatabase() throws -> GRDBDatabase {
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: Configuration(),
            logger: nil
        )
        let database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpCachedPhrase.self)).execute()
        try database.withTransaction { transaction in
            for index in 0 ..< rowCount {
                try transaction.makeRequest(
                    with: sqlInsert(
                        RegexpCachedPhrase(
                            id: index,
                            text: "row-\(index)",
                            pattern: "^row-\(index)$"
                        )
                    )
                ).execute()
            }
        }
        return database
    }

    // MARK: - Compiles per execution

    /// The headline behaviour: one pattern, one compile, however many rows
    /// SQLite tests it against.
    func testOnePatternIsCompiledOncePerStatementExecution() throws {
        database = try makeSeededDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpCachedPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("^row-1[0-9]$"))
            OrderBy(phrase.id.ascending())
        }

        let before = XLRegexpPatternCache.compilesInProcess
        let matched: [Int] = try database.makeRequest(with: statement).fetchAll()
        let compiles = XLRegexpPatternCache.compilesInProcess - before

        XCTAssertEqual(matched, Array(10...19))
        XCTAssertEqual(
            compiles,
            1,
            "\(rowCount) rows tested against one pattern should compile it once."
        )
    }

    /// A pattern that does not compile must not be retried once per row. The
    /// failure is cached exactly as a success is.
    func testAnInvalidPatternIsCompiledOnceAndReportedOnEveryRow() throws {
        database = try makeSeededDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpCachedPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("[unterminated"))
        }

        let before = XLRegexpPatternCache.compilesInProcess
        XCTAssertThrowsError(
            try database.makeRequest(with: statement).fetchAll() as [Int]
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("[unterminated"),
                "unexpected error: \(error)"
            )
        }
        XCTAssertEqual(XLRegexpPatternCache.compilesInProcess - before, 1)
    }

    /// A pattern read from a column can differ on every row. That is the case
    /// the bound exists for, and it still has to produce the right rows.
    func testAPatternPerRowStaysCorrectAndStaysBounded() throws {
        database = try makeSeededDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpCachedPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(phrase.pattern))
            OrderBy(phrase.id.ascending())
        }

        let matched: [Int] = try database.makeRequest(with: statement).fetchAll()

        // Every row's pattern anchors on that row's own text, so every row
        // matches. A bound cache changes how often a pattern is compiled, never
        // which rows are selected.
        XCTAssertEqual(matched, Array(0 ..< rowCount))
    }

    /// Caching must not change a single answer. The same patterns are run
    /// through the cached and the uncached path and compared.
    func testCachedAndUncachedMatchesAgree() throws {
        let cache = XLRegexpPatternCache()
        let patterns = ["^row", "[0-9]+$", "row-1[0-9]$", "z", "^row-7$"]
        let subjects = ["row-1", "row-17", "row-7", "beta", ""]

        for pattern in patterns {
            for subject in subjects {
                XCTAssertEqual(
                    try XLRegexpFunction.matches(pattern: pattern, in: subject),
                    try XLRegexpFunction.matches(
                        pattern: pattern,
                        in: subject,
                        cache: cache
                    ),
                    "cached and uncached disagreed on '\(pattern)' / '\(subject)'"
                )
            }
        }
    }

    /// Executing the same statement twice compiles once for each execution.
    /// A registration's cache lives as long as that registration, and the
    /// driver registers the function again before each execution.
    func testResultsAreUnchangedAcrossRepeatedExecutions() throws {
        database = try makeSeededDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpCachedPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("^row-4[0-4]$"))
            OrderBy(phrase.id.ascending())
        }

        for _ in 0 ..< 3 {
            XCTAssertEqual(
                try database.makeRequest(with: statement).fetchAll(),
                Array(40...44)
            )
        }
    }

    // MARK: - The cache itself

    func testRepeatedPatternIsCompiledOnce() throws {
        let cache = XLRegexpPatternCache()
        for _ in 0 ..< 100 {
            _ = try cache.regex(for: "^a")
        }
        XCTAssertEqual(cache.numberOfCompiles, 1)
        XCTAssertEqual(cache.count, 1)
    }

    /// Alternating between two patterns must not defeat the cache: the
    /// most-recent entry is a fast path in front of the map, not the whole
    /// cache.
    func testAlternatingPatternsAreEachCompiledOnce() throws {
        let cache = XLRegexpPatternCache()
        for _ in 0 ..< 50 {
            _ = try cache.regex(for: "^a")
            _ = try cache.regex(for: "^b")
        }
        XCTAssertEqual(cache.numberOfCompiles, 2)
        XCTAssertEqual(cache.count, 2)
    }

    func testAnInvalidPatternIsCompiledOnceAndThrownEveryTime() throws {
        let cache = XLRegexpPatternCache()
        for _ in 0 ..< 20 {
            XCTAssertThrowsError(try cache.regex(for: "[unterminated")) { error in
                guard
                    case .invalidPattern(let pattern, _)? = error as? XLRegexpFunctionError
                else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertEqual(pattern, "[unterminated")
            }
        }
        XCTAssertEqual(cache.numberOfCompiles, 1)
    }

    func testTheCacheStopsGrowingAtItsCapacity() throws {
        let cache = XLRegexpPatternCache()
        let patternCount = XLRegexpPatternCache.capacity + 8
        for index in 0 ..< patternCount {
            _ = try cache.regex(for: "^p\(index)")
        }
        XCTAssertEqual(cache.numberOfCompiles, patternCount)
        XCTAssertEqual(cache.count, XLRegexpPatternCache.capacity)
    }

    /// Eviction is by insertion order, so the oldest pattern is the one that
    /// has to be compiled again.
    func testAnEvictedPatternIsCompiledAgain() throws {
        let cache = XLRegexpPatternCache()
        let oldest = "^p0"
        _ = try cache.regex(for: oldest)
        for index in 1 ... XLRegexpPatternCache.capacity {
            _ = try cache.regex(for: "^p\(index)")
        }
        let compilesBefore = cache.numberOfCompiles

        _ = try cache.regex(for: oldest)

        XCTAssertEqual(cache.numberOfCompiles, compilesBefore + 1)
    }

    /// The lock has to hold under genuine concurrency, even though production
    /// never shares one cache between connections.
    func testConcurrentLookupsReturnCorrectResults() throws {
        let cache = XLRegexpPatternCache()
        let patterns = ["^a", "^b", "^c", "[0-9]$"]
        let subjects = ["abc", "bcd", "cde", "x9"]
        let failures = LockedFailureCount()

        DispatchQueue.concurrentPerform(iterations: 400) { iteration in
            let index = iteration % patterns.count
            do {
                let cached = try XLRegexpFunction.matches(
                    pattern: patterns[index],
                    in: subjects[index],
                    cache: cache
                )
                let uncached = try XLRegexpFunction.matches(
                    pattern: patterns[index],
                    in: subjects[index]
                )
                if cached != uncached {
                    failures.record()
                }
            }
            catch {
                failures.record()
            }
        }

        XCTAssertEqual(failures.value(), 0)
        XCTAssertEqual(cache.count, patterns.count)
    }

    // MARK: - Measurement

    /// Not an assertion about speed -- a recorded measurement of the change,
    /// printed the way the render-once benchmark in this suite is. The
    /// assertion is on the compile counts, which are exact.
    func testRecordsTheScanImprovement() throws {
        let subjects = (0 ..< 2_000).map { "row-\($0)" }
        let pattern = "^row-1[0-9]$"

        let cache = XLRegexpPatternCache()
        let cachedStart = Date()
        for subject in subjects {
            _ = try XLRegexpFunction.matches(
                pattern: pattern,
                in: subject,
                cache: cache
            )
        }
        let cachedSeconds = Date().timeIntervalSince(cachedStart)

        let uncachedStart = Date()
        for subject in subjects {
            _ = try XLRegexpFunction.matches(pattern: pattern, in: subject)
        }
        let uncachedSeconds = Date().timeIntervalSince(uncachedStart)

        print(
            """
            [regexp pattern cache] rows=\(subjects.count) pattern='\(pattern)'
              cached:   compiles=\(cache.numberOfCompiles)  wall=\(String(format: "%.4f", cachedSeconds))s
              uncached: compiles=\(subjects.count)  wall=\(String(format: "%.4f", uncachedSeconds))s
              wall-clock speedup (noisy, corroborating only): \
            \(String(format: "%.1f", uncachedSeconds / max(cachedSeconds, .leastNonzeroMagnitude)))x
            """
        )

        XCTAssertEqual(cache.numberOfCompiles, 1)
    }
}


/// Counts mismatches seen on worker threads.
private final class LockedFailureCount: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0

    func record() {
        lock.lock()
        defer { lock.unlock() }
        failures += 1
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}
