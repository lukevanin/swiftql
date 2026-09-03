//
//  SQLRegexPatternRegistry.swift
//  SwiftQLCore
//
//  Matching a REGEXP operand against a Swift `Regex` value rather than a
//  pattern string.
//
//  Issue #614.
//

import Foundation
import RegexBuilder


///
/// A `Regex` value usable as the right operand of `REGEXP`.
///
/// A string pattern gives up everything Swift offers over a raw regular
/// expression: no compile-time check, no composition, and no way to build a
/// pattern from named pieces. `RegexBuilder` provides all three, but a compiled
/// `Regex` cannot be sent to SQLite -- SQLite carries only text, integers,
/// reals, blobs, and nulls.
///
/// This type closes that gap. It registers the `Regex` and takes a key that
/// *can* travel through SQLite; the bundled `regexp` function resolves the key
/// back to the `Regex` when SQLite calls it.
///
/// ```swift
/// let leadingA = XLRegexPattern {
///     Anchor.startOfSubject
///     "A"
///     ZeroOrMore(.any)
///     "n"
///     Anchor.endOfSubject
/// }
///
/// let statement = sql { schema in
///     let person = schema.table(Person.self)
///     Select(person)
///     From(person)
///     Where(person.name.regexp(leadingA))
/// }
/// ```
///
/// ## Ownership
///
/// The registry does **not** keep your pattern alive. Hold the
/// ``XLRegexPattern`` -- in a `static let`, or a stored property -- for as long
/// as statements using it can still execute. A pattern that has been released
/// leaves its key unresolvable, and executing a statement that carries it
/// raises ``XLRegexpFunctionError/unregisteredPattern(key:)`` naming the key,
/// rather than silently matching nothing.
///
/// Weak ownership is deliberate. Retaining every pattern would leak one entry
/// for every pattern an application ever builds, and evicting from a bounded
/// table would break a pattern that is still in use, under load, with no way
/// for the caller to see it coming. Not retaining gives a caller who builds a
/// pattern per request a clear error the first time they try it.
///
/// ## Keys are process-local
///
/// A key names a registration in one process, so the SQL a statement renders is
/// meaningful only in the process that rendered it. Do not turn a statement
/// using an ``XLRegexPattern`` into a static query descriptor: a descriptor is
/// database-independent build metadata, and `XLStaticStatementDefinition`
/// rejects one for exactly this reason.
///
/// ## Captures
///
/// The registry stores the erased form. `REGEXP` answers only whether a subject
/// matches, so captures are not exposed and a `Regex`'s output type is not
/// carried. Use the `Regex` directly in Swift when you need its captures.
///
public struct XLRegexPattern: Sendable {

    private let registration: XLRegexRegistration

    /// The text this pattern renders as the right operand of `REGEXP`.
    ///
    /// Not a pattern: it names this registration, and cannot be read as a
    /// regular expression.
    public var key: String {
        registration.key
    }

    /// Registers a compiled `Regex`.
    ///
    /// - Parameter regex: The regular expression to match with. Its output type
    ///   is erased; see the note on captures.
    public init<Output>(_ regex: Regex<Output>) {
        self.registration = XLRegexPatternRegistry.shared.register(
            Regex<AnyRegexOutput>(regex)
        )
    }

    /// Registers a pattern written with `RegexBuilder`.
    ///
    /// - Parameter content: Builds the regular expression.
    public init<Content: RegexComponent>(
        @RegexComponentBuilder _ content: () -> Content
    ) {
        self.init(content().regex)
    }

    /// Whether `subject` matches this pattern.
    public func matches(_ subject: String) -> Bool {
        registration.matches(subject)
    }
}


///
/// One registered ``XLRegexPattern``.
///
/// Matching holds a lock. Swift's `Regex` is not `Sendable`, and one
/// registration is reachable from every pooled connection at once, so two
/// connections matching against the same pattern would otherwise share a value
/// the standard library does not promise is safe to share. A match is short and
/// a lock is uncontended unless two connections use the same pattern at the
/// same moment, which is the case that has to serialize. The lock can go when
/// `Regex` conforms to `Sendable`.
///
final class XLRegexRegistration: @unchecked Sendable {

    let key: String

    private let lock = NSLock()

    private let regex: Regex<AnyRegexOutput>

    init(key: String, regex: Regex<AnyRegexOutput>) {
        self.key = key
        self.regex = regex
    }

    deinit {
        XLRegexPatternRegistry.shared.remove(key: key)
    }

    /// Whether `subject` matches, treating a thrown match as no match.
    ///
    /// A `Regex` the caller built is already compiled, so this never compiles
    /// anything and never consults the pattern cache.
    ///
    /// `firstMatch(in:)` can still throw: a `RegexBuilder` pattern may carry a
    /// capture transform that throws, and `REGEXP` has nowhere to put that
    /// failure -- the operator answers a yes-or-no question about one row, and
    /// captures are not exposed at all, so the transform's result is discarded
    /// either way. A throw is therefore read as "this row does not match"
    /// rather than failing the statement. Write the transform to be total, or
    /// match in Swift, if a failing transform has to be visible.
    ///
    /// `try?` flattens the optional it wraps, so one `guard let` covers both
    /// answers that mean no match: the call threw, or it found nothing.
    func matches(_ subject: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard (try? regex.firstMatch(in: subject)) != nil else {
            return false
        }
        return true
    }
}


///
/// The ``XLRegexPattern`` registrations this process can resolve.
///
/// Keyed dispatch, not a second pattern language: the key SQLite carries is an
/// opaque name, and this is the only thing that can read it.
///
public enum XLRegexPatternRegistry {

    /// The registry every ``XLRegexPattern`` registers with.
    static let shared = Storage()

    ///
    /// The key form: a marker, this process's registrations, and a number.
    ///
    /// Both delimiters are U+0001, which is not a character anyone writes in a
    /// regular expression. That is what keeps a key apart from a pattern
    /// without a second argument or a second operator spelling: a plain pattern
    /// is passed through untouched unless it carries the marker, and one that
    /// carries the marker but names no registration is reported rather than
    /// matched, because it can only have come from a pattern that no longer
    /// exists.
    ///
    static let marker = "\u{1}swiftql.regex\u{1}"

    /// The key for one registration number.
    static func key(forIdentifier identifier: Int) -> String {
        "\(marker)\(identifier)\u{1}"
    }

    /// Whether `text` is a registry key rather than a pattern.
    public static func isKey(_ text: String) -> Bool {
        text.hasPrefix(marker) && text.hasSuffix("\u{1}")
    }

    /// Whether rendered SQL carries a registry key anywhere in it.
    ///
    /// Used to refuse a static query descriptor built from a statement that
    /// uses an ``XLRegexPattern``: a key names a registration in one process,
    /// and a descriptor is meant to be reproducible build metadata.
    public static func textContainsKey(_ text: String) -> Bool {
        text.contains(marker)
    }

    /// The pattern `key` names, or `nil` if this process has none.
    static func registration(forKey key: String) -> XLRegexRegistration? {
        shared.registration(forKey: key)
    }

    /// The registrations, and the counter that names them.
    final class Storage: @unchecked Sendable {

        private let lock = NSLock()

        private var nextIdentifier = 0

        /// Weak, so a pattern's lifetime is the caller's to decide. See the
        /// ownership note on ``XLRegexPattern``.
        private var entries: [String: WeakRegistration] = [:]

        func register(_ regex: Regex<AnyRegexOutput>) -> XLRegexRegistration {
            lock.lock()
            let identifier = nextIdentifier
            nextIdentifier += 1
            lock.unlock()

            let registration = XLRegexRegistration(
                key: XLRegexPatternRegistry.key(forIdentifier: identifier),
                regex: regex
            )

            lock.lock()
            defer { lock.unlock() }
            entries[registration.key] = WeakRegistration(registration)
            return registration
        }

        func registration(forKey key: String) -> XLRegexRegistration? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]?.registration
        }

        func remove(key: String) {
            lock.lock()
            defer { lock.unlock() }
            // Unconditional. A key is never reused, so an entry under this key
            // can only ever be the registration that is deinitializing. Making
            // it conditional on the weak reference already reading `nil` would
            // tie correctness to exactly when the runtime zeroes a weak
            // reference during deallocation, and leave a dead entry behind for
            // ever if that timing were not what it is assumed to be.
            entries.removeValue(forKey: key)
        }

        /// The registrations this process can still resolve. Read by tests.
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.values.filter { $0.registration != nil }.count
        }

        /// Every entry the table holds, resolvable or not. Read by the test
        /// that pins that a released pattern leaves nothing behind.
        var storedEntryCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.count
        }
    }

    private struct WeakRegistration {
        weak var registration: XLRegexRegistration?

        init(_ registration: XLRegexRegistration) {
            self.registration = registration
        }
    }

    static func remove(key: String) {
        shared.remove(key: key)
    }
}
