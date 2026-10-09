//
//  SQLQueryStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//
//  Each statement carries its dialect (issue #822). The methods here take a
//  table or an ordering term, whose dialect is part of its type. The methods
//  that take an expression, such as `where(_:)` and `innerJoin(_:on:)`, take
//  the dialect's expression protocol, so each dialect's surface declares them,
//  from scripts/dialect-surface/Templates/QueryStatements.swift.template.
//

import Foundation


// MARK: - Query


///
/// Builder used to construct a select query statement.
///
public struct XLQueryStatementComponents<Row>: XLEncodable, XLRowReadable {

    var commonTables: [XLCommonTableDependency]

    package let reader: any XLRowReadable<Row>

    var components: [any XLEncodable]

    /// Creates the components of a statement that begins with `select`.
    @_spi(XLDialectSurface)
    public init<Dialect>(commonTables: [XLCommonTableDependency] = [], select: Select<Row, Dialect>, components: [any XLEncodable] = []) {
        self.commonTables = commonTables
        self.reader = select
        self.components = [select] + components
    }

    init(commonTables: [XLCommonTableDependency] = [], reader: any XLRowReadable<Row>, components: [any XLEncodable] = []) {
        self.commonTables = commonTables
        self.reader = reader
        self.components = components
    }

    public mutating func append<T>(_ expression: T) where T: XLEncodable {
        components.append(expression)
    }

    public func appending<T>(_ expression: T) -> XLQueryStatementComponents<Row> where T: XLEncodable {
        var newStatement = XLQueryStatementComponents(commonTables: commonTables, reader: reader, components: components)
        newStatement.append(expression)
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
        for component in components {
            component.makeSQL(context: &context)
        }
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try self.reader.readRow(reader: reader)
    }
}


///
/// A select query statement.
///
/// A statement of any dialect. A database runs one through this protocol, so
/// it is the type a query is usually stored and passed as. A statement that
/// another statement contains, such as a subquery, a common table, or a
/// branch of a compound select, is an ``XLDialectQueryStatement`` of the
/// containing statement's dialect.
///
public protocol XLQueryStatement<Row>: XLEncodable, XLRowReadable {
    var components: XLQueryStatementComponents<Row> { get }
}

extension XLQueryStatement {
    public func makeSQL(context: inout XLBuilder) {
        components.makeSQL(context: &context)
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try components.readRow(reader: reader)
    }
}


///
/// A select query statement of `Dialect`.
///
/// Every clause of the statement belongs to `Dialect`: its tables, its common
/// tables, and the expressions in its clauses (issue #822). A subquery, a
/// common table, and a branch of a compound select take a statement of the
/// containing statement's dialect, so a statement of another dialect is a
/// compile error where it is used.
///
/// `sql { }` returns one for SQLite, and `sql(dialect:)` for its dialect. An
/// `any XLDialectQueryStatement<Row, Dialect>` is an
/// `any XLQueryStatement<Row>`, so code that stores or runs a query as an
/// ``XLQueryStatement`` keeps working.
///
public protocol XLDialectQueryStatement<Row, Dialect>: XLQueryStatement {

    /// The dialect of the statement.
    associatedtype Dialect: XLSQLDialect
}


///
/// A query statement.
///
struct AbstractXLQueryStatement<Row, Dialect>: XLDialectQueryStatement where Dialect: XLSQLDialect {
    var components: XLQueryStatementComponents<Row>
}


///
/// A query statement that can be combined with another query statement.
///
public protocol XLSimpleSelectQueryStatement<Row>: XLDialectQueryStatement {
}

extension XLSimpleSelectQueryStatement {

    // MARK: Union

    public func union(_ statement: () -> any XLDialectQueryStatement<Row, Dialect>) -> XLQueryUnionStatement<Row, Dialect> {
        let union = BooleanClause<Row>(kind: .union, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }

    public func unionAll(_ statement: () -> any XLDialectQueryStatement<Row, Dialect>) -> XLQueryUnionStatement<Row, Dialect> {
        let union = BooleanClause<Row>(kind: .unionAll, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }

    public func intersect(_ statement: () -> any XLDialectQueryStatement<Row, Dialect>) -> XLQueryUnionStatement<Row, Dialect> {
        let union = BooleanClause<Row>(kind: .intersect, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }

    public func except(_ statement: () -> any XLDialectQueryStatement<Row, Dialect>) -> XLQueryUnionStatement<Row, Dialect> {
        let union = BooleanClause<Row>(kind: .except, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
}


///
/// A select query statement.
///
public struct XLQuerySelectStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: From

    public func from<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(From<Dialect>(t)))
    }

    ///
    /// Adds a `FROM` clause whose table can resolve to `NULL`, for use as the
    /// left-hand table of a `RIGHT JOIN` or either side of a `FULL OUTER JOIN`.
    ///
    public func from<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(From<Dialect>(t)))
    }
}


///
/// A select query statement with a from clause.
///
public struct XLQueryTableStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Join

    public func innerJoin<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .innerJoin, table: t, constraint: nil)))
    }

    public func crossJoin<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .crossJoin, table: t, constraint: nil)))
    }

    ///
    /// Adds an inner join whose constraint is a `USING (columns...)` clause.
    ///
    public func innerJoin<T>(_ t: T, using firstColumn: XLName, _ otherColumns: XLName...) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .innerJoin, table: t, using: [firstColumn] + otherColumns)))
    }

    ///
    /// Adds a left join whose constraint is a `USING (columns...)` clause.
    ///
    public func leftJoin<T>(_ t: T, using firstColumn: XLName, _ otherColumns: XLName...) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .leftJoin, table: t, using: [firstColumn] + otherColumns)))
    }

    ///
    /// Adds a natural (inner) join, which implicitly matches every shared column.
    ///
    public func naturalJoin<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .naturalJoin, table: t, constraint: nil)))
    }

    ///
    /// Adds a natural left join, whose joined table can resolve to `NULL`.
    ///
    public func naturalLeftJoin<T>(_ t: T) -> XLQueryTableStatement<Row, Dialect> where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        XLQueryTableStatement(components: components.appending(Join<Dialect>(kind: .naturalLeftJoin, table: t, constraint: nil)))
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select query statement with a where clause.
///
public struct XLQueryWhereStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select query statement with a group-by clause.
///
public struct XLQueryGroupByStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select query with a group-by having clause.
///
public struct XLQueryHavingStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A partial union specifying one query.
///
public struct XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {

    internal let kind: BooleanClause<Statement.Row>.Kind

    public let query: Statement
}


///
/// A query combining two queries.
///
public struct XLQueryUnionStatement<Row, Dialect>: XLQueryStatement, XLSimpleSelectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }

    // MARK: Order

    public func orderBy(_ terms: any XLOrderingTerm<Dialect>...) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: components.appending(OrderBy<Dialect>(terms: terms)))
    }
}


///
/// A select query with an order-by clause.
///
public struct XLQueryOrderByStatement<Row, Dialect>: XLDialectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }
}


///
/// A select query with a limit clause.
///
public struct XLQueryLimitStatement<Row, Dialect>: XLDialectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }
}


///
/// A select query with an offset clause.
///
public struct XLQueryOffsetStatement<Row, Dialect>: XLDialectQueryStatement where Dialect: XLSQLDialect {

    public let components: XLQueryStatementComponents<Row>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLQueryStatementComponents<Row>) {
        self.components = components
    }
}
