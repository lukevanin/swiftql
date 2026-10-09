//
//  QueryOnlyDialectExpression.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


///
/// An expression of a the query-only compile-fail dialect query.
///
/// The operators and functions of the query-only compile-fail dialect take and return
/// `QueryOnlyDialectExpression`, so they compose a the query-only compile-fail dialect query's columns, its
/// values, and the expressions made from them, and nothing of another
/// dialect: comparing a column of a model declared for another dialect, or
/// calling a function the query-only compile-fail dialect does not have, is a compile error at the
/// call site.
///
/// These are the query-only compile-fail dialect expressions:
///
/// - A column of a model declared for the query-only compile-fail dialect.
/// - A Swift value (`Bool`, `Int`, `Double`, `String`, `Data`), an optional of
///   one, and a named binding. A value is written the same way in every
///   dialect, so it is an expression of every dialect.
/// - An enum or a custom type that conforms to this protocol. A protocol
///   cannot be made to refine this one from outside, so a type declares it,
///   usually through `QueryOnlyDialectEnum` or `QueryOnlyDialectCustomType`, and a type used in
///   another dialect's query conforms to that dialect's composition as well.
/// - A capture or contextual binding that encodes its value for
///   the query-only compile-fail dialect.
/// - The result of a the query-only compile-fail dialect operator or function, which returns
///   `some QueryOnlyDialectExpression`.
///
/// A node built through its public initializer, such as
/// `XLBinaryOperatorExpression(op:lhs:rhs:)`, takes any expression and is an
/// expression of every dialect, so building one directly is not checked.
///
/// A helper that builds part of a query takes and returns this protocol:
///
/// ```swift
/// func isAdult(_ age: any QueryOnlyDialectExpression<Int>) -> some QueryOnlyDialectExpression<Bool> {
///     age >= 18
/// }
/// ```
///
protocol QueryOnlyDialectExpression<T>: XLExpression {
}


// MARK: - Enums and custom types


///
/// An enum that is a the query-only compile-fail dialect value: a column of a model declared for
/// the query-only compile-fail dialect, and an operand of its operators and functions.
///
/// `XLEnumRepresentable` holds the requirements and their defaults, and names
/// no dialect. An enum used in several dialects conforms to each dialect's
/// composition, or to a composition of its own (issue #790).
///
typealias QueryOnlyDialectEnum = XLEnumRepresentable & QueryOnlyDialectExpression

///
/// A custom scalar type that is a the query-only compile-fail dialect value: it binds to, reads
/// from, and renders into a the query-only compile-fail dialect query.
///
/// `XLCustomValue` holds the requirements, and names no dialect. A type used
/// in several dialects conforms to each dialect's composition, or to a
/// composition of its own (issue #790).
///
typealias QueryOnlyDialectCustomType = XLCustomValue & QueryOnlyDialectExpression


// MARK: - The dialect's name for its expressions


extension QueryOnlyDialect {

    ///
    /// Any expression of the query-only compile-fail dialect: `any QueryOnlyDialectExpression<T>`.
    ///
    /// The macros type a model's value slots, such as an assignment in
    /// `Setting { row in ... }` and an argument of `columns(...)`, as
    /// `Dialect.XLAnyExpression<T>`, naming the expression protocol through
    /// the model's dialect type, so a slot takes only the query-only compile-fail dialect
    /// expressions and Swift values (issue #825).
    ///
    typealias XLAnyExpression<T> = any QueryOnlyDialectExpression<T>
}


// MARK: - Columns and dialect-encoded values


extension XLColumnReference: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension XLColumnResult: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension XLDialectExpression: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension XLQueryCapture: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension XLContextualBindingReference: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}


// MARK: - Values


extension Bool: QueryOnlyDialectExpression {
}

extension Int: QueryOnlyDialectExpression {
}

extension Double: QueryOnlyDialectExpression {
}

extension String: QueryOnlyDialectExpression {
}

extension Data: QueryOnlyDialectExpression {
}

extension Optional: QueryOnlyDialectExpression where Wrapped: QueryOnlyDialectExpression {
}

extension XLNamedBindingReference: QueryOnlyDialectExpression {
}

extension XLAllColumns: QueryOnlyDialectExpression {
}


// MARK: - Composed expressions


// An operator or a function of the dialect returns `some QueryOnlyDialectExpression`,
// which hides the type of the node it builds. The node itself conforms for
// every dialect, and the opaque result is what keeps it in one.

extension XLUnaryOperatorExpression: QueryOnlyDialectExpression {
}

extension XLPrefixOperatorExpression: QueryOnlyDialectExpression {
}

extension XLPostfixOperatorExpression: QueryOnlyDialectExpression {
}

extension XLComparisonExpression: QueryOnlyDialectExpression {
}

extension XLNullTestExpression: QueryOnlyDialectExpression {
}

extension XLBinaryOperatorExpression: QueryOnlyDialectExpression {
}

extension XLConcatenationExpression: QueryOnlyDialectExpression {
}

extension XLInValueExpression: QueryOnlyDialectExpression {
}

extension XLInTableExpression: QueryOnlyDialectExpression {
}

extension XLTypeCastExpression: QueryOnlyDialectExpression {
}

extension XLTypeAffinityExpression: QueryOnlyDialectExpression {
}

extension XLNullCoalesceExpression: QueryOnlyDialectExpression {
}

extension XLIfExpression: QueryOnlyDialectExpression {
}

extension XLFunction: QueryOnlyDialectExpression {
}

extension XLLikeEscapeExpression: QueryOnlyDialectExpression {
}

extension XLBetweenExpression: QueryOnlyDialectExpression {
}

extension XLNullExpression: QueryOnlyDialectExpression {
}
