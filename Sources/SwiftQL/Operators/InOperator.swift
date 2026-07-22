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

    // Currently this creates ambiguous expressions with the in operator for non-null expressions. Possibly a solution
    // is to remove XLLiteral and/or XLExpression conformance from Optional.
    public func `in`<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        return XLInValueExpression(lhs: self, rhs: expression())
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
    /// operand. Optional operand shapes are tracked by
    /// [#68](https://github.com/lukevanin/swiftql/issues/68).
    ///
    public func notIn(expression: () -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        XLInValueExpression(lhs: self, rhs: expression(), negated: true)
    }

    public func notIn(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
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

    public func notIn<T>(_ table: T) -> some XLExpression<Bool> where T: XLMetaCommonTable {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias,
            negated: true
        )
    }
}
