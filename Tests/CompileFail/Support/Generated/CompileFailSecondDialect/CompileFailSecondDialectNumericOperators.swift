//
//  CompileFailSecondDialectNumericOperators.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Unary plus


@_disfavoredOverload
prefix func +<T>(operand: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}

@_disfavoredOverload
prefix func +<Wrapped>(operand: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}


// MARK: - Negate


@_disfavoredOverload
prefix func -<T>(operand: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}

@_disfavoredOverload
prefix func -<Wrapped>(operand: any CompileFailSecondDialectExpression<Optional<Wrapped>>) -> some CompileFailSecondDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}
