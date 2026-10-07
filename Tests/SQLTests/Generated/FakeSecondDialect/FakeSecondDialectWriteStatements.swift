//
//  FakeSecondDialectWriteStatements.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/WriteStatements.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Insert ... select


extension XLInsertSelectTableStatement where Dialect == FakeSecondDialect {

    // MARK: Join

    @_disfavoredOverload
    func innerJoin<T, U>(_ t: T, on condition: any FakeSecondDialectExpression<U>) -> XLInsertSelectTableStatement<Row, FakeSecondDialect> where T: XLMetaResult, T.XLModelDialect == FakeSecondDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<FakeSecondDialect>(_dialectSurfaceKind: .innerJoin, table: t, constraint: condition)))
    }

    @_disfavoredOverload
    func leftJoin<T, U>(_ t: T, on condition: any FakeSecondDialectExpression<U>) -> XLInsertSelectTableStatement<Row, FakeSecondDialect> where T: XLMetaNullableResult, T.XLModelDialect == FakeSecondDialect, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join<FakeSecondDialect>(_dialectSurfaceKind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where

    @_disfavoredOverload
    func `where`<T>(_ condition: any FakeSecondDialectExpression<T>) -> XLInsertSelectWhereStatement<Row, FakeSecondDialect> where T: XLBoolean {
        XLInsertSelectWhereStatement(components: components.appending(Where<FakeSecondDialect>(_dialectSurface: condition)))
    }

    // MARK: Group

    @_disfavoredOverload
    func groupBy(_ expressions: any FakeSecondDialectExpression...) -> XLInsertSelectGroupByStatement<Row, FakeSecondDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<FakeSecondDialect>(_dialectSurface: expressions)))
    }

    // MARK: Limit

    @_disfavoredOverload
    func limit(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, FakeSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<FakeSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectWhereStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func groupBy(_ expressions: any FakeSecondDialectExpression...) -> XLInsertSelectGroupByStatement<Row, FakeSecondDialect> {
        XLInsertSelectGroupByStatement(components: components.appending(GroupBy<FakeSecondDialect>(_dialectSurface: expressions)))
    }

    @_disfavoredOverload
    func limit(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, FakeSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<FakeSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectGroupByStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func having<T>(_ condition: any FakeSecondDialectExpression<T>) -> XLInsertSelectHavingStatement<Row, FakeSecondDialect> where T: XLBoolean {
        XLInsertSelectHavingStatement(components: components.appending(Having<FakeSecondDialect>(_dialectSurface: condition)))
    }

    @_disfavoredOverload
    func limit(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, FakeSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<FakeSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectHavingStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, FakeSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<FakeSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectOrderByStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func limit(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectLimitStatement<Row, FakeSecondDialect> {
        XLInsertSelectLimitStatement(components: components.appending(Limit<FakeSecondDialect>(_dialectSurface: count)))
    }
}


extension XLInsertSelectLimitStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func offset(_ count: any FakeSecondDialectExpression<Int>) -> XLInsertSelectOffsetStatement<Row, FakeSecondDialect> {
        XLInsertSelectOffsetStatement(components: components.appending(Offset<FakeSecondDialect>(_dialectSurface: count)))
    }
}


// MARK: - Update


extension XLUpdateSetStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func `where`<U>(_ expression: any FakeSecondDialectExpression<U>) -> XLUpdateWhereStatement<Row, FakeSecondDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<FakeSecondDialect>(_dialectSurface: expression)))
    }
}


extension XLUpdateFromStatement where Dialect == FakeSecondDialect {

    @_disfavoredOverload
    func `where`<U>(_ expression: any FakeSecondDialectExpression<U>) -> XLUpdateWhereStatement<Row, FakeSecondDialect> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where<FakeSecondDialect>(_dialectSurface: expression)))
    }
}


// MARK: - Delete


extension XLDeleteTableStatement where Dialect == FakeSecondDialect {

    ///
    /// Adds a where clause to the delete statement.
    ///
    @_disfavoredOverload
    func `where`<U>(_ expression: any FakeSecondDialectExpression<U>) -> XLDeleteWhereStatement<Table, FakeSecondDialect> where U: XLBoolean {
        XLDeleteWhereStatement(components: components.appending(Where<FakeSecondDialect>(_dialectSurface: expression)))
    }
}
