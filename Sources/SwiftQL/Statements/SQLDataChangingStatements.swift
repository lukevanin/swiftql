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
