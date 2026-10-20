//
//  QueryOnlyDialectInOperator.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/InOperator.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - IN

extension QueryOnlyDialectExpression {

    func `in`(expression: () -> any XLDialectQueryStatement<T, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> {
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
    func `in`(@XLDialectQueryExpressionBuilder<QueryOnlyDialect> expression: (XLSchema<QueryOnlyDialect>) -> any XLDialectQueryStatement<T, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> {
        let schema = XLSchema(dialect: QueryOnlyDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }

    ///
    /// Membership of an optional value in the results of `expression`.
    ///
    /// The result is `Optional<Bool>` because SQL yields NULL when the
    /// left-hand value is NULL, or when no row matches and the candidate set
    /// contains NULL.
    ///
    func `in`<Wrapped>(expression: () -> any XLDialectQueryStatement<Wrapped, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as in the non-optional overload. Use the closure form without
    ///   a schema for a correlated query.
    func `in`<Wrapped>(@XLDialectQueryExpressionBuilder<QueryOnlyDialect> expression: (XLSchema<QueryOnlyDialect>) -> any XLDialectQueryStatement<Wrapped, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema(dialect: QueryOnlyDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }
    func `in`(_ expressions: [any QueryOnlyDialectExpression<T>]) -> some QueryOnlyDialectExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            list: expressions
        )
    }

    func `in`<Wrapped>(_ expressions: [any QueryOnlyDialectExpression<Wrapped>]) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
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
    func `in`<Wrapped>(_ expressions: [any QueryOnlyDialectExpression<Optional<Wrapped>>]) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions
        )
    }

    func `in`<T>(_ table: T) -> some QueryOnlyDialectExpression<Bool> where T: XLMetaCommonTable, T.Result.XLModelDialect == QueryOnlyDialect {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias
        )
    }
}


// MARK: - NOT IN


extension QueryOnlyDialectExpression {

    ///
    /// Matches rows whose value is absent from the results of `expression`.
    ///
    /// SQL evaluates `NOT IN` as the negation of `IN`, so an unmatched value
    /// compared against a set containing NULL is NULL rather than true. In
    /// SQLite the one exception is an empty set, where `NOT IN` is true even
    /// for a NULL operand.
    ///
    func notIn(expression: () -> any XLDialectQueryStatement<T, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as for `in`. Use the closure form without a schema for a
    ///   correlated query.
    func notIn(@XLDialectQueryExpressionBuilder<QueryOnlyDialect> expression: (XLSchema<QueryOnlyDialect>) -> any XLDialectQueryStatement<T, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> {
        let schema = XLSchema(dialect: QueryOnlyDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    ///
    /// The optional-operand counterparts of the query-backed `notIn`
    /// overloads. As with `in`, the result is `Optional<Bool>` because a NULL
    /// operand or a NULL in the candidate set makes the answer unknown.
    ///
    func notIn<Wrapped>(expression: () -> any XLDialectQueryStatement<Wrapped, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    /// - Important: The schema passed to `expression` starts an independent
    ///   scope, as for `in`. Use the closure form without a schema for a
    ///   correlated query.
    func notIn<Wrapped>(@XLDialectQueryExpressionBuilder<QueryOnlyDialect> expression: (XLSchema<QueryOnlyDialect>) -> any XLDialectQueryStatement<Wrapped, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema(dialect: QueryOnlyDialect.self)
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    func notIn(_ expressions: [any QueryOnlyDialectExpression<T>]) -> some QueryOnlyDialectExpression<Bool> {
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
    func notIn<Wrapped>(_ expressions: [any QueryOnlyDialectExpression<Wrapped>]) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
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
    func notIn<Wrapped>(_ expressions: [any QueryOnlyDialectExpression<Optional<Wrapped>>]) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            list: expressions,
            negated: true
        )
    }

    func notIn<T>(_ table: T) -> some QueryOnlyDialectExpression<Bool> where T: XLMetaCommonTable, T.Result.XLModelDialect == QueryOnlyDialect {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias,
            negated: true
        )
    }
}


// MARK: - Scalar common tables


extension QueryOnlyDialectExpression {

    ///
    /// Tests whether the expression appears in a scalar common table.
    ///
    func `in`<Value>(_ scalarCommonTable: XLScalarCommonTable<Value, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias)
    }

    ///
    /// Tests whether the expression does not appear in a scalar common table.
    ///
    func notIn<Value>(_ scalarCommonTable: XLScalarCommonTable<Value, QueryOnlyDialect>) -> some QueryOnlyDialectExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias, negated: true)
    }
}
