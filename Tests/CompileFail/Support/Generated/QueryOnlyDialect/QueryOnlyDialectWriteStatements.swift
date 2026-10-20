//
//  QueryOnlyDialectWriteStatements.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/WriteStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


// MARK: - Insert ... select


extension XLInsertSelectTableStatement where Dialect == QueryOnlyDialect {

    // MARK: Join

    func innerJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLInsertSelectTableStatement<Row, QueryOnlyDialect> where T: XLMetaResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    func leftJoin<T, U>(_ t: T, on condition: any QueryOnlyDialectExpression<U>) -> XLInsertSelectTableStatement<Row, QueryOnlyDialect> where T: XLMetaNullableResult, T.XLModelDialect == QueryOnlyDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<QueryOnlyDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    func `where`<T>(_ condition: any QueryOnlyDialectExpression<T>) -> XLInsertSelectWhereStatement<Row, QueryOnlyDialect> where T: XLBoolean {
        XLInsertSelectWhereStatement(components: components.appending(Where<QueryOnlyDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    func groupBy(_ expressions: any QueryOnlyDialectExpression...) -> XLInsertSelectGroupByStatement<Row, QueryOnlyDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<QueryOnlyDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, QueryOnlyDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectWhereStatement where Dialect == QueryOnlyDialect {

    func groupBy(_ expressions: any QueryOnlyDialectExpression...) -> XLInsertSelectGroupByStatement<Row, QueryOnlyDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<QueryOnlyDialect>(_dialectSurface: expressions)))
    }

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, QueryOnlyDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectGroupByStatement where Dialect == QueryOnlyDialect {

    func having<T>(_ condition: any QueryOnlyDialectExpression<T>) -> XLInsertSelectHavingStatement<Row, QueryOnlyDialect> where T: XLBoolean {
        XLInsertSelectHavingStatement(components: components.appending(Having<QueryOnlyDialect>(_dialectSurface: condition)))
    }

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, QueryOnlyDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectHavingStatement where Dialect == QueryOnlyDialect {

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, QueryOnlyDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectOrderByStatement where Dialect == QueryOnlyDialect {

    func limit(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, QueryOnlyDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectLimitStatement where Dialect == QueryOnlyDialect {

    func offset(_ count: any QueryOnlyDialectExpression<Int>) -> XLInsertSelectOffsetStatement<Row, QueryOnlyDialect> {
        XLInsertSelectOffsetStatement(components: components.appending(Offset<QueryOnlyDialect>(_dialectSurface: count)))
    }
}


// MARK: - Update


extension XLUpdateSetStatement where Dialect == QueryOnlyDialect {

    func `where`<U>(_ expression: any QueryOnlyDialectExpression<U>) -> XLUpdateWhereStatement<Row, QueryOnlyDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<QueryOnlyDialect>(_dialectSurface: expression)))
    }
}


extension XLUpdateFromStatement where Dialect == QueryOnlyDialect {

    func `where`<U>(_ expression: any QueryOnlyDialectExpression<U>) -> XLUpdateWhereStatement<Row, QueryOnlyDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<QueryOnlyDialect>(_dialectSurface: expression)))
    }
}


// MARK: - Delete


extension XLDeleteTableStatement where Dialect == QueryOnlyDialect {

    ///
    /// Adds a where clause to the delete statement.
    ///
    func `where`<U>(_ expression: any QueryOnlyDialectExpression<U>) -> XLDeleteWhereStatement<Table, QueryOnlyDialect> where U: XLBoolean {
        XLDeleteWhereStatement(components: components.appending(Where<QueryOnlyDialect>(_dialectSurface: expression)))
    }
}
