//
//  RealOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Addition

public func +<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction

public func -<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication

public func *<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division

public func /<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}
