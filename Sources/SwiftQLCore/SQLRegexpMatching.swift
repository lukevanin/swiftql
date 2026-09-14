//
//  SQLRegexpMatching.swift
//  SwiftQLCore
//
//  Matching a SQLite REGEXP pattern with Swift `Regex`, and keeping compiled
//  patterns for the life of one physical connection's `regexp` install, up
//  to a bounded number, instead of compiling once per row.
//
//  Adapter-neutral on purpose (issue #615). The SQLite function this backs is
//  registered by the GRDB adapter at runtime and by the build validator on its
//  own snapshot connection, and neither target can reach the other's module.
//
//  Issues #612 and #613.
//

import Foundation


/// A failure raised by the bundled `regexp` implementation.
///
/// SQLite reports the failure as an execution error on the statement that used
/// the `REGEXP` operator. A pattern is only known to be invalid once SQLite
/// hands it to the function, so this cannot be a preparation error.
public enum XLRegexpFunctionError: Error, Equatable {

    /// The pattern is not a valid Swift regular expression.
    ///
    /// - Parameters:
    ///   - pattern: The pattern text SQLite passed to the function.
    ///   - message: The description Swift's regular-expression parser gave.
    case invalidPattern(pattern: String, message: String)

    /// The operand names an ``XLRegexPattern`` this process cannot resolve.
    ///
    /// Almost always a key passed on as a string after its pattern was
    /// released. A statement built with `regexp(_:)` from the
    /// ``XLRegexPattern`` itself keeps the pattern alive; a bare key does not.
    /// See its ownership note.
    ///
    /// - Parameter key: The key SQLite passed to the function.
    case unregisteredPattern(key: String)
}


extension XLRegexpFunctionError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .invalidPattern(let pattern, let message):
            return "Invalid REGEXP pattern '\(pattern)': \(message)"
        case .unregisteredPattern(let key):
            return """
                REGEXP names an XLRegexPattern this process cannot resolve \
                (key \(key.debugDescription)). The key was most likely passed \
                as a string after its pattern was released. Pass the \
                XLRegexPattern itself to regexp(_:), which keeps it alive for \
                the statement, or hold the pattern while the key is in use.
                """
        }
    }
}


extension XLRegexpFunctionError: LocalizedError {

    public var errorDescription: String? {
        description
    }
}


/// A `REGEXP` operand longer than the bundled function accepts.
///
/// Raised before any compile or match, so an oversized pattern or subject costs
/// one length check rather than an unbounded match. SQLite reports it as an
/// execution error on the statement, the same way it reports an invalid
/// pattern. See ``XLRegexpMatcher/maximumPatternLength`` and
/// ``XLRegexpMatcher/maximumSubjectLength`` for the limits and the reason.
///
/// A separate type rather than a new ``XLRegexpFunctionError`` case, so a
/// caller that switches over that enum exhaustively keeps compiling.
public struct XLRegexpLengthLimitError: Error, Equatable, Sendable {

    /// Which operand of `X REGEXP Y` was too long.
    public enum Operand: String, Equatable, Sendable {

        /// The right operand, `Y`: the pattern.
        case pattern

        /// The left operand, `X`: the text searched.
        case subject
    }

    /// The operand that exceeded its limit.
    public let operand: Operand

    /// The operand's length, in UTF-8 bytes.
    public let length: Int

    /// The limit it exceeded, in UTF-8 bytes.
    public let limit: Int

    public init(operand: Operand, length: Int, limit: Int) {
        self.operand = operand
        self.length = length
        self.limit = limit
    }
}


extension XLRegexpLengthLimitError: CustomStringConvertible {

    public var description: String {
        """
        REGEXP \(operand.rawValue) is \(length) UTF-8 bytes, which exceeds the \
        limit of \(limit) bytes. SwiftQL refuses it rather than truncating it \
        or matching it without a bound. Validate the \(operand.rawValue) \
        before the statement runs.
        """
    }
}


extension XLRegexpLengthLimitError: LocalizedError {

    public var errorDescription: String? {
        description
    }
}


///
/// Matches a subject against a `REGEXP` pattern.
///
/// The behaviour this defines is described on `XLRegexpFunction`, which is the
/// SQLite function that calls it.
///
public enum XLRegexpMatcher {

    ///
    /// The longest pattern string the bundled function compiles, in UTF-8
    /// bytes.
    ///
    /// A match runs inside a SQLite function callback, where
    /// `sqlite3_interrupt` is never checked, so nothing can cancel a statement
    /// while one row is being matched. The pattern is also the operand a
    /// search field usually supplies. Bounding its size bounds the compile and
    /// the size of the automaton a match walks.
    ///
    /// 1,024 bytes is far longer than a pattern a person types or a program
    /// assembles for one search, and short enough that compiling it is cheap.
    /// The limit applies to pattern text only. An ``XLRegexPattern`` is
    /// compiled by the application in Swift, and its key is not a pattern.
    ///
    /// Measured in UTF-8 bytes because that is how SQLite measures TEXT and
    /// because `String.utf8.count` is constant time for native strings, so the
    /// check itself costs nothing proportional to the input.
    public static let maximumPatternLength = 1_024

    ///
    /// The longest subject the bundled function searches, in UTF-8 bytes.
    ///
    /// Search time depends on the pattern as well as on the subject. A pattern
    /// that runs in linear time, such as `[0-9]+$`, searches 16,384 bytes in
    /// under a millisecond, and searches a mebibyte in tens of milliseconds. A pattern whose search is quadratic, such as `.*x` against
    /// a subject with no `x`, grows much faster. Measured with the Xcode
    /// toolchain on Apple silicon, it took 0.02 s at 1,024 bytes, 0.3 s at
    /// 4,096 bytes, 8 s at 16,384 bytes, and 76 s at 65,536 bytes. This limit
    /// keeps that case to seconds for one row rather than minutes.
    ///
    /// The limit does **not** make an untrusted pattern safe. A pattern with
    /// nested quantifiers, such as `(a+)+$`, backtracks exponentially: it took
    /// 0.2 s against 15 bytes and did not finish in 400 s against 25 bytes.
    /// No limit long enough for ordinary column text prevents that, so a
    /// pattern from untrusted input still has to be validated before it
    /// reaches a statement.
    ///
    /// 16,384 bytes admits the short text a `REGEXP` filter usually tests,
    /// such as names, titles, identifiers, and notes. Search a longer document
    /// with full-text search or in Swift.
    public static let maximumSubjectLength = 16_384

    /// Whether `pattern` occurs anywhere in `subject`.
    ///
    /// - Parameters:
    ///   - pattern: The pattern text.
    ///   - subject: The text searched.
    ///   - cache: Holds the compiled form of each pattern already seen, so a
    ///     scan compiles one pattern once rather than once per row. A caller
    ///     that passes none compiles on every call.
    /// - Throws: ``XLRegexpLengthLimitError`` if `subject` is longer than
    ///   ``maximumSubjectLength``, or a pattern string is longer than
    ///   ``maximumPatternLength``;
    ///   ``XLRegexpFunctionError/invalidPattern(pattern:message:)`` if
    ///   the pattern does not compile; or
    ///   ``XLRegexpFunctionError/unregisteredPattern(key:)`` if `pattern` is an
    ///   ``XLRegexPattern`` key this process cannot resolve.
    public static func matches(
        pattern: String,
        in subject: String,
        cache: XLRegexpPatternCache? = nil
    ) throws -> Bool {
        // Checked before anything else, and for a registered pattern too: a
        // registration serializes its matches behind one lock, so one long
        // match would hold up every pooled connection using that pattern.
        let subjectLength = subject.utf8.count
        guard subjectLength <= maximumSubjectLength else {
            throw XLRegexpLengthLimitError(
                operand: .subject,
                length: subjectLength,
                limit: maximumSubjectLength
            )
        }
        // A registered `XLRegexPattern` renders an opaque key rather than a
        // pattern, because a compiled `Regex` cannot travel through SQLite.
        // The key carries a marker no regular expression would, so an ordinary
        // pattern never reaches this branch (issue #614).
        if XLRegexPatternRegistry.isKey(pattern) {
            guard
                let registration = XLRegexPatternRegistry.registration(
                    forKey: pattern
                )
            else {
                throw XLRegexpFunctionError.unregisteredPattern(key: pattern)
            }
            return registration.matches(subject)
        }
        // Before the cache, so an oversized pattern is never compiled and
        // never takes a cache slot.
        let patternLength = pattern.utf8.count
        guard patternLength <= maximumPatternLength else {
            throw XLRegexpLengthLimitError(
                operand: .pattern,
                length: patternLength,
                limit: maximumPatternLength
            )
        }
        let regex = try cache?.regex(for: pattern) ?? compile(pattern)
        return try regex.firstMatch(in: subject) != nil
    }

    /// Compiles one pattern, reporting a parse failure as a SwiftQL error.
    public static func compile(_ pattern: String) throws -> Regex<AnyRegexOutput> {
        do {
            return try Regex(pattern)
        }
        catch {
            throw XLRegexpFunctionError.invalidPattern(
                pattern: pattern,
                message: String(describing: error)
            )
        }
    }
}


///
/// The compiled patterns one registration of the bundled `regexp` function
/// keeps.
///
/// SQLite calls a scalar function once for every candidate row and passes the
/// pattern again on each of those calls, so compiling on each call compiles one
/// statement's single pattern once per row. Compiling a regular expression
/// costs far more than matching with an already compiled one, which makes that
/// the dominant cost of a `WHERE text REGEXP ?` scan rather than the matching.
///
/// ## Scope
///
/// One cache belongs to one registered SQLite function, created by
/// `XLCustomFunctionRegistration.bundledRegexp` when the driver installs the
/// function on a connection -- once per physical connection. It is never
/// shared between connections, and it is not a process-wide cache:
///
/// - Swift's `Regex` is not `Sendable`. Sharing one compiled value between the
///   pooled connections that match with it concurrently would be exactly the
///   sharing the type does not promise is safe. Confining a cache to the
///   registration that created it means a compiled `Regex` is only ever matched
///   against by the one connection that compiled it.
/// - A cache that lives as long as one connection's installation sees every
///   statement that connection runs, including patterns built from user input.
///   ``capacity`` is therefore the real limit on the compiled patterns one
///   connection keeps; see "Bound" below.
///
/// The lock is therefore not there to make cross-connection sharing safe --
/// nothing shares one of these. It is there so the `@unchecked Sendable`
/// conformance the GRDB registration closure needs is true rather than merely
/// unobserved. An uncontended lock costs far less than one regular-expression
/// match.
///
/// ## Bound
///
/// A statement almost always uses one pattern, from a literal or from a
/// parameter SQLite binds once per execution. The bound exists for the cases
/// where one cache sees many patterns -- a pattern read from a *column*, which
/// can differ on every row, and the many statements with different patterns
/// that one connection runs over its life -- so that the cache compiles
/// repeatedly instead of growing without limit. Eviction is by insertion
/// order, which needs no per-hit bookkeeping; a most-recent entry in front of
/// the map keeps the common single-pattern statement from touching the map at
/// all.
///
/// A failed compile is cached with the same rules as a successful one, so a
/// statement with an invalid pattern reports the failure once per row without
/// retrying the failing compile.
///
public final class XLRegexpPatternCache: @unchecked Sendable {

    /// The most distinct patterns one registration keeps compiled.
    public static let capacity = 16

    /// Counts every compile, across every cache in this process.
    ///
    /// A `let` holding a class rather than a `static var`: a mutable global is
    /// not concurrency-safe, and is an error in the Swift 6 language mode.
    private static let statistics = Statistics()

    /// How many patterns every cache in this process has compiled between them.
    ///
    /// Avoiding a compile per row is the entire purpose of this type, and a
    /// cache that belongs to one registered SQLite function cannot be reached
    /// from outside the connection that owns it. This counter is how a test
    /// pins the number of compiles a scan performs. Read it before and after
    /// the work being measured and take the difference; nothing resets it, and
    /// nothing in the library reads it.
    public static var compilesInProcess: Int {
        statistics.total
    }

    /// The process-wide compile count.
    private final class Statistics: @unchecked Sendable {

        private let lock = NSLock()

        private var compiles = 0

        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return compiles
        }

        func record() {
            lock.lock()
            defer { lock.unlock() }
            compiles += 1
        }
    }

    /// A compiled pattern, or the failure compiling it produced.
    private typealias Entry = Result<Regex<AnyRegexOutput>, XLRegexpFunctionError>

    private let lock = NSLock()

    /// The last pattern asked for. Answers the single-pattern statement, which
    /// is nearly every statement, without a dictionary lookup or any eviction
    /// bookkeeping.
    private var mostRecent: (pattern: String, entry: Entry)?

    private var entries: [String: Entry] = [:]

    /// Patterns in the order they were first compiled, oldest first.
    private var insertionOrder: [String] = []

    private var compiles = 0

    /// How many patterns this cache has compiled.
    ///
    /// Read by the tests that pin the compile count for a scan. Nothing in the
    /// library reads it.
    public var numberOfCompiles: Int {
        lock.lock()
        defer { lock.unlock() }
        return compiles
    }

    /// How many patterns this cache currently holds.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// The compiled form of one pattern, compiling it only the first time.
    ///
    /// - Parameter pattern: The pattern text SQLite passed to the function.
    /// - Returns: The compiled regular expression.
    /// - Throws: ``XLRegexpFunctionError/invalidPattern(pattern:message:)`` if
    ///   the pattern does not compile, on this call and on every later call for
    ///   the same pattern.
    public init() {}

    public func regex(for pattern: String) throws -> Regex<AnyRegexOutput> {
        try entry(for: pattern).get()
    }

    private func entry(for pattern: String) -> Entry {
        lock.lock()
        if let mostRecent, mostRecent.pattern == pattern {
            defer { lock.unlock() }
            return mostRecent.entry
        }
        if let existing = entries[pattern] {
            mostRecent = (pattern, existing)
            lock.unlock()
            return existing
        }
        // Compile without holding the lock. Two callers racing on the same new
        // pattern would each compile it and store the same result, which costs
        // one extra compile and stays correct; holding the lock across a
        // compile would instead block every other pattern's lookup behind it.
        lock.unlock()

        Self.statistics.record()
        let compiled: Entry
        do {
            compiled = .success(try Regex(pattern))
        }
        catch {
            compiled = .failure(
                XLRegexpFunctionError.invalidPattern(
                    pattern: pattern,
                    message: String(describing: error)
                )
            )
        }

        lock.lock()
        defer { lock.unlock() }
        compiles += 1
        // A racing caller may have stored its own copy first. Keep that one, so
        // the cache never holds one value while it hands out another.
        if let existing = entries[pattern] {
            mostRecent = (pattern, existing)
            return existing
        }
        entries[pattern] = compiled
        insertionOrder.append(pattern)
        while insertionOrder.count > Self.capacity {
            let evicted = insertionOrder.removeFirst()
            entries.removeValue(forKey: evicted)
            if mostRecent?.pattern == evicted {
                mostRecent = nil
            }
        }
        mostRecent = (pattern, compiled)
        return compiled
    }
}
