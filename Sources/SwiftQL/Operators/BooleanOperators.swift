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
public prefix func !<D>(operand: any XLExpression<Bool, D>) -> some XLExpression<Bool, D> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


///
/// Inverts an optional boolean expression.
///
/// - Parameter operand: The expression to invert.
///
/// - Returns: `nil` if the `operand` is `nil`, or `false` if the `operand` is `true`, or `true` if the `operand` is `false`.
///
public prefix func !<D>(operand: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


///
/// Performs a boolean AND operation on two boolean expressions.
///
public func &&<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Bool, XLUniversalDialect>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Bool, XLUniversalDialect>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on a boolean expression and an optional boolean expression.
///
public func &&<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Optional<Bool>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Bool, XLUniversalDialect>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on an optional boolean expression and a boolean expression.
///
public func &&<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Bool, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Optional<Bool>, XLUniversalDialect>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

///
/// Performs a boolean AND operation on two optional boolean expressions.
///
public func &&<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Optional<Bool>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func &&<D>(lhs: any XLExpression<Optional<Bool>, XLUniversalDialect>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


public func ||<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Bool, XLUniversalDialect>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Bool, XLUniversalDialect>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Bool, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Bool, D>, rhs: any XLExpression<Optional<Bool>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Bool, XLUniversalDialect>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Bool, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Optional<Bool>, XLUniversalDialect>, rhs: any XLExpression<Bool, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Optional<Bool>, D>, rhs: any XLExpression<Optional<Bool>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ||<D>(lhs: any XLExpression<Optional<Bool>, XLUniversalDialect>, rhs: any XLExpression<Optional<Bool>, D>) -> some XLExpression<Optional<Bool>, D> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
