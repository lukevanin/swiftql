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

   /// Builds a factored select from a static row layout.
   ///
   /// The layout's metadata already names its columns, so the select does not
   /// replay `readRow` to find them.
   public func select<T>(_ layout: T) -> XLQuerySelectStatement<T.Row> where T: XLStaticRowReadable {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select(layout)))
   }

   public func select<T>(_ t: T) -> XLQuerySelectStatement<T.Row> where T: XLRowReadable {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select(t)))
   }

   /// Builds a factored scalar select without constraining its logical result
   /// type. Contextual-only values still need a static row layout for decoding.
   public func select<T>(
       _ expression: any XLExpression<T>
   ) -> XLQuerySelectStatement<T> {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select(expression)))
   }

   // MARK: Insert

   public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
       let components = XLInsertStatementComponents(commonTables: commonTables, insert: Insert(meta))
       return XLInsertTableStatement(components: components)
   }

   // MARK: Update

   public func update<T, S>(_ table: T, set values: S) -> XLUpdateSetStatement<T.Row> where T: XLMetaWritableTable, S: XLMetaUpdate, S.Row == T.Row {
       let components = XLUpdateStatementComponents(commonTables: commonTables, update: Update(table), components: [values])
       return XLUpdateSetStatement(components: components)
   }

   public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row> where T: XLMetaWritableTable {
       let components = XLUpdateStatementComponents(commonTables: commonTables, update: Update(table))
       return XLUpdateTableStatement(components: components)
   }

   // MARK: Delete

   public func delete<T>(_ table: T) -> XLDeleteTableStatement<T> where T: XLMetaWritableTable, T.Row: XLTable {
       XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: commonTables, delete: Delete(table)))
   }
}
