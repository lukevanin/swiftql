//
//  SQLCreateExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation


///
/// Result builder used to construct a create statement..
///
@resultBuilder public struct XLCreateExpressionBuilder<Table> {
    
    ///
    /// Constructs an initial Create expression.
    ///
    public static func buildPartialBlock(first: Create<Table>) -> XLCreateTableStatement<Table> {
        XLCreateTableStatement(components: XLCreateTableStatementComponents(create: first))
    }
    
    ///
    /// Constructs a Create statement with an As clause.
    ///
    /// An As clause is used to specify a select query which is used to populate the contents of the newly
    /// created table.
    ///
    public static func buildPartialBlock(accumulated: XLCreateTableStatement<Table>, next: As<Table>) -> XLCreateTableAsStatement<Table> where Table: XLTable, Table.MetaCreateAs.Table == Table {
        let meta = Table.makeSQLCreateAs()
        let components = XLCreateTableStatementComponents(create: Create(meta), components: [next.queryStatement])
        return XLCreateTableAsStatement(components: components)
    }
}


///
/// Constructs a Create expression in `dialect`.
///
/// The builder receives a schema of `dialect`, which accepts only models
/// declared for it (issue #789), and the table must be declared for
/// `dialect` (issue #822).
///
public func sql<Table, Dialect>(dialect: Dialect.Type, @XLCreateExpressionBuilder<Table> builder: (XLSchema<Dialect>) -> any XLCreateStatement<Table>) -> any XLCreateStatement<Table> where Table: XLTable, Table.XLModelDialect == Dialect {
    let schema = XLSchema(dialect: dialect)
    return builder(schema)
}
