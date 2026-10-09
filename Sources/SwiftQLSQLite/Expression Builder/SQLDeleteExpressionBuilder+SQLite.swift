//
//  SQLDeleteExpressionBuilder+SQLite.swift
//
//  SQLite's spelling of the delete expression builder and its sql { }
//  statement. Split from SQLDeleteExpressionBuilder.swift, whose builder
//  is every dialect's (issue #790).
//

import Foundation


///
/// Result builder used to construct a SQLite delete statement.
///
public typealias XLDeleteExpressionBuilder = XLDialectDeleteExpressionBuilder<XLSQLiteDialect>


///
/// Constructs a SQLite delete expression.
///
public func sql(@XLDeleteExpressionBuilder builder: (XLSQLiteSchema) -> any XLDeleteStatement) -> any XLDeleteStatement {
    let schema = XLSchema()
    return builder(schema)
}
