import Foundation
import GRDB
import XCTest
@testable import SwiftQL


@SQLTable(name: "Phrase")
struct RegexpPhrase: Equatable {
    let id: String
    let text: String
}


@SQLTable(name: "OptionalPhrase")
struct RegexpOptionalPhrase: Equatable {
    let id: String
    let text: String?
    let pattern: String?
}


///
/// Issue #78: the `REGEXP` operator. Issue #612: SwiftQL now ships the
/// `regexp` implementation the operator needs, so these tests cover the
/// bundled function's behaviour, its registration, and the rule that an
/// application-supplied function still wins.
///
final class XLRegexpOperatorTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    override func tearDownWithError() throws {
        // Close the pool before removing the file: leaving it open can keep
        // the SQLite file locked and make the cleanup below fail silently.
        try? database?.databasePool.close()
        database = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    /// Builds a database and seeds the phrase table.
    ///
    /// `applicationRegexp` registers a `regexp/2` the way an application would,
    /// through a caller-supplied configuration. It is `nil` for every test of
    /// the bundled function, so those tests prove SwiftQL registered it.
    private func makeDatabase(
        maximumReaderCount: Int? = nil,
        applicationRegexp: (@Sendable ([DatabaseValue]) -> (any DatabaseValueConvertible)?)? = nil
    ) throws -> GRDBDatabase {
        var configuration = Configuration()
        if let maximumReaderCount {
            configuration.maximumReaderCount = maximumReaderCount
        }
        if let applicationRegexp {
            configuration.prepareDatabase { db in
                db.add(
                    function: DatabaseFunction("regexp", argumentCount: 2) { values in
                        applicationRegexp(values)
                    }
                )
            }
        }
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: configuration,
            logger: nil
        )
        let database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpPhrase.self)).execute()
        for phrase in [
            RegexpPhrase(id: "1", text: "alpha-123"),
            RegexpPhrase(id: "2", text: "beta"),
            RegexpPhrase(id: "3", text: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }
        return database
    }

    private func matchingIdentifiers(_ pattern: String) throws -> [String] {
        let statement = sql { schema in
            let phrase = schema.table(RegexpPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(pattern))
            OrderBy(phrase.id.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll()
    }

    // MARK: - The bundled implementation

    /// The headline behaviour of issue #612: the operator executes with no
    /// registration by the caller at all. Before this issue the same statement
    /// failed with `no such function: regexp`.
    func testRegexpMatchesWithoutAnyApplicationRegistration() throws {
        database = try makeDatabase()
        XCTAssertEqual(try matchingIdentifiers("[0-9]+$"), ["1", "3"])
    }

    /// The other execution path that carries a rendered encoding. It builds its
    /// own executor, so it registers custom functions separately from
    /// `makeRequest(with:)`.
    func testRegexpMatchesThroughPrepareInvocation() throws {
        database = try makeDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("^beta$"))
        }
        let invocation = database.prepareInvocation(with: statement)
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: invocation.parameterLayout,
            bindings: []
        ).validatingComplete()
        let rows: [[XLSQLiteValue]] = try invocation.fetchAllValues(bindings: bindings)
        XCTAssertEqual(rows, [[.text("2")]])
    }

    /// A pattern is searched for, not matched against the whole subject. Both
    /// assertions use the same pattern so the difference is the subject, not
    /// the pattern.
    func testPatternMatchesAnywhereInTheSubject() throws {
        database = try makeDatabase()
        XCTAssertEqual(try matchingIdentifiers("alpha"), ["1"])
        XCTAssertEqual(try matchingIdentifiers("-1"), ["1"])
        XCTAssertEqual(try matchingIdentifiers("mma"), ["3"])
    }

    /// Anchors are how a caller asks for a whole-subject match.
    func testAnchoredPatternMatchesTheWholeSubjectOnly() throws {
        database = try makeDatabase()
        XCTAssertEqual(try matchingIdentifiers("^beta$"), ["2"])
        XCTAssertEqual(try matchingIdentifiers("^alpha$"), [])
        XCTAssertEqual(try matchingIdentifiers("^alpha"), ["1"])
    }

    /// `X REGEXP Y` is a call to `regexp(Y, X)`. Getting this backwards would
    /// still compile and still return rows for a symmetric pattern, so the
    /// order is observed directly rather than inferred from a result.
    func testRegexpPassesPatternAsTheFirstFunctionArgument() throws {
        let observed = LockedPair()
        database = try makeDatabase(applicationRegexp: { values in
            guard
                let pattern = String.fromDatabaseValue(values[0]),
                let subject = String.fromDatabaseValue(values[1])
            else {
                return nil
            }
            observed.record(pattern: pattern, subject: subject)
            return subject.range(of: pattern, options: .regularExpression) != nil
        })
        XCTAssertEqual(try matchingIdentifiers("^beta$"), ["2"])

        let seen = observed.value()
        XCTAssertEqual(seen?.pattern, "^beta$")
        XCTAssertTrue(
            ["alpha-123", "beta", "gamma-456"].contains(seen?.subject ?? ""),
            "subject should be a column value, got \(seen?.subject ?? "nil")"
        )
    }

    // MARK: - NULL and error behaviour

    /// SQL three-valued logic: a comparison with an unknown operand is
    /// unknown, so a row with a NULL subject or a NULL pattern is not selected
    /// and is not reported as an error.
    func testNullOperandYieldsNullRatherThanFalseOrAnError() throws {
        database = try makeDatabase()
        try database.makeRequest(with: sqlCreate(RegexpOptionalPhrase.self)).execute()
        for phrase in [
            RegexpOptionalPhrase(id: "match", text: "beta", pattern: "^b"),
            RegexpOptionalPhrase(id: "nullSubject", text: nil, pattern: "^b"),
            RegexpOptionalPhrase(id: "nullPattern", text: "beta", pattern: nil),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }

        let selected = sql { schema in
            let phrase = schema.table(RegexpOptionalPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp(phrase.pattern))
            OrderBy(phrase.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: selected).fetchAll(),
            ["match"]
        )

        // Not selected, and not an error: `NOT NULL` is also NULL, so neither
        // branch of the predicate claims the NULL rows.
        let rejected = sql { schema in
            let phrase = schema.table(RegexpOptionalPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(!phrase.text.regexp(phrase.pattern))
            OrderBy(phrase.id.ascending())
        }
        XCTAssertEqual(try database.makeRequest(with: rejected).fetchAll(), [])
    }

    /// A mistyped pattern is reported. Returning false instead would silently
    /// select no rows, which reads exactly like a pattern that matches nothing.
    func testInvalidPatternRaisesAnErrorNamingThePattern() throws {
        database = try makeDatabase()
        XCTAssertThrowsError(try matchingIdentifiers("[unterminated")) { error in
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("[unterminated"),
                "the error should name the pattern, got: \(message)"
            )
        }
    }

    /// A TEXT column can hold any storage class, because SQLite does not
    /// enforce column types. Reading an integer as text would be a silent
    /// conversion, so it is an error instead.
    func testNonTextArgumentRaisesAnError() throws {
        let reader = StubColumnReader(values: [.text("a"), .integer(7)])
        XCTAssertThrowsError(try XLRegexpFunction.evaluate(reader: reader))
    }

    /// The unit-level statement of the NULL rule, independent of how SQLite
    /// happens to evaluate a predicate.
    func testEvaluateReturnsNilForANullArgument() throws {
        XCTAssertNil(
            try XLRegexpFunction.evaluate(
                reader: StubColumnReader(values: [.null, .text("beta")])
            )
        )
        XCTAssertNil(
            try XLRegexpFunction.evaluate(
                reader: StubColumnReader(values: [.text("^b"), .null])
            )
        )
    }

    // MARK: - Precedence over an application registration

    /// An application that already registers `regexp` keeps its own
    /// implementation. This one inverts the match, so a bundled function that
    /// replaced it would return the opposite rows.
    func testApplicationRegisteredFunctionWinsOverTheBundledOne() throws {
        database = try makeDatabase(applicationRegexp: { values in
            guard
                let pattern = String.fromDatabaseValue(values[0]),
                let subject = String.fromDatabaseValue(values[1])
            else {
                return nil
            }
            return subject.range(of: pattern, options: .regularExpression) == nil
        })
        XCTAssertEqual(try matchingIdentifiers("[0-9]+$"), ["2"])
    }

    /// The same rule for the upfront registration seam, which is the spelling
    /// the documentation recommends.
    func testAddFunctionRegistrationWinsOverTheBundledOne() throws {
        var builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: Configuration(),
            logger: nil
        )
        builder.addFunction(InvertedRegexpFunction.self)
        database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpPhrase.self)).execute()
        for phrase in [
            RegexpPhrase(id: "1", text: "alpha-123"),
            RegexpPhrase(id: "2", text: "beta"),
            RegexpPhrase(id: "3", text: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }
        XCTAssertEqual(try matchingIdentifiers("[0-9]+$"), ["2"])
    }

    // MARK: - Pool concurrency

    /// `DatabasePool` keeps several persistent reader connections and hands a
    /// read to whichever is idle, while `Database.add(function:)` registers on
    /// only the one physical connection it runs on. The bundled `regexp` has to
    /// reach every one of them.
    ///
    /// Concurrency is observed, not inferred from elapsed time. A barrier
    /// function in the same statement blocks each execution until
    /// `maximumReaderCount` of them are inside it at once. SQLite runs one
    /// statement at a time per physical connection, so reaching the barrier
    /// proves that many distinct connections each prepared and ran a statement
    /// containing `REGEXP`. A slow machine only makes the barrier take longer;
    /// a pool that never spreads the reads fails on the barrier's own timeout.
    func testRegexpRegistersOnEveryPooledConnection() throws {
        let maximumReaderCount = 4
        database = try makeDatabase(maximumReaderCount: maximumReaderCount)

        let barrier = RegexpConcurrencyBarrier(
            target: maximumReaderCount,
            timeout: 30
        )
        RegexpBarrierFunction.barrier.set(barrier)
        defer { RegexpBarrierFunction.barrier.set(nil) }

        let iterations = 8
        let outcomes = RegexpOutcomes()
        let completed = DispatchGroup()
        for index in 0 ..< iterations {
            completed.enter()
            // Dedicated threads rather than `concurrentPerform`, which is free
            // to run its iterations on fewer threads than the barrier needs.
            let worker = Thread { [self] in
                defer { completed.leave() }
                let statement = sql { schema in
                    let phrase = schema.table(RegexpPhrase.self)
                    Select(phrase.id)
                    From(phrase)
                    Where(phrase.text.regexp("[0-9]+$") && RegexpBarrierFunction())
                    OrderBy(phrase.id.ascending())
                }
                do {
                    outcomes.record(
                        .success(try database.makeRequest(with: statement).fetchAll())
                    )
                }
                catch {
                    outcomes.record(.failure(error))
                }
            }
            worker.name = "bundled-regexp-\(index)"
            worker.start()
        }

        XCTAssertEqual(
            completed.wait(timeout: .now() + 60),
            .success,
            "Concurrent pooled reads did not all finish."
        )
        XCTAssertGreaterThanOrEqual(
            barrier.peakConcurrency,
            maximumReaderCount,
            """
            Only \(barrier.peakConcurrency) statement(s) using REGEXP ever ran at once, short of \
            the \(maximumReaderCount) needed to prove the function reached more than one pooled \
            connection.
            """
        )
        let results = outcomes.value()
        XCTAssertEqual(results.count, iterations)
        for result in results {
            switch result {
            case .success(let identifiers):
                XCTAssertEqual(identifiers, ["1", "3"])
            case .failure(let error):
                XCTFail("pooled read failed: \(error)")
            }
        }
    }

    // MARK: - Rendering and registration recording

    /// The rendered SQL is unchanged by issue #612. The operator still renders
    /// as an ordinary parenthesised binary operator; only the recorded
    /// registration is new.
    func testRenderedSQLIsUnchanged() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp("^a.*z$"))
            }
        )
        XCTAssertEqual(
            encoding.sql,
            #"SELECT "t0"."id" FROM "Phrase" AS "t0" WHERE ("t0"."text" REGEXP '^a.*z$')"#
        )
    }

    /// All four nullability overloads record the registration, so none of them
    /// can render SQL that SQLite cannot prepare.
    func testEveryOverloadRecordsTheBundledRegistration() throws {
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        let nonNullPatternAndSubject = encoder.makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp("^a"))
            }
        )
        let nullablePattern = encoder.makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpOptionalPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.id.regexp(phrase.pattern))
            }
        )
        let nullableSubject = encoder.makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpOptionalPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp("^a"))
            }
        )
        let nullableBoth = encoder.makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpOptionalPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp(phrase.pattern))
            }
        )

        for encoding in [
            nonNullPatternAndSubject,
            nullablePattern,
            nullableSubject,
            nullableBoth,
        ] {
            XCTAssertNotNil(
                encoding.customFunctions[XLRegexpFunction.definition],
                "no registration recorded for: \(encoding.sql)"
            )
        }
    }

    /// A statement that never uses the operator must not carry the
    /// registration, so an unrelated query does not pay for it.
    func testAStatementWithoutRegexpRecordsNoRegistration() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.like("a%"))
            }
        )
        XCTAssertNil(encoding.customFunctions[XLRegexpFunction.definition])
    }
}


/// An application-supplied `regexp` that inverts the match, registered through
/// ``GRDBDatabaseBuilder/addFunction(_:)``. Inverting makes the precedence rule
/// observable from the rows a query returns.
private struct InvertedRegexpFunction: XLCustomFunction {
    typealias T = Bool

    static let definition = XLRegexpFunction.definition

    func makeSQL(context: inout XLBuilder) {
        context.customFunctionCall(Self.self) { _ in }
    }

    static func execute(reader: XLColumnReader) throws -> Bool {
        let pattern = try reader.readText(at: 0)
        let subject = try reader.readText(at: 1)
        return subject.range(of: pattern, options: .regularExpression) == nil
    }
}


/// Feeds ``XLRegexpFunction/evaluate(reader:)`` exact storage classes, which a
/// typed SwiftQL query cannot produce on its own.
private struct StubColumnReader: XLColumnReader {

    enum Value {
        case null
        case text(String)
        case integer(Int)
    }

    let values: [Value]

    private func value(at index: Int) throws -> Value {
        guard values.indices.contains(index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: nil,
                failure: .indexOutOfBounds(valueCount: values.count)
            )
        }
        return values[index]
    }

    func isNull(at index: Int) throws -> Bool {
        if case .null = try value(at: index) {
            return true
        }
        return false
    }

    func readInteger(at index: Int) throws -> Int {
        guard case .integer(let integer) = try value(at: index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: String(reflecting: Int.self),
                failure: .typeMismatch(actualType: "not an integer")
            )
        }
        return integer
    }

    func readReal(at index: Int) throws -> Double {
        Double(try readInteger(at: index))
    }

    func readText(at index: Int) throws -> String {
        guard case .text(let text) = try value(at: index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: String(reflecting: String.self),
                failure: .typeMismatch(actualType: "not text")
            )
        }
        return text
    }

    func readBlob(at index: Int) throws -> Data {
        Data(try readText(at: index).utf8)
    }
}


/// Minimal thread-safe box; the SQLite function runs on the database queue.
private final class LockedPair: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (pattern: String, subject: String)?

    func record(pattern: String, subject: String) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil {
            stored = (pattern, subject)
        }
    }

    func value() -> (pattern: String, subject: String)? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}


/// Always true, and blocks inside the barrier a test installs.
///
/// Used only to make simultaneous execution across pooled connections
/// observable. It opts into implicit registration, so a statement that uses it
/// needs no upfront registration either.
private struct RegexpBarrierFunction: XLCustomFunction {
    typealias T = Bool

    static let definition = XLCustomFunctionDefinition(
        name: "regexpTestBarrier",
        numberOfArguments: 0
    )

    static let barrier = RegexpBarrierBox()

    func makeSQL(context: inout XLBuilder) {
        context.customFunctionCall(Self.self) { _ in }
    }

    static func execute(reader: XLColumnReader) throws -> Bool {
        barrier.get()?.arriveAndWait()
        return true
    }
}


/// Holds the barrier a test installs, if any.
private final class RegexpBarrierBox: @unchecked Sendable {
    private let lock = NSLock()
    private var barrier: RegexpConcurrencyBarrier?

    func set(_ barrier: RegexpConcurrencyBarrier?) {
        lock.lock()
        defer { lock.unlock() }
        self.barrier = barrier
    }

    func get() -> RegexpConcurrencyBarrier? {
        lock.lock()
        defer { lock.unlock() }
        return barrier
    }
}


/// Releases every caller once `target` of them are waiting at the same time,
/// and records the highest number that ever waited together.
private final class RegexpConcurrencyBarrier: @unchecked Sendable {

    private let condition = NSCondition()
    private let target: Int
    private let timeout: TimeInterval
    private var inside = 0
    private var peak = 0
    private var isOpen = false

    init(target: Int, timeout: TimeInterval) {
        self.target = target
        self.timeout = timeout
    }

    func arriveAndWait() {
        condition.lock()
        defer { condition.unlock() }
        inside += 1
        peak = max(peak, inside)
        if inside >= target {
            isOpen = true
            condition.broadcast()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !isOpen {
            guard condition.wait(until: deadline) else {
                break
            }
        }
        inside -= 1
    }

    var peakConcurrency: Int {
        condition.lock()
        defer { condition.unlock() }
        return peak
    }
}


/// Collects the result of each concurrent read.
private final class RegexpOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[String], Error>] = []

    func record(_ result: Result<[String], Error>) {
        lock.lock()
        defer { lock.unlock() }
        results.append(result)
    }

    func value() -> [Result<[String], Error>] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}
