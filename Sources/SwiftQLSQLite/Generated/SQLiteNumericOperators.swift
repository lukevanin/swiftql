//
//  SQLiteNumericOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Unary plus


public prefix func +<T>(operand: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}

public prefix func +<Wrapped>(operand: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}


// MARK: - Negate


public prefix func -<T>(operand: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}

public prefix func -<Wrapped>(operand: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}
