//
//  XLMeta.swift
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


//public protocol XLSelectable {
//    func select(reader: XLRowReader) -> Self
//}


#warning("TODO: Throw error when reading fails")
public protocol XLColumnReader {
    func isNull(at index: Int) -> Bool
    func readInteger(at index: Int) -> Int
    func readReal(at index: Int) -> Double
    func readText(at index: Int) -> String
    func readBlob(at index: Int) -> Data
}


public protocol XLRowReader: AnyObject {
    func column<T>(_ expression: any XLExpression<T>, alias: XLName) throws -> T where T: XLLiteral
//    func column<T>(_ subquery: any XLQueryStatement<T>) -> T where T: XLLiteral
}

extension XLRowReader {
    
    //    public func subquery<T>(statement: () -> any XLQueryStatement<T>) -> T where T: XLLiteral {
    //        return subquery(statement())
    //    }
    
    //    public func subquery<T>(@XLQueryStatementBuilder builder: () -> any XLQueryStatement<T>) -> T where T: XLLiteral {
    //        return subquery(builder())
    //    }
    
//    func column<T>(_ expression: T) -> T where T: XLSelectable {
//        expression.select(reader: self)
//    }

//    func columns<T>(_ table: T) -> T.Row where T: XLRowReadable & XLDefault {
//        table.readRow(reader: self)
//    }
}


///
/// Introspect the expressions used to produce the columns so that we can generate the columns for the select statement.
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


final class XLColumnValuesRowReader<Output>: XLRowReader {
    
    private var count: Int = 0
    
    private var reader: XLColumnReader!
    
    init() {
    }
    
    func reset(reader: XLColumnReader) {
        count = 0
        self.reader = reader
    }
    
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


public protocol XLRowReadable<Row> {
    associatedtype Row
    func readRow(reader: XLRowReader) throws -> Row
}


public protocol XLRowWritable<Row>: XLEncodable {
    associatedtype Row
}


#warning("TODO: Remove makeSQLAnonymous... methods (column names are no longer anonymized ie c0, c1, c2 ... cN).")

///
/// Note: The word `...anonymous...` used in method names refers to a defuct implementation detail where column names were anonymized as c0, c1, ... cN. This was
/// done to reduce the length of the XL string that needed to be parsed. However this reduced readability for humans and this was later changed to use the proper
/// names for columns.
/// The word `...named...` indicates that the result is an identifiable type such as a table, from, join, subquery, or common table, and can be used in an `IN`
/// expression. Examples of results that are unnamed include the set of columns in a `SELECT` statement, and the result of a `UNION`, `INTERSECT`,
/// or `EXCLUDE`.
///
public protocol XLResult {
    typealias MetaRowIterator = (XLRowReader) throws -> Self
    associatedtype Nullable: XLMetaNullable
    associatedtype MetaResult: XLMetaResult
    associatedtype MetaNamedResult: XLMetaNamedResult
    associatedtype MetaNullableResult: XLMetaNullableResult
    associatedtype MetaNullableNamedResult: XLMetaNullableNamedResult
    associatedtype MetaCommonTable: XLMetaCommonTable
    associatedtype SQLReader: XLRowReadable

    static func makeSQLCommonTable(namespace: XLNamespace, dependency: XLCommonTableDependency) -> MetaCommonTable

    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaResult

    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaNamedResult

    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult
    
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    static func makeSQLAnonymousNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    static func makeSQLAnonymousNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult
}


// XL Table, Common Table Expression, and Subquery
public protocol XLTable: XLResult {
    
    #warning("TODO: Only Tables should be writable (able to insert and update), Views, Common Table Expression and Subquery should not be writable.")
    
    associatedtype MetaWritableTable: XLMetaWritableTable
    associatedtype MetaInsert: XLMetaInsert
    associatedtype MetaUpdate: XLMetaUpdate
    associatedtype MetaCreate: XLMetaCreate
    associatedtype MetaCreateAs: XLMetaCreate

    static func sqlTableName() -> XLQualifiedTableName
    
    static func makeSQLTable(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult

    static func makeSQLNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    static func makeSQLNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    static func makeSQLNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult

    static func makeSQLInsert(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    static func makeSQLUpdate(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    static func makeSQLCreate() -> MetaCreate
    
    static func makeSQLCreateAs() -> MetaCreateAs
}


public class XLNamespace {
    
    private var usedAlises: Set<XLName> = []
    
    private var aliasCount = 0
    
    public var nameFormat: String
    
    private init(nameFormat: String) {
        self.nameFormat = nameFormat
    }

    func makeAlias(alias: XLName?) -> XLName {
        let newAlias = alias ?? nextAlias()
        #warning("TODO: Rename alias if alias already exists")
        usedAlises.insert(newAlias)
        return newAlias
    }
    
    func nextAlias() -> XLName {
        defer {
            aliasCount += 1
        }
        return XLName(String(format: nameFormat, aliasCount))
    }
    
    public static func common() -> XLNamespace {
        XLNamespace(nameFormat: "cte%d")
    }
    
    public static func table() -> XLNamespace {
        XLNamespace(nameFormat: "t%d")
    }
    
    public static func parameter() -> XLNamespace {
        XLNamespace(nameFormat: "p%d")
    }
}


public protocol XLMetaNullable {
    associatedtype Basis
}


public protocol XLMetaResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLTableDeclaration { get }
}


public protocol XLMetaNamedResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLNamedTableDeclaration { get }
}


public protocol XLMetaNullableResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


public protocol XLMetaNullableNamedResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration & XLNamedDependency
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


public protocol XLMetaCommonTable {
    associatedtype Result: XLResult
    var definition: XLCommonTableDependency { get }
}


public protocol XLMetaWritableTable<Row>: XLEncodable {
    associatedtype Row
    var _table: any XLEncodable { get }
}


public protocol XLMetaInsert<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init(_ instance: Row)
}


public protocol XLMetaUpdate<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init()
}


public protocol XLMetaCreate: XLEncodable {
    associatedtype Table
}


public protocol XLColumnDependency {
    func qualifiedName(forColumn name: XLName) -> XLQualifiedName
}


///
/// A dependency which can be identified by an alias which can be used in an IN clause, such as a table, common table, from clause, join clause. Excludes
/// unnammed results such as select columns, UNION, UNION ALL, INTERSECT, and EXCLUDE.
///
public protocol XLNamedDependency {
    var alias: XLName { get }
}


public typealias XLTableDeclaration = XLEncodable & XLColumnDependency


public typealias XLNamedTableDeclaration = XLEncodable & XLColumnDependency & XLNamedDependency


public struct XLCommonTableDependency: XLColumnDependency, XLNamedDependency {
    
    public var alias: XLName

    internal var statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        // It should not be possible to reference the columns of a common table expression directly.
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }

    public func makeSQL(context: inout XLCommonTablesBuilder) {
        context.commonTable(alias: alias) { context in
            statement.makeSQL(context: &context)
        }
    }
}


///
/// Wraps a statement to be injected after the dependency is instantiated.
/// Note: Recursive common table requires stack allocation.
///
internal class XLRecursiveCommonTableStatement: XLEncodable {
    
    internal var statement: (any XLEncodable)!

    func makeSQL(context: inout XLBuilder) {
        statement.makeSQL(context: &context)
    }
}


public struct XLSelectResultDependency: XLTableDeclaration {
    
    public init() {
        
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        
    }
}

#warning("TODO: Unify XLFromTableDependency and XLCommonTableDependency - use generic any XLEncodable instead of qualifiedName ")

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


public struct XLUnionDependency: XLTableDeclaration {

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
}

public enum JoinKind: String {
    case innerJoin = "INNER JOIN"
    case leftJoin = "LEFT JOIN"
    #warning("TODO: Support cross and full outer join")
}


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



// MARK: - Query builder




public protocol XLQueryContext {
//    func with<T: XLColumns>(as alias: XLName, @XLQueryStatementBuilder builder: (inout XLQueryContext) -> any XLQueryStatement<T>) -> T.MetaCommonTable
//    func subquery<T: XLColumns>(as alias: XLName, @XLQueryStatementBuilder builder: (inout XLQueryContext) -> any XLQueryStatement<T>) -> T.MetaSubqueryTable
//    func table<T: SQLTable>(_ table: T.Type, as alias: XLName) -> T.MetaTable
//    func result<T: SQLTableColumns>(iterator: @escaping (XLRowReader) -> T) -> T.MetaResultColumns
}


public struct XLiteQueryContext: XLQueryContext {

//    public func with<T>(as alias: XLName, builder: (inout XLQueryContext) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T : XLColumns {
//        var queryContext: XLQueryContext = XLiteQueryContext()
//        let statement = builder(&queryContext)
//        return T.MetaCommonTable(alias: alias, statement: statement)
//    }
//
//    public func subquery<T>(as alias: XLName, builder: (inout XLQueryContext) -> any XLQueryStatement<T>) -> T.MetaSubqueryTable where T : XLColumns {
//        var queryContext: XLQueryContext = XLiteQueryContext()
//        let statement = builder(&queryContext)
//        return T.MetaSubqueryTable(alias: alias, statement: statement)
//    }
//    
//    #warning("TODO: Generate table alias from context")
//    public func table<T>(_ table: T.Type, as alias: XLName) -> T.MetaTable where T : SQLTable {
//        T.MetaTable(alias: alias)
//    }
//
//    public func result<T>(iterator: @escaping (XLRowReader) -> T) -> T.MetaResultColumns where T : SQLTableColumns {
//        T.MetaResultColumns(rowIterator: iterator)
//    }
}
