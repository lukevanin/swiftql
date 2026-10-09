//
//  SQLFunctionalSyntax+SQLite.swift
//
//  SQLite's functional syntax: the sqlQuery, sqlUpdate, sqlInsert and
//  sqlCreate statements, the SQLite schema, and the subqueries that open
//  their own SQLite scope. Split from SQLFunctionalSyntax.swift, whose
//  schema and statements are every dialect's (issue #790).
//

import Foundation


///
/// Returns a statement that selects rows matching the expression returned by the provided builder.
///
public func sqlQuery<Row>(builder: (XLSQLiteSchema) -> some XLDialectQueryStatement<Row, XLSQLiteDialect>) -> any XLDialectQueryStatement<Row, XLSQLiteDialect> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that updates a row using the expression returned by the provided builder.
///
public func sqlUpdate<Row, Statement>(builder: (XLSQLiteSchema) -> Statement) -> any XLUpdateStatement<Row> where Statement: XLUpdateStatement, Statement.Table == Row, Statement.Dialect == XLSQLiteDialect {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that inserts a row using the expression returned by the provided builder.
///
public func sqlInsert<Row, Statement>(builder: (XLSQLiteSchema) -> Statement) -> any XLInsertStatement<Row> where Statement: XLInsertStatement, Statement.Row == Row, Statement.Dialect == XLSQLiteDialect {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that inserts a row into an `SQLTable`.
///
public func sqlInsert<Row>(_ row: Row) -> XLInsertTableValuesStatement<Row, XLSQLiteDialect> where Row: XLTable, Row.XLModelDialect == XLSQLiteDialect, Row.MetaNamedResult.Row == Row, Row.MetaInsert.Row == Row {
    let schema = XLSchema()
    let table = schema.table(Row.self)
    return insert(table).values(Row.MetaInsert(row))
}


///
/// Returns a statement that creates a table using the expression returned by the provided builder.
///
public func sqlCreate<Row>(builder: (XLSQLiteSchema) -> some XLCreateStatement<Row>) -> any XLCreateStatement<Row> where Row: XLTable, Row.XLModelDialect == XLSQLiteDialect {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that creates a given `SQLTable`.
///
public func sqlCreate<T>(_ table: T.Type) -> any XLCreateStatement<T> where T: XLTable, T.XLModelDialect == XLSQLiteDialect, T.MetaCreate.Table == T {
    let schema = XLSchema()
    let table = schema.create(T.self)
    return create(table)
}


extension XLSchema where Dialect == XLSQLiteDialect {

    ///
    /// Creates a schema for a top-level SQLite statement.
    ///
    public init() {
        self.init(dialect: XLSQLiteDialect.self)
    }
}


///
/// The scope of a SQLite statement.
///
/// SQLite code that names the schema's type, such as a helper that takes one,
/// writes `XLSQLiteSchema` where v1 code wrote `XLSchema`.
///
public typealias XLSQLiteSchema = XLSchema<XLSQLiteDialect>


// MARK: Subquery

///
/// Constructs a subquery with a select query statement that returns a column set.
///
/// - Important: This function cannot see the enclosing schema, so it opens an
///   independent scope: an unnamed subquery is aliased `t0`, and its body's
///   aliases and bindings restart. Use `XLSchema.subquery(alias:_:)` to
///   derive them from the enclosing schema, or name the subquery explicitly.
///
public func subquery<T>(alias: XLName? = nil, _ statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.MetaNamedResult where T: XLResult, T.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNamedResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery whose columns can evaluate to NULL, for use on the
/// nullable side of a `LEFT JOIN`.
///
/// This is the subquery counterpart of `XLSchema.nullableTable(_:as:)`. The
/// inner statement is an ordinary one selecting `T`; nullability describes how
/// the *result* is joined, not what the subquery selects.
///
/// - Important: This function opens an independent scope, as the free
///   `subquery(alias:_:)` function does. Use `XLSchema.nullableSubquery(alias:_:)`
///   to derive the alias and the body's names from the enclosing schema.
///
public func nullableSubquery<T>(alias: XLName? = nil, _ statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.MetaNullableNamedResult where T: XLResult, T.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNullableNamedResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery with a select query statement that returns a column set that can evaluate to NULL.
///
/// - Warning: Unreachable through SwiftQL's own `select` functions, which only
///   produce a statement whose row type is the basis type rather than its
///   generated `Nullable` companion. Use ``nullableSubquery(alias:_:)``.
///
@available(*, deprecated, message: "Use nullableSubquery(alias:_:); this overload cannot be selected because no select function produces a statement over a Nullable row type.")
public func subquery<T>(alias: XLName? = nil, _ statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> T.Basis.MetaNullableNamedResult where T: XLMetaNullable, T.Basis: XLResult, T.Basis.XLModelDialect == XLSQLiteDialect {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.Basis.makeSQLAnonymousNullableNamedResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery with a select query statement that returns a scalar value that can evaluate
/// to NULL.
///
/// - Important: The schema passed to `statement` starts an independent scope.
///   Use the schema method `XLSchema.subquery(_:)`, or the form whose closure
///   takes no schema, to use names from the enclosing schema.
///
public func subquery<T>(_ statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLDialectExpression<Optional<T>, XLSQLiteDialect>(XLSubquery<T>(statement: statement(schema)))
}


///
/// Constructs a subquery with a select query statement that returns a scalar value.
///
public func subquery<T>(_ statement: () -> any XLDialectQueryStatement<T, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<T>> where T: XLLiteral {
    return XLDialectExpression<Optional<T>, XLSQLiteDialect>(XLSubquery<T>(statement: statement()))
}


///
/// Constructs a scalar subquery whose inner statement is already nullable.
///
/// A scalar subquery is always nullable, because it yields NULL when it selects
/// no row. When the inner statement is itself optional — an aggregate such as
/// `sumOrNull()`, or a nullable column — the two sources of NULL collapse into
/// one rather than nesting into `Optional<Optional<Wrapped>>`.
///
/// - Important: The schema passed to `statement` starts an independent scope.
///   Use the schema method `XLSchema.subquery(_:)`, or the form whose closure
///   takes no schema, to use names from the enclosing schema.
///
public func subquery<Wrapped>(_ statement: (XLSQLiteSchema) -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    let schema = XLSchema()
    return XLDialectExpression<Optional<Wrapped>, XLSQLiteDialect>(XLSubquery<Wrapped>(statement: statement(schema)))
}


public func subquery<Wrapped>(_ statement: () -> any XLDialectQueryStatement<Optional<Wrapped>, XLSQLiteDialect>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    XLDialectExpression<Optional<Wrapped>, XLSQLiteDialect>(XLSubquery<Wrapped>(statement: statement()))
}
