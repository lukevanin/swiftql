//
//  SQLCreateExpressionBuilder+SQLite.swift
//
//  SQLite's spelling of the create expression builder and its sql { }
//  statement. Split from SQLCreateExpressionBuilder.swift, whose builder
//  is every dialect's (issue #790).
//

import Foundation


///
/// Constructs a SQLite Create expression.
///
public func sql<Table>(@XLCreateExpressionBuilder<Table> builder: (XLSQLiteSchema) -> any XLCreateStatement<Table>) -> any XLCreateStatement<Table> where Table: XLTable, Table.XLModelDialect == XLSQLiteDialect {
    let schema = XLSchema()
    return builder(schema)
}
