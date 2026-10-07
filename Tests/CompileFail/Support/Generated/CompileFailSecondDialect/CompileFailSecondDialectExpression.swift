//
//  CompileFailSecondDialectExpression.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


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
/// - A Swift value (`Bool`, `Int`, `Double`, `String`, `Data`), an optional of
///   one, and a named binding. A value is written the same way in every
///   dialect, so it is an expression of every dialect.
/// - An enum or a custom type that conforms to this protocol. A protocol
///   cannot be made to refine this one from outside, so a type declares it:
///   `XLEnum` and `XLCustomType` include SQLite's, and a type used in another
///   dialect's query conforms to that dialect's protocol as well.
/// - A capture or contextual binding that encodes its value for
///   the compile-fail second dialect.
/// - The result of a the compile-fail second dialect operator or function, which returns
///   `some CompileFailSecondDialectExpression`.
///
/// A node built through its public initializer, such as
/// `XLBinaryOperatorExpression(op:lhs:rhs:)`, takes any expression and is an
/// expression of every dialect, so building one directly is not checked.
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


// MARK: - The dialect's name for its expressions


extension CompileFailSecondDialect {

    ///
    /// Any expression of the compile-fail second dialect: `any CompileFailSecondDialectExpression<T>`.
    ///
    /// The macros type a model's value slots, such as an assignment in
    /// `Setting { row in ... }` and an argument of `columns(...)`, as
    /// `Dialect.XLAnyExpression<T>`, naming the expression protocol through
    /// the model's dialect type, so a slot takes only the compile-fail second dialect
    /// expressions and Swift values (issue #825).
    ///
    typealias XLAnyExpression<T> = any CompileFailSecondDialectExpression<T>
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

extension XLLegacyDynamicValueExpression: CompileFailSecondDialectExpression {
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
