//
//  CompileFailSecondDialectExpressionConversions.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ExpressionConversions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension CompileFailSecondDialectExpression {

    @_disfavoredOverload
    func toRawValue() -> some CompileFailSecondDialectExpression<Int> where T: XLEnum, T.RawValue == Int {
        XLTypeAffinityExpression(expression: self)
    }

    @_disfavoredOverload
    func toRawValue() -> some CompileFailSecondDialectExpression<Double> where T: XLEnum, T.RawValue == Double {
        XLTypeAffinityExpression(expression: self)
    }

    @_disfavoredOverload
    func toRawValue() -> some CompileFailSecondDialectExpression<String> where T: XLEnum, T.RawValue == String {
        XLTypeAffinityExpression(expression: self)
    }
}


extension CompileFailSecondDialectExpression {

    ///
    /// Cast a non-null expression to an optional value expression.
    ///
    @_disfavoredOverload
    func toNullable() -> some CompileFailSecondDialectExpression<Optional<T>> {
        XLTypeAffinityExpression(expression: self)
    }
}
