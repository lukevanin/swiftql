//
//  SQLOperators.swift
//
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation


///
/// Unary operator.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// +69
/// ```
///
/// *SQL:*
/// ```SQL
/// +69
/// ```
///
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


///
/// Prefix operator.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// !foo
/// ```
///
/// *SQL:*
/// ```SQL
/// (NOT foo)
/// ```
///
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



///
/// Postfix operator.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.isNull()
/// ```
///
/// *SQL:*
/// ```SQL
/// (foo ISNULL)
/// ```
///
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


///
/// Binary operator expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo * bar
/// ```
///
/// *SQL:*
/// ```SQL
/// (foo * bar)
/// ```
///
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


///
/// String contatenation expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo + bar
/// ```
///
/// *SQL:*
/// ```SQL
/// foo || bar
/// ```
///
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


///
/// IN value expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.in("bar", "baz")
/// ```
///
/// *SQL:*
/// ```SQL
/// (foo IN ('bar', 'baz'))
/// ```
///
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


///
/// IN table expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.in(bar)
/// ```
///
/// *SQL:*
/// ```SQL
/// (foo IN bar)
/// ```
///
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


///
/// Type case expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.toString()
/// ```
///
/// *SQL:*
/// ```SQL
/// CASE(foo AS TEXT)
/// ```
///
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
/// Type affinity expression.
///
/// Changes the type affinity of an expression. This is similar to type case in that it can be used to force a type
/// to meet compile time type constraints.
///
/// A type case is used when the data is interpreted into a different representation, such as converting an
/// `Int` to a `String`. Type affinity is used when the  of the type does not change but the compile time
/// type constraints do change, such as converting an Int to an `Optional<Int>`, or converting an
/// `enum` with a raw value of type `Int` to an `Int`.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.toNullable()
/// ```
///
/// *SQL:*
/// ```SQL
/// foo
/// ```
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


///
/// Null coalescing expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// foo.coalesce("bar")
/// ```
///
/// *SQL:*
/// ```SQL
/// COALESCE(foo, 'bar')
/// ```
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


///
/// IIF expression.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// iif(foo.bar.isNull(), then: "baz", else: "buzz")
/// ```
///
/// *SQL:*
/// ```SQL
/// IIF((foo.bar ISNULL), 'baz', 'buzz')
/// ```
///
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

