//
//  SQLiteEquatableExpressionOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/EquatableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Equality


public func ==<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

public func ==<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


public func !=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

public func !=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}
