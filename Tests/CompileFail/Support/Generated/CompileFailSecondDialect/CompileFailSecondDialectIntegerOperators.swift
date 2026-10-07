//
//  CompileFailSecondDialectIntegerOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/IntegerOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Bitwise NOT


@_disfavoredOverload
prefix func ~<T>(operand: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}

@_disfavoredOverload
prefix func ~<Wrapped>(operand: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}


// MARK: - Addition


@_disfavoredOverload
func +<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any CompileFailSecondDialectExpression< Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func +<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction


@_disfavoredOverload
func -<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func -<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication


@_disfavoredOverload
func *<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func *<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division


@_disfavoredOverload
func /<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func /<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}


// MARK: - Modulo


@_disfavoredOverload
func %<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func %<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

