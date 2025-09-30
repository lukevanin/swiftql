//
//  NumericOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Unary plus


public prefix func +<T>(operand: any XLExpression<T>) -> some XLExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}

public prefix func +<Wrapped>(operand: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "+", operand: operand)
}


// MARK: - Negate


public prefix func -<T>(operand: any XLExpression<T>) -> some XLExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}

public prefix func -<Wrapped>(operand: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "-", operand: operand)
}


// MARK: - Bitwise negate


public prefix func ~<T>(operand: any XLExpression<T>) -> some XLExpression<T> where T: Numeric {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}

public prefix func ~<Wrapped>(operand: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: Numeric {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}
