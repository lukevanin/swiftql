//
//  SQLInsertStatement.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


// MARK: - Insert


///
/// An insert statement.
///
struct AbstractXLInsertStatement<Row>: XLInsertStatement {
    var components: XLInsertStatementComponents<Row>
}


///
/// Builder used to construct insert statements.
///
public struct XLInsertStatementComponents<Row>: XLEncodable {

    var commonTables: [XLCommonTableDependency]
    
    let insert: Insert<Row>
    
    var components: [any XLEncodable]

    init(commonTables: [XLCommonTableDependency] = [], insert: Insert<Row>, components: [any XLEncodable] = []) {
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
public struct XLInsertTableStatement<Table> {
    
    public let components: XLInsertStatementComponents<Table>
    
    public func values(_ values: Table.MetaInsert) -> XLInsertTableValuesStatement<Table> where Table: XLTable {
        XLInsertTableValuesStatement(components: components.appending(values))
    }
    
    public func values(_ values: Table.MetaInsert.Row) -> XLInsertTableValuesStatement<Table> where Table: XLTable {
        XLInsertTableValuesStatement(components: components.appending(Table.MetaInsert(values)))
    }
    
    public func select<T>(_ result: T) -> XLInsertSelectStatement<T.Row> where T: XLRowReadable, T.Row == Table {
        XLInsertSelectStatement(components: components.appending(Select(result)))
    }
    
}


///
/// Values clause for an insert statement.
///
/// Specifies values for columns in an insert statement.
///
public struct XLInsertTableValuesStatement<Table>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Table>

}


///
/// Select clause in insert statement.
///
/// Specifies a select query used to insert rows.
///
public struct XLInsertSelectStatement<Table>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Table>

    // MARK: From
    
    public func from<T>(_ t: T) -> XLInsertSelectTableStatement<Row> where T: XLMetaNamedResult {
        XLInsertSelectTableStatement(components: components.appending(From(t)))
    }

}


///
/// A select from statement used in an insert statement.
///
public struct XLInsertSelectTableStatement<Row>: XLInsertStatement {
        
    public let components: XLInsertStatementComponents<Row>
    
    // MARK: Inner Join
    
    public func innerJoin<T, U>(_ t: T, on condition: any XLExpression<U>) -> XLInsertSelectTableStatement<Row> where T: XLMetaResult, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join(kind: .innerJoin, table: t, constraint: condition)))
    }
    
    public func innerJoin<T>(_ t: T) -> XLInsertSelectTableStatement<Row> where T: XLMetaResult {
        XLInsertSelectTableStatement(components: components.appending(Join(kind: .innerJoin, table: t, constraint: nil)))
    }
    
    public func crossJoin<T>(_ t: T) -> XLInsertSelectTableStatement<Row> where T: XLMetaResult {
        XLInsertSelectTableStatement(components: components.appending(Join(kind: .crossJoin, table: t, constraint: nil)))
    }

    // MARK: Left Join
    
    public func leftJoin<T, U>(_ t: T, on condition: any XLExpression<U>) -> XLInsertSelectTableStatement<Row> where T: XLMetaNullableResult, U: XLBoolean {
        XLInsertSelectTableStatement(components: components.appending(Join(kind: .leftJoin, table: t, constraint: condition)))
    }

    // MARK: Where
    
    public func `where`<T>(_ condition: any XLExpression<T>) -> XLInsertSelectWhereStatement<Row> where T: XLBoolean {
        `where`(Where(condition))
    }

    func `where`(_ expression: Where) -> XLInsertSelectWhereStatement<Row> {
        XLInsertSelectWhereStatement(components: components.appending(expression))
    }
    
    // MARK: Group

    public func groupBy(_ expressions: any XLExpression...) -> XLInsertSelectGroupByStatement<Row> {
        groupBy(GroupBy(expressions))
    }

    func groupBy(_ expression: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: components.appending(expression))
    }
    
    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLInsertSelectOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLInsertSelectLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: components.appending(expression))
    }
}


///
/// A select where statement used in an insert statement.
///
public struct XLInsertSelectWhereStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>

    // MARK: Group
    
    public func groupBy(_ expressions: any XLExpression...) -> XLInsertSelectGroupByStatement<Row> {
        groupBy(GroupBy(expressions))
    }

    func groupBy(_ expression: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: components.appending(expression))
    }
    
    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLInsertSelectOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLInsertSelectLimitStatement<Row> {
        limit(Limit(count))
    }
    
    func limit(_ expression: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: components.appending(expression))
    }
}


///
/// A select group-by statement used in an insert statement.
///
public struct XLInsertSelectGroupByStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>

    // MARK: Having
    
    public func having<T>(_ condition: any XLExpression<T>) -> XLInsertSelectHavingStatement<Row> where T: XLBoolean {
        having(Having(condition))
    }

    func having(_ expression: Having) -> XLInsertSelectHavingStatement<Row> {
        XLInsertSelectHavingStatement(components: components.appending(expression))
    }

    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLInsertSelectOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit

    public func limit(_ count: any XLExpression<Int>) -> XLInsertSelectLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: components.appending(expression))
    }
}


///
/// An insert ... having statement used in an insert statement.
///
public struct XLInsertSelectHavingStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>

    // MARK: Order
    
    public func orderBy(_ terms: any XLOrderingTerm...) -> XLInsertSelectOrderByStatement<Row> {
        orderBy(OrderBy(terms: terms))
    }

    func orderBy(_ expression: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: components.appending(expression))
    }
    
    // MARK: Limit

    public func limit(_ count: any XLExpression<Int>) -> XLInsertSelectLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: components.appending(expression))
    }
}

///
/// A select order-by statement used in an insert statement.
///
public struct XLInsertSelectOrderByStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>

    // MARK: Limit
    
    public func limit(_ count: any XLExpression<Int>) -> XLInsertSelectLimitStatement<Row> {
        limit(Limit(count))
    }

    func limit(_ expression: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: components.appending(expression))
    }
}


///
/// A select limit statement used in an insert statement.
///
public struct XLInsertSelectLimitStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>
    
    public func offset(_ count: any XLExpression<Int>) -> XLInsertSelectOffsetStatement<Row> {
        offset(Offset(count))
    }

    func offset(_ expression: Offset) -> XLInsertSelectOffsetStatement<Row> {
        XLInsertSelectOffsetStatement(components: components.appending(expression))
    }
}


///
/// A select offset statement used in an insert statement.
///
public struct XLInsertSelectOffsetStatement<Row>: XLInsertStatement {
    
    public let components: XLInsertStatementComponents<Row>

}
