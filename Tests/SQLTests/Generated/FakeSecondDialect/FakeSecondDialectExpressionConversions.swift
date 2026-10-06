//
//  FakeSecondDialectExpressionConversions.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ExpressionConversions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension FakeSecondDialectExpression {

    @_disfavoredOverload
    func toRawValue() -> some FakeSecondDialectExpression<Int> where T: XLEnum, T.RawValue == Int {
        XLTypeAffinityExpression(expression: self)
    }

    @_disfavoredOverload
    func toRawValue() -> some FakeSecondDialectExpression<Double> where T: XLEnum, T.RawValue == Double {
        XLTypeAffinityExpression(expression: self)
    }

    @_disfavoredOverload
    func toRawValue() -> some FakeSecondDialectExpression<String> where T: XLEnum, T.RawValue == String {
        XLTypeAffinityExpression(expression: self)
    }
}


extension FakeSecondDialectExpression {

    ///
    /// Cast a non-null expression to an optional value expression.
    ///
    @_disfavoredOverload
    func toNullable() -> some FakeSecondDialectExpression<Optional<T>> {
        XLTypeAffinityExpression(expression: self)
    }
}
