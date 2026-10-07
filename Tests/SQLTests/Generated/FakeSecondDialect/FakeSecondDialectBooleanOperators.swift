//
//  FakeSecondDialectBooleanOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BooleanOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL



// MARK: - NOT


///
/// Inverts a boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
@_disfavoredOverload
prefix func !(operand: any FakeSecondDialectExpression<Bool>) -> some FakeSecondDialectExpression<Bool> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


///
/// Inverts an optional boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `nil` if the `operand` is `nil`, or `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
@_disfavoredOverload
prefix func !(operand: any FakeSecondDialectExpression<Optional<Bool>>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
@_disfavoredOverload
func &&(lhs: any FakeSecondDialectExpression<Bool>, rhs: any FakeSecondDialectExpression<Bool>) -> some FakeSecondDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
@_disfavoredOverload
func &&(lhs: any FakeSecondDialectExpression<Bool>, rhs: any FakeSecondDialectExpression<Optional<Bool>>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
@_disfavoredOverload
func &&(lhs: any FakeSecondDialectExpression<Optional<Bool>>, rhs: any FakeSecondDialectExpression<Bool>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
@_disfavoredOverload
func &&(lhs: any FakeSecondDialectExpression<Optional<Bool>>, rhs: any FakeSecondDialectExpression<Optional<Bool>>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


@_disfavoredOverload
func ||(lhs: any FakeSecondDialectExpression<Bool>, rhs: any FakeSecondDialectExpression<Bool>) -> some FakeSecondDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any FakeSecondDialectExpression<Bool>, rhs: any FakeSecondDialectExpression<Optional<Bool>>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any FakeSecondDialectExpression<Optional<Bool>>, rhs: any FakeSecondDialectExpression<Bool>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any FakeSecondDialectExpression<Optional<Bool>>, rhs: any FakeSecondDialectExpression<Optional<Bool>>) -> some FakeSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
