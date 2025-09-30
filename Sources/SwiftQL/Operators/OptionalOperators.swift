//
//  XLOptionalOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


extension XLExpression {
 
    public func coalesce<Wrapped>(_ expression: any XLExpression<Wrapped>) -> some XLExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: self, rhs: expression)
    }
    
    public static func ??<Wrapped>(lhs: Self, rhs: any XLExpression<Wrapped>) -> some XLExpression<Wrapped> where T == Optional<Wrapped> {
        XLNullCoalesceExpression(lhs: lhs, rhs: rhs)
    }
}


// MARK: - isNull

//public func isNull<Wrapped>(_ expression: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Bool>  {
//    XLPostfixOperatorExpression(op: "ISNULL", operand: expression)
//}
//
//public func isNull<Wrapped>(@XLExpressionBuilder expression: () -> any XLExpression<Optional<Wrapped>>) -> some XLExpression<Bool>  {
//    XLPostfixOperatorExpression(op: "ISNULL", operand: expression())
//}


extension XLExpression {
    
    public func isNull<Wrapped>() -> some XLExpression<Bool> where T == Optional<Wrapped> {
        XLPostfixOperatorExpression(op: "ISNULL", operand: self)
    }
}


// MARK: - notNull

//public func notNull<Wrapped>(_ expression: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Bool>  {
//    XLPostfixOperatorExpression(op: "NOTNULL", operand: expression)
//}
//
//public func notNull<Wrapped>(@XLExpressionBuilder expression: () -> any XLExpression<Optional<Wrapped>>) -> some XLExpression<Bool>  {
//    XLPostfixOperatorExpression(op: "NOTNULL", operand: expression())
//}
extension XLExpression {
    
    public func notNull() -> some XLExpression<Bool> where T: ExpressibleByNilLiteral {
        XLPostfixOperatorExpression(op: "NOTNULL", operand: self)
    }
}
