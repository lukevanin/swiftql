//
//  QueryOnlyDialectQueryBuilder.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryBuilder.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension XLDialectQueryBuilder where Dialect == QueryOnlyDialect {

    ///
    /// Creates a query builder using an expression. The expression should use one or more fields in one or
    /// more tables in the from clause.
    ///
    /// The logical result type is unconstrained. Contextual-only values still
    /// require a static row layout to supply result codec metadata.
    ///
    init(select expression: any QueryOnlyDialectExpression<Row>) {
        self.init(select: Select<Row, QueryOnlyDialect>(_dialectSurface: expression))
    }

    ///
    /// Adds an inner join clause to the query.
    ///
    func innerJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an inner join clause to the query, using an optional field.
    ///
    func innerJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    func leftJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    func leftJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    func leftJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    func leftJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query. The joined table stays non-nullable;
    /// declare the from table with `from(_:)`'s nullable overload so its columns
    /// decode as optionals. Requires SQLite 3.39.0 or later.
    ///
    func rightJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query, using an optional constraint.
    ///
    func rightJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query. Both sides can be `NULL`: the joined
    /// table is nullable, and the from table must be declared with `from(_:)`'s
    /// nullable overload. Requires SQLite 3.39.0 or later.
    ///
    func fullOuterJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query, using an optional constraint.
    ///
    func fullOuterJoin<T>(_ table: T, on constraint: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order: each call combines the whole condition so far
    /// with its term. `and(a).or(b).and(c)` renders `((a OR b) AND c)`. Build
    /// a grouped expression and pass it as one term for another grouping.
    ///
    func and(_ condition: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceAnd(condition)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    func and(_ condition: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
        _dialectSurfaceAnd(condition)
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    /// Terms fold in call order: each call combines the whole condition so far
    /// with its term. `and(a).or(b).and(c)` renders `((a OR b) AND c)`. The
    /// operator of the first term is not used, so `or(a).and(b)` renders
    /// `(a AND b)`.
    ///
    func or(_ condition: any QueryOnlyDialectExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceOr(condition)
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    func or(_ condition: any QueryOnlyDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
        _dialectSurfaceOr(condition)
    }

    ///
    /// Adds a group by expression to the where clause.
    ///
    func groupBy(_ expression: any QueryOnlyDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceGroupBy(expression)
    }

    ///
    /// Adds a limit clause.
    ///
    func limit(_ expression: any QueryOnlyDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceLimit(expression)
    }

    ///
    /// Adds an offset clause.
    ///
    /// SQLite requires an explicit limit before an offset. `build()` throws if an offset is set without a
    /// limit. Use `limit(-1).offset(n)` to apply an offset without an upper bound.
    ///
    func offset(_ expression: any QueryOnlyDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceOffset(expression)
    }
}
