//
//  CompileFailSecondDialectClauses.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/Clauses.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQL


// MARK: - Select


extension Select where Dialect == CompileFailSecondDialect {

    /// Builds a scalar select without requiring the logical result type to
    /// adopt the legacy expression and literal protocols.
    ///
    /// Bare contextual values can be rendered by this initializer, but their
    /// row decoding still requires an `XLStaticRowLayout` carrying codec
    /// metadata. The legacy path reports
    /// `XLStaticRowReadError.staticLayoutRequired(valueType:alias:)`
    /// instead of fabricating a value.
    @_disfavoredOverload
    init(
        @XLScalarExpressionBuilder _ expression: @escaping () -> some CompileFailSecondDialectExpression<Row>
    ) {
        self.init(_dialectSurfaceBuilder: { expression() })
    }

    /// Builds an unconstrained scalar select.
    ///
    /// Bare contextual values still require an `XLStaticRowLayout` to carry
    /// the codec metadata needed during row decoding.
    @_disfavoredOverload
    init(_ expression: any CompileFailSecondDialectExpression<Row>) {
        self.init(_dialectSurface: expression)
    }
}


// MARK: - Join


extension Join where Dialect == CompileFailSecondDialect {

    ///
    /// `Join` is a synonym for `Join.Inner`.
    ///
    @_disfavoredOverload
    init<T, U>(_ table: T, on constraint: any CompileFailSecondDialectExpression<U>) where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        self.init(_dialectSurfaceKind: .innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates an inner join with a column constraint.
    ///
    @_disfavoredOverload
    static func Inner<T, U>(_ table: T, on constraint: any CompileFailSecondDialectExpression<U>) -> Join where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        Join(_dialectSurfaceKind: .innerJoin, table: table, constraint: constraint)
    }

    ///
    /// Creates a left join with a column constraint.
    ///
    @_disfavoredOverload
    static func Left<T, U>(_ table: T, on constraint: any CompileFailSecondDialectExpression<U>) -> Join where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        Join(_dialectSurfaceKind: .leftJoin, table: table, constraint: constraint)
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
    @_disfavoredOverload
    static func Right<T, U>(_ table: T, on constraint: any CompileFailSecondDialectExpression<U>) -> Join where T: XLMetaNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        Join(_dialectSurfaceKind: .rightJoin, table: table, constraint: constraint)
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
    @_disfavoredOverload
    static func FullOuter<T, U>(_ table: T, on constraint: any CompileFailSecondDialectExpression<U>) -> Join where T: XLMetaNullableNamedResult, T.XLModelDialect == CompileFailSecondDialect, U: XLBoolean {
        Join(_dialectSurfaceKind: .fullOuterJoin, table: table, constraint: constraint)
    }
}


// MARK: - Where


extension Where where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(_ condition: any CompileFailSecondDialectExpression<Bool>) {
        self.init(_dialectSurface: condition)
    }

    @_disfavoredOverload
    init(_ condition: any CompileFailSecondDialectExpression<Optional<Bool>>) {
        self.init(_dialectSurface: condition)
    }
}


// MARK: - Order


extension Ascending where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(@XLScalarExpressionBuilder expression: () -> any CompileFailSecondDialectExpression) {
        self.init(_dialectSurface: expression())
    }

    @_disfavoredOverload
    init(expression: any CompileFailSecondDialectExpression) {
        self.init(_dialectSurface: expression)
    }
}


extension Descending where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(@XLScalarExpressionBuilder expression: () -> any CompileFailSecondDialectExpression) {
        self.init(_dialectSurface: expression())
    }

    @_disfavoredOverload
    init(expression: any CompileFailSecondDialectExpression) {
        self.init(_dialectSurface: expression)
    }
}


extension CompileFailSecondDialectExpression {

    @_disfavoredOverload
    func ascending() -> some XLOrderingTerm<CompileFailSecondDialect> {
        Ascending<CompileFailSecondDialect>(_dialectSurface: self)
    }

    @_disfavoredOverload
    func descending() -> some XLOrderingTerm<CompileFailSecondDialect> {
        Descending<CompileFailSecondDialect>(_dialectSurface: self)
    }
}


// MARK: - Limit


extension Limit where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(_ count: any CompileFailSecondDialectExpression<Int>) {
        self.init(_dialectSurface: count)
    }

    @_disfavoredOverload
    init(@XLScalarExpressionBuilder _ count: () -> any CompileFailSecondDialectExpression<Int>) {
        self.init(_dialectSurface: count())
    }
}


// MARK: - Offset


extension Offset where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(_ count: any CompileFailSecondDialectExpression<Int>) {
        self.init(_dialectSurface: count)
    }

    @_disfavoredOverload
    init(@XLScalarExpressionBuilder _ count: () -> any CompileFailSecondDialectExpression<Int>) {
        self.init(_dialectSurface: count())
    }
}


// MARK: - Group By


extension GroupBy where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(_ columns: any CompileFailSecondDialectExpression...) {
        self.init(_dialectSurface: columns)
    }

    @_disfavoredOverload
    init(_ columns: [any CompileFailSecondDialectExpression]) {
        self.init(_dialectSurface: columns)
    }
}


// MARK: - Having


extension Having where Dialect == CompileFailSecondDialect {

    @_disfavoredOverload
    init(_ condition: any CompileFailSecondDialectExpression<Bool>) {
        self.init(_dialectSurface: condition)
    }

    @_disfavoredOverload
    init(_ condition: any CompileFailSecondDialectExpression<Optional<Bool>>) {
        self.init(_dialectSurface: condition)
    }
}


// MARK: - On Conflict


extension OnConflict where Row: XLTable, Row.XLModelDialect == CompileFailSecondDialect {

    ///
    /// Creates an `ON CONFLICT (targets) DO UPDATE SET ... WHERE ...` clause.
    ///
    /// At least one conflict target is required, because SQLite rejects
    /// `DO UPDATE` without a conflict target. The `WHERE` predicate constrains
    /// which conflicting rows are updated; rows that fail the predicate are
    /// left unchanged without raising an error.
    ///
    @_disfavoredOverload
    static func doUpdate<B>(
        on firstTarget: XLName,
        _ otherTargets: XLName...,
        set values: @escaping (inout Row.MetaUpdate) -> Void,
        where filter: any CompileFailSecondDialectExpression<B>
    ) -> OnConflict where B: XLBoolean {
        _dialectSurfaceDoUpdate(on: [firstTarget] + otherTargets, set: values, where: filter)
    }
}
