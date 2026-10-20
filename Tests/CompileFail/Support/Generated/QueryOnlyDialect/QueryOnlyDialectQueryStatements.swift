//
//  QueryOnlyDialectQueryStatements.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Select


///
/// Constructs a select statement that returns a scalar value.
///
/// The logical result type is unconstrained. Bare contextual values can be
/// rendered here, but decoding them requires an `XLStaticRowLayout` carrying
/// result codec metadata.
///
func select<T>(
    _ expression: any QueryOnlyDialectExpression<T>
) -> XLQuerySelectStatement<T, QueryOnlyDialect> {
    XLQuerySelectStatement(components: XLQueryStatementComponents(select: Select<T, QueryOnlyDialect>(_dialectSurface: expression)))
}


extension XLWithStatement where Dialect == QueryOnlyDialect {

    /// Builds a factored scalar select without constraining its logical result
    /// type. Contextual-only values still need a static row layout for decoding.
    func select<T>(
        _ expression: any QueryOnlyDialectExpression<T>
    ) -> XLQuerySelectStatement<T, QueryOnlyDialect> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select<T, QueryOnlyDialect>(_dialectSurface: expression)))
    }
}


// MARK: - From


extension XLQueryTableStatement where Dialect == QueryOnlyDialect {

    // MARK: Join

    func innerJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLQueryTableStatement<Row, QueryOnlyDialect> where T: XLMetaNamedResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    func leftJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLQueryTableStatement<Row, QueryOnlyDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `RIGHT JOIN`. The joined table stays non-nullable; declare the
    /// `FROM` table with `nullableTable(_:)` so its columns decode as optionals.
    /// Requires SQLite 3.39.0 or later.
    ///
    func rightJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLQueryTableStatement<Row, QueryOnlyDialect> where T: XLMetaNamedResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .rightJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `FULL OUTER JOIN`. Both sides can be `NULL`: the joined table is
    /// nullable, and the `FROM` table must be declared with `nullableTable(_:)`.
    /// Requires SQLite 3.39.0 or later.
    ///
    func fullOuterJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLQueryTableStatement<Row, QueryOnlyDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .fullOuterJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    func `where`<T>(_ condition: any QueryOnlyDialectExpression<T>) -> XLQueryWhereStatement<Row, QueryOnlyDialect> where T: XLBoolean {
        XLQueryWhereStatement(components: components.appending(Where<QueryOnlyDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    func groupBy(_ expressions: any QueryOnlyDialectExpression...) -> XLQueryGroupByStatement<Row, QueryOnlyDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<QueryOnlyDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Where


extension XLQueryWhereStatement where Dialect == QueryOnlyDialect {

    func groupBy(_ expressions: any QueryOnlyDialectExpression...) -> XLQueryGroupByStatement<Row, QueryOnlyDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<QueryOnlyDialect>(_dialectSurface: expressions)))
    }

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Group By


extension XLQueryGroupByStatement where Dialect == QueryOnlyDialect {

    func having<T>(_ condition: any QueryOnlyDialectExpression<T>) -> XLQueryHavingStatement<Row, QueryOnlyDialect> where T: XLBoolean {
        XLQueryHavingStatement(components: components.appending(Having<QueryOnlyDialect>(_dialectSurface: condition)))
    }

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Having


extension XLQueryHavingStatement where Dialect == QueryOnlyDialect {

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Union


extension XLQueryUnionStatement where Dialect == QueryOnlyDialect {

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Order By


extension XLQueryOrderByStatement where Dialect == QueryOnlyDialect {

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryLimitStatement<Row, QueryOnlyDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Limit


extension XLQueryLimitStatement where Dialect == QueryOnlyDialect {

    func offset(_ count: any QueryOnlyDialectExpression<Int>) -> XLQueryOffsetStatement<Row, QueryOnlyDialect> {
        XLQueryOffsetStatement(components: components.appending(Offset<QueryOnlyDialect>(_dialectSurface: count)))
    }
}
