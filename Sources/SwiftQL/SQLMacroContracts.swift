//
//  SQLMacroContracts.swift
//  SwiftQL
//
//  What `@SQLTable` and `@SQLResult` generate, stated as protocols: the
//  metadata shapes a model is selected as, and the members the macros supply
//  for each.
//
//  Split out of SQLMeta.swift (issue #559).
//

import Foundation


// MARK: - Result


///
/// Metadata associated with a struct annotated with `@SQLResult`.
///
/// The types and methods defined by this protocol are implemented by macro-generated code.
///
/// The word `...anonymous...` used in method names refers to a defunct implementation detail
/// where column names were anonymized as `c0`, `c1`, ... `cN`. This reduced the length of the SQL
/// string that needed to be parsed, but also reduced readability, so columns now retain their names.
/// The word `...named...` indicates that the result is an
/// identifiable type such as a table, from, join, subquery, or common table, and can be used in an `IN`
/// expression. Examples of results that are unnamed include the set of columns in a `SELECT` statement,
/// and the result of a `UNION`, `INTERSECT`, or `EXCEPT`.
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

    // The anonymous-result requirements below are live, not pending removal.
    // `SQLFunctionalSyntax` calls them for every selection whose rows are
    // assembled by the query rather than by the result type itself, and the
    // `@SQLTable`/`@SQLResult` macros generate all six. They carried a
    // `TODO: Remove` each; retiring the surface is tracked by issue #90 and is
    // a v2 change, not something to do in passing.

    ///
    /// Creates a result whose rows the caller assembles.
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaResult

    ///
    /// Creates a named result whose rows the caller assembles.
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaNamedResult

    ///
    /// Creates a result that reads its own rows from the columns it is given.
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult

    ///
    /// Creates a named result that reads its own rows.
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    ///
    /// Creates a nullable result that reads its own rows -- the shape an outer
    /// join produces, where every column may be absent.
    ///
    static func makeSQLAnonymousNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    ///
    /// Creates a nullable named result that reads its own rows.
    ///
    static func makeSQLAnonymousNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult
}


// MARK: - Table


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
    
    private var usedAliases: Set<String> = []
    
    private var aliasCount = 0
    
    public var nameFormat: String
    
    private init(nameFormat: String) {
        self.nameFormat = nameFormat
    }

    ///
    /// Creates an alias with a given name.
    ///
    /// Creates and returns an alias with a given name. The alias is tracked to avoid conflicts. If the alias is
    /// not specified then one is assigned automatically using `nextAlias()`.
    ///
    func makeAlias(alias: XLName?) -> XLName {
        let newAlias = alias ?? nextAlias()
        usedAliases.insert(aliasKey(newAlias))
        return newAlias
    }
    
    ///
    /// Creates the next alias in the sequence.
    ///
    func nextAlias() -> XLName {
        var attemptedAliases: Set<String> = []
        while true {
            let alias = XLName(String(format: nameFormat, aliasCount))
            aliasCount += 1
            let key = aliasKey(alias)
            if !usedAliases.contains(key) {
                return alias
            }
            if !attemptedAliases.insert(key).inserted {
                return nextFallbackAlias(stem: alias.rawValue)
            }
        }
    }

    private func aliasKey(_ alias: XLName) -> String {
        alias.rawValue.lowercased()
    }

    private func nextFallbackAlias(stem: String) -> XLName {
        var suffix = 0
        while true {
            let alias = XLName("\(stem)\(suffix)")
            suffix += 1
            if !usedAliases.contains(aliasKey(alias)) {
                return alias
            }
        }
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
