//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


// MARK: - Query


public struct XLQueryStatementComponents<Row>: XLEncodable, XLRowReadable {

    #warning("TODO: Record tables which are used in the query - create publisher which triggers when tables are updated")
    
    var commonTables: [XLCommonTableDependency]
    
//    let select: Select<Row>
    let reader: any XLRowReadable<Row>
    
    var components: [any XLEncodable]

    init(commonTables: [XLCommonTableDependency] = [], select: Select<Row>, components: [any XLEncodable] = []) {
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
//        reader.makeSQL(context: &context)
        for component in components {
            component.makeSQL(context: &context)
        }
    }
    
    public func readRow(reader: XLRowReader) throws -> Row {
        try self.reader.readRow(reader: reader)
    }
}


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
    

struct AbstractXLQueryStatement<Row>: XLQueryStatement {
    var components: XLQueryStatementComponents<Row>
}


public protocol XLSimpleSelectQueryStatement<Row>: XLQueryStatement {
}

extension XLSimpleSelectQueryStatement {
    
    // MARK: Union
    
    public func union(_ statement: () -> any XLQueryStatement<Row>) -> XLQueryUnionStatement<Row> where Row: XLResult, Row.MetaResult: XLRowReadable, Row.MetaResult.Row == Row {
        let union = BooleanClause<Row>(kind: .union, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    public func unionAll(_ statement: () -> any XLQueryStatement<Row>) -> XLQueryUnionStatement<Row> where Row: XLResult, Row.MetaResult: XLRowReadable, Row.MetaResult.Row == Row {
        let union = BooleanClause<Row>(kind: .unionAll, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    public func intersect(_ statement: () -> any XLQueryStatement<Row>) -> XLQueryUnionStatement<Row> where Row: XLResult, Row.MetaResult: XLRowReadable, Row.MetaResult.Row == Row {
        let union = BooleanClause<Row>(kind: .intersect, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    public func except(_ statement: () -> any XLQueryStatement<Row>) -> XLQueryUnionStatement<Row> where Row: XLResult, Row.MetaResult: XLRowReadable, Row.MetaResult.Row == Row {
        let union = BooleanClause<Row>(kind: .except, lhs: components, rhs: statement().components)
        return XLQueryUnionStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
}


public struct XLQuerySelectStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
        
    public let components: XLQueryStatementComponents<Row>
    
    // MARK: From
    
    public func from<T>(_ t: T) -> XLQueryTableStatement<Row> where T: XLMetaNamedResult {
        XLQueryTableStatement(components: components.appending(From(t)))
    }
}


public struct XLQueryTableStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
        
    public let components: XLQueryStatementComponents<Row>
    
    // MARK: Join
    
    public func innerJoin<T, U>(_ t: T, on condition: any XLExpression<U>) -> XLQueryTableStatement<Row> where T: XLMetaNamedResult, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join(kind: .innerJoin, table: t, constraint: condition)))
    }

    public func innerJoin<T>(_ t: T) -> XLQueryTableStatement<Row> where T: XLMetaNamedResult {
        XLQueryTableStatement(components: components.appending(Join(kind: .innerJoin, table: t, constraint: nil)))
    }

    public func crossJoin<T>(_ t: T) -> XLQueryTableStatement<Row> where T: XLMetaNamedResult {
        XLQueryTableStatement(components: components.appending(Join(kind: .crossJoin, table: t, constraint: nil)))
    }

    public func leftJoin<T, U>(_ t: T, on condition: any XLExpression<U>) -> XLQueryTableStatement<Row> where T: XLMetaNullableNamedResult, U: XLBoolean {
        XLQueryTableStatement(components: components.appending(Join(kind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where
    
    public func `where`<T>(_ condition: any XLExpression<T>) -> XLQueryWhereStatement<Row> where T: XLBoolean {
        `where`(Where(condition))
    }

    func `where`(_ expression: Where) -> XLQueryWhereStatement<Row> {
        XLQueryWhereStatement(components: components.appending(expression))
    }
    
    // MARK: Group

    public func groupBy(_ expressions: any XLExpression...) -> XLQueryGroupByStatement<Row> {
        groupBy(GroupBy(expressions))
    }

    func groupBy(_ expression: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: components.appending(expression))
    }
    
    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLQueryOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }

}


public struct XLQueryWhereStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

    // MARK: Group
    
    public func groupBy(_ expressions: any XLExpression...) -> XLQueryGroupByStatement<Row> {
        groupBy(GroupBy(expressions))
    }

    func groupBy(_ expression: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: components.appending(expression))
    }
    
    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLQueryOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }
    
    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }
}


public struct XLQueryGroupByStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

    // MARK: Having
    
    public func having<T>(_ condition: any XLExpression<T>) -> XLQueryHavingStatement<Row> where T: XLBoolean {
        having(Having(condition))
    }

    func having(_ expression: Having) -> XLQueryHavingStatement<Row> {
        XLQueryHavingStatement(components: components.appending(expression))
    }

    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLQueryOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit

    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }
}


public struct XLQueryHavingStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLQueryOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit

    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }
}


public struct XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
    
    internal let kind: BooleanClause<Statement.Row>.Kind
    
    public let query: Statement
}


public struct XLQueryUnionStatement<Row>: XLQueryStatement, XLSimpleSelectQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLQueryOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit

    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }
}


public struct XLQueryOrderByStatement<Row>: XLQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLQueryLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: components.appending(expression))
    }
}


public struct XLQueryLimitStatement<Row>: XLQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>
    
    public func offset(_ count: any XLExpression<Int>) -> XLQueryOffsetStatement<Row> {
        offset(Offset(count))
    }

    func offset(_ expression: Offset) -> XLQueryOffsetStatement<Row> {
        XLQueryOffsetStatement(components: components.appending(expression))
    }
}


public struct XLQueryOffsetStatement<Row>: XLQueryStatement {
    
    public let components: XLQueryStatementComponents<Row>

}
