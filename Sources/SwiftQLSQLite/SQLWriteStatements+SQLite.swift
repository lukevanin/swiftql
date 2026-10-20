//
//  SQLWriteStatements+SQLite.swift
//
//  SQLite's own write clauses: INSERT OR, REPLACE, and the SQLite spelling of
//  AS. Split from SQLWriteStatements.swift, whose clauses are every dialect's
//  (issue #790).
//

import Foundation


// MARK: - Insert


///
/// A conflict-resolution algorithm applied by an `INSERT OR ...` statement.
///
/// SQLite parses the algorithm as part of the `INSERT` keyword, immediately
/// before `INTO`. `replace` is the same algorithm reached by the standalone
/// `REPLACE` statement.
///
/// The algorithm is SQLite's own. PostgreSQL has no equivalent opening: it
/// resolves a conflict with a trailing `ON CONFLICT` clause, so the
/// algorithm lives in this product and not in the shared vocabulary (issue
/// #791).
///
public enum XLInsertOrAction: String, CaseIterable, Hashable, Sendable {
    case rollback = "ROLLBACK"
    case abort = "ABORT"
    case fail = "FAIL"
    case ignore = "IGNORE"
    case replace = "REPLACE"
}


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
        self.init(table: meta._dependency, opening: "INSERT OR \(action.rawValue) INTO")
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

    let insert: Insert<Row>

    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row, T.XLModelDialect == XLSQLiteDialect {
        self.insert = Insert(table: meta._dependency, opening: "REPLACE INTO")
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
