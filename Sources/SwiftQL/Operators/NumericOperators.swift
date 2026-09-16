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


// MARK: - Standard library numeric operands


// `Int` and `Double` conform to `XLExpression`, so a plain `Int` or `Double`
// operand also matches the generic operators above. Swift 5.9 and Swift 6.4
// still pick the standard library operator for such an operand, but Swift 6.3
// picks SwiftQL's, and `let x = -someInt` stops compiling in every file that
// imports SwiftQL (issue #771). These exact-match overloads restore `Int` and
// `Double` on every compiler.
//
// `Double` gets a `+` overload only. For `-someDouble`, Swift 6.3 already picks
// the standard library operator, and an exact-match `-` overload for `Double`
// makes `-someDouble` ambiguous.

public prefix func +(operand: Int) -> Int {
    operand
}

public prefix func -(operand: Int) -> Int {
    0 - operand
}

public prefix func +(operand: Double) -> Double {
    operand
}
