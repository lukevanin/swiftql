//
//  SQLDataChangingStatements+SQLite.swift
//
//  SQLite's own data-changing statements: INSERT OR and REPLACE. Split from
//  SQLDataChangingStatements.swift, whose upsert is every dialect's
//  (issue #790).
//

import Foundation


///
/// Constructs an `INSERT OR <action> INTO` statement.
///
public func insert<T>(_ meta: T, or action: XLInsertOrAction) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
    let components = XLInsertStatementComponents(insert: Insert(meta, or: action))
    return XLInsertTableStatement(components: components)
}


///
/// Constructs a `REPLACE INTO` statement.
///
public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
    let components = XLInsertStatementComponents(insert: Replace(meta).insert)
    return XLInsertTableStatement(components: components)
}


extension XLWithStatement where Dialect == XLSQLiteDialect {

    ///
    /// Constructs a `REPLACE INTO` statement scoped by the with clause's common
    /// table expressions.
    ///
    public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
        XLInsertTableStatement(
            components: XLInsertStatementComponents(commonTables: commonTables, insert: Replace(meta).insert)
        )
    }
}
