//
//  QueryOnlyDialectOptionalOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/OptionalOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension QueryOnlyDialectExpression {
 
    func coalesce<Wrapped>(_ expression: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    static func ??<Wrapped>(lhs: Self, rhs: any QueryOnlyDialectExpression<Wrapped>) -> some QueryOnlyDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

extension QueryOnlyDialectExpression {
    
    func isNull<Wrapped>() -> some QueryOnlyDialectExpression<Bool> where T == Optional<Wrapped> {
        XLNullTestExpression(.isNull, operand: self)
    }
}


// MARK: - notNull

extension QueryOnlyDialectExpression {
    
    func notNull() -> some QueryOnlyDialectExpression<Bool> where T: ExpressibleByNilLiteral {
        XLNullTestExpression(.isNotNull, operand: self)
    }
}
