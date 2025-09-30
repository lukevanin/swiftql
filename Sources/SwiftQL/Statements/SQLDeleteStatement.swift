//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


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


public protocol XLDeleteStatement<Table>: XLEncodable {
    associatedtype Table
    var components: XLDeleteStatementComponents<Table> { get }
}

extension XLDeleteStatement {
    
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }

    #warning("TODO: Enable XLRowReadable conformance to implement `returning` clause")
    //    public func readRow(reader: XLRowReader) throws -> Row {
    //        try components.readRow(reader: reader)
    //    }
}


public struct XLDeleteTableStatement<Table>: XLDeleteStatement {
    
    public var components: XLDeleteStatementComponents<Table>
    
    public func `where`<U>(_ expression: any XLExpression<U>) -> XLDeleteWhereStatement<Table> where U: XLBoolean {
        XLDeleteWhereStatement(components: components.appending(Where(expression)))
    }
}


public struct XLDeleteWhereStatement<Table>: XLDeleteStatement {
    
    public let components: XLDeleteStatementComponents<Table>

}
