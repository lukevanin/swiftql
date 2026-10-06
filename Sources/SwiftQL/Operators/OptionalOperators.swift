//
//  OptionalOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


extension XLExpression {
 
    public func coalesce<Wrapped>(_ expression: any XLTypedExpression<Wrapped>) -> some XLExpression<Wrapped, Dialect> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    // An operator, so like every binary operator its expression operands
    // share one dialect, and a value stands in for either one (issue #789).
    public static func ??<Wrapped>(lhs: Self, rhs: any XLExpression<Wrapped, Dialect>) -> some XLExpression<Wrapped, Dialect> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }

    @_disfavoredOverload
    public static func ??<Wrapped>(lhs: Self, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Wrapped, Dialect> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

extension XLExpression {
    
    public func isNull<Wrapped>() -> some XLExpression<Bool, Dialect> where T == Optional<Wrapped> {
        XLNullTestExpression(.isNull, operand: self)
    }
}


// MARK: - notNull

extension XLExpression {
    
    public func notNull() -> some XLExpression<Bool, Dialect> where T: ExpressibleByNilLiteral {
        XLNullTestExpression(.isNotNull, operand: self)
    }
}
