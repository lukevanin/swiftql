//
//  SQLInsertExpressionBuilder+SQLite.swift
//
//  SQLite's spelling of the insert expression builder and its sql { }
//  statement. Split from SQLInsertExpressionBuilder.swift, whose builder
//  is every dialect's (issue #790).
//

import Foundation


// `REPLACE` is SQLite's own, so the builder's `Replace` clauses are declared
// here, with `Replace` (issue #790).
extension XLDialectInsertExpressionBuilder {

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
