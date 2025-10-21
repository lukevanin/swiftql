//
//  SQLCreateExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to construct a create statement..
///
@resultBuilder public struct XLCreateExpressionBuilder<Table> {
    
    ///
    /// Constructs an initial Create expression.
    ///
    public static func buildPartialBlock(first: Create<Table>) -> XLCreateTableStatement<Table> {
        XLCreateTableStatement(components: XLCreateTableStatementComponents(create: first))
    }
    
    ///
    /// Constructs a Create statement with an As clause.
    ///
    /// An As clause is used to specify a select query which is used to populate the contents of the newly
    /// created table.
    ///
    public static func buildPartialBlock(accumulated: XLCreateTableStatement<Table>, next: As<Table>) -> XLCreateTableAsStatement<Table> where Table: XLTable, Table.MetaCreateAs.Table == Table {
        let meta = Table.makeSQLCreateAs()
        let components = XLCreateTableStatementComponents(create: Create(meta), components: [next.queryStatement])
        return XLCreateTableAsStatement(components: components)
    }
}


///
/// Constructs a Create expression.
///
public func sql<Table>(@XLCreateExpressionBuilder<Table> builder: (XLSchema) -> any XLCreateStatement<Table>) -> any XLCreateStatement<Table> {
    let schema = XLSchema()
    return builder(schema)
}
