//
//  TextOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation



// MARK: - LIKE


///
/// A typed SQLite `LIKE` expression with an explicit `ESCAPE` clause.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// name.like(pattern, escape: "\\")
/// ```
///
/// *SQL:*
/// ```SQL
/// (name LIKE pattern ESCAPE '\')
/// ```
///
/// `ESCAPE` binds to its `LIKE`, so the three operands render as one grammar
/// production rather than a nested binary expression.
///
public struct XLLikeEscapeExpression<T>: XLExpression {

    private let term: any XLExpression

    private let pattern: any XLExpression

    private let escape: any XLExpression

    /// SwiftQL's dialect-surface SPI, for a dialect's generated operators: a
    /// node built here belongs to every dialect, so it is not public API
    /// (issue #822).
    @_spi(XLDialectSurface)
    public init(
        term: any XLExpression,
        pattern: any XLExpression,
        escape: any XLExpression
    ) {
        self.term = term
        self.pattern = pattern
        self.escape = escape
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                "LIKE",
                left: term.makeSQL,
                right: { context in
                    context.binaryOperator(
                        "ESCAPE",
                        left: pattern.makeSQL,
                        right: escape.makeSQL
                    )
                }
            )
        }
    }
}


// MARK: - REGEXP


///
/// A `REGEXP` comparison.
///
/// Renders exactly what ``XLBinaryOperatorExpression`` renders for the same
/// operands, and additionally records `XLCustomFunctionRegistration.bundledRegexp`
/// so the driver registers SwiftQL's own `regexp` implementation on whichever
/// connection executes the statement. Recording the registration is the only
/// reason this is a distinct type: a plain binary-operator node records nothing,
/// so before issue #612 the operator rendered SQL that SQLite could not prepare.
///
/// When the right operand is an ``XLRegexPattern``, the node also holds the
/// pattern, and records it on the registration, so the statement and every
/// request rendered from it keep the registration alive. The registry holds a
/// pattern weakly, so without this a pattern built as a local was released as
/// soon as the statement was built, and the statement then failed at
/// execution with `unregisteredPattern` (issue #646).
///
struct XLRegexpExpression<T>: XLSQLiteExpression {

    let lhs: any XLSQLiteExpression

    let rhs: any XLSQLiteExpression

    /// The pattern whose key `rhs` renders, or `nil` for a pattern string.
    let pattern: XLRegexPattern?

    init(lhs: any XLSQLiteExpression, rhs: any XLSQLiteExpression) {
        self.lhs = lhs
        self.rhs = rhs
        self.pattern = nil
    }

    init(lhs: any XLSQLiteExpression, pattern: XLRegexPattern) {
        self.lhs = lhs
        self.rhs = pattern.key
        self.pattern = pattern
    }

    func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.regexMatch(
                .matches,
                left: lhs.makeSQL,
                right: rhs.makeSQL,
                retaining: pattern.map { [$0] } ?? []
            )
        }
    }
}


extension XLSQLiteExpression {

    ///
    /// Matches `other` as a regular expression.
    ///
    /// SwiftQL supplies the implementation. SQLite parses `X REGEXP Y` as a
    /// call to `regexp(Y, X)` and ships no such function, so SwiftQL registers
    /// `XLRegexpFunction` on the connection that executes the statement. The
    /// pattern syntax, the match rule, and the NULL and error behaviour are
    /// described there.
    ///
    /// ```swift
    /// Where(person.name.regexp("^A.*n$"))
    /// ```
    ///
    /// An application that registers its own two-argument `regexp` keeps it;
    /// the bundled function never replaces one already on the connection.
    ///
    public func regexp(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Bool> where T == String {
        XLRegexpExpression<Bool>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == String {
        XLRegexpExpression<Optional<Bool>>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLRegexpExpression<Optional<Bool>>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLRegexpExpression<Optional<Bool>>(lhs: self, rhs: other)
    }

    ///
    /// Matches a Swift `Regex` rather than a pattern string.
    ///
    /// ```swift
    /// let leadingA = XLRegexPattern {
    ///     Anchor.startOfSubject
    ///     "A"
    ///     ZeroOrMore(.any)
    /// }
    ///
    /// Where(person.name.regexp(leadingA))
    /// ```
    ///
    /// A compiled `Regex` cannot be sent to SQLite, so the statement carries
    /// the pattern's key instead and the bundled `regexp` function resolves it.
    /// The statement holds the `XLRegexPattern`, and so does every request
    /// made from it, so the pattern stays registered for as long as either can
    /// execute. The key names a registration in this process, so do not build
    /// a static query descriptor from such a statement. Both rules are
    /// described on `XLRegexPattern`.
    ///
    public func regexp(_ pattern: XLRegexPattern) -> some XLSQLiteExpression<Bool> where T == String {
        XLRegexpExpression<Bool>(lhs: self, pattern: pattern)
    }

    public func regexp(_ pattern: XLRegexPattern) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLRegexpExpression<Optional<Bool>>(lhs: self, pattern: pattern)
    }
}


// MARK: - GLOB

// SQLite's own: `GLOB`. Declared only on a SQLite expression, not generated
// for every dialect (issue #789).



extension XLSQLiteExpression {
    
    public func glob(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
}
