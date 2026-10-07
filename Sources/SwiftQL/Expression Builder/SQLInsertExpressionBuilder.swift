//
//  SQLInsertExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to construct an insert statement in `Dialect`.
///
/// Every clause of the body must belong to `Dialect`: the table it inserts
/// into, and the tables and expressions of a select that feeds it
/// (issue #822). ``XLInsertExpressionBuilder`` is the builder for SQLite.
///
@resultBuilder public struct XLDialectInsertExpressionBuilder<Dialect> where Dialect: XLSQLDialect {

    ///
    /// Accepts a clause of the builder's dialect.
    ///
    public static func buildExpression<Clause>(_ clause: Clause) -> Clause where Clause: XLDialectClause, Clause.Dialect == Dialect {
        clause
    }

    ///
    /// Constructs a With expression.
    ///
    public static func buildPartialBlock(first: With<Dialect>) -> XLWithStatement<Dialect> {
        XLWithStatement(_dialectSurface: first.commonTables)
    }

    ///
    /// Constructs an Insert expression using a With expression.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement<Dialect>, next: Insert<Row>) -> XLInsertTableStatement<Row, Dialect> {
        XLInsertTableStatement(components: XLInsertStatementComponents(commonTables: accumulated.commonTables, insert: next))
    }

    ///
    /// Constructs an Insert expression.
    ///
    public static func buildPartialBlock<Row>(first: Insert<Row>) -> XLInsertTableStatement<Row, Dialect> {
        XLInsertTableStatement(components: XLInsertStatementComponents(insert: first))
    }

    ///
    /// Constructs a Replace expression.
    ///
    public static func buildPartialBlock<Row>(first: Replace<Row>) -> XLInsertTableStatement<Row, Dialect> {
        XLInsertTableStatement(components: XLInsertStatementComponents(insert: first.insert))
    }

    ///
    /// Constructs a Replace expression using a With expression.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement<Dialect>, next: Replace<Row>) -> XLInsertTableStatement<Row, Dialect> {
        XLInsertTableStatement(components: XLInsertStatementComponents(commonTables: accumulated.commonTables, insert: next.insert))
    }


    // MARK: Insert
    
    ///
    /// Constructs an Insert statement with a Values clause.
    ///
    /// The Values clause specifies the values for columns which are inserted.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row, Dialect>, next: Values<Row>) -> XLInsertTableValuesStatement<Row, Dialect> {
        XLInsertTableValuesStatement(components: accumulated.components.appending(next.values))
    }

    ///
    /// Constructs an Insert statement with a Select clause.
    ///
    /// The Select clause specifies the rows which are to be inserted.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertTableStatement<Row, Dialect>, next: Select<Row, Dialect>) -> XLInsertSelectStatement<Row, Dialect> {
        XLInsertSelectStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Select
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectStatement<Row, Dialect>, next: From<Dialect>) -> XLInsertSelectTableStatement<Row, Dialect> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Join clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row, Dialect>, next: Join<Dialect>) -> XLInsertSelectTableStatement<Row, Dialect> {
        XLInsertSelectTableStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row, Dialect>, next: Where<Dialect>) -> XLInsertSelectWhereStatement<Row, Dialect> {
        XLInsertSelectWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row, Dialect>, next: GroupBy<Dialect>) -> XLInsertSelectGroupByStatement<Row, Dialect> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectTableStatement<Row, Dialect>, next: Limit<Dialect>) -> XLInsertSelectLimitStatement<Row, Dialect> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row, Dialect>, next: GroupBy<Dialect>) -> XLInsertSelectGroupByStatement<Row, Dialect> {
        XLInsertSelectGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Where clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectWhereStatement<Row, Dialect>, next: Limit<Dialect>) -> XLInsertSelectLimitStatement<Row, Dialect> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with a Having clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row, Dialect>, next: Having<Dialect>) -> XLInsertSelectHavingStatement<Row, Dialect> {
        XLInsertSelectHavingStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a GroupBy clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectGroupByStatement<Row, Dialect>, next: Limit<Dialect>) -> XLInsertSelectLimitStatement<Row, Dialect> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Having clause with an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLInsertSelectOrderByStatement<Row, Dialect> {
        XLInsertSelectOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Insert statement with a Select clause which includes a Having clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectHavingStatement<Row, Dialect>, next: Limit<Dialect>) -> XLInsertSelectLimitStatement<Row, Dialect> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    ///
    /// Constructs an Insert statement with a Select clause which includes an OrderBy clause with a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectOrderByStatement<Row, Dialect>, next: Limit<Dialect>) -> XLInsertSelectLimitStatement<Row, Dialect> {
        XLInsertSelectLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    ///
    /// Constructs an Insert statement with a Select clause which includes an Limit clause with an Offset clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLInsertSelectLimitStatement<Row, Dialect>, next: Offset<Dialect>) -> XLInsertSelectOffsetStatement<Row, Dialect> {
        XLInsertSelectOffsetStatement(components: accumulated.components.appending(next))
    }
}


///
/// Result builder used to construct a SQLite insert statement.
///
public typealias XLInsertExpressionBuilder = XLDialectInsertExpressionBuilder<XLSQLiteDialect>


///
/// Constructs a SQLite Insert statement.
///
public func sql(@XLInsertExpressionBuilder builder: (XLSQLiteSchema) -> any XLInsertStatement) -> any XLInsertStatement {
    let schema = XLSchema()
    return builder(schema)
}

///
/// Constructs an Insert statement in `dialect`.
///
/// The builder receives a schema of `dialect`, which accepts only models
/// declared for it (issue #789), and every clause of the body must belong to
/// `dialect` (issue #822).
///
public func sql<Dialect>(dialect: Dialect.Type, @XLDialectInsertExpressionBuilder<Dialect> builder: (XLSchema<Dialect>) -> any XLInsertStatement) -> any XLInsertStatement {
    let schema = XLSchema(dialect: dialect)
    return builder(schema)
}
