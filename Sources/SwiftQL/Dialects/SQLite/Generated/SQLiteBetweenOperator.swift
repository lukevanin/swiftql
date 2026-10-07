//
//  SQLiteBetweenOperator.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BetweenOperator.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


extension XLSQLiteExpression where T: XLComparable {

    /// Returns whether this expression is inclusively between two compatible bounds.
    public func isBetween(
        _ minimum: any XLSQLiteExpression<T>,
        _ maximum: any XLSQLiteExpression<T>
    ) -> some XLSQLiteExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns whether this expression is outside two compatible inclusive bounds.
    public func isNotBetween(
        _ minimum: any XLSQLiteExpression<T>,
        _ maximum: any XLSQLiteExpression<T>
    ) -> some XLSQLiteExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}


extension XLSQLiteExpression {

    /// Returns `nil` for a `NULL` expression, or whether its value is inclusively between the bounds.
    public func isBetween<Wrapped>(
        _ minimum: any XLSQLiteExpression<Wrapped>,
        _ maximum: any XLSQLiteExpression<Wrapped>
    ) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns `nil` for a `NULL` expression, or whether its value is outside the bounds.
    public func isNotBetween<Wrapped>(
        _ minimum: any XLSQLiteExpression<Wrapped>,
        _ maximum: any XLSQLiteExpression<Wrapped>
    ) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}
