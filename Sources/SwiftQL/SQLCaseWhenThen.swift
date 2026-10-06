//
//  SQLCaseWhenThen.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation


// MARK: - Constant Case-When-Then expression

///
/// Builder used to construct CASE...END expressions.
///
/// Do not instantiate this class directly - use one of the relevant methods on a case expression instead.
///
private struct ConstantCaseComponents {
    
    typealias Builder = (inout XLBuilder) -> Void
    
    let condition: any XLEncodable
    
    private(set) var expressions: [Builder] = []
    
    func appending(_ expression: @escaping Builder) -> ConstantCaseComponents {
        var output = ConstantCaseComponents(condition: condition, expressions: expressions)
        output.expressions.append(expression)
        return output
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.block(beginsWith: "CASE", endsWith: "END", separator: .tuple) { context in
                condition.makeSQL(context: &context)
                for expression in expressions {
                    expression(&context)
                }
            }
        }
    }
}


///
/// Root for a `Case` expression.
///
/// A `Case` expression is similar to a `switch` statement in Swift: it returns a single value from a list of
/// possible choices.
///
/// A `Case` expression must be followed by one or more `when(then:)` clauses. The `Case`
/// expression returns the value of the `then` expression for the first condition that matches the case
/// statement.
///
/// `Dialect` is the dialect of the case term, which the whole expression
/// carries (issue #789).
///
public struct ConstantCase<T, Dialect> {

    private let condition: any XLExpression<T, Dialect>

    fileprivate init(condition: any XLExpression<T, Dialect>) {
        self.condition = condition
    }
    
    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    public func when<U>(_ condition: any XLTypedExpression<T>, then result: any XLTypedExpression<U>) -> ConstantCaseWhenThen<T, U, Dialect> {
        ConstantCaseWhenThen(
            components: ConstantCaseComponents(condition: self.condition),
            condition: condition,
            result: result
        )
    }
}


///
/// A complete case/when/then expression.
///
/// The expression can be expanded by repeatedly calling `when(then:)` and specifying additional
/// conditions and results, or by calling `else()` and specifying a fallback result.
///
/// If an `else` expression is defined and no `when` conditions match the case term then the case
/// expression evaluates to the result defined in the `else` expression. If an `else` expression is not
/// defined and no `when` conditions match the case term then the case expression evaluates to `nil`.
///
public struct ConstantCaseWhenThen<Condition, Result, Dialect>: XLExpression {
    
    public typealias T = Optional<Result>
    
    private let components: ConstantCaseComponents

    fileprivate init(components: ConstantCaseComponents, condition: any XLTypedExpression<Condition>, result: any XLTypedExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("WHEN", expression: condition.makeSQL)
            context.unaryPrefix("THEN", expression: result.makeSQL)
        }
    }
    
    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    public func when(_ condition: any XLTypedExpression<Condition>, then result: any XLTypedExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, Dialect> {
        ConstantCaseWhenThen(components: components, condition: condition, result: result)
    }
    
    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    public func `else`(_ result: any XLTypedExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, Dialect> {
        ConstantCaseWhenThenElse(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct ConstantCaseWhenThenElse<Condition, Result, Dialect>: XLExpression {
    
    public typealias T = Result

    private let components: ConstantCaseComponents
    
    fileprivate init(components: ConstantCaseComponents, result: any XLTypedExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("ELSE", expression: result.makeSQL)
        }
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// Starts a `CASE` expression over `condition`. The expression takes the
/// dialect of `condition`.
///
public func switchCase<T, Dialect>(_ condition: any XLExpression<T, Dialect>) -> ConstantCase<T, Dialect> {
    ConstantCase(condition: condition)
}


// MARK: Variable Case-When-Then expression


private struct VariableCaseComponents {
    
    typealias Builder = (inout XLBuilder) -> Void
    
    private(set) var expressions: [Builder] = []
    
    func appending(_ expression: @escaping Builder) -> VariableCaseComponents {
        var output = VariableCaseComponents(expressions: expressions)
        output.expressions.append(expression)
        return output
    }

    func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.block(beginsWith: "CASE", endsWith: "END", separator: .tuple) { context in
                for expression in expressions {
                    expression(&context)
                }
            }
        }
    }
}


public struct VariableCaseWhenThen<Result, Dialect>: XLExpression {

    public typealias T = Optional<Result>

    private let components: VariableCaseComponents
    
    fileprivate init(components: VariableCaseComponents, condition: any XLTypedExpression, result: any XLTypedExpression) {
        self.components = components.appending { context in
            context.unaryPrefix("WHEN", expression: condition.makeSQL)
            context.unaryPrefix("THEN", expression: result.makeSQL)
        }
    }
    
    public func when<Condition>(_ condition: any XLTypedExpression<Condition>, then result: any XLTypedExpression<Result>) -> VariableCaseWhenThen<Result, Dialect> where Condition: XLBoolean {
        VariableCaseWhenThen(
            components: components,
            condition: condition,
            result: result
        )
    }
    
    public func `else`(_ result: any XLTypedExpression<Result>) -> some XLExpression<Result, Dialect> {
        VariableCaseElse<Result, Dialect>(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct VariableCaseElse<Result, Dialect>: XLExpression {
    
    public typealias T = Result

    private let components: VariableCaseComponents
    
    fileprivate init(components: VariableCaseComponents, result: any XLTypedExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("ELSE", expression: result.makeSQL)
        }
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// Starts a `CASE WHEN` expression. The expression takes the dialect of the
/// first condition.
///
public func when<Condition, Result, Dialect>(_ condition: any XLExpression<Condition, Dialect>, then result: any XLTypedExpression<Result>) -> VariableCaseWhenThen<Result, Dialect> where Condition: XLBoolean {
    VariableCaseWhenThen(
        components: VariableCaseComponents(),
        condition: condition,
        result: result
    )
}
