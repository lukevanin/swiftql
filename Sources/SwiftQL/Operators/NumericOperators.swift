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


// MARK: - Standard library integer operands


// `Int` conforms to `XLExpression`, so a plain `Int` operand also matches the
// generic operators above. Swift 5.9 and Swift 6.4 still pick the standard
// library operator for it, but Swift 6.3 picks SwiftQL's, and `let x = -someInt`
// stops compiling in every file that imports SwiftQL (issue #771). These
// exact-match overloads restore `Int` on every compiler. `Double` needs no such
// overload: it is not affected, and adding one makes `-someDouble` ambiguous.

public prefix func +(operand: Int) -> Int {
    operand
}

public prefix func -(operand: Int) -> Int {
    0 - operand
}
