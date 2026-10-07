//
//  FakeSecondDialectExpression.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


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
/// - A Swift value (`Bool`, `Int`, `Double`, `String`, `Data`), an optional of
///   one, and a named binding. A value is written the same way in every
///   dialect, so it is an expression of every dialect.
/// - An enum or a custom type that conforms to this protocol. A protocol
///   cannot be made to refine this one from outside, so a type declares it:
///   `XLEnum` and `XLCustomType` include SQLite's, and a type used in another
///   dialect's query conforms to that dialect's protocol as well.
/// - A capture or contextual binding that encodes its value for
///   the SQLTests second dialect.
/// - The result of a the SQLTests second dialect operator or function, which returns
///   `some FakeSecondDialectExpression`.
///
/// A node built through its public initializer, such as
/// `XLBinaryOperatorExpression(op:lhs:rhs:)`, takes any expression and is an
/// expression of every dialect, so building one directly is not checked.
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


// MARK: - The dialect's name for its expressions


extension FakeSecondDialect {

    ///
    /// Any expression of the SQLTests second dialect: `any FakeSecondDialectExpression<T>`.
    ///
    /// The macros type a model's value slots, such as an assignment in
    /// `Setting { row in ... }` and an argument of `columns(...)`, as
    /// `Dialect.XLAnyExpression<T>`, naming the expression protocol through
    /// the model's dialect type, so a slot takes only the SQLTests second dialect
    /// expressions and Swift values (issue #825).
    ///
    typealias XLAnyExpression<T> = any FakeSecondDialectExpression<T>
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

extension XLLegacyDynamicValueExpression: FakeSecondDialectExpression {
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
