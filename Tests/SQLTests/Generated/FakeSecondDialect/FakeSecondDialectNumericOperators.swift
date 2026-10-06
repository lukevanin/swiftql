//
//  FakeSecondDialectNumericOperators.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - Unary plus


@_disfavoredOverload
prefix func +<T>(operand: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}

@_disfavoredOverload
prefix func +<Wrapped>(operand: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}


// MARK: - Negate


@_disfavoredOverload
prefix func -<T>(operand: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}

@_disfavoredOverload
prefix func -<Wrapped>(operand: any FakeSecondDialectExpression<Optional<Wrapped>>) -> some FakeSecondDialectExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}
