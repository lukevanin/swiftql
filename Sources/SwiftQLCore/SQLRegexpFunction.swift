//
//  SQLRegexpFunction.swift
//  SwiftQLCore
//
//  The `regexp` implementation SwiftQL ships with, backed by Swift `Regex`.
//
//  Issue #612. Moved to SwiftQLCore and written over SQLite values rather
//  than a GRDB function (issue #683), so every adapter, and the SQLite build
//  validator, installs the same implementation.
//

import Foundation


///
/// The two-argument `regexp` function SwiftQL registers for the `REGEXP`
/// operator.
///
/// SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and ships no
/// implementation of that function, so before issue #612 every query that used
/// the operator failed with `no such function: regexp` unless the application
/// registered a function itself. SwiftQL now supplies one, and
/// `XLExpression.regexp(_:)` records it while the statement renders, so a
/// query executes without any registration by the caller.
///
/// ## Behaviour
///
/// SQLite defines no regular-expression dialect of its own, so this function
/// defines SwiftQL's:
///
/// - **Pattern syntax** is Swift's regular-expression syntax, as accepted by
///   `Regex.init(_:)`.
/// - **A pattern matches anywhere in the subject.** `"alpha-123" REGEXP
///   '[0-9]+$'` is true, because the pattern is searched for rather than
///   matched against the whole subject. Anchor the pattern with `^` and `$` to
///   require a whole-subject match. This follows the widely used `regexp`
///   extensions for SQLite, and PostgreSQL's `~` operator.
/// - **A NULL argument yields NULL**, on either side of the operator, which is
///   what SQL three-valued logic requires of a comparison.
/// - **An invalid pattern raises** `XLRegexpFunctionError.invalidPattern`
///   rather than returning false, so a mistyped pattern is reported instead of
///   silently selecting no rows.
/// - **A non-text argument raises** ``XLColumnReadError``. SQLite stores values
///   without a fixed column type, so a TEXT column can hold an integer; TEXT
///   and UTF-8 BLOB are both read as text, and any other storage class is an
///   error rather than a silent conversion.
/// - **An oversized operand raises** `XLRegexpLengthLimitError`. A pattern
///   string longer than `XLRegexpMatcher.maximumPatternLength` or a subject
///   longer than `XLRegexpMatcher.maximumSubjectLength` is refused before it
///   is compiled or matched, never truncated. The limits reduce how long one
///   match can run, but they do not stop an exponential pattern, so validate
///   a pattern that comes from untrusted input.
///
/// These errors are raised inside SQLite, which keeps only their text. The
/// statement fails, and the caller receives an `XLDatabaseError` whose
/// `XLDatabaseError.message` is the raised error's description, such as the
/// invalid pattern and why it is invalid. The typed error does not reach the
/// caller, so `catch let error as XLRegexpFunctionError` around a fetch does
/// not match. When you need the typed error, check a pattern with
/// `XLRegexpMatcher.matches(pattern:in:cache:)` before it reaches a statement.
///
/// ## Cost
///
/// SQLite calls the function once per candidate row and passes the pattern each
/// time. The driver installs the function once per physical connection, and
/// that installation keeps one `XLRegexpPatternCache`. While a pattern stays in
/// that cache, the connection only matches with it, however many rows and
/// statements test it. The cache keeps at most `XLRegexpPatternCache.capacity`
/// compiled patterns and evicts the oldest first, so a connection that sees
/// more distinct patterns than that -- for example, patterns read from a column
/// or built from user input -- compiles an evicted pattern again the next time
/// it appears.
///
/// ## Replacing it
///
/// An application that registers its own two-argument `regexp` keeps it. The
/// bundled function is never registered on a connection that already provides
/// one, so an existing `GRDBDatabaseBuilder.addFunction(_:)` call or
/// GRDB `Configuration.prepareDatabase(_:)` registration continues to decide what
/// `REGEXP` means.
///
public enum XLRegexpFunction {

    /// The SQLite registration signature: `regexp(pattern, subject)`.
    public static let definition = XLCustomFunctionDefinition(
        name: "regexp",
        numberOfArguments: 2
    )

    /// Evaluates one `regexp(pattern, subject)` call.
    ///
    /// - Parameters:
    ///   - arguments: The call's two arguments, as SQLite passes them.
    ///   - cache: Holds the compiled form of each pattern this installation
    ///     has already seen, so a scan compiles one pattern once rather than
    ///     once per row. A caller that passes none compiles on every call.
    /// - Returns: Whether the pattern occurs in the subject, or `nil` when
    ///   either argument is NULL.
    /// - Throws: `XLColumnReadError` for a missing or non-text argument, and
    ///   the errors `XLRegexpMatcher.matches(pattern:in:cache:)` raises.
    public static func evaluate(
        _ arguments: [XLSQLiteValue],
        cache: XLRegexpPatternCache? = nil
    ) throws -> Bool? {
        // Argument 0 is the pattern and argument 1 is the subject: SQLite
        // rewrites `X REGEXP Y` to `regexp(Y, X)`, so the operator's right
        // operand arrives first.
        // Either NULL yields NULL before either argument is read as text, so a
        // NULL beside a non-text value is still NULL rather than an error.
        if arguments.indices.contains(0), arguments[0] == .null {
            return nil
        }
        if arguments.indices.contains(1), arguments[1] == .null {
            return nil
        }
        guard
            let pattern = try text(at: 0, in: arguments),
            let subject = try text(at: 1, in: arguments)
        else {
            return nil
        }
        return try XLRegexpMatcher.matches(
            pattern: pattern,
            in: subject,
            cache: cache
        )
    }

    /// The argument at `index` as text, or `nil` when it is NULL.
    ///
    /// TEXT and UTF-8 BLOB read as text, as a SwiftQL column reader reads
    /// them. Any other storage class is an error rather than a silent
    /// conversion.
    private static func text(at index: Int, in arguments: [XLSQLiteValue]) throws -> String? {
        guard arguments.indices.contains(index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: "String",
                failure: .indexOutOfBounds(valueCount: arguments.count)
            )
        }
        switch arguments[index] {
        case .null:
            return nil
        case .text(let text):
            return text
        case .blob(let blob):
            if let text = String(data: blob, encoding: .utf8) {
                return text
            }
            throw typeMismatch(at: index, storageClass: "BLOB")
        case .integer:
            throw typeMismatch(at: index, storageClass: "INTEGER")
        case .real:
            throw typeMismatch(at: index, storageClass: "REAL")
        }
    }

    private static func typeMismatch(at index: Int, storageClass: String) -> XLColumnReadError {
        XLColumnReadError(
            index: index,
            expectedType: "String",
            failure: .typeMismatch(actualType: storageClass)
        )
    }
}
