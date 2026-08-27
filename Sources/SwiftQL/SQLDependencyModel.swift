//
//  SQLDependencyModel.swift
//  SwiftQL
//
//  What a column can be read from: a table in a FROM clause, a common table
//  expression, a subquery, the EXCLUDED pseudo-table of an upsert. A
//  dependency is what a rendered column reference qualifies itself against.
//
//  Split out of SQLMeta.swift (issue #559).
//

import Foundation


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
/// common table, from clause, join clause. Excludes unnamed results such as select columns, UNION,
/// UNION ALL, INTERSECT, and EXCEPT.
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
/// An optional optimization hint controlling whether SQLite materializes a
/// common table expression into a temporary table.
///
/// `unspecified` renders no hint and leaves the decision to SQLite's query
/// planner (the default). `materialized` and `notMaterialized` render the
/// `MATERIALIZED` / `NOT MATERIALIZED` keywords, which SQLite honors from
/// version 3.35.0 (2021-03-12).
///
public enum XLCommonTableMaterialization: Sendable, Equatable {
    case unspecified
    case materialized
    case notMaterialized

    /// The SQL keyword rendered between `AS` and the CTE body, or `nil` for the
    /// unspecified default.
    public var keyword: String? {
        switch self {
        case .unspecified:
            return nil
        case .materialized:
            return "MATERIALIZED"
        case .notMaterialized:
            return "NOT MATERIALIZED"
        }
    }
}


///
/// A common table expression.
///
public struct XLCommonTableDependency: XLColumnDependency, XLNamedDependency {

    public var alias: XLName

    internal var statement: any XLEncodable

    /// The materialization hint rendered for this common table, if any.
    public var materialization: XLCommonTableMaterialization

    /// An explicit CTE column list, rendered as `alias(col, col) AS (...)`. Empty
    /// for the ordinary `alias AS (...)` form. Used to give a scalar common table
    /// a stable one-column name without changing its body's column labels.
    public var columns: [XLName]

    public init(
        alias: XLName,
        statement: any XLEncodable,
        materialization: XLCommonTableMaterialization = .unspecified,
        columns: [XLName] = []
    ) {
        self.alias = alias
        self.statement = statement
        self.materialization = materialization
        self.columns = columns
    }

    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }

    /// Returns a copy of this dependency carrying the given materialization hint.
    public func materialized(_ materialization: XLCommonTableMaterialization) -> XLCommonTableDependency {
        var copy = self
        copy.materialization = materialization
        return copy
    }

    public func makeSQL(context: inout XLCommonTablesBuilder) {
        context.commonTable(alias: alias, materialization: materialization, columns: columns) { context in
            statement.makeSQL(context: &context)
        }
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

    internal let source: any XLEncodable

    public var alias: XLName

    internal init(source: any XLEncodable, alias: XLName) {
        self.source = source
        self.alias = alias
    }

    public init(qualifiedName: XLQualifiedName, alias: XLName) {
        self.init(source: qualifiedName, alias: alias)
    }

    public init(commonTable: XLCommonTableDependency, alias: XLName) {
        self.init(source: commonTable.alias, alias: alias)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: source.makeSQL, right: alias.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// The `excluded` pseudo table available inside an `ON CONFLICT ... DO UPDATE`
/// clause.
///
/// Unlike ``XLFromTableDependency``, the excluded pseudo table renders as the
/// bare `excluded` keyword rather than `<table> AS excluded`, while its columns
/// still qualify as `excluded.<column>`. An update assignment such as
/// `row.value = excluded.value` therefore resolves to the candidate row's
/// value. Rendering the bare keyword also means the reference cannot silently
/// resolve to the base table if it is ever used outside an upsert: such misuse
/// renders `excluded`, which SQLite rejects as an unknown table.
///
public struct XLExcludedTableDependency: XLTableDeclaration, XLNamedDependency {

    public let alias = XLName("excluded")

    public init() {}

    public func makeSQL(context: inout XLBuilder) {
        alias.makeSQL(context: &context)
    }

    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


@available(*, deprecated, renamed: "XLFromTableDependency")
public typealias XLFromCommonTableDependency = XLFromTableDependency


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
/// Vestigial join-kind enumeration.
///
/// This type is unused by the library — join rendering is driven by the
/// canonical ``Join/Kind``, which covers inner, left, right, full outer, and
/// cross joins. It is retained (deprecated) only for source compatibility and
/// does not receive new cases.
///
@available(*, deprecated, message: "Unused; the canonical join kinds are Join.Kind.")
public enum JoinKind: String {
    case innerJoin = "INNER JOIN"
    case leftJoin = "LEFT JOIN"
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
