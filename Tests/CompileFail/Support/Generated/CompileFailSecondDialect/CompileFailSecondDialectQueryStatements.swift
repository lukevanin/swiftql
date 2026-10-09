//
//  CompileFailSecondDialectQueryStatements.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/QueryStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Select


///
/// Constructs a select statement that returns a scalar value.
///
/// The logical result type is unconstrained. Bare contextual values can be
/// rendered here, but decoding them requires an `XLStaticRowLayout` carrying
/// result codec metadata.
///
@_disfavoredOverload
func select<T>(
    _ expression: any CompileFailSecondDialectExpression<T>
) -> XLQuerySelectStatement<T, CompileFailSecondDialect> {
    XLQuerySelectStatement(components: XLQueryStatementComponents(select: Select<T, CompileFailSecondDialect>(_dialectSurface: expression)))
}


extension XLWithStatement where Dialect == CompileFailSecondDialect {

    /// Builds a factored scalar select without constraining its logical result
    /// type. Contextual-only values still need a static row layout for decoding.
    @_disfavoredOverload
    func select<T>(
        _ expression: any CompileFailSecondDialectExpression<T>
    ) -> XLQuerySelectStatement<T, CompileFailSecondDialect> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select<T, CompileFailSecondDialect>(_dialectSurface: expression)))
    }
}


// MARK: - From


extension XLQueryTableStatement where Dialect == CompileFailSecondDialect {

    // MARK: Join

    @_disfavoredOverload
    func innerJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLQueryTableStatement<Row, CompileFailSecondDialect> where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    @_disfavoredOverload
    func leftJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLQueryTableStatement<Row, CompileFailSecondDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `RIGHT JOIN`. The joined table stays non-nullable; declare the
    /// `FROM` table with `nullableTable(_:)` so its columns decode as optionals.
    /// Requires SQLite 3.39.0 or later.
    ///
    @_disfavoredOverload
    func rightJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLQueryTableStatement<Row, CompileFailSecondDialect> where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .rightJoin, table: t, constraint: condition)))
    }

    ///
    /// Adds a `FULL OUTER JOIN`. Both sides can be `NULL`: the joined table is
    /// nullable, and the `FROM` table must be declared with `nullableTable(_:)`.
    /// Requires SQLite 3.39.0 or later.
    ///
    @_disfavoredOverload
    func fullOuterJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLQueryTableStatement<Row, CompileFailSecondDialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .fullOuterJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    @_disfavoredOverload
    func `where`<T>(_ condition: any CompileFailSecondDialectExpression<T>) -> XLQueryWhereStatement<Row, CompileFailSecondDialect> where T: XLBoolean {
        XLQueryWhereStatement(components: components.appending(Where<CompileFailSecondDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    @_disfavoredOverload
    func groupBy(_ expressions: any CompileFailSecondDialectExpression...) -> XLQueryGroupByStatement<Row, CompileFailSecondDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<CompileFailSecondDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Where


extension XLQueryWhereStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func groupBy(_ expressions: any CompileFailSecondDialectExpression...) -> XLQueryGroupByStatement<Row, CompileFailSecondDialect> {
        XLQueryGroupByStatement(components: components.appending(GroupBy<CompileFailSecondDialect>(_dialectSurface: expressions)))
    }

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Group By


extension XLQueryGroupByStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func having<T>(_ condition: any CompileFailSecondDialectExpression<T>) -> XLQueryHavingStatement<Row, CompileFailSecondDialect> where T: XLBoolean {
        XLQueryHavingStatement(components: components.appending(Having<CompileFailSecondDialect>(_dialectSurface: condition)))
    }

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Having


extension XLQueryHavingStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Union


extension XLQueryUnionStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Order By


extension XLQueryOrderByStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryLimitStatement<Row, CompileFailSecondDialect> {
        XLQueryLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Limit


extension XLQueryLimitStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func offset(_ count: any CompileFailSecondDialectExpression<Int>) -> XLQueryOffsetStatement<Row, CompileFailSecondDialect> {
        XLQueryOffsetStatement(components: components.appending(Offset<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}
