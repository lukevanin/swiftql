//
//  CompileFailSecondDialectBooleanOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
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
prefix func !(operand: any CompileFailSecondDialectExpression<Bool>) -> some CompileFailSecondDialectExpression<Bool> {
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
prefix func !(operand: any CompileFailSecondDialectExpression<Optional<Bool>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
@_disfavoredOverload
func &&(lhs: any CompileFailSecondDialectExpression<Bool>, rhs: any CompileFailSecondDialectExpression<Bool>) -> some CompileFailSecondDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
@_disfavoredOverload
func &&(lhs: any CompileFailSecondDialectExpression<Bool>, rhs: any CompileFailSecondDialectExpression<Optional<Bool>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
@_disfavoredOverload
func &&(lhs: any CompileFailSecondDialectExpression<Optional<Bool>>, rhs: any CompileFailSecondDialectExpression<Bool>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
@_disfavoredOverload
func &&(lhs: any CompileFailSecondDialectExpression<Optional<Bool>>, rhs: any CompileFailSecondDialectExpression<Optional<Bool>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


@_disfavoredOverload
func ||(lhs: any CompileFailSecondDialectExpression<Bool>, rhs: any CompileFailSecondDialectExpression<Bool>) -> some CompileFailSecondDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any CompileFailSecondDialectExpression<Bool>, rhs: any CompileFailSecondDialectExpression<Optional<Bool>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any CompileFailSecondDialectExpression<Optional<Bool>>, rhs: any CompileFailSecondDialectExpression<Bool>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ||(lhs: any CompileFailSecondDialectExpression<Optional<Bool>>, rhs: any CompileFailSecondDialectExpression<Optional<Bool>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
