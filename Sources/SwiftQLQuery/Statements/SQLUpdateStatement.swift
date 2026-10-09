//
//  SQLUpdateStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//
//  Each statement carries the dialect of the table it updates (issue #822).
//  `where(_:)` takes the dialect's expression protocol, so each dialect's
//  surface declares it, from
//  scripts/dialect-surface/Templates/WriteStatements.swift.template.
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
    /// The dialect of the table the statement updates, and of every clause
    /// in it (issue #822).
    associatedtype Dialect: XLSQLDialect
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
public struct XLUpdateTableStatement<Row, Dialect> where Dialect: XLSQLDialect {

    public let components: XLUpdateStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLUpdateStatementComponents<Row>) {
        self.components = components
    }

    public func `set`<S>(_ values: S) -> XLUpdateSetStatement<Row, Dialect> where S: XLMetaUpdate, S.Row == Row, Row: XLTable {
        XLUpdateSetStatement(components: components.appending(Setting(values)))
    }

    public func `set`(_ values: @escaping (inout Row.MetaUpdate) -> Void) -> XLUpdateSetStatement<Row, Dialect> where Row: XLTable {
        XLUpdateSetStatement(components: components.appending(Setting<Row>(values)))
    }
}


///
/// An update statement with a set clause.
///
public struct XLUpdateSetStatement<Row, Dialect>: XLUpdateStatement where Dialect: XLSQLDialect {

    public let components: XLUpdateStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLUpdateStatementComponents<Row>) {
        self.components = components
    }

    public func from<R>(_ statement: R) -> XLUpdateFromStatement<Row, Dialect> where R: XLMetaNamedResult, R.XLModelDialect == Dialect {
        XLUpdateFromStatement(components: components.appending(From<Dialect>(statement)))
    }
}


///
/// An update statement with a from clause.
///
public struct XLUpdateFromStatement<Row, Dialect>: XLUpdateStatement where Dialect: XLSQLDialect {

    public let components: XLUpdateStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLUpdateStatementComponents<Row>) {
        self.components = components
    }
}


///
/// An update statement with a where clause.
///
public struct XLUpdateWhereStatement<Row, Dialect>: XLUpdateStatement where Dialect: XLSQLDialect {

    public let components: XLUpdateStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLUpdateStatementComponents<Row>) {
        self.components = components
    }
}
