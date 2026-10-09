//
//  SQLWriteStatements+SQLite.swift
//
//  SQLite's own write clauses: INSERT OR, REPLACE, and the SQLite spelling of
//  AS. Split from SQLWriteStatements.swift, whose clauses are every dialect's
//  (issue #790).
//

import Foundation


// MARK: - Insert


extension Insert {

    ///
    /// Creates an insert statement with an `OR` conflict-resolution clause.
    ///
    /// Renders `INSERT OR <action> INTO`. The algorithm applies to every
    /// uniqueness constraint violated while the statement runs.
    ///
    /// `INSERT OR` is SQLite's own, so the table must be a SQLite table
    /// (issue #789).
    ///
    public init<T>(_ meta: T, or action: XLInsertOrAction) where T: XLMetaNamedResult, T.Row == Row, T.XLModelDialect == XLSQLiteDialect {
        self.init(table: meta._dependency, target: .insertOr(action))
    }
}


///
/// Replace statement.
///
/// `REPLACE INTO` is the SQLite shorthand for `INSERT OR REPLACE INTO`. A row
/// that would violate a uniqueness constraint is deleted before the new row is
/// inserted. It is SQLite's own, so the table must be a SQLite table (issue
/// #789).
///
public struct Replace<Row>: XLEncodable, XLRowWritable {

    package let insert: Insert<Row>

    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row, T.XLModelDialect == XLSQLiteDialect {
        self.insert = Insert(table: meta._dependency, target: .replace)
    }

    public func makeSQL(context: inout XLBuilder) {
        insert.makeSQL(context: &context)
    }
}


extension Replace: XLDialectClause where Row: XLTable {
    public typealias Dialect = Row.XLModelDialect
}



// MARK: - As


extension As {

    ///
    /// Populates a SQLite table from a query.
    ///
    public init(@XLQueryExpressionBuilder builder: (XLSQLiteSchema) -> some XLDialectQueryStatement<Table, XLSQLiteDialect>) where Table: XLTable, Table.XLModelDialect == XLSQLiteDialect {
        let schema = XLSchema()
        self.init(queryStatement: builder(schema))
    }
}
