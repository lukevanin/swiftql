//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


@resultBuilder public struct XLInsertExpressionBuilder {

    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    public static func buildPartialBlock<Row>(accumulated: XLWithStatement, next: Insert<Row>) -> XLInsertTableStatement<Row> {
        XLInsertTableStatement(components: XLInsertStatementComponents(commonTables: accumulated.commonTables, insert: next))
    }

    public static func buildPartialBlock<Row>(first: Insert<Row>) -> XLInsertTableStatement<Row> {
        XLInsertTableStatement(components: XLInsertStatementComponents(insert: first))
    }
    
    
    // MARK: Insert
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row>, next: Values<Row>) -> XLInsertTableValuesStatement<Row> {
        XLInsertTableValuesStatement(components: accumulated.components.appending(next.values))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row>, next: Select<Row>) -> XLInsertSelectStatement<Row> {
        XLInsertSelectStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Select
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectStatement<Row>, next: From) -> XLInsertSelectTableStatement<Row> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Join) -> XLInsertSelectTableStatement<Row> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Where) -> XLInsertSelectWhereStatement<Row> {
        XLInsertSelectWhereStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: Having) -> XLInsertSelectHavingStatement<Row> {
        XLInsertSelectHavingStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectOrderByStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectLimitStatement<Row>, next: Offset) -> XLInsertSelectOffsetStatement<Row> {
        XLInsertSelectOffsetStatement(components: accumulated.components.appending(next))
    }
}


///
///
///
public func sql(@XLInsertExpressionBuilder builder: (XLSchema) -> any XLInsertStatement) -> any XLInsertStatement {
    let schema = XLSchema()
    return builder(schema)
}
