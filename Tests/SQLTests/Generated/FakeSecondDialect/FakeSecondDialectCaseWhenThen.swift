//
//  FakeSecondDialectCaseWhenThen.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/CaseWhenThen.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Constant Case-When-Then expression


extension ConstantCaseWhenThen: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension ConstantCaseWhenThenElse: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}


///
/// Starts a `CASE` expression that compares `condition` with the condition of
/// each `when(_:then:)` arm.
///
@_disfavoredOverload
func switchCase<T>(_ condition: any FakeSecondDialectExpression<T>) -> ConstantCase<T, FakeSecondDialect> {
    ConstantCase(_dialectSurfaceCondition: condition)
}


extension ConstantCase where Dialect == FakeSecondDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    @_disfavoredOverload
    func when<U>(_ condition: any FakeSecondDialectExpression<T>, then result: any FakeSecondDialectExpression<U>) -> ConstantCaseWhenThen<T, U, FakeSecondDialect> {
        _when(condition, then: result)
    }
}


extension ConstantCaseWhenThen where Dialect == FakeSecondDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    @_disfavoredOverload
    func when(_ condition: any FakeSecondDialectExpression<Condition>, then result: any FakeSecondDialectExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, FakeSecondDialect> {
        _when(condition, then: result)
    }

    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    @_disfavoredOverload
    func `else`(_ result: any FakeSecondDialectExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, FakeSecondDialect> {
        _else(result)
    }
}


// MARK: Variable Case-When-Then expression


extension VariableCaseWhenThen: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}

extension VariableCaseElse: FakeSecondDialectExpression where Dialect == FakeSecondDialect {
}


///
/// Starts a `CASE` expression whose first arm gives `result` when `condition`
/// is true.
///
@_disfavoredOverload
func when<Condition, Result>(_ condition: any FakeSecondDialectExpression<Condition>, then result: any FakeSecondDialectExpression<Result>) -> VariableCaseWhenThen<Result, FakeSecondDialect> where Condition: XLBoolean {
    VariableCaseWhenThen(_dialectSurfaceCondition: condition, then: result)
}


extension VariableCaseWhenThen where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func when<Condition>(_ condition: any FakeSecondDialectExpression<Condition>, then result: any FakeSecondDialectExpression<Result>) -> VariableCaseWhenThen<Result, FakeSecondDialect> where Condition: XLBoolean {
        _when(condition, then: result)
    }

    @_disfavoredOverload
    func `else`(_ result: any FakeSecondDialectExpression<Result>) -> some FakeSecondDialectExpression<Result> {
        _else(result)
    }
}
