//
//  TextOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation



// MARK: - Concatenation


public func +(lhs: any XLExpression<String>, rhs: any XLExpression<String>) -> some XLExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<String>, rhs: any XLExpression<Optional<String>>) -> some XLExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<Optional<String>>, rhs: any XLExpression<String>) -> some XLExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<Optional<String>>, rhs: any XLExpression<Optional<String>>) -> some XLExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


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

    init(
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


extension XLExpression {

    public func like(_ other: any XLExpression<String>) -> some XLExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLExpression<String>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    ///
    /// Matches `other` as a `LIKE` pattern in which `escape` marks the next
    /// character as a literal, so `%` and `_` can be matched exactly.
    ///
    /// SQLite requires `escape` to evaluate to a single character. A longer or
    /// empty value prepares successfully and then fails when the statement is
    /// stepped, with `ESCAPE expression must be a single character`. That is a
    /// constraint on the value, not something the Swift type can express.
    ///
    public func like(
        _ other: any XLExpression<String>,
        escape: any XLExpression<String>
    ) -> some XLExpression<Bool> where T == String {
        XLLikeEscapeExpression<Bool>(term: self, pattern: other, escape: escape)
    }

    public func like(
        _ other: any XLExpression<Optional<String>>,
        escape: any XLExpression<String>
    ) -> some XLExpression<Optional<Bool>> where T == String {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    public func like(
        _ other: any XLExpression<String>,
        escape: any XLExpression<String>
    ) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    public func like(
        _ other: any XLExpression<Optional<String>>,
        escape: any XLExpression<String>
    ) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
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
struct XLRegexpExpression<T>: XLExpression {

    let lhs: any XLExpression

    let rhs: any XLExpression

    /// The pattern whose key `rhs` renders, or `nil` for a pattern string.
    let pattern: XLRegexPattern?

    init(lhs: any XLExpression, rhs: any XLExpression) {
        self.lhs = lhs
        self.rhs = rhs
        self.pattern = nil
    }

    init(lhs: any XLExpression, pattern: XLRegexPattern) {
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


extension XLExpression {

    ///
    /// Matches `other` as a regular expression.
    ///
    /// SwiftQL supplies the implementation. SQLite parses `X REGEXP Y` as a
    /// call to `regexp(Y, X)` and ships no such function, so SwiftQL registers
    /// ``XLRegexpFunction`` on the connection that executes the statement. The
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
    public func regexp(_ other: any XLExpression<String>) -> some XLExpression<Bool> where T == String {
        XLRegexpExpression<Bool>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == String {
        XLRegexpExpression<Optional<Bool>>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLExpression<String>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLRegexpExpression<Optional<Bool>>(lhs: self, rhs: other)
    }

    public func regexp(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
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
    public func regexp(_ pattern: XLRegexPattern) -> some XLExpression<Bool> where T == String {
        XLRegexpExpression<Bool>(lhs: self, pattern: pattern)
    }

    public func regexp(_ pattern: XLRegexPattern) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLRegexpExpression<Optional<Bool>>(lhs: self, pattern: pattern)
    }
}


// MARK: - GLOB


extension XLExpression {
    
    public func glob(_ other: any XLExpression<String>) -> some XLExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<String>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
}
