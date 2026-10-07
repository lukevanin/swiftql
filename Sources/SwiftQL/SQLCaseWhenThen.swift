//
//  SQLCaseWhenThen.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation


// Each builder carries the dialect of the query it belongs to, and is an
// expression of that dialect only. The functions that start and extend a case
// expression take that dialect's expressions, so each dialect's surface
// declares them, from scripts/dialect-surface/Templates/CaseWhenThen.swift.template
// (issue #789). They call the underscored primitives here, which take any
// expression and are not meant to be called directly.


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
public struct ConstantCase<T, Dialect> {

    private let condition: any XLExpression<T>

    /// Starts a case expression of `Dialect` on `condition`, which must be an
    /// expression of `Dialect`. Used by the generated `switchCase(_:)`.
    public init(_dialectSurfaceCondition condition: any XLExpression<T>) {
        self.condition = condition
    }

    /// Adds a `WHEN ... THEN` arm. Used by the generated `when(_:then:)`,
    /// which takes only expressions of `Dialect`.
    public func _when<U>(_ condition: any XLExpression<T>, then result: any XLExpression<U>) -> ConstantCaseWhenThen<T, U, Dialect> {
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

    fileprivate init(components: ConstantCaseComponents, condition: any XLExpression<Condition>, result: any XLExpression<Result>) {
        self.components = components.appending { context in
            context.unaryPrefix("WHEN", expression: condition.makeSQL)
            context.unaryPrefix("THEN", expression: result.makeSQL)
        }
    }
    
    /// Adds a `WHEN ... THEN` arm. Used by the generated `when(_:then:)`,
    /// which takes only expressions of `Dialect`.
    public func _when(_ condition: any XLExpression<Condition>, then result: any XLExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, Dialect> {
        ConstantCaseWhenThen(components: components, condition: condition, result: result)
    }

    /// Adds the `ELSE` result. Used by the generated `else(_:)`, which takes
    /// only an expression of `Dialect`.
    public func _else(_ result: any XLExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, Dialect> {
        ConstantCaseWhenThenElse(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct ConstantCaseWhenThenElse<Condition, Result, Dialect>: XLExpression {
    
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

    fileprivate init(components: VariableCaseComponents, condition: any XLExpression, result: any XLExpression) {
        self.components = components.appending { context in
            context.unaryPrefix("WHEN", expression: condition.makeSQL)
            context.unaryPrefix("THEN", expression: result.makeSQL)
        }
    }

    /// Starts a case expression of `Dialect` with its first arm, whose
    /// expressions must be of `Dialect`. Used by the generated `when(_:then:)`.
    public init<Condition>(_dialectSurfaceCondition condition: any XLExpression<Condition>, then result: any XLExpression<Result>) where Condition: XLBoolean {
        self.init(
            components: VariableCaseComponents(),
            condition: condition,
            result: result
        )
    }

    /// Adds a `WHEN ... THEN` arm. Used by the generated `when(_:then:)`,
    /// which takes only expressions of `Dialect`.
    public func _when<Condition>(_ condition: any XLExpression<Condition>, then result: any XLExpression<Result>) -> VariableCaseWhenThen<Result, Dialect> where Condition: XLBoolean {
        VariableCaseWhenThen(
            components: components,
            condition: condition,
            result: result
        )
    }

    /// Adds the `ELSE` result. Used by the generated `else(_:)`, which takes
    /// only an expression of `Dialect`.
    public func _else(_ result: any XLExpression<Result>) -> VariableCaseElse<Result, Dialect> {
        VariableCaseElse(components: components, result: result)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct VariableCaseElse<Result, Dialect>: XLExpression {
    
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

