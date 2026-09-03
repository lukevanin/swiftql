//
//  SQLRegexpFunction.swift
//  SwiftQL
//
//  The `regexp` implementation SwiftQL ships with, backed by Swift `Regex`.
//
//  Issue #612.
//

import Foundation
import GRDB


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
/// The two-argument `regexp` function SwiftQL registers for the `REGEXP`
/// operator.
///
/// SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and ships no
/// implementation of that function, so before issue #612 every query that used
/// the operator failed with `no such function: regexp` unless the application
/// registered a function itself. SwiftQL now supplies one, and
/// ``XLExpression/regexp(_:)`` records it while the statement renders, so a
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
/// - **An invalid pattern raises** ``XLRegexpFunctionError/invalidPattern(pattern:message:)``
///   rather than returning false, so a mistyped pattern is reported instead of
///   silently selecting no rows.
/// - **A non-text argument raises** ``XLColumnReadError``. SQLite stores values
///   without a fixed column type, so a TEXT column can hold an integer; TEXT
///   and UTF-8 BLOB are both read as text, and any other storage class is an
///   error rather than a silent conversion.
///
/// ## Replacing it
///
/// An application that registers its own two-argument `regexp` keeps it. The
/// bundled function is never registered on a connection that already provides
/// one, so an existing `GRDBDatabaseBuilder/addFunction(_:)` call or
/// `Configuration.prepareDatabase(_:)` registration continues to decide what
/// `REGEXP` means. See ``XLCustomFunctionRegistration/bundledRegexp``.
///
public enum XLRegexpFunction {

    /// The SQLite registration signature: `regexp(pattern, subject)`.
    public static let definition = XLCustomFunctionDefinition(
        name: "regexp",
        numberOfArguments: 2
    )

    /// Evaluates one `regexp(pattern, subject)` call.
    ///
    /// - Parameter reader: A reader positioned over the two function arguments.
    /// - Returns: Whether the pattern occurs in the subject, or `nil` when
    ///   either argument is NULL.
    static func evaluate(reader: some XLColumnReader) throws -> Bool? {
        // Argument 0 is the pattern and argument 1 is the subject: SQLite
        // rewrites `X REGEXP Y` to `regexp(Y, X)`, so the operator's right
        // operand arrives first.
        if try reader.isNull(at: 0) {
            return nil
        }
        if try reader.isNull(at: 1) {
            return nil
        }
        let pattern = try reader.readText(at: 0)
        let subject = try reader.readText(at: 1)
        return try matches(pattern: pattern, in: subject)
    }

    /// Whether `pattern` occurs anywhere in `subject`.
    static func matches(pattern: String, in subject: String) throws -> Bool {
        try compile(pattern).firstMatch(in: subject) != nil
    }

    /// Compiles one pattern, reporting a parse failure as a SwiftQL error.
    static func compile(_ pattern: String) throws -> Regex<AnyRegexOutput> {
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


extension XLCustomFunctionRegistration {

    ///
    /// Registration for the bundled ``XLRegexpFunction``.
    ///
    /// Recorded by every ``XLExpression/regexp(_:)`` overload while a statement
    /// renders, so the driver registers the function on whichever connection
    /// executes that statement.
    ///
    /// `defersToExistingRegistration` is `true`: an application that already
    /// provides `regexp` keeps it. Without that, registering here would replace
    /// the caller's function, because `sqlite3_create_function` replaces any
    /// earlier registration of the same name and argument count, and every
    /// caller-supplied registration necessarily runs earlier — both
    /// ``GRDBDatabaseBuilder/addFunction(_:)`` and
    /// `Configuration.prepareDatabase(_:)` run when a connection opens, and
    /// this runs when a statement is prepared.
    ///
    /// The function is declared pure. Its result depends only on its two
    /// arguments, which lets SQLite hoist a call whose arguments do not change
    /// between rows.
    ///
    static let bundledRegexp = XLCustomFunctionRegistration(
        definition: XLRegexpFunction.definition,
        defersToExistingRegistration: true,
        makeDatabaseFunction: {
            DatabaseFunction(
                XLRegexpFunction.definition.name,
                argumentCount: XLRegexpFunction.definition.numberOfArguments,
                pure: true,
                function: { values in
                    try XLRegexpFunction.evaluate(
                        reader: GRDBValuesAdapter(values: values)
                    )
                }
            )
        }
    )
}
