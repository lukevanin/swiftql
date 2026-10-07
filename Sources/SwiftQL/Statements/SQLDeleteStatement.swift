//
//  SQLDeleteStatement.swift
//  
//
//  Created by Luke Van In on 2024/10/29.
//
//  Each statement carries the dialect of the table it deletes from (issue
//  #822). `where(_:)` takes the dialect's expression protocol, so each
//  dialect's surface declares it, from
//  scripts/dialect-surface/Templates/WriteStatements.swift.template.
//

import Foundation


///
/// Builder that is used to construct a delete statement.
///
public struct XLDeleteStatementComponents<Table>: XLEncodable {
    
    public var commonTables: [XLCommonTableDependency]
    
    public var delete: Delete<Table>
    
    public var components: [any XLEncodable]
    
    public init(commonTables: [XLCommonTableDependency] = [], delete: Delete<Table>, components: [any XLEncodable] = []) {
        self.commonTables = commonTables
        self.delete = delete
        self.components = components
    }
    
    public func appending(_ component: any XLEncodable) -> XLDeleteStatementComponents {
        return XLDeleteStatementComponents(commonTables: commonTables, delete: delete, components: components + [component])
    }
    
    public func makeSQL(context: inout XLBuilder) {
        if !commonTables.isEmpty {
            context.commonTables { context in
                for commonTable in commonTables {
                    commonTable.makeSQL(context: &context)
                }
            }
        }
        delete.makeSQL(context: &context)
        for component in components {
            component.makeSQL(context: &context)
        }
    }
}


///
/// A delete statement.
///
public protocol XLDeleteStatement<Table>: XLEncodable {
    associatedtype Table
    /// The dialect of the table the statement deletes from, and of every
    /// clause in it (issue #822).
    associatedtype Dialect: XLSQLDialect
    var components: XLDeleteStatementComponents<Table> { get }
}

extension XLDeleteStatement {
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// Delete statement.
///
/// > Warning: A delete statement without a where clause affects all rows in the given table.
///
public struct XLDeleteTableStatement<Table, Dialect>: XLDeleteStatement where Dialect: XLSQLDialect {

    public var components: XLDeleteStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLDeleteStatementComponents<Table>) {
        self.components = components
    }
}


///
/// Where clause on a delete statement.
///
public struct XLDeleteWhereStatement<Table, Dialect>: XLDeleteStatement where Dialect: XLSQLDialect {

    public let components: XLDeleteStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLDeleteStatementComponents<Table>) {
        self.components = components
    }
}
