//
//  XLOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation


#warning("TODO: Implement between operator")


public struct XLUnaryOperatorExpression<T>: XLExpression {
    
    let op: String
    
    let operand: any XLExpression
    
    public init(op: String, operand: any XLExpression) {
        self.op = op
        self.operand = operand
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryOperator(op, expression: operand.makeSQL)
    }
}


public struct XLPrefixOperatorExpression<T>: XLExpression {
    
    let op: String
    
    let operand: any XLExpression
    
    public init(op: String, operand: any XLExpression) {
        self.op = op
        self.operand = operand
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.unaryPrefix(op, expression: operand.makeSQL)
        }
    }
}


public struct XLPostfixOperatorExpression<T>: XLExpression {
    
    let op: String
    
    let operand: any XLExpression
    
    public init(op: String, operand: any XLExpression) {
        self.op = op
        self.operand = operand
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.unarySuffix(op, expression: operand.makeSQL)
        }
    }
}


public struct XLBinaryOperatorExpression<T>: XLExpression {
    
    let op: String
    
    let lhs: any XLExpression
    
    let rhs: any XLExpression
    
    public init(op: String, lhs: any XLExpression, rhs: any XLExpression) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(op, left: lhs.makeSQL, right: rhs.makeSQL)
        }
    }
}


public struct XLConcatenationExpression<T>: XLExpression {
    
    let op: String
    
    let lhs: any XLExpression
    
    let rhs: any XLExpression
    
    public init(op: String, lhs: any XLExpression, rhs: any XLExpression) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(op, left: lhs.makeSQL, right: rhs.makeSQL)
    }
}


public struct XLInValueExpression<T>: XLExpression {
    
    let lhs: any XLExpression
    
    let rhs: any XLEncodable
    
    public init(lhs: any XLExpression, rhs: any XLEncodable) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                "IN",
                left: lhs.makeSQL,
                right: { context in
                    context.parenthesis(contents: rhs.makeSQL)
                }
            )
        }
    }
}


public struct XLInTableExpression<T>: XLExpression {
    
    let lhs: any XLExpression
    
    let rhs: any XLEncodable
    
    public init(lhs: any XLExpression, rhs: any XLEncodable) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                "IN",
                left: lhs.makeSQL,
                right: rhs.makeSQL
            )
        }
    }
}


public struct XLTypeCastExpression<T>: XLExpression {
    
    private let type: String
    
    private let expression: any XLExpression
    
    public init(type: String, expression: any XLExpression) {
        self.type = type
        self.expression = expression
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.cast(type: type, expression: expression.makeSQL)
    }
}


///
/// Use XL implicit type affinity to assign an expression to a given type.
///
public struct XLTypeAffinityExpression<T>: XLExpression {
    
    private let expression: any XLExpression
    
    public init(expression: any XLExpression) {
        self.expression = expression
    }
    
    public func makeSQL(context: inout XLBuilder) {
        expression.makeSQL(context: &context)
    }
}


public struct XLNullCoalesceExpression<T>: XLExpression {
    
    let lhs: any XLExpression<Optional<T>>
    
    let rhs: any XLExpression<T>
    
    public init(lhs: any XLExpression<Optional<T>>, rhs: any XLExpression<T>) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: "COALESCE") { context in
            context.listItem { context in
                lhs.makeSQL(context: &context)
            }
            context.listItem { context in
                rhs.makeSQL(context: &context)
            }
        }
    }
}


public struct XLIfExpression<T>: XLExpression {
    
    let condition: any XLExpression

    let trueResult: any XLExpression

    let falseResult: any XLExpression
    
    public init(condition: any XLExpression, trueResult: any XLExpression, falseResult: any XLExpression) {
        self.condition = condition
        self.trueResult = trueResult
        self.falseResult = falseResult
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: "IIF") { context in
            context.listItem { context in
                condition.makeSQL(context: &context)
            }
            context.listItem { context in
                trueResult.makeSQL(context: &context)
            }
            context.listItem { context in
                falseResult.makeSQL(context: &context)
            }
        }
    }
}

