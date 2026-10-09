//
//  SQLUpdateExpressionBuilder+SQLite.swift
//
//  SQLite's spelling of the update expression builder and its sql { }
//  statement. Split from SQLUpdateExpressionBuilder.swift, whose builder
//  is every dialect's (issue #790).
//

import Foundation


///
/// Result builder used to construct a SQLite Update statement.
///
public typealias XLUpdateExpressionBuilder = XLDialectUpdateExpressionBuilder<XLSQLiteDialect>


///
/// Constructs a SQLite Update statement.
///
public func sql(@XLUpdateExpressionBuilder builder: (XLSQLiteSchema) -> any XLUpdateStatement) -> any XLUpdateStatement {
    let schema = XLSchema()
    return builder(schema)
}
