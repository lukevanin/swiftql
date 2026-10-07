//
//  FakeSecondDialectIntegerOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/IntegerOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Bitwise NOT


@_disfavoredOverload
prefix func ~<T>(operand: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}

@_disfavoredOverload
prefix func ~<Wrapped>(operand: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}


// MARK: - Addition


@_disfavoredOverload
func +<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any FakeSecondDialectExpression< Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction


@_disfavoredOverload
func -<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication


@_disfavoredOverload
func *<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division


@_disfavoredOverload
func /<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}


// MARK: - Modulo


@_disfavoredOverload
func %<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

