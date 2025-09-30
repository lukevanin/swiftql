//
//  XLQuery.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


// MARK: - Statement builder


public protocol XLQueryComponent: XLEncodable {
    
}


// MARK: Select


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
    
    #warning("TODO: See if it is possible to remove Row type constraint (XLExpression and XLLiteral) - if they can also be removed from the reader")
    
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


public struct Union {
    public init() {
        
    }
}


public struct UnionAll {
    public init() {
        
    }
}


public struct Intersect {
    public init() {
        
    }
}


public struct Except {
    public init() {
        
    }
}


// MARK: - With


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


public struct Setting<Row>: XLEncodable {
    
    private let values: any XLEncodable
    
    #warning("FIXME: Closure requires explicit genric type parameter to resolve Row type.")
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


public struct As<Table> {
    
    internal let queryStatement: any XLEncodable
    
    public init(@XLQueryExpressionBuilder builder: (XLSchema) -> some XLQueryStatement<Table>) where Table: XLTable {
        let schema = XLSchema()
        self.queryStatement = builder(schema)
    }
}


// MARK: - Delete


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


public struct From: XLTableStatement {
    
    let table: XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaResult {
        self.table = meta
    }

    public init<T>(_ meta: T) where T: XLMetaNamedResult {
        self.table = meta
    }
    
//    internal init(table: XLEncodable) {
//        self.table = table
//    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("FROM", expression: table.makeSQL)
    }
}


// MARK: Join


///
/// Note: Right joins are not supported.  A workaround is to LEFT JOIN, and swap the tables in the FROM and JOIN clauses.
/// Note: "INNER JOIN", "CROSS JOIN", "JOIN", "," all perform a cartesian product, which returns every possible combination of rows from the two tables.
/// Note: CROSS JOIN is treated as a special case by XLite in that it returns the cartesian product but does not re-order the tables.
///
public struct Join: XLTableStatement {
    
    #warning("TODO: Support NATURAL JOIN and USING clause")
    
    #warning("TODO: Support RIGHT JOIN (support nullable table in FROM clause)")
    
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
    
    public static func Cross<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .crossJoin, table: table, constraint: nil)
    }

    public static func Inner<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .innerJoin, table: table, constraint: nil)
    }

    public static func Inner<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .innerJoin, table: table, constraint: constraint)
    }

    public static func Left<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNullableNamedResult, U: XLBoolean {
        Join(kind: .leftJoin, table: table, constraint: constraint)
    }

    public static func Outer<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .outerJoin, table: table, constraint: constraint)
    }
}


// MARK: - Where


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


public protocol XLOrderingTerm: XLEncodable {
    
}


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


@resultBuilder public struct XLOrderingTermsBuilder {
    public static func buildBlock(_ components: XLOrderingTerm...) -> any XLEncodable {
        XLEncodableList(separator: ", ", expressions: components)
    }
}


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
