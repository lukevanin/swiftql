//
//  SQLRegexpMatching.swift
//  SwiftQLCore
//
//  Matching a SQLite REGEXP pattern with Swift `Regex`, and compiling each
//  pattern once per statement instead of once per row.
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
}


extension XLRegexpFunctionError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .invalidPattern(let pattern, let message):
            return "Invalid REGEXP pattern '\(pattern)': \(message)"
        }
    }
}


extension XLRegexpFunctionError: LocalizedError {

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

    /// Whether `pattern` occurs anywhere in `subject`.
    ///
    /// - Parameters:
    ///   - pattern: The pattern text.
    ///   - subject: The text searched.
    ///   - cache: Holds the compiled form of each pattern already seen, so a
    ///     scan compiles one pattern once rather than once per row. A caller
    ///     that passes none compiles on every call.
    /// - Throws: ``XLRegexpFunctionError/invalidPattern(pattern:message:)`` if
    ///   the pattern does not compile.
    public static func matches(
        pattern: String,
        in subject: String,
        cache: XLRegexpPatternCache? = nil
    ) throws -> Bool {
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
/// `XLCustomFunctionRegistration.bundledRegexp` each time the driver
/// registers the function on a connection. It is never shared between
/// connections, and it is not a process-wide cache:
///
/// - Swift's `Regex` is not `Sendable`. Sharing one compiled value between the
///   pooled connections that match with it concurrently would be exactly the
///   sharing the type does not promise is safe. Confining a cache to the
///   registration that created it means a compiled `Regex` is only ever matched
///   against by the one connection that compiled it.
/// - A cache that outlived a statement would have to decide when a pattern
///   built from user input stops being worth keeping. One that lives as long as
///   one registration does not: the patterns it holds are the patterns the
///   statement being prepared can present.
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
/// parameter SQLite binds once per execution. The bound exists for the case
/// that does not hold -- a pattern read from a *column*, which can differ on
/// every row -- so that such a statement compiles repeatedly instead of
/// growing the cache without limit. Eviction is by insertion order, which needs
/// no per-hit bookkeeping; a most-recent entry in front of the map keeps the
/// common single-pattern statement from touching the map at all.
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
