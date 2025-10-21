//
//  SQLStatements.swift
//
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


// MARK: - Statement builder


///
/// A clause within a query, such as `GroupBy`.
///
public protocol XLQueryComponent: XLEncodable {
    
}


// MARK: Select


///
/// A select statement.
///
public struct Select<Row>: XLEncodable, XLRowReadable {
    
    private let fields: any XLEncodable
    
    private let row: (XLRowReader) throws -> Row
    
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
    
    public init(@XLScalarExpressionBuilder _ expression: @escaping () -> some XLExpression<Row>) where Row: XLExpression & XLLiteral {
        self.fields = expression()
        self.row = { reader in
            try reader.column(expression(), alias: "c0")
        }
    }
    
    public init(_ expression: any XLExpression<Row>) where Row: XLExpression & XLLiteral {
        self.fields = expression
        self.row = { reader in
            try reader.column(expression, alias: "c0")
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
    
    internal init(kind: Kind, lhs: any XLEncodable, rhs: any XLEncodable) where Row: XLResult, Row.MetaResult: XLRowReadable, Row.MetaResult.Row == Row {
        self.kind = kind
        self.lhs = lhs
        self.rhs = rhs
        
        let namespace = XLNamespace.table()
        let dependency = XLUnionDependency()
        let meta = Row.makeSQLAnonymousResult(namespace: namespace, dependency: dependency)
        self.row = meta.readRow
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


// MARK: - Update


//internal struct UpdateSet<Row>: XLEncodable, XLRowWritable {
//    
//    private let table: any XLEncodable
//    
//    private let set: any XLEncodable
//    
//    internal init<T, S>(table: T, set: S) where T: XLMetaWritableTable, S: XLMetaUpdate, T.Row == Row, S.Row == Row {
//        self.table = table._table
//        self.set = set
//    }
//
//    internal func makeSQL(context: inout XLBuilder) {
//        context.unaryPrefix("UPDATE", expression: table.makeSQL)
//        set.makeSQL(context: &context)
//    }
//}


///
/// Update statement.
///
public struct Update<Row>: XLEncodable, XLRowWritable {
    
    private let table: any XLEncodable
    
    public init<T>(_ table: T) where T: XLMetaWritableTable, T.Row == Row {
        self.table = table._table
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("UPDATE", expression: table.makeSQL)
    }
}


// MARK: - Set


///
/// Setting clause.
///
/// Specifies the values for specific columns in an update statement.
///
public struct Setting<Row>: XLEncodable {
    
    private let values: any XLEncodable
    
    public init(_ values: (inout Row.MetaUpdate) -> Void) where Row: XLTable {
        var meta = Row.MetaUpdate()
        values(&meta)
        self.values = meta
    }
    
    public init<S>(_ values: S) where S: XLMetaUpdate, S.Row == Row {
        self.values = values
    }

    public func makeSQL(context: inout XLBuilder) {
        values.makeSQL(context: &context)
    }
}



// MARK: - Insert


///
/// Insert statement.
///
public struct Insert<Row>: XLEncodable, XLRowWritable {
    
    private let table: any XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row {
        self.table = meta._dependency
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("INSERT INTO", expression: table.makeSQL)
    }
}


// MARK: - Values


///
/// Values clause.
///
/// Specifies the values for columns for an insert clause.
///
public struct Values<Row> {
    
    internal let values: any XLEncodable
    
    public init<M>(_ values: M) where M: XLMetaInsert, M.Row == Row {
        self.values = values
    }
    
    public init(_ values: Row) where Row: XLTable, Row.MetaInsert.Row == Row {
        self.values = Row.MetaInsert(values)
    }
}


// MARK: - Create


///
/// Create statement.
///
public struct Create<Table>: XLEncodable {
    
    private let meta: any XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaCreate, T.Table == Table {
        self.meta = meta
    }
    
    public func makeSQL(context: inout XLBuilder) {
        meta.makeSQL(context: &context)
    }
}


// MARK: - As


///
/// As clause.
///
/// Specifies a query to use to populate a table in a create statement.
///
public struct As<Table> {
    
    internal let queryStatement: any XLEncodable
    
    public init(@XLQueryExpressionBuilder builder: (XLSchema) -> some XLQueryStatement<Table>) where Table: XLTable {
        let schema = XLSchema()
        self.queryStatement = builder(schema)
    }
}


// MARK: - Delete


///
/// Delete statement.
///
public struct Delete<Table>: XLEncodable {
    
    internal let name: any XLEncodable
    
    public init(_ table: Table) where Table: XLMetaWritableTable, Table.Row: XLTable {
        name = table._table
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("DELETE FROM") { builder in
            name.makeSQL(context: &builder)
        }
    }
}


// MARK: - From


///
/// From clause.
///
/// Specifies the table to use in a select clause.
///
public struct From: XLTableStatement {
    
    let table: XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaResult {
        self.table = meta
    }

    public init<T>(_ meta: T) where T: XLMetaNamedResult {
        self.table = meta
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("FROM", expression: table.makeSQL)
    }
}


// MARK: Join


///
/// Join clause.
///
/// Joins a table in a select statement.
///
/// > Note: Right joins are not supported.  A workaround is to LEFT JOIN, and swap the tables in the FROM and
/// JOIN clauses.
///
/// > Note: "INNER JOIN", "CROSS JOIN", "JOIN", "," all perform a cartesian product, which returns every
/// possible combination of rows from the two tables.
///
/// > Note: CROSS JOIN is treated as a special case by XLite in that it returns the cartesian product but does
/// not re-order the tables.
///
public struct Join: XLTableStatement {
    
    public enum Kind: String {
        case innerJoin = "INNER JOIN"
        case leftJoin = "LEFT JOIN"
        case outerJoin = "OUTER JOIN"
        case crossJoin = "CROSS JOIN"
    }
    
    private let kind: Kind
    
    private let table: XLEncodable
    
    private let constraint: (any XLExpression)?

    ///
    /// `Join` is a synonym for `Join.Inner`.
    ///
    public init<T, U>(_ table: T, on constraint: any XLExpression<U>) where T: XLMetaNamedResult, U: XLBoolean {
        self.init(kind: .innerJoin, table: table, constraint: constraint)
    }

    internal init(kind: Kind, table: XLEncodable, constraint: (any XLExpression)?) {
        self.kind = kind
        self.table = table
        self.constraint = constraint
    }
 
    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix(kind.rawValue, expression: table.makeSQL)
        if let constraint {
            context.unaryPrefix("ON", expression: constraint.makeSQL)
        }
    }
    
    ///
    /// Creates a cross join.
    ///
    public static func Cross<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .crossJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join.
    ///
    public static func Inner<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .innerJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join with a column constraint.
    ///
    public static func Inner<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates a left join with a column constraint.
    ///
    public static func Left<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNullableNamedResult, U: XLBoolean {
        Join(kind: .leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates an outer join with a column constraint.
    ///
    public static func Outer<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .outerJoin, table: table, constraint: constraint)
    }
}


// MARK: - Where


///
/// Where clause.
///
public struct Where: XLQueryComponent {
    
    private let condition: any XLExpression
    
    init(_ condition: any XLExpression) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Bool>) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Optional<Bool>>) {
        self.condition = condition
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("WHERE", expression: condition.makeSQL)
    }
}


// MARK: - Order


///
/// An ordering term such as ascending or descending.
///
public protocol XLOrderingTerm: XLEncodable {
    
}


///
/// Ascending ordering term used in an OrderBy expression.
///
public struct Ascending: XLOrderingTerm {
    
    private let expression: any XLExpression
    
    public init(@XLScalarExpressionBuilder expression: () -> any XLExpression) {
        self.expression = expression()
    }
    
    public init(expression: any XLExpression) {
        self.expression = expression
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("ASC", expression: expression.makeSQL)
    }
}


///
/// Descending ordering term used in an OrderBy expression.
///
public struct Descending: XLOrderingTerm {
    
    private let expression: any XLExpression
    
    public init(@XLScalarExpressionBuilder expression: () -> any XLExpression) {
        self.expression = expression()
    }
    
    public init(expression: any XLExpression) {
        self.expression = expression
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("DESC", expression: expression.makeSQL)
    }
}


///
/// Constructs a list of ordering term sub-expressions.
///
@resultBuilder public struct XLOrderingTermsBuilder {
    public static func buildBlock(_ components: XLOrderingTerm...) -> any XLEncodable {
        XLEncodableList(separator: ", ", expressions: components)
    }
}


///
/// OrderBy clause.
///
public struct OrderBy: XLQueryComponent {
    
    private let orderingTerms: XLEncodableList
    
    public init(_ terms: any XLOrderingTerm...) {
        self.init(terms: terms)
    }
    
    internal init(terms: [any XLOrderingTerm]) {
        self.orderingTerms = XLEncodableList(separator: .comma, expressions: terms)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("ORDER BY", expression: orderingTerms.makeSQL)
    }
}


// MARK: - Limit


///
/// Limit clause.
///
public struct Limit: XLQueryComponent {
    
    private let count: any XLExpression
    
    public init(_ count: any XLExpression<Int>) {
        self.count = count
    }
    
    public init(@XLScalarExpressionBuilder _ count: () -> any XLExpression<Int>) {
        self.count = count()
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("LIMIT", expression: count.makeSQL(context:))
    }
}


// MARK: - Offset


///
/// Offset clause.
///
public struct Offset: XLQueryComponent {
    
    private let count: any XLExpression
    
    public init(_ count: any XLExpression<Int>) {
        self.count = count
    }
    
    public init(@XLScalarExpressionBuilder _ count: () -> any XLExpression<Int>) {
        self.count = count()
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("OFFSET", expression: count.makeSQL(context:))
    }
}


// MARK: - Group By


///
/// GroupBy clause.
///
public struct GroupBy: XLQueryComponent {
    
    private let columns: any XLEncodable
    
    public init(_ columns: any XLExpression...) {
        self.columns = XLEncodableList(separator: .comma, expressions: columns)
    }

    public init(_ columns: [any XLExpression]) {
        self.columns = XLEncodableList(separator: .comma, expressions: columns)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("GROUP BY", expression: columns.makeSQL)
    }
}


// MARK: - Having


///
/// Having clause.
///
/// Constrains a GroupBy clause.
///
public struct Having: XLQueryComponent {
    
    private let condition: any XLExpression
    
    init(_ condition: any XLExpression) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Bool>) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Optional<Bool>>) {
        self.condition = condition
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("HAVING", expression: condition.makeSQL)
    }
}
