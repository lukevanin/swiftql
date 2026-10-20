//
//  QueryOnlyDialectTextOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/TextOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Concatenation


func +(lhs: any QueryOnlyDialectExpression<String>, rhs: any QueryOnlyDialectExpression<String>) -> some QueryOnlyDialectExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

func +(lhs: any QueryOnlyDialectExpression<String>, rhs: any QueryOnlyDialectExpression<Optional<String>>) -> some QueryOnlyDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

func +(lhs: any QueryOnlyDialectExpression<Optional<String>>, rhs: any QueryOnlyDialectExpression<String>) -> some QueryOnlyDialectExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

func +(lhs: any QueryOnlyDialectExpression<Optional<String>>, rhs: any QueryOnlyDialectExpression<Optional<String>>) -> some QueryOnlyDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


// MARK: - LIKE


extension QueryOnlyDialectExpression {

    func like(_ other: any QueryOnlyDialectExpression<String>) -> some QueryOnlyDialectExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    func like(_ other: any QueryOnlyDialectExpression<Optional<String>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    func like(_ other: any QueryOnlyDialectExpression<String>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    func like(_ other: any QueryOnlyDialectExpression<Optional<String>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    ///
    /// Matches `other` as a `LIKE` pattern in which `escape` marks the next
    /// character as a literal, so `%` and `_` can be matched exactly.
    ///
    /// `escape` must evaluate to a single character. In SQLite a longer or
    /// empty value prepares successfully and then fails when the statement is
    /// stepped, with `ESCAPE expression must be a single character`. That is a
    /// constraint on the value, not something the Swift type can express.
    ///
    func like(
        _ other: any QueryOnlyDialectExpression<String>,
        escape: any QueryOnlyDialectExpression<String>
    ) -> some QueryOnlyDialectExpression<Bool> where T == String {
        XLLikeEscapeExpression<Bool>(term: self, pattern: other, escape: escape)
    }

    func like(
        _ other: any QueryOnlyDialectExpression<Optional<String>>,
        escape: any QueryOnlyDialectExpression<String>
    ) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == String {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    func like(
        _ other: any QueryOnlyDialectExpression<String>,
        escape: any QueryOnlyDialectExpression<String>
    ) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    func like(
        _ other: any QueryOnlyDialectExpression<Optional<String>>,
        escape: any QueryOnlyDialectExpression<String>
    ) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }
}
