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
//
// An optional operand makes the result `Optional<Bool>`: SQL's `=` and `<>`
// yield `NULL` when either operand is `NULL`, as the ordering operators do. To
// compare `NULL` as a value, use `isNotDistinctFrom(_:)` and
// `isDistinctFrom(_:)` below (issue #692).


@_disfavoredOverload
func ==<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func ==<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


@_disfavoredOverload
func !=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
func !=<Wrapped>(lhs: any FakeSecondDialectExpression<Optional<Wrapped>>, rhs: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Comparison with nil
//
// `expression == nil` tests the expression for `NULL` in SQL, as `isNull()`
// does, and `expression != nil` tests it as `notNull()` does. Without these
// overloads, Swift's own `Optional == nil` compares the expression value itself
// with `nil`, which is a constant, so the clause rendered `WHERE 0` or
// `WHERE 1` (issue #847).


@_disfavoredOverload
func ==<T>(lhs: any FakeSecondDialectExpression<T>, rhs: _OptionalNilComparisonType) -> some FakeSecondDialectExpression<Bool> {
    XLNullTestExpression(.isNull, operand: lhs)
}

@_disfavoredOverload
func ==<T>(lhs: _OptionalNilComparisonType, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
    XLNullTestExpression(.isNull, operand: rhs)
}

@_disfavoredOverload
func !=<T>(lhs: any FakeSecondDialectExpression<T>, rhs: _OptionalNilComparisonType) -> some FakeSecondDialectExpression<Bool> {
    XLNullTestExpression(.isNotNull, operand: lhs)
}

@_disfavoredOverload
func !=<T>(lhs: _OptionalNilComparisonType, rhs: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
    XLNullTestExpression(.isNotNull, operand: rhs)
}


// MARK: - NULL-safe comparison
//
// These treat `NULL` as a comparable value, so they yield `true` or `false`
// and never `NULL`. SQLite spells them `IS` and `IS NOT`; standard SQL spells
// them `IS NOT DISTINCT FROM` and `IS DISTINCT FROM`. The dialect's vocabulary
// decides the text (issue #692).

extension FakeSecondDialectExpression where T: XLEquatable {

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    @_disfavoredOverload
    func isNotDistinctFrom(_ other: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    @_disfavoredOverload
    func isNotDistinctFrom(_ other: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    @_disfavoredOverload
    func isDistinctFrom(_ other: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    @_disfavoredOverload
    func isDistinctFrom(_ other: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}


extension FakeSecondDialectExpression {

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    @_disfavoredOverload
    func isNotDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    @_disfavoredOverload
    func isNotDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    @_disfavoredOverload
    func isDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    @_disfavoredOverload
    func isDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}
