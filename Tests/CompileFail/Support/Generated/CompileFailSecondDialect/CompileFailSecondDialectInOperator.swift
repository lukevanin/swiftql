//
//  CompileFailSecondDialectInOperator.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/InOperator.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - IN

extension CompileFailSecondDialectExpression {

    @_disfavoredOverload
    func `in`(expression: () -> any XLQueryStatement<T>) -> some CompileFailSecondDialectExpression<Bool> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    ///
    /// Membership of this value in the results of a query built with its own
    /// schema.
    ///
    /// - Important: This overload cannot see the enclosing schema, so the
    ///   schema passed to `expression` starts an independent scope, and its
    ///   automatic aliases and bindings restart at `t0` and `p0`. If the
    ///   enclosing statement also has an automatic binding `p0`, rendering
    ///   fails with `XLInvocationBindingError.conflictingParameterKey`. For a
    ///   correlated query, use the overload whose closure takes no schema, and
    ///   build the inner tables from the enclosing schema, or from
    ///   `XLSchema(parent:)`.
    ///
    @_disfavoredOverload
    func `in`(@XLQueryExpressionBuilder expression: (XLSchema<CompileFailSecondDialect>) -> any XLQueryStatement<T>) -> some CompileFailSecondDialectExpression<Bool> {
        let schema = XLSchema(dialect: CompileFailSecondDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }

    ///
    /// Membership of an optional value in the results of `expression`.
    ///
    /// The result is `Optional<Bool>` because SQL yields NULL when the
    /// left-hand value is NULL, or when no row matches and the candidate set
    /// contains NULL.
    ///
    @_disfavoredOverload
    func `in`<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as in the non-optional overload. Use the closure form without
    ///   a schema for a correlated query.
    @_disfavoredOverload
    func `in`<Wrapped>(@XLQueryExpressionBuilder expression: (XLSchema<CompileFailSecondDialect>) -> any XLQueryStatement<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema(dialect: CompileFailSecondDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }
    @_disfavoredOverload
    func `in`(_ expressions: [any CompileFailSecondDialectExpression<T>]) -> some CompileFailSecondDialectExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            list: expressions
        )
    }

    @_disfavoredOverload
    func `in`<Wrapped>(_ expressions: [any CompileFailSecondDialectExpression<Wrapped>]) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions
        )
    }

    ///
    /// Membership in a candidate set that may itself contain NULL.
    ///
    /// SQL compares against each element in turn: a match yields true even
    /// when another element is NULL, but an exhausted search yields NULL rather
    /// than false if any element was NULL.
    ///
    /// `@_disfavoredOverload` is required, not cosmetic. An empty array literal
    /// carries no element type, so `in([])` matches this overload and the
    /// non-optional one equally well and fails to compile as ambiguous.
    /// Disfavouring this one makes the non-optional overload win that tie while
    /// still allowing a list that actually contains NULL to select this one.
    /// The empty-list cases in `testInAndNotInWithNullElementSemantics` stop
    /// compiling if the attribute is removed.
    ///
    @_disfavoredOverload
    func `in`<Wrapped>(_ expressions: [any CompileFailSecondDialectExpression<Optional<Wrapped>>]) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions
        )
    }

    @_disfavoredOverload
    func `in`<T>(_ table: T) -> some CompileFailSecondDialectExpression<Bool> where T: XLMetaCommonTable, T.Result.Dialect == CompileFailSecondDialect {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias
        )
    }
}


// MARK: - NOT IN


extension CompileFailSecondDialectExpression {

    ///
    /// Matches rows whose value is absent from the results of `expression`.
    ///
    /// SQL evaluates `NOT IN` as the negation of `IN`, so an unmatched value
    /// compared against a set containing NULL is NULL rather than true. In
    /// SQLite the one exception is an empty set, where `NOT IN` is true even
    /// for a NULL operand.
    ///
    @_disfavoredOverload
    func notIn(expression: () -> any XLQueryStatement<T>) -> some CompileFailSecondDialectExpression<Bool> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as for `in`. Use the closure form without a schema for a
    ///   correlated query.
    @_disfavoredOverload
    func notIn(@XLQueryExpressionBuilder expression: (XLSchema<CompileFailSecondDialect>) -> any XLQueryStatement<T>) -> some CompileFailSecondDialectExpression<Bool> {
        let schema = XLSchema(dialect: CompileFailSecondDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    ///
    /// The optional-operand counterparts of the query-backed `notIn`
    /// overloads. As with `in`, the result is `Optional<Bool>` because a NULL
    /// operand or a NULL in the candidate set makes the answer unknown.
    ///
    @_disfavoredOverload
    func notIn<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as for `in`. Use the closure form without a schema for a
    ///   correlated query.
    @_disfavoredOverload
    func notIn<Wrapped>(@XLQueryExpressionBuilder expression: (XLSchema<CompileFailSecondDialect>) -> any XLQueryStatement<Wrapped>) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema(dialect: CompileFailSecondDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    @_disfavoredOverload
    func notIn(_ expressions: [any CompileFailSecondDialectExpression<T>]) -> some CompileFailSecondDialectExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            list: expressions,
            negated: true
        )
    }

    ///
    /// The counterpart of the optional-operand `in(_:)` overload. A NULL
    /// left-hand value makes the result NULL rather than true, so a `Where`
    /// clause filters that row.
    ///
    @_disfavoredOverload
    func notIn<Wrapped>(_ expressions: [any CompileFailSecondDialectExpression<Wrapped>]) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions,
            negated: true
        )
    }

    ///
    /// The `NOT IN` counterpart for a candidate set that may contain NULL. An
    /// exhausted search yields NULL rather than true if any element was NULL.
    ///
    /// Disfavoured for the same empty-array-literal reason as `in(_:)` above.
    ///
    @_disfavoredOverload
    func notIn<Wrapped>(_ expressions: [any CompileFailSecondDialectExpression<Optional<Wrapped>>]) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions,
            negated: true
        )
    }

    @_disfavoredOverload
    func notIn<T>(_ table: T) -> some CompileFailSecondDialectExpression<Bool> where T: XLMetaCommonTable, T.Result.Dialect == CompileFailSecondDialect {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias,
            negated: true
        )
    }
}


// MARK: - Scalar common tables


extension CompileFailSecondDialectExpression {

    ///
    /// Tests whether the expression appears in a scalar common table.
    ///
    @_disfavoredOverload
    func `in`<Value>(_ scalarCommonTable: XLScalarCommonTable<Value, CompileFailSecondDialect>) -> some CompileFailSecondDialectExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias)
    }

    ///
    /// Tests whether the expression does not appear in a scalar common table.
    ///
    @_disfavoredOverload
    func notIn<Value>(_ scalarCommonTable: XLScalarCommonTable<Value, CompileFailSecondDialect>) -> some CompileFailSecondDialectExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias, negated: true)
    }
}
