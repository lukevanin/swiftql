//
//  FakeSecondDialectTextOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/TextOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - Concatenation


@_disfavoredOverload
func +(lhs: any FakeSecondDialectExpression<String>, rhs: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any FakeSecondDialectExpression<String>, rhs: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any FakeSecondDialectExpression<Optional<String>>, rhs: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any FakeSecondDialectExpression<Optional<String>>, rhs: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


// MARK: - LIKE


extension FakeSecondDialectExpression {

    @_disfavoredOverload
    func like(_ other: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
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
    @_disfavoredOverload
    func like(
        _ other: any FakeSecondDialectExpression<String>,
        escape: any FakeSecondDialectExpression<String>
    ) -> some FakeSecondDialectExpression<Bool> where T == String {
        XLLikeEscapeExpression<Bool>(term: self, pattern: other, escape: escape)
    }

    @_disfavoredOverload
    func like(
        _ other: any FakeSecondDialectExpression<Optional<String>>,
        escape: any FakeSecondDialectExpression<String>
    ) -> some FakeSecondDialectExpression<Optional<Bool>> where T == String {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    @_disfavoredOverload
    func like(
        _ other: any FakeSecondDialectExpression<String>,
        escape: any FakeSecondDialectExpression<String>
    ) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    @_disfavoredOverload
    func like(
        _ other: any FakeSecondDialectExpression<Optional<String>>,
        escape: any FakeSecondDialectExpression<String>
    ) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }
}


// MARK: - GLOB


extension FakeSecondDialectExpression {
    
    @_disfavoredOverload
    func glob(_ other: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    @_disfavoredOverload
    func glob(_ other: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    @_disfavoredOverload
    func glob(_ other: any FakeSecondDialectExpression<String>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    @_disfavoredOverload
    func glob(_ other: any FakeSecondDialectExpression<Optional<String>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
}
