//
//  QueryOnlyDialectBooleanOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BooleanOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery



// MARK: - NOT


///
/// Inverts a boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
prefix func !(operand: any QueryOnlyDialectExpression<Bool>) -> some QueryOnlyDialectExpression<Bool> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


///
/// Inverts an optional boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `nil` if the `operand` is `nil`, or `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
prefix func !(operand: any QueryOnlyDialectExpression<Optional<Bool>>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
func &&(lhs: any QueryOnlyDialectExpression<Bool>, rhs: any QueryOnlyDialectExpression<Bool>) -> some QueryOnlyDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
func &&(lhs: any QueryOnlyDialectExpression<Bool>, rhs: any QueryOnlyDialectExpression<Optional<Bool>>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
func &&(lhs: any QueryOnlyDialectExpression<Optional<Bool>>, rhs: any QueryOnlyDialectExpression<Bool>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
func &&(lhs: any QueryOnlyDialectExpression<Optional<Bool>>, rhs: any QueryOnlyDialectExpression<Optional<Bool>>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


func ||(lhs: any QueryOnlyDialectExpression<Bool>, rhs: any QueryOnlyDialectExpression<Bool>) -> some QueryOnlyDialectExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

func ||(lhs: any QueryOnlyDialectExpression<Bool>, rhs: any QueryOnlyDialectExpression<Optional<Bool>>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

func ||(lhs: any QueryOnlyDialectExpression<Optional<Bool>>, rhs: any QueryOnlyDialectExpression<Bool>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

func ||(lhs: any QueryOnlyDialectExpression<Optional<Bool>>, rhs: any QueryOnlyDialectExpression<Optional<Bool>>) -> some QueryOnlyDialectExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
