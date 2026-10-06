//
//  FakeSecondDialectOptionalOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/OptionalOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension FakeSecondDialectExpression {
 
    @_disfavoredOverload
    func coalesce<Wrapped>(_ expression: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    @_disfavoredOverload
    static func ??<Wrapped>(lhs: Self, rhs: any FakeSecondDialectExpression<Wrapped>) -> some FakeSecondDialectExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

extension FakeSecondDialectExpression {
    
    @_disfavoredOverload
    func isNull<Wrapped>() -> some FakeSecondDialectExpression<Bool> where T == Optional<Wrapped> {
        XLNullTestExpression(.isNull, operand: self)
    }
}


// MARK: - notNull

extension FakeSecondDialectExpression {
    
    @_disfavoredOverload
    func notNull() -> some FakeSecondDialectExpression<Bool> where T: ExpressibleByNilLiteral {
        XLNullTestExpression(.isNotNull, operand: self)
    }
}
