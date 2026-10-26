//
//  QueryOnlyDialectEquatableExpressionOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/EquatableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Equality
//
// An optional operand makes the result `Optional<Bool>`: SQL's `=` and `<>`
// yield `NULL` when either operand is `NULL`, as the ordering operators do. To
// compare `NULL` as a value, use `isNotDistinctFrom(_:)` and
// `isDistinctFrom(_:)` below (issue #692).


func ==<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

func ==<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

func ==<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

func ==<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


func !=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

func !=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

func !=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

func !=<Wrapped>(lhs: any QueryOnlyDialectExpression<Optional<Wrapped>>, rhs: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Comparison with nil
//
// `expression == nil` tests the expression for `NULL` in SQL, as `isNull()`
// does, and `expression != nil` tests it as `notNull()` does. Without these
// overloads, Swift's own `Optional == nil` compares the expression value itself
// with `nil`, which is a constant, so the clause rendered `WHERE 0` or
// `WHERE 1` (issue #847).


func ==<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: _OptionalNilComparisonType) -> some QueryOnlyDialectExpression<Bool> {
    XLNullTestExpression(.isNull, operand: lhs)
}

func ==<T>(lhs: _OptionalNilComparisonType, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> {
    XLNullTestExpression(.isNull, operand: rhs)
}

func !=<T>(lhs: any QueryOnlyDialectExpression<T>, rhs: _OptionalNilComparisonType) -> some QueryOnlyDialectExpression<Bool> {
    XLNullTestExpression(.isNotNull, operand: lhs)
}

func !=<T>(lhs: _OptionalNilComparisonType, rhs: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> {
    XLNullTestExpression(.isNotNull, operand: rhs)
}


// MARK: - NULL-safe comparison
//
// These treat `NULL` as a comparable value, so they yield `true` or `false`
// and never `NULL`. SQLite spells them `IS` and `IS NOT`; standard SQL spells
// them `IS NOT DISTINCT FROM` and `IS DISTINCT FROM`. The dialect's vocabulary
// decides the text (issue #692).

extension QueryOnlyDialectExpression where T: XLEquatable {

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    func isNotDistinctFrom(_ other: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    func isNotDistinctFrom(_ other: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    func isDistinctFrom(_ other: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    func isDistinctFrom(_ other: any QueryOnlyDialectExpression<Optional<T>>) -> some QueryOnlyDialectExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}


extension QueryOnlyDialectExpression {

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    func isNotDistinctFrom<Wrapped>(_ other: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value equals the other or both are `NULL`, and `false` otherwise. Never `NULL`.
    func isNotDistinctFrom<Wrapped>(_ other: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    func isDistinctFrom<Wrapped>(_ other: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns `true` if this value differs from the other or only one is `NULL`, and `false` if they are equal or both are `NULL`. Never `NULL`.
    func isDistinctFrom<Wrapped>(_ other: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}
