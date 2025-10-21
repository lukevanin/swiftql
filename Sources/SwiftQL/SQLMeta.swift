//
//  SQLMeta.swift
//
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Database


public protocol XLDatabaseMetadata {
    func schema() -> XLSchemaName
}


public class XLDatabaseMetadataObject: XLDatabaseMetadata {
    
    private let _schema: XLSchemaName
    
    init(schema: XLSchemaName = .main) {
        self._schema = schema
    }
    
    public func schema() -> XLSchemaName {
        _schema
    }
    
}


// MARK: - Table


///
/// Reads the value for a column for a row returned from a select query.
///
/// Used when reading results of a query returned by SQLite.
///
public protocol XLColumnReader {
    
    ///
    /// Determines if the value for a column at a given index contains a NULL value.
    ///
    /// - Parameter index: Index of the column to examine.
    ///
    /// - Returns: `true` if the column value is NULL.
    ///
    func isNull(at index: Int) -> Bool
    
    ///
    /// Reads an integer value for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Integer value for the column.
    ///
    func readInteger(at index: Int) -> Int
    
    ///
    /// Reads a real number for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Floating point value for the column.
    ///
    func readReal(at index: Int) -> Double
    
    ///
    /// Reads a text value for the column at a given index
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: String value for the column.
    ///
    func readText(at index: Int) -> String
    
    ///
    /// Reads a BLOB value for the column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Data value for the column.
    ///
    func readBlob(at index: Int) -> Data
}


///
/// Reads the value for columns in rows returned by a select query statement.
///
public protocol XLRowReader: AnyObject {
    
    ///
    /// Reads and returns the value for the current column.
    ///
    /// Columns are read sequentially in order starting at the first column in the result set. This method
    /// should be called multiple times, to read each column in sequence.
    ///
    func column<T>(_ expression: any XLExpression<T>, alias: XLName) throws -> T where T: XLLiteral
}


///
/// Introspects a query expression to determine the columns that are used.
///
final class XLColumnsDefinitionRowReader: XLRowReader, XLEncodable {
    
    private var expressions: [any XLEncodable] = []
    private var names: [XLName] = []
    
    func column<T>(_ expression: any XLExpression<T>, alias: XLName) -> T where T: XLLiteral {
        names.append(alias)
        if expression is any XLQueryStatement {
            expressions.append(XLParenthesis<T>(expression: expression))
        }
        else {
            expressions.append(expression)
        }
        return T.sqlDefault()
    }
    
    func makeSQL(context: inout XLBuilder) {
        context.list(separator: ", ") { listBuilder in
            for (name, expression) in zip(names, expressions) {
                listBuilder.listItem { builder in
                    builder.alias(name, expression: expression.makeSQL)
                }
            }
        }
    }
}


///
/// Reads the columns for a row returned by a select query statement.
///
final class XLColumnValuesRowReader<Output>: XLRowReader {
    
    private var count: Int = 0
    
    private var reader: XLColumnReader!
    
    init() {
    }
    
    ///
    /// Resets the reader state so that the next call to the `column` method will return the first column in
    /// the row.
    ///
    func reset(reader: XLColumnReader) {
        count = 0
        self.reader = reader
    }
    
    ///
    /// Reads the value of the current column from the row, then advances the state to the next column.
    ///
    func column<T>(_ expression: any XLExpression<T>, alias: XLName) throws -> T where T: XLLiteral {
        try readValue()
    }

    private func readValue<T>() throws -> T where T: XLLiteral {
        defer {
            count += 1
        }
        return try T.init(reader: reader, at: count)
    }

}


///
/// Reads rows from a database using an `XLRowReader`.
///
public protocol XLRowReadable<Row> {
    associatedtype Row
    func readRow(reader: XLRowReader) throws -> Row
}


///
/// An `XLEncodable` type that can be written to a database.
///
public protocol XLRowWritable<Row>: XLEncodable {
    associatedtype Row
}


///
/// Metadata associated with a struct annotated with `@SQLResult`.
///
/// The types and method defined by this protocol  are implemented by macro code generation.
///
/// The word `...anonymous...` used in method names refers to a defuct implementation detail
/// where column names were anonymized as c0, c1, ... cN. This was done to reduce the length of the XL
/// string that needed to be parsed. However this reduced readability for humans and this was later changed.
///
/// to use the proper names for columns. The word `...named...` indicates that the result is an
/// identifiable type such as a table, from, join, subquery, or common table, and can be used in an `IN`
/// expression. Examples of results that are unnamed include the set of columns in a `SELECT` statement,
/// and the result of a `UNION`, `INTERSECT`, or `EXCLUDE`.
///
public protocol XLResult {
    typealias MetaRowIterator = (XLRowReader) throws -> Self
    
    ///
    /// Duplicate of the struct where each field is forced to be nullable.
    ///
    associatedtype Nullable: XLMetaNullable
    
    ///
    /// Metadata used when the result is returned in a query.
    ///
    associatedtype MetaResult: XLMetaResult
    
    ///
    /// Metadata used when the result is returned with a name.
    ///
    associatedtype MetaNamedResult: XLMetaNamedResult
    
    ///
    /// Metadata used when the result can evaluate to null, such as when the result is used in a left join
    /// expression.
    ///
    associatedtype MetaNullableResult: XLMetaNullableResult
    
    ///
    /// Metadata used when the result is used with a named table that can evaluate to null.
    ///
    associatedtype MetaNullableNamedResult: XLMetaNullableNamedResult
    
    ///
    /// Metadata used when the result is returned by a common table expression.
    ///
    associatedtype MetaCommonTable: XLMetaCommonTable
    
    ///
    /// Reader used to assign values to each field of the result.
    ///
    associatedtype SQLReader: XLRowReadable

    ///
    /// Creates a common table reference.
    ///
    static func makeSQLCommonTable(namespace: XLNamespace, dependency: XLCommonTableDependency) -> MetaCommonTable

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaNamedResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult
    
    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult
}


///
/// Metadata associated with a struct annotated with `SQLTable`.
///
/// Types and methods defined by this protocol are implemented by macro code generation.
///
public protocol XLTable: XLResult {
        
    ///
    /// Metadata used when the table is used as the target destination in a write statement.
    ///
    associatedtype MetaWritableTable: XLMetaWritableTable
    
    ///
    /// Metadata used when the table is used in an insert statement.
    ///
    associatedtype MetaInsert: XLMetaInsert
    
    ///
    /// Metadata used when the table is used in an update statement.
    ///
    associatedtype MetaUpdate: XLMetaUpdate
    
    ///
    /// Metadata used when the table is used in a create statement.
    ///
    associatedtype MetaCreate: XLMetaCreate
    
    ///
    /// Metadata used when a table is used in a create statement with a select query.
    ///
    associatedtype MetaCreateAs: XLMetaCreate

    ///
    /// The name of the underlying SQL table represented by the struct.
    ///
    static func sqlTableName() -> XLQualifiedTableName
    
    ///
    /// Creates metadata for using the struct as a table in a statement.
    ///
    static func makeSQLTable(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult

    ///
    /// Creates metadata for using the struct as a table with a name in a statement.
    ///
    static func makeSQLNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    ///
    /// Creates metadata for using the struct as a table in a statement where the table can evaluate to null,
    /// such as when it is used in a left join.
    ///
    static func makeSQLNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    ///
    /// Creates metadata for using the struct as a table with a name in a statement where the table can
    /// evaluate to null.
    ///
    static func makeSQLNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult

    ///
    /// Creates metadata for using the struct in an insert statement.
    ///
    static func makeSQLInsert(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    ///
    /// Creates metadata for using the struct in an update statement.
    ///
    static func makeSQLUpdate(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    ///
    /// Creates metadata for using the struct in a create statement.
    ///
    static func makeSQLCreate() -> MetaCreate
    
    ///
    /// Creates metadata for using the struct in a create statement with a select query.
    ///
    static func makeSQLCreateAs() -> MetaCreateAs
}


///
/// Maintains a collection of unique names for common table expressions, tables, and parameters.
///
/// Aliases are used to refer to tables, columns and values by names. If an alias is not defined explicitly, one
/// is assigned automatically. Automatically assigned aliases are assigned sequentially in the order in which
/// they are requested.
///
public class XLNamespace {
    
    private var usedAlises: Set<XLName> = []
    
    private var aliasCount = 0
    
    public var nameFormat: String
    
    private init(nameFormat: String) {
        self.nameFormat = nameFormat
    }

    ///
    /// Creates an alias with a given name.
    ///
    /// Creates and returns an alias with a given name. The alias is tracked to avoid conflcits. If the alias is
    /// not specified then one is assigned automatically using `nextAlias()`.
    ///
    func makeAlias(alias: XLName?) -> XLName {
        let newAlias = alias ?? nextAlias()
        usedAlises.insert(newAlias)
        return newAlias
    }
    
    ///
    /// Creates the next alias in the sequence.
    ///
    func nextAlias() -> XLName {
        defer {
            aliasCount += 1
        }
        return XLName(String(format: nameFormat, aliasCount))
    }
    
    ///
    /// instantiates a namespace used for common table expressions.
    ///
    public static func common() -> XLNamespace {
        XLNamespace(nameFormat: "cte%d")
    }
    
    ///
    /// Instantiates a namespace used for tables.
    ///
    public static func table() -> XLNamespace {
        XLNamespace(nameFormat: "t%d")
    }
    
    ///
    /// Instantiates a namespace used for parameters.
    ///
    public static func parameter() -> XLNamespace {
        XLNamespace(nameFormat: "p%d")
    }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where every field is forced to be optional.
///
/// Implemented by macro.
///
public protocol XLMetaNullable {
    associatedtype Basis
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a normal table in a
/// query.
///
/// Implemented by macro.
///
public protocol XLMetaResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLTableDeclaration { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a table with a given
/// name in a query.
///
/// Implemented by macro.
///
public protocol XLMetaNamedResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLNamedTableDeclaration { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a table in a query
/// where the table can resolve to NULL, such as in a LEFT JOIN.
///
/// Implemented by macro.
///
public protocol XLMetaNullableResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct  where the struct is used as a table with a given
/// name in a query, and where the table can resolve to NULL, such as a LEFT JOIN in a common table
/// expression.
///
/// Implemented by macro.
///
public protocol XLMetaNullableNamedResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration & XLNamedDependency
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is returned from a common
/// table expression.
///
/// Implemented by macro.
///
public protocol XLMetaCommonTable {
    associatedtype Result: XLResult
    var definition: XLCommonTableDependency { get }
}


///
/// Metadata for a `@SQLTable` struct where the table is written to.
///
/// Implemented by macro.
///
public protocol XLMetaWritableTable<Row>: XLEncodable {
    associatedtype Row
    var _table: any XLEncodable { get }
}


///
/// Metadata for a `@SQLTable` struct where the struct is used in an INSERT statement.
///
/// Implemented by macro.
///
public protocol XLMetaInsert<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init(_ instance: Row)
}


///
/// Metadata for a `@SQLTable`struct where the struct is used in an UPDATE statement.
///
/// Implemented by macro.
///
public protocol XLMetaUpdate<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init()
}


///
/// Metadata for a `@SQLTable` struct where the struct is used in a CREATE statement.
///
public protocol XLMetaCreate: XLEncodable {
    associatedtype Table
}


///
/// A `@SQLTable` or `@SQLResult` struct which contains a set of columns.
///
/// The struct may be named, such as a `@SQLTable` where the columns are defined on a specific table, or
/// unnamed, such as a `@SQLResult` where the columns are returned in a select query.
///
public protocol XLColumnDependency {
    
    ///
    /// Creates a qualified name for a column on the struct.
    ///
    /// For a `@SQLTable` struct this method returns the qualified name of the column including the table
    /// name. For a `@SQLResult` struct this method returns the bare column name.
    ///
    func qualifiedName(forColumn name: XLName) -> XLQualifiedName
}


///
///
/// A dependency which can be identified by an alias which can be used in an IN clause, such as a table,
/// common table, from clause, join clause. Excludes unnammed results such as select columns, UNION,
/// UNION ALL, INTERSECT, and EXCLUDE.
///
public protocol XLNamedDependency {
    var alias: XLName { get }
}


///
/// A normal SQL table.
///
public typealias XLTableDeclaration = XLEncodable & XLColumnDependency


///
/// A table with a given name.
///
public typealias XLNamedTableDeclaration = XLEncodable & XLColumnDependency & XLNamedDependency


///
/// A common table expression.
///
public struct XLCommonTableDependency: XLColumnDependency, XLNamedDependency {
    
    public var alias: XLName

    internal var statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }

    public func makeSQL(context: inout XLCommonTablesBuilder) {
        context.commonTable(alias: alias) { context in
            statement.makeSQL(context: &context)
        }
    }
}


///
/// A recursive common table expression.
///
/// A recursive common table expression is a common table expression which contains a reference to itself.
///
/// > Note: Recursive common table expressions are represented by a reference type and therefore require
/// stack allocation.
///
internal class XLRecursiveCommonTableStatement: XLEncodable {
    
    internal var statement: (any XLEncodable)!

    func makeSQL(context: inout XLBuilder) {
        statement.makeSQL(context: &context)
    }
}


///
/// The result of a select statement.
///
public struct XLSelectResultDependency: XLTableDeclaration {
    
    public init() {
        
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        
    }
}

///
/// A table used in a FROM clause in a select query.
///
public struct XLFromTableDependency: XLTableDeclaration, XLNamedDependency {

    private var qualifiedName: XLQualifiedName

    public var alias: XLName

    public init(qualifiedName: XLQualifiedName, alias: XLName) {
        self.qualifiedName = qualifiedName
        self.alias = alias
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: qualifiedName.makeSQL, right: alias.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a FROM clause in a common table expression.
///
public struct XLFromCommonTableDependency: XLTableDeclaration, XLNamedDependency {
    
    public var alias: XLName
    
    private let commonTable: XLCommonTableDependency
    
    public init(commonTable: XLCommonTableDependency, alias: XLName) {
        self.alias = alias
        self.commonTable = commonTable
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: commonTable.alias.makeSQL, right: alias.makeSQL)
    }
}


///
/// A table used in a FROM clause in an UPDATE statement.
///
public struct XLUpdateFromTableDependency: XLTableDeclaration, XLNamedDependency {

    public var alias: XLName
    
    public var statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "AS",
            left: { builder in
                builder.parenthesis(contents: statement.makeSQL)
            },
            right: alias.makeSQL
        )
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a UNION clause.
///
public struct XLUnionDependency: XLTableDeclaration {

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
}


///
/// Supported joins.
///
public enum JoinKind: String {
    case innerJoin = "INNER JOIN"
    case leftJoin = "LEFT JOIN"
}


///
/// A table used in a JOIN clause.
///
final class XLJoinTableDependency: XLTableDeclaration, XLNamedDependency {
    
    private let name: XLEncodable
    
    public var alias: XLName
    
    public var condition: (any XLExpression)!
    
    private let kind: JoinKind

    public init(kind: JoinKind, name: any XLEncodable, alias: XLName) {
        self.kind = kind
        self.name = name
        self.alias = alias
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: name.makeSQL, right: alias.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a JOIN clause in a common table expression.
///
final class XLJoinCommonTableDependency: XLTableDeclaration, XLNamedDependency {
    
    private let commonTable: XLCommonTableDependency

    public var alias: XLName
    
    public var condition: (any XLExpression)!
    
    private let kind: JoinKind

    public init(kind: JoinKind, commonTable: XLCommonTableDependency, alias: XLName) {
        self.kind = kind
        self.commonTable = commonTable
        self.alias = alias
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: commonTable.alias.makeSQL, right: alias.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a subquery.
///
public struct XLSubqueryDependency: XLTableDeclaration, XLNamedDependency {
    
    public var alias: XLName

    private let statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "AS",
            left: { context in
                context.parenthesis(contents: statement.makeSQL)
            }, 
            right: alias.makeSQL
        )
        
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a FROM clause in a subquery.
///
public struct XLFromSubqueryDependency: XLTableDeclaration, XLNamedDependency {
    
    public var alias: XLName

    private let statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis(contents: statement.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}
