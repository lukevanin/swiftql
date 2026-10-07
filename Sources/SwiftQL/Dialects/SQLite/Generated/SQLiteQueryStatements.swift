//
//  SQLiteQueryStatements.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Select


///
/// Constructs a select statement that returns a scalar value.
///
/// The logical result type is unconstrained. Bare contextual values can be
/// rendered here, but decoding them requires an ``XLStaticRowLayout`` carrying
/// result codec metadata.
///
public func select<T>(
    _ expression: any XLSQLiteExpression<T>
) -> XLQuerySelectStatement<T, XLSQLiteDialect> {
    XLQuerySelectStatement(components: XLQueryStatementComponents(select: Select<T, XLSQLiteDialect>(_dialectSurface: expression)))
}


extension XLWithStatement where Dialect == XLSQLiteDialect {

    /// Builds a factored scalar select without constraining its logical result
    /// type. Contextual-only values still need a static row layout for decoding.
    public func select<T>(
        _ expression: any XLSQLiteExpression<T>
    ) -> XLQuerySelectStatement<T, XLSQLiteDialect> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select<T, XLSQLiteDialect>(_dialectSurface: expression)))
    }
}


// MARK: - From


extension XLQueryTableStatement where Dialect == XLSQLiteDialect {

    // MARK: Join

    public func innerJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLQueryTableStatement<Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    public func leftJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLQueryTableStatement<Row, XLSQLiteDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `RIGHT JOIN`. The joined table stays non-nullable; declare the
    /// `FROM` table with `nullableTable(_:)` so its columns decode as optionals.
    /// Requires SQLite 3.39.0 or later.
    ///
    public func rightJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLQueryTableStatement<Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .rightJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `FULL OUTER JOIN`. Both sides can be `NULL`: the joined table is
    /// nullable, and the `FROM` table must be declared with `nullableTable(_:)`.
    /// Requires SQLite 3.39.0 or later.
    ///
    public func fullOuterJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLQueryTableStatement<Row, XLSQLiteDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .fullOuterJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    public func `where`<T>(_ condition: any XLSQLiteExpression<T>) -> XLQueryWhereStatement<Row, XLSQLiteDialect> where T: XLBoolean {
        XLQueryWhereStatement(components: components.appending(Where<XLSQLiteDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    public func groupBy(_ expressions: any XLSQLiteExpression...) -> XLQueryGroupByStatement<Row, XLSQLiteDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<XLSQLiteDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Where


extension XLQueryWhereStatement where Dialect == XLSQLiteDialect {

    public func groupBy(_ expressions: any XLSQLiteExpression...) -> XLQueryGroupByStatement<Row, XLSQLiteDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<XLSQLiteDialect>(_dialectSurface: expressions)))
    }

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Group By


extension XLQueryGroupByStatement where Dialect == XLSQLiteDialect {

    public func having<T>(_ condition: any XLSQLiteExpression<T>) -> XLQueryHavingStatement<Row, XLSQLiteDialect> where T: XLBoolean {
        XLQueryHavingStatement(components: components.appending(Having<XLSQLiteDialect>(_dialectSurface: condition)))
    }

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Having


extension XLQueryHavingStatement where Dialect == XLSQLiteDialect {

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Union


extension XLQueryUnionStatement where Dialect == XLSQLiteDialect {

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Order By


extension XLQueryOrderByStatement where Dialect == XLSQLiteDialect {

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLQueryLimitStatement<Row, XLSQLiteDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Limit


extension XLQueryLimitStatement where Dialect == XLSQLiteDialect {

    public func offset(_ count: any XLSQLiteExpression<Int>) -> XLQueryOffsetStatement<Row, XLSQLiteDialect> {
        XLQueryOffsetStatement(components: components.appending(Offset<XLSQLiteDialect>(_dialectSurface: count)))
    }
}
