//
//  InOperator.swift
//  
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


// MARK: - IN

extension XLExpression {

    public func `in`(expression: () -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    public func `in`(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        let schema = XLSchema()
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }

    ///
    /// Membership of an optional value in the results of `expression`.
    ///
    /// The result is `Optional<Bool>` because SQLite yields NULL when the
    /// left-hand value is NULL, or when no row matches and the candidate set
    /// contains NULL.
    ///
    public func `in`<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    public func `in`<Wrapped>(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema()
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }
    public func `in`(_ expressions: [any XLExpression<T>]) -> some XLExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions)
        )
    }

    public func `in`<Wrapped>(_ expressions: [any XLExpression<Wrapped>]) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions)
        )
    }

    ///
    /// Membership in a candidate set that may itself contain NULL.
    ///
    /// SQLite compares against each element in turn: a match yields true even
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
    public func `in`<Wrapped>(_ expressions: [any XLExpression<Optional<Wrapped>>]) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions)
        )
    }

    public func `in`<T>(_ table: T) -> some XLExpression<Bool> where T: XLMetaCommonTable {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias
        )
    }
}


// MARK: - NOT IN


extension XLExpression {

    ///
    /// Matches rows whose value is absent from the results of `expression`.
    ///
    /// SQLite evaluates `NOT IN` as the negation of `IN`, so an unmatched value
    /// compared against a set containing NULL is NULL rather than true. The
    /// one exception is an empty set, where `NOT IN` is true even for a NULL
    /// operand.
    ///
    public func notIn(expression: () -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    public func notIn(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        let schema = XLSchema()
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    ///
    /// The optional-operand counterparts of the query-backed `notIn`
    /// overloads. As with `in`, the result is `Optional<Bool>` because a NULL
    /// operand or a NULL in the candidate set makes the answer unknown.
    ///
    public func notIn<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    public func notIn<Wrapped>(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        let schema = XLSchema()
        return XLInValueExpression(lhs: self, rhs: expression(schema), negated: true)
    }

    public func notIn(_ expressions: [any XLExpression<T>]) -> some XLExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions),
            negated: true
        )
    }

    ///
    /// The counterpart of the optional-operand `in(_:)` overload. A NULL
    /// left-hand value makes the result NULL rather than true, so a `Where`
    /// clause filters that row.
    ///
    public func notIn<Wrapped>(_ expressions: [any XLExpression<Wrapped>]) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions),
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
    public func notIn<Wrapped>(_ expressions: [any XLExpression<Optional<Wrapped>>]) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .list, expressions: expressions),
            negated: true
        )
    }

    public func notIn<T>(_ table: T) -> some XLExpression<Bool> where T: XLMetaCommonTable {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias,
            negated: true
        )
    }
}
