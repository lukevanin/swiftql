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
/// +foo
/// ```
///
/// *SQL:*
/// ```SQL
/// +(foo)
/// ```
///
/// The operand is grouped so adjacent unary operators cannot form SQL tokens such as SQLite's `--`
/// line-comment marker.
///
public struct XLUnaryOperatorExpression<T, Dialect>: XLExpression {
    
    let op: String
    
    let operand: any XLTypedExpression
    
    public init(op: String, operand: any XLTypedExpression) {
        self.op = op
        self.operand = operand
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryOperator(op) { context in
            context.parenthesis(contents: operand.makeSQL)
        }
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
public struct XLPrefixOperatorExpression<T, Dialect>: XLExpression {
    
    let op: String
    
    let operand: any XLTypedExpression
    
    public init(op: String, operand: any XLTypedExpression) {
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
public struct XLPostfixOperatorExpression<T, Dialect>: XLExpression {
    
    let op: String
    
    let operand: any XLTypedExpression
    
    public init(op: String, operand: any XLTypedExpression) {
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
/// A comparison whose keyword the dialect spells.
///
/// Renders what ``XLBinaryOperatorExpression`` renders for the same operands,
/// except that the operator text comes from ``XLBuilder/vocabulary`` instead
/// of from this node. SQLite spells a null-safe equality `IS`, which is a
/// syntax error in PostgreSQL.
///
public struct XLComparisonExpression<T, Dialect>: XLExpression {

    let comparison: XLComparisonOperator

    let lhs: any XLTypedExpression

    let rhs: any XLTypedExpression

    public init(
        _ comparison: XLComparisonOperator,
        lhs: any XLTypedExpression,
        rhs: any XLTypedExpression
    ) {
        self.comparison = comparison
        self.lhs = lhs
        self.rhs = rhs
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.comparison(comparison, left: lhs.makeSQL, right: rhs.makeSQL)
        }
    }
}


///
/// A postfix test for `NULL` whose keyword the dialect spells.
///
/// SQLite accepts `ISNULL` and `NOTNULL`; standard SQL spells the same tests
/// `IS NULL` and `IS NOT NULL`.
///
public struct XLNullTestExpression<T, Dialect>: XLExpression {

    let test: XLNullTest

    let operand: any XLTypedExpression

    public init(_ test: XLNullTest, operand: any XLTypedExpression) {
        self.test = test
        self.operand = operand
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.nullTest(test, expression: operand.makeSQL)
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
public struct XLBinaryOperatorExpression<T, Dialect>: XLExpression {
    
    let op: String
    
    let lhs: any XLTypedExpression
    
    let rhs: any XLTypedExpression
    
    public init(op: String, lhs: any XLTypedExpression, rhs: any XLTypedExpression) {
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
/// String concatenation expression.
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
/// (foo || bar)
/// ```
///
/// The result is grouped so postfix operators such as `COLLATE` apply to the complete
/// concatenation, and so nesting on either side of another binary operator is unambiguous.
///
public struct XLConcatenationExpression<T, Dialect>: XLExpression {
    
    let op: String
    
    let lhs: any XLTypedExpression
    
    let rhs: any XLTypedExpression
    
    public init(op: String, lhs: any XLTypedExpression, rhs: any XLTypedExpression) {
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
public struct XLInValueExpression<T, Dialect>: XLExpression {
    
    let lhs: any XLTypedExpression
    
    let rhs: any XLEncodable

    let negated: Bool
    
    ///
    /// - Parameter lhs: Expression tested for membership.
    /// - Parameter rhs: Value list or query supplying the candidate set.
    /// - Parameter negated: Renders `NOT IN` instead of `IN`. The negation is
    ///   carried by this expression rather than a wrapping `NOT`, so composing
    ///   the result cannot move it outwards.
    ///
    public init(lhs: any XLTypedExpression, rhs: any XLEncodable, negated: Bool = false) {
        self.lhs = lhs
        self.rhs = rhs
        self.negated = negated
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                negated ? "NOT IN" : "IN",
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
public struct XLInTableExpression<T, Dialect>: XLExpression {
    
    let lhs: any XLTypedExpression
    
    let rhs: any XLEncodable

    let negated: Bool
    
    ///
    /// - Parameter lhs: Expression tested for membership.
    /// - Parameter rhs: Name of the table or common table supplying the
    ///   candidate set, which must expose exactly one column.
    /// - Parameter negated: Renders `NOT IN` instead of `IN`. The negation is
    ///   carried by this expression rather than a wrapping `NOT`, so composing
    ///   the result cannot move it outwards.
    ///
    public init(lhs: any XLTypedExpression, rhs: any XLEncodable, negated: Bool = false) {
        self.lhs = lhs
        self.rhs = rhs
        self.negated = negated
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                negated ? "NOT IN" : "IN",
                left: lhs.makeSQL,
                right: rhs.makeSQL
            )
        }
    }
}


///
/// Type cast expression.
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
/// CAST(foo AS TEXT)
/// ```
///
public struct XLTypeCastExpression<T, Dialect>: XLExpression {
    
    private let type: String
    
    private let expression: any XLTypedExpression
    
    public init(type: String, expression: any XLTypedExpression) {
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
/// Changes the type affinity of an expression. This is similar to a type cast in that it can be used to force a type
/// to meet compile-time type constraints.
///
/// A type cast is used when data is interpreted using a different representation, such as converting an
/// `Int` to a `String`. Type affinity is used when the representation does not change but the compile-time
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
public struct XLTypeAffinityExpression<T, Dialect>: XLExpression {
    
    private let expression: any XLTypedExpression
    
    public init(expression: any XLTypedExpression) {
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
public struct XLNullCoalesceExpression<T, Dialect>: XLExpression {
    
    let lhs: any XLTypedExpression<Optional<T>>
    
    let rhs: any XLTypedExpression<T>
    
    public init(lhs: any XLTypedExpression<Optional<T>>, rhs: any XLTypedExpression<T>) {
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
/// foo.bar.isNull().iif(then: "baz", else: "buzz")
/// ```
///
/// *SQL:*
/// ```SQL
/// IIF((foo.bar ISNULL), 'baz', 'buzz')
/// ```
///
public struct XLIfExpression<T, Dialect>: XLExpression {
    
    let condition: any XLTypedExpression

    let trueResult: any XLTypedExpression

    let falseResult: any XLTypedExpression
    
    public init(condition: any XLTypedExpression, trueResult: any XLTypedExpression, falseResult: any XLTypedExpression) {
        self.condition = condition
        self.trueResult = trueResult
        self.falseResult = falseResult
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.conditional(.immediateIf) { context in
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
