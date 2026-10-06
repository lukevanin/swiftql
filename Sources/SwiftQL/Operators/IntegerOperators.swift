//
//  IntegerOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


// MARK: - Bitwise NOT


public prefix func ~<T, D>(operand: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}

public prefix func ~<Wrapped, D>(operand: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}


// Keeps `~someInt` typed as `Int` on Swift 6.3. NumericOperators.swift explains
// why the exact-match overload is needed (issue #771).

public prefix func ~(operand: Int) -> Int {
    operand ^ -1
}


// MARK: - Addition


public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func +<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction


public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func -<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication


public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func *<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division


public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func /<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}


// MARK: - Modulo


public func %<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<T, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<T>, D> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func %<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Wrapped>, D> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

