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
