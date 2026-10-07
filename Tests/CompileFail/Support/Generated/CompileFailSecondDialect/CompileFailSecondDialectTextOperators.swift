//
//  CompileFailSecondDialectTextOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/TextOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Concatenation


@_disfavoredOverload
func +(lhs: any CompileFailSecondDialectExpression<String>, rhs: any CompileFailSecondDialectExpression<String>) -> some CompileFailSecondDialectExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any CompileFailSecondDialectExpression<String>, rhs: any CompileFailSecondDialectExpression<Optional<String>>) -> some CompileFailSecondDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any CompileFailSecondDialectExpression<Optional<String>>, rhs: any CompileFailSecondDialectExpression<String>) -> some CompileFailSecondDialectExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +(lhs: any CompileFailSecondDialectExpression<Optional<String>>, rhs: any CompileFailSecondDialectExpression<Optional<String>>) -> some CompileFailSecondDialectExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


// MARK: - LIKE


extension CompileFailSecondDialectExpression {

    @_disfavoredOverload
    func like(_ other: any CompileFailSecondDialectExpression<String>) -> some CompileFailSecondDialectExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any CompileFailSecondDialectExpression<Optional<String>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any CompileFailSecondDialectExpression<String>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    @_disfavoredOverload
    func like(_ other: any CompileFailSecondDialectExpression<Optional<String>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
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
    @_disfavoredOverload
    func like(
        _ other: any CompileFailSecondDialectExpression<String>,
        escape: any CompileFailSecondDialectExpression<String>
    ) -> some CompileFailSecondDialectExpression<Bool> where T == String {
        XLLikeEscapeExpression<Bool>(term: self, pattern: other, escape: escape)
    }

    @_disfavoredOverload
    func like(
        _ other: any CompileFailSecondDialectExpression<Optional<String>>,
        escape: any CompileFailSecondDialectExpression<String>
    ) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == String {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    @_disfavoredOverload
    func like(
        _ other: any CompileFailSecondDialectExpression<String>,
        escape: any CompileFailSecondDialectExpression<String>
    ) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    @_disfavoredOverload
    func like(
        _ other: any CompileFailSecondDialectExpression<Optional<String>>,
        escape: any CompileFailSecondDialectExpression<String>
    ) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }
}
