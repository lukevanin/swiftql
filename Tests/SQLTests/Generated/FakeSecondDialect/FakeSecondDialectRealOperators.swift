//
//  FakeSecondDialectRealOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/RealOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Addition

@_disfavoredOverload
func +<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction

@_disfavoredOverload
func -<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication

@_disfavoredOverload
func *<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division

@_disfavoredOverload
func /<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}
