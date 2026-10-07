//
//  SQLiteQueryBuilder.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryBuilder.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


extension XLDialectQueryBuilder where Dialect == XLSQLiteDialect {

    ///
    /// Creates a query builder using an expression. The expression should use one or more fields in one or
    /// more tables in the from clause.
    ///
    /// The logical result type is unconstrained. Contextual-only values still
    /// require a static row layout to supply result codec metadata.
    ///
    public init(select expression: any XLSQLiteExpression<Row>) {
        self.init(select: Select<Row, XLSQLiteDialect>(_dialectSurface: expression))
    }

    ///
    /// Adds an inner join clause to the query.
    ///
    public func innerJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an inner join clause to the query, using an optional field.
    ///
    public func innerJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query. The joined table stays non-nullable;
    /// declare the from table with `from(_:)`'s nullable overload so its columns
    /// decode as optionals. Requires SQLite 3.39.0 or later.
    ///
    public func rightJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a right join to the query, using an optional constraint.
    ///
    public func rightJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query. Both sides can be `NULL`: the joined
    /// table is nullable, and the from table must be declared with `from(_:)`'s
    /// nullable overload. Requires SQLite 3.39.0 or later.
    ///
    public func fullOuterJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds a full outer join to the query, using an optional constraint.
    ///
    public func fullOuterJoin<T>(_ table: T, on constraint: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect {
        _dialectSurfaceJoin(.fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order: each call combines the whole condition so far
    /// with its term. `and(a).or(b).and(c)` renders `((a OR b) AND c)`. Build
    /// a grouped expression and pass it as one term for another grouping.
    ///
    public func and(_ condition: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceWhereTerm("AND", condition: condition)
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    public func and(_ condition: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
        _dialectSurfaceWhereTerm("AND", condition: condition)
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    /// Terms fold in call order: each call combines the whole condition so far
    /// with its term. `and(a).or(b).and(c)` renders `((a OR b) AND c)`. The
    /// operator of the first term is not used, so `or(a).and(b)` renders
    /// `(a AND b)`.
    ///
    public func or(_ condition: any XLSQLiteExpression<Bool>) -> XLDialectQueryBuilder {
        _dialectSurfaceWhereTerm("OR", condition: condition)
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    /// Terms fold in call order, as for the non-optional overload.
    ///
    public func or(_ condition: any XLSQLiteExpression<Optional<Bool>>) -> XLDialectQueryBuilder {
        _dialectSurfaceWhereTerm("OR", condition: condition)
    }

    ///
    /// Adds a group by expression to the where clause.
    ///
    public func groupBy(_ expression: any XLSQLiteExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceGroupBy(expression)
    }

    ///
    /// Adds a limit clause.
    ///
    public func limit(_ expression: any XLSQLiteExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceLimit(expression)
    }

    ///
    /// Adds an offset clause.
    ///
    /// SQLite requires an explicit limit before an offset. `build()` throws if an offset is set without a
    /// limit. Use `limit(-1).offset(n)` to apply an offset without an upper bound.
    ///
    public func offset(_ expression: any XLSQLiteExpression) -> XLDialectQueryBuilder {
        _dialectSurfaceOffset(expression)
    }
}
