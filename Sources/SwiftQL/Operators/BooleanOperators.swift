//
//  XLBooleanOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation



// MARK: - NOT


public prefix func !(operand: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}

public prefix func !(operand: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLPrefixOperatorExpression(op: "NOT", operand: operand)
}


// MARK: - AND


public func &&(lhs: any XLExpression<Bool>, rhs: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

public func &&(lhs: any XLExpression<Bool>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

public func &&(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Bool>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}

public func &&(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "AND", lhs: lhs, rhs: rhs)
}


// MARK: - OR


public func ||(lhs: any XLExpression<Bool>, rhs: any XLExpression<Bool>) -> some XLExpression<Bool> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLExpression<Bool>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public func ||(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Bool>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}

public  func ||(lhs: any XLExpression<Optional<Bool>>, rhs: any XLExpression<Optional<Bool>>) -> some XLExpression<Optional<Bool>> {
    XLBinaryOperatorExpression(op: "OR", lhs: lhs, rhs: rhs)
}
