//
//  SQLiteExpression.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Expression.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


///
/// An expression of a SQLite query.
///
/// The operators and functions of SQLite take and return
/// `XLSQLiteExpression`, so they compose a SQLite query's columns, its
/// values, and the expressions made from them, and nothing of another
/// dialect: comparing a column of a model declared for another dialect, or
/// calling a function SQLite does not have, is a compile error at the
/// call site.
///
/// These are SQLite expressions:
///
/// - A column of a model declared for SQLite.
/// - A Swift value (`Bool`, `Int`, `Double`, `String`, `Data`), an optional of
///   one, and a named binding. A value is written the same way in every
///   dialect, so it is an expression of every dialect.
/// - An enum or a custom type that conforms to this protocol. A protocol
///   cannot be made to refine this one from outside, so a type declares it:
///   `XLEnum` and `XLCustomType` include SQLite's, and a type used in another
///   dialect's query conforms to that dialect's protocol as well.
/// - A capture or contextual binding that encodes its value for
///   SQLite.
/// - The result of a SQLite operator or function, which returns
///   `some XLSQLiteExpression`.
///
/// A node built through its public initializer, such as
/// `XLBinaryOperatorExpression(op:lhs:rhs:)`, takes any expression and is an
/// expression of every dialect, so building one directly is not checked.
///
/// A helper that builds part of a query takes and returns this protocol:
///
/// ```swift
/// func isAdult(_ age: any XLSQLiteExpression<Int>) -> some XLSQLiteExpression<Bool> {
///     age >= 18
/// }
/// ```
///
public protocol XLSQLiteExpression<T>: XLExpression {
}


// MARK: - Columns and dialect-encoded values


extension XLColumnReference: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension XLColumnResult: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension XLDialectExpression: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension XLQueryCapture: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension XLContextualBindingReference: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}


// MARK: - Values


extension Bool: XLSQLiteExpression {
}

extension Int: XLSQLiteExpression {
}

extension Double: XLSQLiteExpression {
}

extension String: XLSQLiteExpression {
}

extension Data: XLSQLiteExpression {
}

extension Optional: XLSQLiteExpression where Wrapped: XLSQLiteExpression {
}

extension XLNamedBindingReference: XLSQLiteExpression {
}

extension XLAllColumns: XLSQLiteExpression {
}


// MARK: - Composed expressions


// An operator or a function of the dialect returns `some XLSQLiteExpression`,
// which hides the type of the node it builds. The node itself conforms for
// every dialect, and the opaque result is what keeps it in one.

extension XLUnaryOperatorExpression: XLSQLiteExpression {
}

extension XLPrefixOperatorExpression: XLSQLiteExpression {
}

extension XLPostfixOperatorExpression: XLSQLiteExpression {
}

extension XLComparisonExpression: XLSQLiteExpression {
}

extension XLNullTestExpression: XLSQLiteExpression {
}

extension XLBinaryOperatorExpression: XLSQLiteExpression {
}

extension XLConcatenationExpression: XLSQLiteExpression {
}

extension XLInValueExpression: XLSQLiteExpression {
}

extension XLInTableExpression: XLSQLiteExpression {
}

extension XLTypeCastExpression: XLSQLiteExpression {
}

extension XLTypeAffinityExpression: XLSQLiteExpression {
}

extension XLNullCoalesceExpression: XLSQLiteExpression {
}

extension XLIfExpression: XLSQLiteExpression {
}

extension XLFunction: XLSQLiteExpression {
}

extension XLLikeEscapeExpression: XLSQLiteExpression {
}

extension XLBetweenExpression: XLSQLiteExpression {
}
