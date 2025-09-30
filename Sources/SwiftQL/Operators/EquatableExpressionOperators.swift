//
//  XLExpressionOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


// MARK: - Equality


public func ==<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLEquatable {
    XLBinaryOperatorExpression(op: "==", lhs: lhs, rhs: rhs)
}

public func ==<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLEquatable {
    XLBinaryOperatorExpression(op: "IS", lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLBinaryOperatorExpression(op: "IS", lhs: lhs, rhs: rhs)
}

public func ==<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLBinaryOperatorExpression(op: "IS", lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


public func !=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLEquatable {
    XLBinaryOperatorExpression(op: "!=", lhs: lhs, rhs: rhs)
}

public func !=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLEquatable {
    XLBinaryOperatorExpression(op: "IS NOT", lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLEquatable {
    XLBinaryOperatorExpression(op: "IS NOT", lhs: lhs, rhs: rhs)
}

public func !=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLEquatable{
    XLBinaryOperatorExpression(op: "IS NOT", lhs: lhs, rhs: rhs)
}
