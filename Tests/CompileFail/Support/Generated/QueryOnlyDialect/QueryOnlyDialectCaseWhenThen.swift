//
//  QueryOnlyDialectCaseWhenThen.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/CaseWhenThen.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Constant Case-When-Then expression


extension ConstantCaseWhenThen: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension ConstantCaseWhenThenElse: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}


///
/// Starts a `CASE` expression that compares `condition` with the condition of
/// each `when(_:then:)` arm.
///
func switchCase<T>(_ condition: any QueryOnlyDialectExpression<T>) -> ConstantCase<T, QueryOnlyDialect> {
    ConstantCase(_dialectSurfaceCondition: condition)
}


extension ConstantCase where Dialect == QueryOnlyDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    func when<U>(_ condition: any QueryOnlyDialectExpression<T>, then result: any QueryOnlyDialectExpression<U>) -> ConstantCaseWhenThen<T, U, QueryOnlyDialect> {
        _when(condition, then: result)
    }
}


extension ConstantCaseWhenThen where Dialect == QueryOnlyDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    func when(_ condition: any QueryOnlyDialectExpression<Condition>, then result: any QueryOnlyDialectExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, QueryOnlyDialect> {
        _when(condition, then: result)
    }

    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    func `else`(_ result: any QueryOnlyDialectExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, QueryOnlyDialect> {
        _else(result)
    }
}


// MARK: Variable Case-When-Then expression


extension VariableCaseWhenThen: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}

extension VariableCaseElse: QueryOnlyDialectExpression where Dialect == QueryOnlyDialect {
}


///
/// Starts a `CASE` expression whose first arm gives `result` when `condition`
/// is true.
///
func when<Condition, Result>(_ condition: any QueryOnlyDialectExpression<Condition>, then result: any QueryOnlyDialectExpression<Result>) -> VariableCaseWhenThen<Result, QueryOnlyDialect> where Condition: XLBoolean {
    VariableCaseWhenThen(_dialectSurfaceCondition: condition, then: result)
}


extension VariableCaseWhenThen where Dialect == QueryOnlyDialect {

    func when<Condition>(_ condition: any QueryOnlyDialectExpression<Condition>, then result: any QueryOnlyDialectExpression<Result>) -> VariableCaseWhenThen<Result, QueryOnlyDialect> where Condition: XLBoolean {
        _when(condition, then: result)
    }

    func `else`(_ result: any QueryOnlyDialectExpression<Result>) -> some QueryOnlyDialectExpression<Result> {
        _else(result)
    }
}
