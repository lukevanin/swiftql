//
//  QueryBuilder+SQLite.swift
//
//  SQLite's spelling of the dynamic query builder. Split from
//  QueryBuilder.swift, whose builder is every dialect's (issue #790).
//

import Foundation


///
/// QueryBuilder constructs SQLite select statements when the structure of the
/// query is not known at compile time.
///
/// It takes only SQLite tables and expressions. See
/// `XLDialectQueryBuilder` for another dialect.
///
public typealias QueryBuilder<Row> = XLDialectQueryBuilder<Row, XLSQLiteDialect>
