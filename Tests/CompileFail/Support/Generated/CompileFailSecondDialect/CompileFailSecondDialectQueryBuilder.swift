//
//  CompileFailSecondDialectQueryBuilder.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryBuilder.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


extension XLDialectQueryBuilder where Dialect == CompileFailSecondDialect {

    ///
    /// Creates a query builder using an expression. The expression should use one or more fields in one or
    /// more tables in the from clause.
    ///
    /// The logical result type is unconstrained. Contextual-only values still
    /// require a static row layout to supply result codec metadata.
    ///
    @_disfavoredOverload
    init(select expression: any CompileFailSecondDialectExpression<Row>) {
        self.init(select: Select<Row, CompileFailSecondDialect>(_dialectSurface: expression))
    }

    ///
    /// Adds an inner join clause to the query.
    ///
    @_disfavoredOverload
    func innerJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an inner join clause to the query, using an optional field.
    ///
    @_disfavoredOverload
    func innerJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    @_disfavoredOverload
    func leftJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    @_disfavoredOverload
    func leftJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    @_disfavoredOverload
    func leftJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    @_disfavoredOverload
    func leftJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query. The joined table stays non-nullable;
    /// declare the from table with `from(_:)`'s nullable overload so its columns
    /// decode as optionals. Requires SQLite 3.39.0 or later.
    ///
    @_disfavoredOverload
    func rightJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query, using an optional constraint.
    ///
    @_disfavoredOverload
    func rightJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query. Both sides can be `NULL`: the joined
    /// table is nullable, and the from table must be declared with `from(_:)`'s
    /// nullable overload. Requires SQLite 3.39.0 or later.
    ///
    @_disfavoredOverload
    func fullOuterJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query, using an optional constraint.
    ///
    @_disfavoredOverload
    func fullOuterJoin<T>(_ table: T, on constraint: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order: each call combines the whole condition so far
    /// with its term. `and(a).or(b).and(c)` renders `((a OR b) AND c)`. Build
    /// a grouped expression and pass it as one term for another grouping.
    ///
    @_disfavoredOverload
    func and(_ condition: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceAnd(condition)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    @_disfavoredOverload
    func and(_ condition: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
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
    @_disfavoredOverload
    func or(_ condition: any CompileFailSecondDialectExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceOr(condition)
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    @_disfavoredOverload
    func or(_ condition: any CompileFailSecondDialectExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
        _dialectSurfaceOr(condition)
    }

    ///
    /// Adds a group by expression to the where clause.
    ///
    @_disfavoredOverload
    func groupBy(_ expression: any CompileFailSecondDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceGroupBy(expression)
    }

    ///
    /// Adds a limit clause.
    ///
    @_disfavoredOverload
    func limit(_ expression: any CompileFailSecondDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceLimit(expression)
    }

    ///
    /// Adds an offset clause.
    ///
    /// SQLite requires an explicit limit before an offset. `build()` throws if an offset is set without a
    /// limit. Use `limit(-1).offset(n)` to apply an offset without an upper bound.
    ///
    @_disfavoredOverload
    func offset(_ expression: any CompileFailSecondDialectExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceOffset(expression)
    }
}
