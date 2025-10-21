//
//  XLCaseWhenThen.swift
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
            context.block(beginsWith: "CASE", endsWith: "END", separator: .space) { context in
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
public struct ConstantCase<T> {
    
    private let condition: any XLExpression<T>
    
    fileprivate init(condition: any XLExpression<T>) {
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
    public func when<U>(_ condition: any XLExpression<T>, then result: any XLExpression<U>) -> ConstantCaseWhenThen<T, U> {
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
public struct ConstantCaseWhenThen<Condition, Result>: XLExpression {
    
    public typealias T = Optional<Result>
    
    private let components: ConstantCaseComponents

    fileprivate init(components: ConstantCaseComponents, condition: any XLExpression<Condition>, result: any XLExpression<Result>) {
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
    public func when(_ condition: any XLExpression<Condition>, then result: any XLExpression<Result>) -> ConstantCaseWhenThen<Condition, Result> {
        ConstantCaseWhenThen(components: components, condition: condition, result: result)
    }
    
    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    public func `else`(_ result: any XLExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result> {
        ConstantCaseWhenThenElse(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct ConstantCaseWhenThenElse<Condition, Result>: XLExpression {
    
    public typealias T = Result

    private let components: ConstantCaseComponents
    
    fileprivate init(components: ConstantCaseComponents, result: any XLExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("ELSE", expression: result.makeSQL)
        }
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public func switchCase<T>(_ condition: any XLExpression<T>) -> ConstantCase<T> {
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
            context.block(beginsWith: "CASE", endsWith: "END", separator: .space) { context in
                for expression in expressions {
                    expression(&context)
                }
            }
        }
    }
}


public struct VariableCaseWhenThen<Result>: XLExpression {
    
    public typealias T = Optional<String>

    private let components: VariableCaseComponents
    
    fileprivate init(components: VariableCaseComponents, condition: any XLExpression, result: any XLExpression) {
        self.components = components.appending { context in
            context.unaryPrefix("WHEN", expression: condition.makeSQL)
            context.unaryPrefix("THEN", expression: result.makeSQL)
        }
    }
    
    public func when<Condition>(_ condition: any XLExpression<Condition>, then result: any XLExpression<Result>) -> VariableCaseWhenThen<Result> where Condition: XLBoolean {
        VariableCaseWhenThen(
            components: components,
            condition: condition,
            result: result
        )
    }
    
    public func `else`(_ result: any XLExpression<Result>) -> some XLExpression<Result> {
        VariableCaseElse(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct VariableCaseElse<Result>: XLExpression {
    
    public typealias T = Result

    private let components: VariableCaseComponents
    
    fileprivate init(components: VariableCaseComponents, result: any XLExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("ELSE", expression: result.makeSQL)
        }
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public func when<Condition, Result>(_ condition: any XLExpression<Condition>, then result: any XLExpression<Result>) -> VariableCaseWhenThen<Result> {
    VariableCaseWhenThen(
        components: VariableCaseComponents(),
        condition: condition,
        result: result
    )
}
