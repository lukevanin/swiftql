//
//  Join+Factories.swift
//  SwiftQL
//
//  One factory per join shape SQLite supports.
//
//  Split out of SQLStatements.swift (issue #559): eleven of these sat inside
//  `Join` itself, between its stored properties and its rendering, so neither
//  was readable without scrolling past the other. What each factory does is
//  pick a keyword and a nullability -- the joining itself is `Join`'s.
//

import Foundation


extension Join {

    public static func Cross<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .crossJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join.
    ///
    public static func Inner<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .innerJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join with a column constraint.
    ///
    public static func Inner<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates an inner join whose constraint is a `USING (columns...)` clause.
    ///
    /// A `USING` join matches rows where the named columns — which must exist in
    /// both tables — are equal, and SQLite coalesces each named column into a
    /// single output column.
    ///
    public static func Inner<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> Join where T: XLMetaNamedResult {
        Join(kind: .innerJoin, table: table, using: [firstColumn] + otherColumns)
    }

    ///
    /// Creates a left join with a column constraint.
    ///
    public static func Left<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNullableNamedResult, U: XLBoolean {
        Join(kind: .leftJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates a right join with a column constraint.
    ///
    /// A `RIGHT JOIN` keeps every row of the joined (right-hand) `table` and
    /// fills the columns of the `FROM` (left-hand) table with `NULL` when there
    /// is no match. The joined table therefore stays non-nullable, while the
    /// `FROM` table must be declared with `nullableTable(_:as:)`
    /// so its columns decode as optionals.
    ///
    /// > Important: `RIGHT JOIN` requires SQLite 3.39.0 (2022-06-25) or later.
    ///
    public static func Right<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        Join(kind: .rightJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates a left join whose constraint is a `USING (columns...)` clause.
    ///
    public static func Left<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> Join where T: XLMetaNullableNamedResult {
        Join(kind: .leftJoin, table: table, using: [firstColumn] + otherColumns)
    }

    ///
    /// Creates a natural (inner) join.
    ///
    /// A `NATURAL JOIN` implicitly matches every column the two tables share by
    /// name and takes no `ON` or `USING` constraint. If the tables share no
    /// column names it degenerates to a cross join.
    ///
    public static func Natural<T>(_ table: T) -> Join where T: XLMetaNamedResult {
        Join(kind: .naturalJoin, table: table, constraint: nil)
    }

    ///
    /// Creates a natural left join, whose joined table can resolve to `NULL`.
    ///
    public static func NaturalLeft<T>(_ table: T) -> Join where T: XLMetaNullableNamedResult {
        Join(kind: .naturalLeftJoin, table: table, constraint: nil)
    }

    ///
    /// Creates a full outer join with a column constraint.
    ///
    /// A `FULL OUTER JOIN` keeps every row of both tables, filling the other
    /// table's columns with `NULL` where there is no match. Both sides must
    /// therefore decode as optionals: the joined table is nullable
    /// (`XLMetaNullableNamedResult`) and the `FROM` table must be declared with
    /// `nullableTable(_:as:)`.
    ///
    /// > Important: `FULL OUTER JOIN` requires SQLite 3.39.0 (2022-06-25) or later.
    ///
    public static func FullOuter<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNullableNamedResult, U: XLBoolean {
        Join(kind: .fullOuterJoin, table: table, constraint: constraint)
    }

    ///
    /// `Join.Outer` emitted a bare `OUTER JOIN`, which SQLite rejects ("unknown join type: OUTER"),
    /// so no query using it could ever execute. Use ``Left(_:on:)`` with a nullable table instead.
    ///
    @available(*, unavailable, message: "Join.Outer emitted a bare 'OUTER JOIN', which SQLite rejects, so it could never execute. Use Join.Left with a nullable table instead.")
    public static func Outer<T, U>(_ table: T, on constraint: any XLExpression<U>) -> Join where T: XLMetaNamedResult, U: XLBoolean {
        fatalError("Join.Outer is unavailable")
    }
}
