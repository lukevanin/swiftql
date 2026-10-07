//
//  SQLiteWriteStatements.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/WriteStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Insert ... select


extension XLInsertSelectTableStatement where Dialect == XLSQLiteDialect {

    // MARK: Join

    public func innerJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLInsertSelectTableStatement<Row, XLSQLiteDialect> where T: XLMetaResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    public func leftJoin<T, U>(_ t: T, on condition: any XLSQLiteExpression<U>) -> XLInsertSelectTableStatement<Row, XLSQLiteDialect> where T: XLMetaNullableResult, T.XLModelDialect == XLSQLiteDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<XLSQLiteDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    public func `where`<T>(_ condition: any XLSQLiteExpression<T>) -> XLInsertSelectWhereStatement<Row, XLSQLiteDialect> where T: XLBoolean {
        XLInsertSelectWhereStatement(components: components.appending(Where<XLSQLiteDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    public func groupBy(_ expressions: any XLSQLiteExpression...) -> XLInsertSelectGroupByStatement<Row, XLSQLiteDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<XLSQLiteDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectLimitStatement<Row, XLSQLiteDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectWhereStatement where Dialect == XLSQLiteDialect {

    public func groupBy(_ expressions: any XLSQLiteExpression...) -> XLInsertSelectGroupByStatement<Row, XLSQLiteDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<XLSQLiteDialect>(_dialectSurface: expressions)))
    }

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectLimitStatement<Row, XLSQLiteDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectGroupByStatement where Dialect == XLSQLiteDialect {

    public func having<T>(_ condition: any XLSQLiteExpression<T>) -> XLInsertSelectHavingStatement<Row, XLSQLiteDialect> where T: XLBoolean {
        XLInsertSelectHavingStatement(components: components.appending(Having<XLSQLiteDialect>(_dialectSurface: condition)))
    }

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectLimitStatement<Row, XLSQLiteDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectHavingStatement where Dialect == XLSQLiteDialect {

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectLimitStatement<Row, XLSQLiteDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectOrderByStatement where Dialect == XLSQLiteDialect {

    public func limit(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectLimitStatement<Row, XLSQLiteDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectLimitStatement where Dialect == XLSQLiteDialect {

    public func offset(_ count: any XLSQLiteExpression<Int>) -> XLInsertSelectOffsetStatement<Row, XLSQLiteDialect> {
        XLInsertSelectOffsetStatement(components: components.appending(Offset<XLSQLiteDialect>(_dialectSurface: count)))
    }
}


// MARK: - Update


extension XLUpdateSetStatement where Dialect == XLSQLiteDialect {

    public func `where`<U>(_ expression: any XLSQLiteExpression<U>) -> XLUpdateWhereStatement<Row, XLSQLiteDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<XLSQLiteDialect>(_dialectSurface: expression)))
    }
}


extension XLUpdateFromStatement where Dialect == XLSQLiteDialect {

    public func `where`<U>(_ expression: any XLSQLiteExpression<U>) -> XLUpdateWhereStatement<Row, XLSQLiteDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<XLSQLiteDialect>(_dialectSurface: expression)))
    }
}


// MARK: - Delete


extension XLDeleteTableStatement where Dialect == XLSQLiteDialect {

    ///
    /// Adds a where clause to the delete statement.
    ///
    public func `where`<U>(_ expression: any XLSQLiteExpression<U>) -> XLDeleteWhereStatement<Table, XLSQLiteDialect> where U: XLBoolean {
        XLDeleteWhereStatement(components: components.appending(Where<XLSQLiteDialect>(_dialectSurface: expression)))
    }
}
