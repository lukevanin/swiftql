//
//  SQLSelectStatements.swift
//  SwiftQL
//
//  Reading statements: SELECT and the compound operators that combine several
//  of them, and the WITH clause that names one.
//
//  Split out of SQLStatements.swift (issue #559).
//

import Foundation


public protocol XLQueryComponent: XLEncodable {
    
}


// MARK: Select


///
/// A select statement.
///
public struct Select<Row>: XLEncodable, XLRowReadable {
    
    private let fields: any XLEncodable
    
    private let row: (XLRowReader) throws -> Row

    /// Builds a select directly from immutable static projection metadata.
    ///
    /// This more-specific overload deliberately does not call `readRow` while
    /// constructing the statement. Generated model initializers and
    /// contextual codecs run only when a returned database row is decoded.
    public init<T>(_ layout: T)
    where T: XLStaticRowReadable, T.Row == Row {
        self.fields = layout
        self.row = layout.readRow
    }
    
    public init<T>(_ meta: T) where T: XLRowReadable, T.Row == Row {
        let reader = XLColumnsDefinitionRowReader()
        let _ = try! meta.readRow(reader: reader)
        self.fields = reader
        self.row = meta.readRow
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("SELECT", expression: fields.makeSQL)
    }
    
    public func readRow(reader: XLRowReader) throws -> Row {
        try row(reader)
    }
    
    /// Builds a scalar select without requiring the logical result type to
    /// adopt the legacy expression and literal protocols.
    ///
    /// Bare contextual values can be rendered by this initializer, but their
    /// row decoding still requires an ``XLStaticRowLayout`` carrying codec
    /// metadata. The legacy path reports ``XLStaticRowReadError/staticLayoutRequired(valueType:alias:)``
    /// instead of fabricating a value.
    public init(
        @XLScalarExpressionBuilder _ expression: @escaping () -> some XLExpression<Row>
    ) {
        self.fields = expression()
        self.row = { reader in
            try reader.staticColumn(expression(), alias: "c0")
        }
    }

    /// Builds an unconstrained scalar select.
    ///
    /// Bare contextual values still require an ``XLStaticRowLayout`` to carry
    /// the codec metadata needed during row decoding.
    public init(_ expression: any XLExpression<Row>) {
        self.fields = expression
        self.row = { reader in
            try reader.staticColumn(expression, alias: "c0")
        }
    }
}


// MARK: - Union


///
/// A boolean set operation, succh as a union or intersection.
///
internal struct BooleanClause<Row>: XLEncodable, XLRowReadable {
    
    enum Kind {
        case union
        case unionAll
        case except
        case intersect
    }
    
    private let kind: Kind

    private let lhs: any XLEncodable

    private let rhs: any XLEncodable

    private let row: (XLRowReader) throws -> Row

    ///
    /// Combines two branches, preserving the first branch's existing row reader.
    ///
    /// The compound result decodes with the same reader as its left branch
    /// rather than reconstructing metadata from `Row: XLResult`, so a direct
    /// scalar branch (`select(expr)`) flows through `UNION` / `UNION ALL` /
    /// `INTERSECT` / `EXCEPT` without a boxed `@SQLResult` wrapper.
    ///
    internal init(kind: Kind, lhs: XLQueryStatementComponents<Row>, rhs: any XLEncodable) {
        self.kind = kind
        self.lhs = lhs
        self.rhs = rhs
        self.row = lhs.readRow
    }
    
    public func makeSQL(context: inout XLBuilder) {
        let op: String
        switch kind {
        case .union:
            op = "UNION"
        case .unionAll:
            op = "UNION ALL"
        case .intersect:
            op = "INTERSECT"
        case .except:
            op = "EXCEPT"
        }
        context.binaryOperator(op, left: lhs.makeSQL, right: rhs.makeSQL(context:))
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try row(reader)
    }
}


///
/// Union clause.
///
/// Combines two queries, and returns the rows returned by the first query followed by the rows returned by
/// the second query.
///
/// Duplicate rows are excluded.
///
/// > Note: Both queries must return the same row type.
///
public struct Union {
    public init() {
        
    }
}


///
/// Union all clause.
///
/// Combines two queries, and returns the rows returned by the first query followed by the rows returned by
/// the second query.
///
/// Duplicate rows are included.
///
/// > Note: Both queries must return the same row type.
///
public struct UnionAll {
    public init() {
        
    }
}


///
/// Intersect clause.
///
/// Combines two queries, and returns only the rows which are returned by both queries.
///
/// > Note: Both queries must return the same row type.
///
public struct Intersect {
    public init() {
        
    }
}


///
/// Except clause.
///
/// Combines two queries, and returns the rows from the first query which do not exist in the second query.
///
/// > Note: Both queries must return the same row type.
///
public struct Except {
    public init() {
        
    }
}


// MARK: - With


///
/// With clause.
///
/// Specifies common tables used in a select, update, insert, or delete statement.
///
public struct With {
    
    internal let commonTables: [XLCommonTableDependency]
    
    public init(_ tables: any XLMetaCommonTable...) {
        self.commonTables = tables.map { $0.definition }
    }

    public init(_ commonTables: XLCommonTableDependency...) {
        self.commonTables = commonTables.map { $0 }
    }

    public init(_ commonTables: [XLCommonTableDependency]) {
        self.commonTables = commonTables.map { $0 }
    }
}
