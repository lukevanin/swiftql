//
//  FakeSecondDialectComparableExpressionOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ComparableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - >


@_disfavoredOverload
func ><T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}


// MARK: - <


@_disfavoredOverload
func <<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}


// MARK: - >=

@_disfavoredOverload
func >=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}


// MARK: - <=


@_disfavoredOverload
func <=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}
