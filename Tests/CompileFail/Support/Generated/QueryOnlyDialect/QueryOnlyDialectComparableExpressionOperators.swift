//
//  QueryOnlyDialectComparableExpressionOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ComparableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - >


func ><T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

func ><T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

func ><Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

func ><Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}


// MARK: - <


func <<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

func <<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

func <<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

func <<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}


// MARK: - >=

func >=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

func >=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

func >=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

func >=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}


// MARK: - <=


func <=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

func <=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

func <=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

func <=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}
