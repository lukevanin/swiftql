//
//  CompileFailSecondDialectComparableExpressionOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ComparableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - >


@_disfavoredOverload
func ><T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ><Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}


// MARK: - <


@_disfavoredOverload
func <<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}


// MARK: - >=

@_disfavoredOverload
func >=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func >=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}


// MARK: - <=


@_disfavoredOverload
func <=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func <=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}
