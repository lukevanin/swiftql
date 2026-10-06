//
//  RealOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Addition

public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction

public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication

public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division

public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}
