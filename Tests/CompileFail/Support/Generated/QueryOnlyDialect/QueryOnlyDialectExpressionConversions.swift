//
//  QueryOnlyDialectExpressionConversions.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ExpressionConversions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension QueryOnlyDialectExpression {

    func toRawValue() -> some QueryOnlyDialectExpression<Int> where T: XLEnumRepresentable, T.RawValue == Int {
        XLTypeAffinityExpression(expression: self)
    }

    func toRawValue() -> some QueryOnlyDialectExpression<Double> where T: XLEnumRepresentable, T.RawValue == Double {
        XLTypeAffinityExpression(expression: self)
    }

    func toRawValue() -> some QueryOnlyDialectExpression<String> where T: XLEnumRepresentable, T.RawValue == String {
        XLTypeAffinityExpression(expression: self)
    }
}


extension QueryOnlyDialectExpression {

    ///
    /// Cast a non-null expression to an optional value expression.
    ///
    func toNullable() -> some QueryOnlyDialectExpression<Optional<T>> {
        XLTypeAffinityExpression(expression: self)
    }
}
