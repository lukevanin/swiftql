//
//  SQLDataChangingStatements.swift
//
//  Shared surface for the v1.4.4 data-changing statement features.
//

import Foundation


///
/// Constructs an `INSERT OR <action> INTO` statement.
///
public func insert<T>(_ meta: T, or action: XLInsertOrAction) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Insert(meta, or: action))
    return XLInsertTableStatement(components: components)
}


///
/// Constructs a `REPLACE INTO` statement.
///
public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Replace(meta).insert)
    return XLInsertTableStatement(components: components)
}


extension XLWithStatement {

    ///
    /// Constructs a `REPLACE INTO` statement scoped by the with clause's common
    /// table expressions.
    ///
    public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
        XLInsertTableStatement(
            components: XLInsertStatementComponents(commonTables: commonTables, insert: Replace(meta).insert)
        )
    }
}
