//
//  SQLWithStatement.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Builder used to construct a with statement.
///
public struct XLWithStatement {
   
   public let commonTables: [XLCommonTableDependency]
   
   public init(_ commonTables: [XLCommonTableDependency]) {
       self.commonTables = commonTables
   }

   // MARK: Select
   
   public func select<T>(_ t: T) -> XLQuerySelectStatement<T.Row> where T: XLRowReadable {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select(t)))
   }
   
   public func select<T>(_ expression: any XLExpression<T>) -> XLQuerySelectStatement<T> where T: XLExpression & XLLiteral {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select(expression)))
   }

   // MARK: Update
   
//    public func update<T>(_ meta: T) -> XLUpdateTableStatement<T.Row> where T: SQLTable {
//        XLUpdateTableStatement(components: XLUpdateStatementComponents(commonTables: commonTables, update: Update(meta)))
//    }

   // MARK: Insert
   
    public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
        let components = XLInsertStatementComponents(commonTables: commonTables, insert: Insert(meta))
        return XLInsertTableStatement(components: components)
    }
    
    // MARK: Delete
    
    public func delete<T>(_ table: T) -> XLDeleteTableStatement<T> where T: XLMetaWritableTable, T.Row: XLTable {
        XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: commonTables, delete: Delete(table)))
    }
}
