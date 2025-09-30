//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


public struct XLCreateTableStatementComponents<Table>: XLEncodable {

    let create: Create<Table>
    
    var components: [any XLEncodable]

    init(create: Create<Table>, components: [any XLEncodable] = []) {
        self.create = create
        self.components = components
    }
    
    public func appending<T>(_ expression: T) -> XLCreateTableStatementComponents where T: XLEncodable {
        var newStatement = XLCreateTableStatementComponents(create: create, components: components)
        newStatement.components.append(expression)
        return newStatement
    }

    public func makeSQL(context: inout XLBuilder) {

        create.makeSQL(context: &context)
        
        for component in components {
            component.makeSQL(context: &context)
        }
    }
}


public protocol XLCreateStatement<Table>: XLEncodable  {
    associatedtype Table
    var components: XLCreateTableStatementComponents<Table> { get }
}

extension XLCreateStatement {
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


public struct XLCreateTableStatement<Table>: XLCreateStatement {
    
    #warning("TODO: Table constraints")

    #warning("TODO: Table options")

    #warning("TODO: Temporary table")

    #warning("TODO: Make IF NOT EXISTS opt-in")

    public let components: XLCreateTableStatementComponents<Table>
    
    public func `as`(builder: (XLSchema) -> some XLQueryStatement<Table>) -> some XLCreateStatement where Table: XLTable {
        let meta = Table.makeSQLCreateAs()
        let schema = XLSchema()
        let queryStatement = builder(schema)
        let components = XLCreateTableStatementComponents(create: Create(meta), components: [queryStatement])
        return XLCreateTableAsStatement(components: components)
    }
}


public struct XLCreateTableAsStatement<Table>: XLCreateStatement {
    
    public let components: XLCreateTableStatementComponents<Table>

    
}
