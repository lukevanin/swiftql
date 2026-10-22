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


// MARK: - NULL-safe comparison
//
// These treat `NULL` as a comparable value, so they yield `true` or `false`
// and never `NULL`. SQLite spells them `IS` and `IS NOT`; standard SQL spells
// them `IS NOT DISTINCT FROM` and `IS DISTINCT FROM`. The dialect's vocabulary
// decides the text (issue #692).

extension FakeSecondDialectExpression where T: XLEquatable {

    /// Returns whether this value equals the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isNotDistinctFrom(_ other: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value equals the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isNotDistinctFrom(_ other: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value differs from the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isDistinctFrom(_ other: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value differs from the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isDistinctFrom(_ other: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}


extension FakeSecondDialectExpression {

    /// Returns whether this nullable value equals the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isNotDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value equals the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isNotDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value differs from the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value differs from the other, treating two `NULL`s as equal.
    @_disfavoredOverload
    func isDistinctFrom<Wrapped>(_ other: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}
