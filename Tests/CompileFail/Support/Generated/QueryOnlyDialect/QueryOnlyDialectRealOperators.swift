//
//  QueryOnlyDialectRealOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/RealOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Addition

func +<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

func +<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

func +<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

func +<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction

func -<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

func -<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

func -<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

func -<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication

func *<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

func *<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

func *<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

func *<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division

func /<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

func /<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<T>> where T: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

func /<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

func /<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: BinaryFloatingPoint {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}
