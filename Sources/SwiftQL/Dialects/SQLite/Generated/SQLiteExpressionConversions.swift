//
//  SQLiteExpressionConversions.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ExpressionConversions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


extension XLSQLiteExpression {

    public func toRawValue() -> some XLSQLiteExpression<Int> where T: XLEnumRepresentable, T.RawValue == Int {
        XLTypeAffinityExpression(expression: self)
    }

    public func toRawValue() -> some XLSQLiteExpression<Double> where T: XLEnumRepresentable, T.RawValue == Double {
        XLTypeAffinityExpression(expression: self)
    }

    public func toRawValue() -> some XLSQLiteExpression<String> where T: XLEnumRepresentable, T.RawValue == String {
        XLTypeAffinityExpression(expression: self)
    }
}


extension XLSQLiteExpression {

    ///
    /// Cast a non-null expression to an optional value expression.
    ///
    public func toNullable() -> some XLSQLiteExpression<Optional<T>> {
        XLTypeAffinityExpression(expression: self)
    }
}
