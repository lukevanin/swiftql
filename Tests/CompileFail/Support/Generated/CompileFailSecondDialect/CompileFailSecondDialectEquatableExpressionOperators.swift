//
//  CompileFailSecondDialectEquatableExpressionOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/EquatableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - Equality


@_disfavoredOverload
func ==<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


@_disfavoredOverload
func !=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<T>(lhs: any CompileFailSecondDialectExpression<T>, rhs: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>, rhs: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}
