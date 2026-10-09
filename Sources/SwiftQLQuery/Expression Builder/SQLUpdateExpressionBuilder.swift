//
//  SQLUpdateExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to construct an Update statement in `Dialect`.
///
/// Every clause of the body must belong to `Dialect`: the table it updates,
/// a `From` table, and the `Where` condition (issue #822).
/// `XLUpdateExpressionBuilder` is the builder for SQLite.
///
@resultBuilder public struct XLDialectUpdateExpressionBuilder<Dialect> where Dialect: XLSQLDialect {

    ///
    /// Accepts a clause of the builder's dialect.
    ///
    public static func buildExpression<Clause>(_ clause: Clause) -> Clause where Clause: XLDialectClause, Clause.Dialect == Dialect {
        clause
    }
    
    ///
    /// Constructs an Update expression.
    ///
    public static func buildPartialBlock<Row>(first: Update<Row>) -> XLUpdateTableStatement<Row, Dialect> {
        XLUpdateTableStatement(components: XLUpdateStatementComponents(update: first))
    }
    
    ///
    /// Constructs an Update expression with a Setting clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateTableStatement<Row, Dialect>, next: Setting<Row>) -> XLUpdateSetStatement<Row, Dialect> {
        XLUpdateSetStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Update expression with a Setting clause that includes a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateSetStatement<Row, Dialect>, next: From<Dialect>) -> XLUpdateFromStatement<Row, Dialect> {
        XLUpdateFromStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Update expression with a Setting clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateSetStatement<Row, Dialect>, next: Where<Dialect>) -> XLUpdateWhereStatement<Row, Dialect> {
        XLUpdateWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Update expression with a From clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateFromStatement<Row, Dialect>, next: Where<Dialect>) -> XLUpdateWhereStatement<Row, Dialect> {
        XLUpdateWhereStatement(components: accumulated.components.appending(next))
    }
}


extension XLSchema {
    
    ///
    /// Constructs a select query for a From expression in an Update statement.
    ///
    public func fromExpression<T>(as alias: XLName? = nil, @XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaNamedResult where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let schema = XLSchema(parent: self)
        let dependency = XLUpdateFromTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

}


///
/// Constructs an Update statement in `dialect`.
///
/// The builder receives a schema of `dialect`, which accepts only models
/// declared for it (issue #789), and every clause of the body must belong to
/// `dialect` (issue #822).
///
public func sql<Dialect>(dialect: Dialect.Type, @XLDialectUpdateExpressionBuilder<Dialect> builder: (XLSchema<Dialect>) -> any XLUpdateStatement) -> any XLUpdateStatement {
    let schema = XLSchema(dialect: dialect)
    return builder(schema)
}
