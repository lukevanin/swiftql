//
//  SQLUpdateExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to construct an Update statement.
///
@resultBuilder public struct XLUpdateExpressionBuilder {
    
    ///
    /// Constructs an Update expression.
    ///
    public static func buildPartialBlock<Row>(first: Update<Row>) -> XLUpdateTableStatement<Row> {
        XLUpdateTableStatement(components: XLUpdateStatementComponents(update: first))
    }
    
    ///
    /// Constructs an Update expression with a Setting clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateTableStatement<Row>, next: Setting<Row>) -> XLUpdateSetStatement<Row> {
        XLUpdateSetStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs an Update expression with a Setting clause that includes a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateSetStatement<Row>, next: From) -> XLUpdateFromStatement<Row> {
        XLUpdateFromStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Update expression with a Setting clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateSetStatement<Row>, next: Where) -> XLUpdateWhereStatement<Row> {
        XLUpdateWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs an Update expression with a From clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLUpdateFromStatement<Row>, next: Where) -> XLUpdateWhereStatement<Row> {
        XLUpdateWhereStatement(components: accumulated.components.appending(next))
    }
}


extension XLSchema {
    
    ///
    /// Constructs a select query for a From expression in an Update statement.
    ///
    public func fromExpression<T>(as alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLUpdateFromTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

}


///
/// Constructs an Update statement.
///
public func sql(@XLUpdateExpressionBuilder builder: (XLSchema) -> any XLUpdateStatement) -> any XLUpdateStatement {
    let schema = XLSchema()
    return builder(schema)
}
