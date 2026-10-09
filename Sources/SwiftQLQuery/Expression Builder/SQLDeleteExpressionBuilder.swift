//
//  SQLDeleteExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/30.
//

import Foundation


///
/// Result builder used to construct a delete statement in `Dialect`.
///
/// Every clause of the body must belong to `Dialect`: the table it deletes
/// from, its common tables, and the `Where` condition (issue #822).
/// `XLDeleteExpressionBuilder` is the builder for SQLite.
///
@resultBuilder public struct XLDialectDeleteExpressionBuilder<Dialect> where Dialect: XLSQLDialect {

    ///
    /// Accepts a clause of the builder's dialect.
    ///
    public static func buildExpression<Clause>(_ clause: Clause) -> Clause where Clause: XLDialectClause, Clause.Dialect == Dialect {
        clause
    }
    
    ///
    /// Constructs a With expression.
    ///
    /// The With expression is a precursor to the delete statement and specifies any common table
    /// expressions which are used in the delete statement.
    ///
    public static func buildPartialBlock(first: With<Dialect>) -> XLWithStatement<Dialect> {
        XLWithStatement(_dialectSurface: first.commonTables)
    }

    ///
    /// Constructs a Delete expression.
    ///
    public static func buildPartialBlock<Table>(first: Delete<Table>) -> XLDeleteTableStatement<Table, Dialect> {
        XLDeleteTableStatement(components: XLDeleteStatementComponents(delete: first))
    }
    
    ///
    /// Constructs a Delete expression using a With clause.
    ///
    public static func buildPartialBlock<Table>(accumulated: XLWithStatement<Dialect>, next: Delete<Table>) -> XLDeleteTableStatement<Table, Dialect> {
        XLDeleteTableStatement(components: XLDeleteStatementComponents(commonTables: accumulated.commonTables, delete: next))
    }

    ///
    /// Constructs a Delete expression with a Where clause.
    ///
    public static func buildPartialBlock<Table>(accumulated: XLDeleteTableStatement<Table, Dialect>, next: Where<Dialect>) -> XLDeleteWhereStatement<Table, Dialect> {
        XLDeleteWhereStatement(components: accumulated.components.appending(next))
    }
}


///
/// Constructs a delete expression in `dialect`.
///
/// The builder receives a schema of `dialect`, which accepts only models
/// declared for it (issue #789), and every clause of the body must belong to
/// `dialect` (issue #822).
///
public func sql<Dialect>(dialect: Dialect.Type, @XLDialectDeleteExpressionBuilder<Dialect> builder: (XLSchema<Dialect>) -> any XLDeleteStatement) -> any XLDeleteStatement {
    let schema = XLSchema(dialect: dialect)
    return builder(schema)
}
