//
//  SQLInsertExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to onstruct an insert statement.
///
@resultBuilder public struct XLInsertExpressionBuilder {

    ///
    /// Constructs a With expression.
    ///
    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    ///
    /// Constructs an Insert expression using a With expression.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement, next: Insert<Row>) -> XLInsertTableStatement<Row> {
        XLInsertTableStatement(components: XLInsertStatementComponents(commonTables: accumulated.commonTables, insert: next))
    }

    ///
    /// Constructs an Insert expression.
    ///
    public static func buildPartialBlock<Row>(first: Insert<Row>) -> XLInsertTableStatement<Row> {
        XLInsertTableStatement(components: XLInsertStatementComponents(insert: first))
    }
    
    
    // MARK: Insert
    
    ///
    /// Constructs an Insert statement with a Values clause.
    ///
    /// The Values clause specifies the values for columns which are inserted.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row>, next: Values<Row>) -> XLInsertTableValuesStatement<Row> {
        XLInsertTableValuesStatement(components: accumulated.components.appending(next.values))
    }

    ///
    /// Constructs an Insert statement with a Select clause.
    ///
    /// The Select clause specifies the rows which are to be inserted.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row>, next: Select<Row>) -> XLInsertSelectStatement<Row> {
        XLInsertSelectStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Select
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectStatement<Row>, next: From) -> XLInsertSelectTableStatement<Row> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Join clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Join) -> XLInsertSelectTableStatement<Row> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Where) -> XLInsertSelectWhereStatement<Row> {
        XLInsertSelectWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: GroupBy) -> XLInsertSelectGroupByStatement<Row> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with a Having clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: Having) -> XLInsertSelectHavingStatement<Row> {
        XLInsertSelectHavingStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Having clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row>, next: OrderBy) -> XLInsertSelectOrderByStatement<Row> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Having clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    ///
    /// Constructs an Insert statement with a Select clause which includes an OrderBy clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectOrderByStatement<Row>, next: Limit) -> XLInsertSelectLimitStatement<Row> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    ///
    /// Constructs an Insert statement with a Select clause which includes an Limit clause with an Offset clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectLimitStatement<Row>, next: Offset) -> XLInsertSelectOffsetStatement<Row> {
        XLInsertSelectOffsetStatement(components: accumulated.components.appending(next))
    }
}


///
/// Constructs an Insert statement.
///
public func sql(@XLInsertExpressionBuilder builder: (XLSchema) -> any XLInsertStatement) -> any XLInsertStatement {
    let schema = XLSchema()
    return builder(schema)
}
