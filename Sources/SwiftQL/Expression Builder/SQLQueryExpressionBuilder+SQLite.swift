//
//  SQLQueryExpressionBuilder+SQLite.swift
//
//  SQLite's spelling of the query expression builder, its sql { } statement,
//  and the subqueries that open their own SQLite scope. Split from
//  SQLQueryExpressionBuilder.swift, whose builder is every dialect's
//  (issue #790).
//

import Foundation


///
/// Result builder used to construct a SQLite select query.
///
/// Every clause of the body must be a SQLite clause: a table of a model
/// declared for SQLite, and SQLite's expressions (issue #822). A helper that
/// builds a SQLite query with this builder keeps compiling unchanged.
///
public typealias XLQueryExpressionBuilder = XLDialectQueryExpressionBuilder<XLSQLiteDialect>


// MARK: - Subquery

///
/// Constructs a subquery.
///
/// - Important: This function cannot see the enclosing schema, so it opens an
///   independent scope. Use ``XLSchema/subqueryExpression(alias:statement:)``
///   to derive the alias and the body's names from the enclosing schema.
///
public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.MetaResult where T: XLTable, T.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency)
}

///
/// Constructs a subquery that returns a nullable table.
///
/// - Important: This function opens an independent scope. Give the subquery
///   an explicit alias when it is joined to another source.
///
public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.Basis.MetaNullableResult where T: XLMetaNullable, T.Basis: XLTable, T.Basis.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.Basis.makeSQLAnonymousNullableResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery that returns an optional scalar value.
///
/// - Important: The schema passed to `statement` starts an independent scope.
///   Use the schema method `XLSchema.subqueryExpression(statement:)`, or the
///   form whose closure takes no schema, to use names from the enclosing
///   schema.
///
public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLDialectExpression<Optional<T>, XLSQLiteDialect>(XLSubquery<T>(statement: statement(schema)))
}


///
/// Constructs a subquery that returns a scalar value.
///
public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: () -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    return XLDialectExpression<Optional<T>, XLSQLiteDialect>(XLSubquery<T>(statement: statement()))
}


///
/// Constructs a scalar subquery whose inner statement is already nullable, so
/// the subquery's own nullability does not nest a second `Optional`.
///
/// - Important: The schema passed to `statement` starts an independent scope,
///   as for the non-optional scalar form.
///
public func subqueryExpression<Wrapped>(@XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    let schema = XLSchema()
    return XLDialectExpression<Optional<Wrapped>, XLSQLiteDialect>(XLSubquery<Wrapped>(statement: statement(schema)))
}


public func subqueryExpression<Wrapped>(@XLQueryExpressionBuilder statement: () -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    XLDialectExpression<Optional<Wrapped>, XLSQLiteDialect>(XLSubquery<Wrapped>(statement: statement()))
}


///
/// Constructs a subquery whose columns can evaluate to NULL, for use on the
/// nullable side of a `LEFT JOIN`.
///
/// - Important: This function opens an independent scope. Use the schema
///   method `XLSchema.nullableSubqueryExpression(alias:statement:)` to take the
///   alias and the body's names from the enclosing schema.
///
public func nullableSubqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.MetaNullableNamedResult where T: XLResult, T.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNullableNamedResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a SQLite select query statement.
///
/// The builder receives a SQLite schema, which accepts only models declared
/// for SQLite: a model declared with `@SQLTable` and no `dialect:` argument.
/// Every clause of the body is a SQLite clause (issue #822). The statement is
/// an `any XLQueryStatement<Row>` too, so it can be stored and run as one.
///
public func sql<Row>(@XLQueryExpressionBuilder builder: (XLSQLiteSchema) -> any XLDialectQueryStatement<Row, XLSQLiteDialect>) -> any XLDialectQueryStatement<Row, XLSQLiteDialect> {
    let schema = XLSchema()
    return builder(schema)
}


// MARK: - SQL as subquery

#if compiler(>=6.1)
// `sql { ... }` also works as a subquery, inferring which shape from the
// context expecting its result — a table row, a nullable table row, or a
// scalar value — mirroring `subqueryExpression`'s overload set under the same
// name, so a caller need not remember which name applies where.
//
// ## Why this needs Swift 6.1
//
// These overloads shipped once, in pull request #416, and were reverted in
// #408. Compiled together with the rest of the package, they crash
// swift-frontend on the pinned Swift 5.9.2 toolchain and on the pinned Swift
// 6.0 cell. The crash was bisected to these declarations: removing them alone
// removes it. `sql` is called at nearly every call site in the package, so
// disfavouring six more overloads under that name is enough
// overload-resolution load to trip a compiler bug of that generation.
//
// Swift 6.1 (Xcode 16.4) fixes it. The gate is therefore the compiler, not
// the feature: on 6.1 and later these overloads exist and are exercised; on
// 5.9 and 6.0 they are not compiled at all, so the crash cannot occur and
// every other spelling keeps working. `#row`'s multi-column shapes are gated
// the same way, for the same class of bug — see COMPATIBILITY.md.
//
// A caller on 5.9 or 6.0 writes `subqueryExpression { ... }`, which is what
// every SwiftQL version so far has required and what these overloads forward
// to unchanged.
//
// ## Why `@_disfavoredOverload` is required, not cosmetic
//
// Every shape below structurally overlaps a common top-level `sql { ... }`
// statement: a plain `Select(person); From(person)` already returns
// `any XLQueryStatement<Row>` where `Row: XLTable`, which is exactly the
// table-subquery shape. Without the attribute, existing top-level call sites
// with no surrounding contextual type become ambiguous and fail to compile.
// Disfavouring these makes the plain top-level statement win that tie, while
// still letting a caller reach one of these shapes when the surrounding
// expression — `From(sql { ... })`, a scalar comparison — uniquely requires
// it.
//
// ## Scope
//
// These overloads forward to the free `subqueryExpression` functions, so the
// schema passed to a closure starts an independent scope (issue #644). Use the
// `XLSchema` subquery methods to take names from the enclosing schema.

@_disfavoredOverload
public func sql<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.MetaResult where T: XLTable, T.XLModelDialect == XLSQLiteDialect {
    subqueryExpression(alias: alias, statement: statement)
}

@_disfavoredOverload
public func sql<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.Basis.MetaNullableResult where T: XLMetaNullable, T.Basis: XLTable, T.Basis.XLModelDialect == XLSQLiteDialect {
    subqueryExpression(alias: alias, statement: statement)
}

@_disfavoredOverload
public func sql<T>(@XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<T>(@XLQueryExpressionBuilder statement: () -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<Wrapped>(@XLQueryExpressionBuilder statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<Wrapped>(@XLQueryExpressionBuilder statement: () -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    subqueryExpression(statement: statement)
}
#endif
