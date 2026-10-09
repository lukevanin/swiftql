//
//  SQLiteOptionalOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/OptionalOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension XLSQLiteExpression {
 
    public func coalesce<Wrapped>(_ expression: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    public static func ??<Wrapped>(lhs: Self, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

extension XLSQLiteExpression {
    
    public func isNull<Wrapped>() -> some XLSQLiteExpression<Bool> where T == Optional<Wrapped> {
        XLNullTestExpression(.isNull, operand: self)
    }
}


// MARK: - notNull

extension XLSQLiteExpression {
    
    public func notNull() -> some XLSQLiteExpression<Bool> where T: ExpressibleByNilLiteral {
        XLNullTestExpression(.isNotNull, operand: self)
    }
}
