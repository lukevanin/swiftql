//
//  SQLiteEquatableExpressionOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
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


public func ==<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

public func ==<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


public func !=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

public func !=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}


// MARK: - NULL-safe comparison
//
// These treat `NULL` as a comparable value, so they yield `true` or `false`
// and never `NULL`. SQLite spells them `IS` and `IS NOT`; standard SQL spells
// them `IS NOT DISTINCT FROM` and `IS DISTINCT FROM`. The dialect's vocabulary
// decides the text (issue #692).

extension XLSQLiteExpression where T: XLEquatable {

    /// Returns whether this value equals the other, treating two `NULL`s as equal.
    public func isNotDistinctFrom(_ other: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value equals the other, treating two `NULL`s as equal.
    public func isNotDistinctFrom(_ other: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value differs from the other, treating two `NULL`s as equal.
    public func isDistinctFrom(_ other: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns whether this value differs from the other, treating two `NULL`s as equal.
    public func isDistinctFrom(_ other: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Bool> {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}


extension XLSQLiteExpression {

    /// Returns whether this nullable value equals the other, treating two `NULL`s as equal.
    public func isNotDistinctFrom<Wrapped>(_ other: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value equals the other, treating two `NULL`s as equal.
    public func isNotDistinctFrom<Wrapped>(_ other: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value differs from the other, treating two `NULL`s as equal.
    public func isDistinctFrom<Wrapped>(_ other: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }

    /// Returns whether this nullable value differs from the other, treating two `NULL`s as equal.
    public func isDistinctFrom<Wrapped>(_ other: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Bool> where T == Optional<Wrapped>, Wrapped: XLEquatable {
        XLComparisonExpression<Bool>(.nullSafeNotEqual, lhs: self, rhs: other)
    }
}
