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
//  The factories that take an `ON` constraint take an expression of the
//  join's dialect, so each dialect's surface declares them, from
//  scripts/dialect-surface/Templates/Clauses.swift.template (issue #822).
//

import Foundation


extension Join {

    public static func Cross<T>(_ table: T) -> Join where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .crossJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join.
    ///
    public static func Inner<T>(_ table: T) -> Join where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .innerJoin, table: table, constraint: nil)
    }

    ///
    /// Creates an inner join whose constraint is a `USING (columns...)` clause.
    ///
    /// A `USING` join matches rows where the named columns — which must exist in
    /// both tables — are equal, and SQLite coalesces each named column into a
    /// single output column.
    ///
    public static func Inner<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> Join where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .innerJoin, table: table, using: [firstColumn] + otherColumns)
    }

    ///
    /// Creates a left join whose constraint is a `USING (columns...)` clause.
    ///
    public static func Left<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> Join where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .leftJoin, table: table, using: [firstColumn] + otherColumns)
    }

    ///
    /// Creates a natural (inner) join.
    ///
    /// A `NATURAL JOIN` implicitly matches every column the two tables share by
    /// name and takes no `ON` or `USING` constraint. If the tables share no
    /// column names it degenerates to a cross join.
    ///
    public static func Natural<T>(_ table: T) -> Join where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .naturalJoin, table: table, constraint: nil)
    }

    ///
    /// Creates a natural left join, whose joined table can resolve to `NULL`.
    ///
    public static func NaturalLeft<T>(_ table: T) -> Join where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        Join(kind: .naturalLeftJoin, table: table, constraint: nil)
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
