//
//  SQLDeleteExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/30.
//

import Foundation


///
/// Result builder used to construct a delete statement.
///
@resultBuilder public struct XLDeleteExpressionBuilder {
    
    ///
    /// Constructs a With expression.
    ///
    /// The With expression is a precursor to the delete statement and specifies any common table
    /// expressions which are used in the delete statement.
    ///
    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    ///
    /// Constructs a Delete expression.
    ///
    public static func buildPartialBlock<Table>(first: Delete<Table>) -> XLDeleteTableStatement<Table>{
        XLDeleteTableStatement(components: XLDeleteStatementComponents(delete: first))
    }
    
    ///
    /// Constructs a Delete expression using a With clause.
    ///
    public static func buildPartialBlock<Table>(accumulated: XLWithStatement, next: Delete<Table>) -> XLDeleteTableStatement<Table> {
        XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: accumulated.commonTables, delete: next))
    }

    ///
    /// Constructs a Delete expression with a Where clause.
    ///
    public static func buildPartialBlock<Table>(accumulated: XLDeleteTableStatement<Table>, next: Where) -> XLDeleteWhereStatement<Table> {
        XLDeleteWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Appends a `RETURNING` clause to any delete statement.
    ///
    public static func buildPartialBlock<S, T>(accumulated: S, next: Returning<T>) -> XLReturningStatementOf<T> where S: XLDeleteStatement {
        XLReturningStatementOf(base: accumulated, returning: next)
    }
}


///
/// Constructs a delete statement with a `RETURNING` clause.
///
public func sqlDeleteReturning<Row>(@XLDeleteExpressionBuilder builder: (XLSchema) -> XLReturningStatementOf<Row>) -> XLReturningStatementOf<Row> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Constructs a delete expression.
///
public func sql(@XLDeleteExpressionBuilder builder: (XLSchema) -> any XLDeleteStatement) -> any XLDeleteStatement {
    let schema = XLSchema()
    return builder(schema)
}
