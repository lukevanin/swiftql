//
//  File.swift
//
//
//  Created by Luke Van In on 2024/10/30.
//

import Foundation


@resultBuilder public struct XLDeleteExpressionBuilder {
    
    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    public static func buildPartialBlock<Table>(first: Delete<Table>) -> XLDeleteTableStatement<Table>{
        XLDeleteTableStatement(components: XLDeleteStatementComponents(delete: first))
    }
    
    public static func buildPartialBlock<Table>(accumulated: XLWithStatement, next: Delete<Table>) -> XLDeleteTableStatement<Table> {
        XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: accumulated.commonTables, delete: next))
    }

    public static func buildPartialBlock<Table>(accumulated: XLDeleteTableStatement<Table>, next: Where) -> XLDeleteWhereStatement<Table> {
        XLDeleteWhereStatement(components: accumulated.components.appending(next))
    }
}


///
///
///
public func sql(@XLDeleteExpressionBuilder builder: (XLSchema) -> any XLDeleteStatement) -> any XLDeleteStatement {
    let schema = XLSchema()
    return builder(schema)
}
