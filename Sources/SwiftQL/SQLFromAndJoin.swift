//
//  SQLFromAndJoin.swift
//  SwiftQL
//
//  Where rows come from: the FROM clause and the JOIN that extends it.
//
//  Split out of SQLStatements.swift (issue #559). The eleven join factories --
//  one per join shape SQLite supports -- are in Join+Factories.swift beside it.
//

import Foundation


// MARK: - From


///
/// From clause.
///
/// Specifies the table to use in a select clause.
///
public struct From: XLTableStatement {
    
    let table: XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaResult {
        self.table = meta
    }

    public init<T>(_ meta: T) where T: XLMetaNamedResult {
        self.table = meta
    }

    ///
    /// Specifies a `FROM` table whose columns can resolve to `NULL`.
    ///
    /// Used for the left-hand table of a `RIGHT JOIN` (and either table of a
    /// `FULL OUTER JOIN`), where unmatched rows fill the `FROM` table's columns
    /// with `NULL`. Build the nullable table reference with `nullableTable(_:as:)`.
    ///
    public init<T>(_ meta: T) where T: XLMetaNullableNamedResult {
        self.table = meta
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("FROM", expression: table.makeSQL)
    }
}


// MARK: Join


///
/// Join clause.
///
/// Joins a table in a select statement.
///
/// Inner and left joins combine tables using an `ON` predicate. A cross join
/// returns every combination of rows from its two tables; SQLite also preserves
/// the left-to-right loop order for an explicit `CROSS JOIN`.
///
/// A right join (``Right(_:on:)``) keeps every row of the joined table and fills
/// the `FROM` table's columns with `NULL` when there is no match; declare that
/// `FROM` table with `nullableTable(_:as:)` so its columns
/// decode as optionals. `RIGHT JOIN` requires SQLite 3.39.0 or later.
///
public struct Join: XLTableStatement {
    
    public enum Kind: String, CaseIterable {
        case innerJoin = "INNER JOIN"
        case leftJoin = "LEFT JOIN"
        case rightJoin = "RIGHT JOIN"
        case fullOuterJoin = "FULL OUTER JOIN"
        case crossJoin = "CROSS JOIN"
        case naturalJoin = "NATURAL JOIN"
        case naturalLeftJoin = "NATURAL LEFT JOIN"
    }

    private let kind: Kind

    private let table: XLEncodable

    private let constraint: (any XLExpression)?

    /// Column names shared by both tables for a `USING (...)` join constraint.
    /// Mutually exclusive with `constraint`; `NATURAL` joins use neither.
    private let using: [XLName]?

    ///
    /// `Join` is a synonym for `Join.Inner`.
    ///
    public init<T, U>(_ table: T, on constraint: any XLExpression<U>) where T: XLMetaNamedResult, U: XLBoolean {
        self.init(kind: .innerJoin, table: table, constraint: constraint)
    }

    internal init(kind: Kind, table: XLEncodable, constraint: (any XLExpression)?) {
        self.kind = kind
        self.table = table
        self.constraint = constraint
        self.using = nil
    }

    internal init(kind: Kind, table: XLEncodable, using: [XLName]) {
        self.kind = kind
        self.table = table
        self.constraint = nil
        self.using = using
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix(kind.rawValue, expression: table.makeSQL)
        // NATURAL and CROSS joins never take an ON/USING constraint, even if one
        // were supplied through the internal initializer.
        switch kind {
        case .naturalJoin, .naturalLeftJoin, .crossJoin:
            return
        case .innerJoin, .leftJoin, .rightJoin, .fullOuterJoin:
            break
        }
        if let constraint {
            context.unaryPrefix("ON", expression: constraint.makeSQL)
        } else if let using {
            context.unaryPrefix("USING", expression: { context in
                context.parenthesis { context in
                    context.list(separator: .list) { list in
                        for column in using {
                            list.listItem { $0.name(column) }
                        }
                    }
                }
            })
        }
    }
    
    ///
    /// Creates a cross join.
    ///
}
