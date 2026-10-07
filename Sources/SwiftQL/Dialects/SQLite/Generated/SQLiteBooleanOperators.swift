//
//  SQLiteBooleanOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BooleanOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation



// MARK: - NOT


///
/// Inverts a boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
public prefix func !(operand: any XLSQLiteExpression<Bool>) -> some XLSQLiteExpression<Bool> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


///
/// Inverts an optional boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `nil` if the `operand` is `nil`, or `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
public prefix func !(operand: any XLSQLiteExpression<Optional<Bool>>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
public func &&(lhs: any XLSQLiteExpression<Bool>, rhs: any XLSQLiteExpression<Bool>) -> some XLSQLiteExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
public func &&(lhs: any XLSQLiteExpression<Bool>, rhs: any XLSQLiteExpression<Optional<Bool>>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
public func &&(lhs: any XLSQLiteExpression<Optional<Bool>>, rhs: any XLSQLiteExpression<Bool>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
public func &&(lhs: any XLSQLiteExpression<Optional<Bool>>, rhs: any XLSQLiteExpression<Optional<Bool>>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


public func ||(lhs: any XLSQLiteExpression<Bool>, rhs: any XLSQLiteExpression<Bool>) -> some XLSQLiteExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLSQLiteExpression<Bool>, rhs: any XLSQLiteExpression<Optional<Bool>>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLSQLiteExpression<Optional<Bool>>, rhs: any XLSQLiteExpression<Bool>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public  func ||(lhs: any XLSQLiteExpression<Optional<Bool>>, rhs: any XLSQLiteExpression<Optional<Bool>>) -> some XLSQLiteExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
