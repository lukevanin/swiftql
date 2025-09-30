//
//  File.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


@resultBuilder public struct XLCreateExpressionBuilder<Table> {
    
    public static func buildPartialBlock(first: Create<Table>) -> XLCreateTableStatement<Table> {
        XLCreateTableStatement(components: XLCreateTableStatementComponents(create: first))
    }
    
    public static func buildPartialBlock(accumulated: XLCreateTableStatement<Table>, next: As<Table>) -> XLCreateTableAsStatement<Table> where Table: XLTable, Table.MetaCreateAs.Table == Table {
        let meta = Table.makeSQLCreateAs()
        let components = XLCreateTableStatementComponents(create: Create(meta), components: [next.queryStatement])
        return XLCreateTableAsStatement(components: components)
    }
}


///
///
///
public func sql<Table>(@XLCreateExpressionBuilder<Table> builder: (XLSchema) -> any XLCreateStatement<Table>) -> any XLCreateStatement<Table> {
    let schema = XLSchema()
    return builder(schema)
}
