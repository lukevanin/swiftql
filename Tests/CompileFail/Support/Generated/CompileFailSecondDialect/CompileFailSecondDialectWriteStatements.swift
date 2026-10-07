//
//  CompileFailSecondDialectWriteStatements.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/WriteStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Insert ... select


extension XLInsertSelectTableStatement where Dialect == CompileFailSecondDialect {

    // MARK: Join

    @_disfavoredOverload
    func innerJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLInsertSelectTableStatement<Row, CompileFailSecondDialect> where T: XLMetaResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    @_disfavoredOverload
    func leftJoin<T, U>(_ t: T, on condition: any CompileFailSecondDialectExpression<U>) -> XLInsertSelectTableStatement<Row, CompileFailSecondDialect> where T: XLMetaNullableResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<CompileFailSecondDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    @_disfavoredOverload
    func `where`<T>(_ condition: any CompileFailSecondDialectExpression<T>) -> XLInsertSelectWhereStatement<Row, CompileFailSecondDialect> where T: XLBoolean {
        XLInsertSelectWhereStatement(components: components.appending(Where<CompileFailSecondDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    @_disfavoredOverload
    func groupBy(_ expressions: any CompileFailSecondDialectExpression...) -> XLInsertSelectGroupByStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<CompileFailSecondDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectWhereStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func groupBy(_ expressions: any CompileFailSecondDialectExpression...) -> XLInsertSelectGroupByStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<CompileFailSecondDialect>(_dialectSurface: expressions)))
    }

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectGroupByStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func having<T>(_ condition: any CompileFailSecondDialectExpression<T>) -> XLInsertSelectHavingStatement<Row, CompileFailSecondDialect> where T: XLBoolean {
        XLInsertSelectHavingStatement(components: components.appending(Having<CompileFailSecondDialect>(_dialectSurface: condition)))
    }

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectHavingStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectOrderByStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectLimitStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func offset(_ count: any CompileFailSecondDialectExpression<Int>) -> XLInsertSelectOffsetStatement<Row, CompileFailSecondDialect> {
        XLInsertSelectOffsetStatement(components: components.appending(Offset<CompileFailSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Update


extension XLUpdateSetStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func `where`<U>(_ expression: any CompileFailSecondDialectExpression<U>) -> XLUpdateWhereStatement<Row, CompileFailSecondDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<CompileFailSecondDialect>(_dialectSurface: expression)))
    }
}


extension XLUpdateFromStatement where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    func `where`<U>(_ expression: any CompileFailSecondDialectExpression<U>) -> XLUpdateWhereStatement<Row, CompileFailSecondDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<CompileFailSecondDialect>(_dialectSurface: expression)))
    }
}


// MARK: - Delete


extension XLDeleteTableStatement where Dialect == CompileFailSecondDialect {

    ///
    /// Adds a where clause to the delete statement.
    ///
    @_disfavoredOverload
    func `where`<U>(_ expression: any CompileFailSecondDialectExpression<U>) -> XLDeleteWhereStatement<Table, CompileFailSecondDialect> where U: XLBoolean {
        XLDeleteWhereStatement(components: components.appending(Where<CompileFailSecondDialect>(_dialectSurface: expression)))
    }
}
