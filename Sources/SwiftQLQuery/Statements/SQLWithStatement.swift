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
/// Every common table, and the statement that follows, belongs to `Dialect`
/// (issue #822). The scalar `select(_:)` takes the dialect's expression
/// protocol, so each dialect's surface declares it, from
/// scripts/dialect-surface/Templates/QueryStatements.swift.template.
///
public struct XLWithStatement<Dialect> where Dialect: XLSQLDialect {

   public let commonTables: [XLCommonTableDependency]

   /// Creates the statement from common tables that belong to `Dialect`.
   /// A definition does not record its dialect, so this is SwiftQL's
   /// dialect-surface SPI, not public API.
   @_spi(XLDialectSurface)
   public init(_dialectSurface commonTables: [XLCommonTableDependency]) {
       self.commonTables = commonTables
   }

   // MARK: Select

   /// Builds a factored select from a static row layout.
   ///
   /// The layout's metadata already names its columns, so the select does not
   /// replay `readRow` to find them.
   public func select<T>(_ layout: T) -> XLQuerySelectStatement<T.Row, Dialect> where T: XLStaticRowReadable, T.XLModelDialect == Dialect {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select<T.Row, Dialect>(layout)))
   }

   public func select<T>(_ t: T) -> XLQuerySelectStatement<T.Row, Dialect> where T: XLRowReadable & XLDialectBound, T.XLModelDialect == Dialect {
       XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: commonTables, select: Select<T.Row, Dialect>(t)))
   }

   // MARK: Insert

   public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
       let components = XLInsertStatementComponents(commonTables: commonTables, insert: Insert(meta))
       return XLInsertTableStatement(components: components)
   }

   // MARK: Update

   public func update<T, S>(_ table: T, set values: S) -> XLUpdateSetStatement<T.Row, Dialect> where T: XLMetaWritableTable, T.XLModelDialect == Dialect, S: XLMetaUpdate, S.Row == T.Row {
       let components = XLUpdateStatementComponents(commonTables: commonTables, update: Update(table), components: [values])
       return XLUpdateSetStatement(components: components)
   }

   public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row, Dialect> where T: XLMetaWritableTable, T.XLModelDialect == Dialect {
       let components = XLUpdateStatementComponents(commonTables: commonTables, update: Update(table))
       return XLUpdateTableStatement(components: components)
   }

   // MARK: Delete

   public func delete<T>(_ table: T) -> XLDeleteTableStatement<T, Dialect> where T: XLMetaWritableTable, T.XLModelDialect == Dialect, T.Row: XLTable {
       XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: commonTables, delete: Delete(table)))
   }
}
