//
//  SQLiteCaseWhenThen.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/CaseWhenThen.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Constant Case-When-Then expression


extension ConstantCaseWhenThen: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension ConstantCaseWhenThenElse: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}


///
/// Starts a `CASE` expression that compares `condition` with the condition of
/// each `when(_:then:)` arm.
///
public func switchCase<T>(_ condition: any XLSQLiteExpression<T>) -> ConstantCase<T, XLSQLiteDialect> {
    ConstantCase(_dialectSurfaceCondition: condition)
}


extension ConstantCase where Dialect == XLSQLiteDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    public func when<U>(_ condition: any XLSQLiteExpression<T>, then result: any XLSQLiteExpression<U>) -> ConstantCaseWhenThen<T, U, XLSQLiteDialect> {
        _when(condition, then: result)
    }
}


extension ConstantCaseWhenThen where Dialect == XLSQLiteDialect {

    ///
    /// Defines a condition that is matches against the term in the case statement.
    ///
    /// - Returns: Complete case/when/then expression.
    ///
    /// The case statement evaluates to the `then` result when the condition matches the term in the
    /// case statement.
    ///
    public func when(_ condition: any XLSQLiteExpression<Condition>, then result: any XLSQLiteExpression<Result>) -> ConstantCaseWhenThen<Condition, Result, XLSQLiteDialect> {
        _when(condition, then: result)
    }

    ///
    /// Defines a fallback result that is used when no `when` condition matches the case term.
    ///
    public func `else`(_ result: any XLSQLiteExpression<Result>) -> ConstantCaseWhenThenElse<Condition, Result, XLSQLiteDialect> {
        _else(result)
    }
}


// MARK: Variable Case-When-Then expression


extension VariableCaseWhenThen: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}

extension VariableCaseElse: XLSQLiteExpression where Dialect == XLSQLiteDialect {
}


///
/// Starts a `CASE` expression whose first arm gives `result` when `condition`
/// is true.
///
public func when<Condition, Result>(_ condition: any XLSQLiteExpression<Condition>, then result: any XLSQLiteExpression<Result>) -> VariableCaseWhenThen<Result, XLSQLiteDialect> where Condition: XLBoolean {
    VariableCaseWhenThen(_dialectSurfaceCondition: condition, then: result)
}


extension VariableCaseWhenThen where Dialect == XLSQLiteDialect {

    public func when<Condition>(_ condition: any XLSQLiteExpression<Condition>, then result: any XLSQLiteExpression<Result>) -> VariableCaseWhenThen<Result, XLSQLiteDialect> where Condition: XLBoolean {
        _when(condition, then: result)
    }

    public func `else`(_ result: any XLSQLiteExpression<Result>) -> some XLSQLiteExpression<Result> {
        _else(result)
    }
}
