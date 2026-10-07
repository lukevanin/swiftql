//
//  CompileFailSecondDialectCaseWhenThen.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/CaseWhenThen.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Constant Case-When-Then expression


extension ConstantCaseWhenThen: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension ConstantCaseWhenThenElse: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}


///
/// Starts a `CASE` expression that compares `condition` with the condition of
/// each `when(_:then:)` arm.
///
@_disfavoredOverload
func switchCase<T>(_ condition: any CompileFailSecondDialectExpression<T>) -> ConstantCase<T, CompileFailSecondDialect> {
    ConstantCase(_dialectSurfaceCondition: condition)
}


extension ConstantCase where Dialect == CompileFailSecondDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    @_disfavoredOverload
    func when<U>(_ condition: any CompileFailSecondDialectExpression<T>, then result: any CompileFailSecondDialectExpression<U>) -> ConstantCaseWhenThen<T, U, CompileFailSecondDialect> {
        _when(condition, then: result)
    }
}


extension ConstantCaseWhenThen where Dialect == CompileFailSecondDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    @_disfavoredOverload
    func when(_ condition: any CompileFailSecondDialectExpression<Condition>, then result: any CompileFailSecondDialectExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, CompileFailSecondDialect> {
        _when(condition, then: result)
    }

    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    @_disfavoredOverload
    func `else`(_ result: any CompileFailSecondDialectExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, CompileFailSecondDialect> {
        _else(result)
    }
}


// MARK: Variable Case-When-Then expression


extension VariableCaseWhenThen: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}

extension VariableCaseElse: CompileFailSecondDialectExpression where Dialect == CompileFailSecondDialect {
}


///
/// Starts a `CASE` expression whose first arm gives `result` when `condition`
/// is true.
///
@_disfavoredOverload
func when<Condition, Result>(_ condition: any CompileFailSecondDialectExpression<Condition>, then result: any CompileFailSecondDialectExpression<Result>) -> VariableCaseWhenThen<Result, CompileFailSecondDialect> where Condition: XLBoolean {
    VariableCaseWhenThen(_dialectSurfaceCondition: condition, then: result)
}


extension VariableCaseWhenThen where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func when<Condition>(_ condition: any CompileFailSecondDialectExpression<Condition>, then result: any CompileFailSecondDialectExpression<Result>) -> VariableCaseWhenThen<Result, CompileFailSecondDialect> where Condition: XLBoolean {
        _when(condition, then: result)
    }

    @_disfavoredOverload
    func `else`(_ result: any CompileFailSecondDialectExpression<Result>) -> some CompileFailSecondDialectExpression<Result> {
        _else(result)
    }
}
