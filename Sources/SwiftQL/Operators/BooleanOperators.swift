//
//  BooleanOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
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
public prefix func !(operand: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


///
/// Inverts an optional boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `nil` if the `operand` is `nil`, or `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
public prefix func !(operand: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
public func &&(lhs: any XLExpression<Bool>, rhs: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
public func &&(lhs: any XLExpression<Bool>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
public func &&(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Bool>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
public func &&(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


public func ||(lhs: any XLExpression<Bool>, rhs: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLExpression<Bool>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Bool>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public  func ||(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
