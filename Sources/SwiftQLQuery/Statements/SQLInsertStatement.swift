//
//  SQLInsertStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//
//  Each statement carries the dialect of the table it writes (issue #822).
//  The methods that take an expression, such as `where(_:)` on the select
//  that feeds an insert, take the dialect's expression protocol, so each
//  dialect's surface declares them, from
//  scripts/dialect-surface/Templates/WriteStatements.swift.template.
//

import Foundation


// MARK: - Insert


///
/// An insert statement.
///
struct AbstractXLInsertStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {
    var components: XLInsertStatementComponents<Row>
}


///
/// Builder used to construct insert statements.
///
public struct XLInsertStatementComponents<Row>: XLEncodable {

    var commonTables: [XLCommonTableDependency]
    
    let insert: Insert<Row>
    
    var components: [any XLEncodable]

    package init(commonTables: [XLCommonTableDependency] = [], insert: Insert<Row>, components: [any XLEncodable] = []) {
        self.commonTables = commonTables
        self.insert = insert
        self.components = components
    }
    
    public func appending<T>(_ expression: T) -> XLInsertStatementComponents where T: XLEncodable {
        var newStatement = XLInsertStatementComponents(commonTables: commonTables, insert: insert, components: components)
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
        insert.makeSQL(context: &context)
        
        for component in components {
            component.makeSQL(context: &context)
        }
    }
}


///
/// An insert statement.
///
public protocol XLInsertStatement<Row>: XLEncodable  {
    associatedtype Row
    /// The dialect of the table the statement writes, and of every clause
    /// in it (issue #822).
    associatedtype Dialect: XLSQLDialect
    var components: XLInsertStatementComponents<Row> { get }
}

extension XLInsertStatement {
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }
}


///
/// Insert statement.
///
public struct XLInsertTableStatement<Table, Dialect> where Dialect: XLSQLDialect {
    
    public let components: XLInsertStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Table>) {
        self.components = components
    }
    
    public func values(_ values: Table.MetaInsert) -> XLInsertTableValuesStatement<Table, Dialect> where Table: XLTable {
        XLInsertTableValuesStatement(components: components.appending(values))
    }
    
    public func values(_ values: Table.MetaInsert.Row) -> XLInsertTableValuesStatement<Table, Dialect> where Table: XLTable {
        XLInsertTableValuesStatement(components: components.appending(Table.MetaInsert(values)))
    }
    
    /// Inserts the rows selected through a static row layout. The layout's
    /// metadata names the columns, so no `readRow` replay runs.
    public func select<T>(_ layout: T) -> XLInsertSelectStatement<T.Row, Dialect> where T: XLStaticRowReadable, T.Row == Table, T.XLModelDialect == Dialect {
        XLInsertSelectStatement(components: components.appending(Select<T.Row, Dialect>(layout)))
    }

    public func select<T>(_ result: T) -> XLInsertSelectStatement<T.Row, Dialect> where T: XLRowReadable & XLDialectBound, T.Row == Table, T.XLModelDialect == Dialect {
        XLInsertSelectStatement(components: components.appending(Select<T.Row, Dialect>(result)))
    }
    
}


///
/// Values clause for an insert statement.
///
/// Specifies values for columns in an insert statement.
///
public struct XLInsertTableValuesStatement<Table, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {
    
    public let components: XLInsertStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Table>) {
        self.components = components
    }

}


///
/// Select clause in insert statement.
///
/// Specifies a select query used to insert rows.
///
public struct XLInsertSelectStatement<Table, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {
    
    public let components: XLInsertStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Table>) {
        self.components = components
    }

    // MARK: From
    
    public func from<T>(_ t: T) -> XLInsertSelectTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLInsertSelectTableStatement(components: components.appending(From<Dialect>(t)))
    }

}


///
/// A select from statement used in an insert statement.
///
public struct XLInsertSelectTableStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Inner Join

    public func innerJoin<T>(_ t: T) -> XLInsertSelectTableStatement<Row, Dialect> where T: XLMetaResult, T.XLModelDialect == Dialect {
        XLInsertSelectTableStatement(components: components.appending(Join<Dialect>(kind: .innerJoin, table: t, constraint: nil)))
    }

    public func crossJoin<T>(_ t: T) -> XLInsertSelectTableStatement<Row, Dialect> where T: XLMetaResult, T.XLModelDialect == Dialect {
        XLInsertSelectTableStatement(components: components.appending(Join<Dialect>(kind: .crossJoin, table: t, constraint: nil)))
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select where statement used in an insert statement.
///
public struct XLInsertSelectWhereStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select group-by statement used in an insert statement.
///
public struct XLInsertSelectGroupByStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// An insert ... having statement used in an insert statement.
///
public struct XLInsertSelectHavingStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}

///
/// A select order-by statement used in an insert statement.
///
public struct XLInsertSelectOrderByStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }
}


///
/// A select limit statement used in an insert statement.
///
public struct XLInsertSelectLimitStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }
}


///
/// A select offset statement used in an insert statement.
///
public struct XLInsertSelectOffsetStatement<Row, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {
    
    public let components: XLInsertStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Row>) {
        self.components = components
    }

}
