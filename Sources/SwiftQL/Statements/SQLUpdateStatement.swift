//
//  SQLUpdateStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation

// MARK: - Update



///
/// Builder used to construct an update statement.
///
public struct XLUpdateStatementComponents<Row>: XLEncodable {

    var commonTables: [XLCommonTableDependency]
    
    let update: Update<Row>
    
    var components: [any XLEncodable]

    init(commonTables: [XLCommonTableDependency] = [], update: Update<Row>, components: [any XLEncodable] = []) {
        self.commonTables = commonTables
        self.update = update
        self.components = components
    }
    
    public func appending<T>(_ expression: T) -> XLUpdateStatementComponents where T: XLEncodable {
        var newStatement = XLUpdateStatementComponents(commonTables: commonTables, update: update, components: components)
        newStatement.components.append(expression)
        return newStatement
    }
    
    public func makeSQL(context: inout XLBuilder) {
        if !commonTables.isEmpty {
            context.commonTables { context in
                for commonTable in commonTables {
                    commonTable.makeSQL(context: &context)
                }
            }
        }
        update.makeSQL(context: &context)
        for component in components {
            component.makeSQL(context: &context)
        }
    }
}


///
/// An update statement.
///
public protocol XLUpdateStatement<Table>: XLEncodable  {
    associatedtype Table
    var components: XLUpdateStatementComponents<Table> { get }
}

extension XLUpdateStatement {
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// An update statement.
///
public struct XLUpdateTableStatement<Row> {
    
    public let components: XLUpdateStatementComponents<Row>
    
    public func `set`<S>(_ values: S) -> XLUpdateSetStatement<Row> where S: XLMetaUpdate, S.Row == Row, Row: XLTable {
        XLUpdateSetStatement(components: components.appending(Setting(values)))
    }
    
    public func `set`(_ values: @escaping (inout Row.MetaUpdate) -> Void) -> XLUpdateSetStatement<Row> where Row: XLTable {
        XLUpdateSetStatement(components: components.appending(Setting<Row>(values)))
    }
}


///
/// An update statement with a set clause.
///
public struct XLUpdateSetStatement<Row>: XLUpdateStatement {
    
    public let components: XLUpdateStatementComponents<Row>
    
    public func from<R>(_ statement: R) -> XLUpdateFromStatement<Row> where R: XLMetaNamedResult {
        XLUpdateFromStatement(components: components.appending(From(statement)))
    }
    
    public func `where`<U>(_ expression: any XLExpression<U>) -> XLUpdateWhereStatement<Row> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where(expression)))
    }
}


///
/// An update statement with a from clause.
///
public struct XLUpdateFromStatement<Row>: XLUpdateStatement {
    
    public let components: XLUpdateStatementComponents<Row>

    public func `where`<U>(_ expression: any XLExpression<U>) -> XLUpdateWhereStatement<Row> where U: XLBoolean {
        XLUpdateWhereStatement(components: components.appending(Where(expression)))
    }
}


///
/// An update statement with a where clause.
///
public struct XLUpdateWhereStatement<Row>: XLUpdateStatement {
    
    public let components: XLUpdateStatementComponents<Row>
}
