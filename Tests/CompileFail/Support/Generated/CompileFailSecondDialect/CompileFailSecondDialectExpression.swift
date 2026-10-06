//
//  CompileFailSecondDialectExpression.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


///
/// An expression of a the compile-fail second dialect query.
///
/// The operators and functions of the compile-fail second dialect take and return
/// `CompileFailSecondDialectExpression`, so they compose a the compile-fail second dialect query's columns, its
/// values, and the expressions made from them, and nothing of another
/// dialect: comparing a column of a model declared for another dialect, or
/// calling a function the compile-fail second dialect does not have, is a compile error at the
/// call site.
///
/// These are the compile-fail second dialect expressions:
///
/// - A column of a model declared for the compile-fail second dialect.
/// - A Swift value, an optional of one, a named binding, an enum, and a custom
///   type. A value is written the same way in every dialect, so it is an
///   expression of every dialect.
/// - A capture or contextual binding that encodes its value for
///   the compile-fail second dialect.
/// - The result of a the compile-fail second dialect operator or function, which returns
///   `some CompileFailSecondDialectExpression`.
///
/// A helper that builds part of a query takes and returns this protocol:
///
/// ```swift
/// func isAdult(_ age: any CompileFailSecondDialectExpression<Int>) -> some CompileFailSecondDialectExpression<Bool> {
///     age >= 18
/// }
/// ```
///
protocol CompileFailSecondDialectExpression<T>: XLExpression {
}


// MARK: - Columns and dialect-encoded values


extension XLColumnReference: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension XLColumnResult: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension XLDialectExpression: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension XLQueryCapture: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension XLContextualBindingReference: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}


// MARK: - Values


extension Bool: CompileFailSecondDialectExpression {
}

extension Int: CompileFailSecondDialectExpression {
}

extension Double: CompileFailSecondDialectExpression {
}

extension String: CompileFailSecondDialectExpression {
}

extension Data: CompileFailSecondDialectExpression {
}

extension Optional: CompileFailSecondDialectExpression where Wrapped: CompileFailSecondDialectExpression {
}

extension XLNamedBindingReference: CompileFailSecondDialectExpression {
}

extension XLAllColumns: CompileFailSecondDialectExpression {
}


// MARK: - Composed expressions


// An operator or a function of the dialect returns `some CompileFailSecondDialectExpression`,
// which hides the type of the node it builds. The node itself conforms for
// every dialect, and the opaque result is what keeps it in one.

extension XLUnaryOperatorExpression: CompileFailSecondDialectExpression {
}

extension XLPrefixOperatorExpression: CompileFailSecondDialectExpression {
}

extension XLPostfixOperatorExpression: CompileFailSecondDialectExpression {
}

extension XLComparisonExpression: CompileFailSecondDialectExpression {
}

extension XLNullTestExpression: CompileFailSecondDialectExpression {
}

extension XLBinaryOperatorExpression: CompileFailSecondDialectExpression {
}

extension XLConcatenationExpression: CompileFailSecondDialectExpression {
}

extension XLInValueExpression: CompileFailSecondDialectExpression {
}

extension XLInTableExpression: CompileFailSecondDialectExpression {
}

extension XLTypeCastExpression: CompileFailSecondDialectExpression {
}

extension XLTypeAffinityExpression: CompileFailSecondDialectExpression {
}

extension XLNullCoalesceExpression: CompileFailSecondDialectExpression {
}

extension XLIfExpression: CompileFailSecondDialectExpression {
}

extension XLFunction: CompileFailSecondDialectExpression {
}

extension XLLikeEscapeExpression: CompileFailSecondDialectExpression {
}

extension XLBetweenExpression: CompileFailSecondDialectExpression {
}
