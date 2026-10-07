//
//  FakeSecondDialectEquatableExpressionOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/EquatableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Equality


@_disfavoredOverload
func ==<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


@_disfavoredOverload
func !=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}
