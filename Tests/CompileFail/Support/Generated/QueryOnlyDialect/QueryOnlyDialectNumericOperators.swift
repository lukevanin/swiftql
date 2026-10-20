//
//  QueryOnlyDialectNumericOperators.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Unary plus


prefix func +<T>(operand: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}

prefix func +<Wrapped>(operand: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}


// MARK: - Negate


prefix func -<T>(operand: any QueryOnlyDialectExpression<T>) -> some QueryOnlyDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}

prefix func -<Wrapped>(operand: any QueryOnlyDialectExpression<Optional<Wrapped>>) -> some QueryOnlyDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}
