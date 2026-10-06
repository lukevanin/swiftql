//
//  FakeSecondDialectExpression.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


///
/// An expression of a the SQLTests second dialect query.
///
/// The operators and functions of the SQLTests second dialect take and return
/// `FakeSecondDialectExpression`, so they compose a the SQLTests second dialect query's columns, its
/// values, and the expressions made from them, and nothing of another
/// dialect: comparing a column of a model declared for another dialect, or
/// calling a function the SQLTests second dialect does not have, is a compile error at the
/// call site.
///
/// These are the SQLTests second dialect expressions:
///
/// - A column of a model declared for the SQLTests second dialect.
/// - A Swift value, an optional of one, a named binding, an enum, and a custom
///   type. A value is written the same way in every dialect, so it is an
///   expression of every dialect.
/// - A capture or contextual binding that encodes its value for
///   the SQLTests second dialect.
/// - The result of a the SQLTests second dialect operator or function, which returns
///   `some FakeSecondDialectExpression`.
///
/// A helper that builds part of a query takes and returns this protocol:
///
/// ```swift
/// func isAdult(_ age: any FakeSecondDialectExpression<Int>) -> some FakeSecondDialectExpression<Bool> {
///     age >= 18
/// }
/// ```
///
protocol FakeSecondDialectExpression<T>: XLExpression {
}


// MARK: - Columns and dialect-encoded values


extension XLColumnReference: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension XLColumnResult: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension XLDialectExpression: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension XLQueryCapture: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension XLContextualBindingReference: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}


// MARK: - Values


extension Bool: FakeSecondDialectExpression {
}

extension Int: FakeSecondDialectExpression {
}

extension Double: FakeSecondDialectExpression {
}

extension String: FakeSecondDialectExpression {
}

extension Data: FakeSecondDialectExpression {
}

extension Optional: FakeSecondDialectExpression where Wrapped: FakeSecondDialectExpression {
}

extension XLNamedBindingReference: FakeSecondDialectExpression {
}

extension XLAllColumns: FakeSecondDialectExpression {
}


// MARK: - Composed expressions


// An operator or a function of the dialect returns `some FakeSecondDialectExpression`,
// which hides the type of the node it builds. The node itself conforms for
// every dialect, and the opaque result is what keeps it in one.

extension XLUnaryOperatorExpression: FakeSecondDialectExpression {
}

extension XLPrefixOperatorExpression: FakeSecondDialectExpression {
}

extension XLPostfixOperatorExpression: FakeSecondDialectExpression {
}

extension XLComparisonExpression: FakeSecondDialectExpression {
}

extension XLNullTestExpression: FakeSecondDialectExpression {
}

extension XLBinaryOperatorExpression: FakeSecondDialectExpression {
}

extension XLConcatenationExpression: FakeSecondDialectExpression {
}

extension XLInValueExpression: FakeSecondDialectExpression {
}

extension XLInTableExpression: FakeSecondDialectExpression {
}

extension XLTypeCastExpression: FakeSecondDialectExpression {
}

extension XLTypeAffinityExpression: FakeSecondDialectExpression {
}

extension XLNullCoalesceExpression: FakeSecondDialectExpression {
}

extension XLIfExpression: FakeSecondDialectExpression {
}

extension XLFunction: FakeSecondDialectExpression {
}

extension XLLikeEscapeExpression: FakeSecondDialectExpression {
}

extension XLBetweenExpression: FakeSecondDialectExpression {
}
