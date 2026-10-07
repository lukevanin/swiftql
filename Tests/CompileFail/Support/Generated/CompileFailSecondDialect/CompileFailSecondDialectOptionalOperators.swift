//
//  CompileFailSecondDialectOptionalOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/OptionalOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension CompileFailSecondDialectExpression {
 
    @_disfavoredOverload
    func coalesce<Wrapped>(_ expression: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    @_disfavoredOverload
    static func ??<Wrapped>(lhs: Self, rhs: any CompileFailSecondDialectExpression<Wrapped>) -> some CompileFailSecondDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

extension CompileFailSecondDialectExpression {
    
    @_disfavoredOverload
    func isNull<Wrapped>() -> some CompileFailSecondDialectExpression<Bool> where T == Optional<Wrapped> {
        XLNullTestExpression(.isNull, operand: self)
    }
}


// MARK: - notNull

extension CompileFailSecondDialectExpression {
    
    @_disfavoredOverload
    func notNull() -> some CompileFailSecondDialectExpression<Bool> where T: ExpressibleByNilLiteral {
        XLNullTestExpression(.isNotNull, operand: self)
    }
}
