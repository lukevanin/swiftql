//
//  SQLRegexPatternTests.swift
//
//  Issue #614: matching a Swift `Regex` as the right operand of REGEXP,
//  through a registry with keyed dispatch.
//

import Foundation
import GRDB
import RegexBuilder
@testable import SwiftQLCore
import XCTest
@testable import SwiftQL


@SQLTable(name: "PatternPhrase")
struct RegexPatternPhrase: Equatable {
    let id: String
    let text: String
    let note: String?
}


final class XLRegexPatternTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

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

    private func makeSeededDatabase() throws -> GRDBDatabase {
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: Configuration(),
            logger: nil
        )
        let database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexPatternPhrase.self)).execute()
        for phrase in [
            RegexPatternPhrase(id: "1", text: "alpha-123", note: "alpha-123"),
            RegexPatternPhrase(id: "2", text: "beta", note: nil),
            RegexPatternPhrase(id: "3", text: "gamma-456", note: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }
        return database
    }

    private func matchingIdentifiers(_ pattern: XLRegexPattern) throws -> [String] {
        let statement = sql { schema in
            let phrase = schema.table(RegexPatternPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(pattern))
            OrderBy(phrase.id.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll()
    }

    // MARK: - Matching

    /// The behaviour the issue asks for: a `RegexBuilder` pattern selects the
    /// rows a string pattern would.
    func testARegexBuilderPatternSelectsTheSameRowsAsTheEquivalentString() throws {
        database = try makeSeededDatabase()
        let built = XLRegexPattern {
            OneOrMore(.digit)
            Anchor.endOfSubject
        }

        let byRegex = try matchingIdentifiers(built)

        let byString: [String] = try database.makeRequest(
            with: sql { schema in
                let phrase = schema.table(RegexPatternPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp("[0-9]+$"))
                OrderBy(phrase.id.ascending())
            }
        ).fetchAll()

        XCTAssertEqual(byRegex, ["1", "3"])
        XCTAssertEqual(byRegex, byString)
    }

    /// A `Regex` value, rather than a builder closure.
    func testACompiledRegexCanBeUsedDirectly() throws {
        database = try makeSeededDatabase()
        let pattern = XLRegexPattern(try Regex("^beta$"))

        XCTAssertEqual(try matchingIdentifiers(pattern), ["2"])
    }

    /// The nullable overload, so a pattern works on an optional column too.
    func testAPatternMatchesANullableColumn() throws {
        database = try makeSeededDatabase()
        let pattern = XLRegexPattern {
            OneOrMore(.digit)
            Anchor.endOfSubject
        }
        let statement = sql { schema in
            let phrase = schema.table(RegexPatternPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.note.regexp(pattern))
            OrderBy(phrase.id.ascending())
        }

        // Row 2's note is NULL, so its comparison is NULL and it is not
        // selected -- the same rule a string pattern follows.
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            ["1", "3"]
        )
    }

    /// Anchors composed with `RegexBuilder` behave as they do in Swift.
    func testAnAnchoredBuilderPatternMatchesTheWholeSubject() throws {
        database = try makeSeededDatabase()
        let whole = XLRegexPattern {
            Anchor.startOfSubject
            "beta"
            Anchor.endOfSubject
        }
        let leading = XLRegexPattern {
            Anchor.startOfSubject
            "alpha"
        }

        XCTAssertEqual(try matchingIdentifiers(whole), ["2"])
        XCTAssertEqual(try matchingIdentifiers(leading), ["1"])
    }

    // MARK: - Keys

    /// The caller never names a key, and one pattern used in two statements is
    /// one registration.
    func testOnePatternUsedTwiceResolvesToOneRegistration() throws {
        database = try makeSeededDatabase()
        let pattern = XLRegexPattern { OneOrMore(.digit) }

        XCTAssertEqual(try matchingIdentifiers(pattern), ["1", "3"])
        XCTAssertEqual(try matchingIdentifiers(pattern), ["1", "3"])

        let firstKey = pattern.key
        XCTAssertEqual(pattern.key, firstKey)
    }

    /// Two patterns are two registrations, even when they match the same thing.
    func testTwoPatternsTakeDistinctKeys() {
        let first = XLRegexPattern { OneOrMore(.digit) }
        let second = XLRegexPattern { OneOrMore(.digit) }

        XCTAssertNotEqual(first.key, second.key)
    }

    /// The rendered SQL carries the key, not a pattern.
    func testTheRenderedSQLCarriesTheKey() {
        let pattern = XLRegexPattern { OneOrMore(.digit) }
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { schema in
                let phrase = schema.table(RegexPatternPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp(pattern))
            }
        )

        XCTAssertTrue(
            encoding.sql.contains(pattern.key),
            encoding.sql.debugDescription
        )
        XCTAssertTrue(XLRegexPatternRegistry.isKey(pattern.key))
        XCTAssertNotNil(encoding.customFunctions[XLRegexpFunction.definition])
    }

    /// A pattern deliberately shaped like a key is still a pattern. A key's
    /// marker is a control character, which no regular expression a person
    /// writes contains.
    func testAPatternShapedLikeAKeyIsStillAPattern() throws {
        database = try makeSeededDatabase()
        let lookAlike = "swiftql.regex.0"

        XCTAssertFalse(XLRegexPatternRegistry.isKey(lookAlike))

        // `.` matches any character, so this pattern matches nothing in the
        // seeded rows and is evaluated as a pattern rather than looked up.
        let statement = sql { schema in
            let phrase = schema.table(RegexPatternPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(lookAlike))
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll() as [String],
            []
        )
    }

    /// A key naming no registration is a programmer error, not a match
    /// failure, and the message says what to check.
    func testAnUnregisteredKeyRaisesAClearError() throws {
        database = try makeSeededDatabase()
        let strayKey = XLRegexPatternRegistry.key(forIdentifier: 999_999)
        let statement = sql { schema in
            let phrase = schema.table(RegexPatternPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(strayKey))
        }

        XCTAssertThrowsError(
            try database.makeRequest(with: statement).fetchAll() as [String]
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("XLRegexPattern"),
                "the error should name the type, got: \(message)"
            )
            XCTAssertTrue(
                message.contains("released"),
                "the error should say what to check, got: \(message)"
            )
        }
    }

    /// The same rule at the matcher level, so the error does not depend on how
    /// SQLite reports it.
    func testTheMatcherRejectsAnUnregisteredKey() {
        let strayKey = XLRegexPatternRegistry.key(forIdentifier: 999_998)
        XCTAssertThrowsError(
            try XLRegexpMatcher.matches(pattern: strayKey, in: "anything")
        ) { error in
            XCTAssertEqual(
                error as? XLRegexpFunctionError,
                .unregisteredPattern(key: strayKey)
            )
        }
    }

    // MARK: - Ownership

    /// A released pattern's entry is removed, not merely emptied, so a process
    /// that builds patterns per request does not accumulate dead entries.
    func testAReleasedPatternLeavesNoEntryBehind() {
        let before = XLRegexPatternRegistry.shared.storedEntryCount
        for _ in 0 ..< 50 {
            let pattern = XLRegexPattern { OneOrMore(.digit) }
            XCTAssertTrue(pattern.matches("a1"))
        }

        XCTAssertEqual(XLRegexPatternRegistry.shared.storedEntryCount, before)
    }

    /// The registry does not keep a pattern alive, so a released one stops
    /// resolving. This is the ownership rule, tested rather than only written
    /// down.
    func testAReleasedPatternStopsResolving() {
        var key: String?
        do {
            let pattern = XLRegexPattern { OneOrMore(.digit) }
            key = pattern.key
            XCTAssertTrue(
                try XLRegexpMatcher.matches(pattern: pattern.key, in: "a1")
            )
        }

        let releasedKey = key ?? ""
        XCTAssertThrowsError(
            try XLRegexpMatcher.matches(pattern: releasedKey, in: "a1")
        ) { error in
            XCTAssertEqual(
                error as? XLRegexpFunctionError,
                .unregisteredPattern(key: releasedKey)
            )
        }
    }

    // MARK: - Static descriptors

    /// A key names a registration in one process, so a descriptor built from
    /// such a statement would have an identity that changes between runs.
    func testAStaticDescriptorRefusesAPatternKey() throws {
        let pattern = XLRegexPattern { OneOrMore(.digit) }
        let encoding = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(
                sql { schema in
                    let phrase = schema.table(RegexPatternPhrase.self)
                    Select(phrase.id)
                    From(phrase)
                    Where(phrase.text.regexp(pattern))
                }
            )

        XCTAssertThrowsError(
            try XLStaticStatementDefinition(validating: encoding)
        ) { error in
            guard
                case .processLocalRegexPattern? =
                    error as? XLStaticStatementDefinitionError
            else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    /// The same statement written with a string pattern is still allowed, so
    /// the refusal is about the key and not about `REGEXP`.
    func testAStaticDescriptorStillAcceptsAStringPattern() throws {
        let encoding = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(
                sql { schema in
                    let phrase = schema.table(RegexPatternPhrase.self)
                    Select(phrase.id)
                    From(phrase)
                    Where(phrase.text.regexp("[0-9]+$"))
                }
            )

        XCTAssertNoThrow(try XLStaticStatementDefinition(validating: encoding))
    }

    // MARK: - Concurrency and cost

    /// One registration is reachable from every pooled connection at once.
    func testConcurrentMatchingAgainstOnePatternIsSafe() throws {
        let pattern = XLRegexPattern {
            OneOrMore(.digit)
            Anchor.endOfSubject
        }
        let mismatches = LockedCount()

        DispatchQueue.concurrentPerform(iterations: 500) { iteration in
            let subject = iteration.isMultiple(of: 2) ? "row-\(iteration)" : "beta"
            let expected = iteration.isMultiple(of: 2)
            if pattern.matches(subject) != expected {
                mismatches.record()
            }
        }

        XCTAssertEqual(mismatches.value(), 0)
    }

    /// A `RegexBuilder` transform that throws has nowhere to report itself: the
    /// operator answers a yes-or-no question about one row, and captures are
    /// not exposed. The row does not match, and the statement is not failed.
    func testAThrowingTransformIsReadAsNoMatch() throws {
        let failing = XLRegexPattern {
            TryCapture(OneOrMore(.digit)) { _ -> Int? in nil }
        }

        XCTAssertFalse(failing.matches("123"))
    }

    /// A registered pattern is compiled by the caller, so the function must
    /// never recompile it -- the compile cache is not consulted at all.
    func testAPatternIsNeverRecompiled() throws {
        database = try makeSeededDatabase()
        let pattern = XLRegexPattern { OneOrMore(.digit) }

        let before = XLRegexpPatternCache.compilesInProcess
        XCTAssertEqual(try matchingIdentifiers(pattern), ["1", "3"])
        XCTAssertEqual(XLRegexpPatternCache.compilesInProcess - before, 0)
    }
}


/// Counts mismatches seen on worker threads.
private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
