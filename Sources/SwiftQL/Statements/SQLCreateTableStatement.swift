//
//  SQLCreateTableStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


///
/// Builder used to construct a create statement.
///
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


///
/// A create table statement.
///
public protocol XLCreateStatement<Table>: XLEncodable  {
    associatedtype Table
    var components: XLCreateTableStatementComponents<Table> { get }
}

extension XLCreateStatement {
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// Create table statement.
///
public struct XLCreateTableStatement<Table>: XLCreateStatement {
    
    public let components: XLCreateTableStatementComponents<Table>
    
    ///
    /// Adds an as clause with a select query.
    ///
    /// Adds a select query which is used to populate the table when it is created.
    ///
    public func `as`(builder: (XLSchema) -> some XLQueryStatement<Table>) -> some XLCreateStatement where Table: XLTable {
        let meta = Table.makeSQLCreateAs()
        let schema = XLSchema()
        let queryStatement = builder(schema)
        let components = XLCreateTableStatementComponents(create: Create(meta), components: [queryStatement])
        return XLCreateTableAsStatement(components: components)
    }
}


///
/// Create table as clause.
///
public struct XLCreateTableAsStatement<Table>: XLCreateStatement {
    
    public let components: XLCreateTableStatementComponents<Table>

    
}
