//
//  XLTextOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation


#warning("TODO: Implement regexp and match for XLExpression<String>")


// MARK: - Concatenation


public func +(lhs: any XLExpression<String>, rhs: any XLExpression<String>) -> some XLExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<String>, rhs: any XLExpression<Optional<String>>) -> some XLExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<Optional<String>>, rhs: any XLExpression<String>) -> some XLExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLExpression<Optional<String>>, rhs: any XLExpression<Optional<String>>) -> some XLExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


// MARK: - LIKE


extension XLExpression {
    
    public func like(_ other: any XLExpression<String>) -> some XLExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }
    
    public func like(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLExpression<String>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }
}


// MARK: - GLOB


extension XLExpression {
    
    public func glob(_ other: any XLExpression<String>) -> some XLExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<String>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLExpression<Optional<String>>) -> some XLExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
}
