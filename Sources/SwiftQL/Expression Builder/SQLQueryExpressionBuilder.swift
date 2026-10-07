//
//  SQLQueryExpressionBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/28.
//

import Foundation


// MARK: - Expression builder


///
/// Expression builder used by scalar SELECT statement. ie. Where a SELECT statement returns the result
/// of a single expression.
///
@resultBuilder public struct XLScalarExpressionBuilder {

    /// Returns the expression with its own type, so that a closure that
    /// returns a dialect's expression protocol keeps the expression's dialect
    /// (issue #822).
    public static func buildBlock<Expression>(_ component: Expression) -> Expression where Expression: XLExpression {
        component
    }
}


///
/// Result builder used to construct a select query in `Dialect`.
///
/// Every clause of the body must belong to `Dialect`: a `From` or a join of
/// another dialect's table, or a `Where` over another dialect's columns, is a
/// compile error at the clause, which names both dialects (issue #822). The
/// builder is also the context in which each clause's initializer is chosen,
/// so a clause built from values alone, such as `Where(true)` or `Limit(10)`,
/// takes `Dialect`.
///
/// ``XLQueryExpressionBuilder`` is the builder for SQLite.
///
@resultBuilder public struct XLDialectQueryExpressionBuilder<Dialect> where Dialect: XLSQLDialect {

    ///
    /// Accepts a clause of the builder's dialect.
    ///
    public static func buildExpression<Clause>(_ clause: Clause) -> Clause where Clause: XLDialectClause, Clause.Dialect == Dialect {
        clause
    }

    ///
    /// Constructs a With expression.
    ///
    public static func buildPartialBlock(first: With<Dialect>) -> XLWithStatement<Dialect> {
        XLWithStatement(_dialectSurface: first.commonTables)
    }

    ///
    /// Constructs a Select expression.
    ///
    public static func buildPartialBlock<Row>(first: Select<Row, Dialect>) -> XLQuerySelectStatement<Row, Dialect> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(select: first))
    }


    // MARK: With

    ///
    /// Constructs a Select expression with a With clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement<Dialect>, next: Select<Row, Dialect>) -> XLQuerySelectStatement<Row, Dialect> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: accumulated.commonTables, select: next))
    }

    
    // MARK: Union
    
    ///
    /// Constructs a Union expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Union<Dialect>) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement, Statement.Dialect == Dialect {
        return XLQueryPartialUnion(kind: .union, query: accumulated)
    }
    
    ///
    /// Constructs a UnionAll expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: UnionAll<Dialect>) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement, Statement.Dialect == Dialect {
        return XLQueryPartialUnion(kind: .unionAll, query: accumulated)
    }
    
    ///
    /// Constructs an Intersect expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Intersect<Dialect>) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement, Statement.Dialect == Dialect {
        return XLQueryPartialUnion(kind: .intersect, query: accumulated)
    }
    
    ///
    /// Constructs an Except expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Except<Dialect>) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement, Statement.Dialect == Dialect {
        return XLQueryPartialUnion(kind: .except, query: accumulated)
    }

    ///
    /// Constructs a Select expression with a partial union.
    ///
    public static func buildPartialBlock<Statement>(accumulated: XLQueryPartialUnion<Statement>, next: Select<Statement.Row, Dialect>) -> XLQuerySelectStatement<Statement.Row, Dialect> where Statement: XLSimpleSelectQueryStatement, Statement.Dialect == Dialect {
        let union = BooleanClause(kind: accumulated.kind, lhs: accumulated.query.components, rhs: next)
        return XLQuerySelectStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    
    // MARK: Select
    
    ///
    /// Constructs a Select expression with a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQuerySelectStatement<Row, Dialect>, next: From<Dialect>) -> XLQueryTableStatement<Row, Dialect> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    ///
    /// Constructs a Select expression with a From clause that includes a Join clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row, Dialect>, next: Join<Dialect>) -> XLQueryTableStatement<Row, Dialect> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row, Dialect>, next: Where<Dialect>) -> XLQueryWhereStatement<Row, Dialect> {
        XLQueryWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row, Dialect>, next: GroupBy<Dialect>) -> XLQueryGroupByStatement<Row, Dialect> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row, Dialect>, next: Limit<Dialect>) -> XLQueryLimitStatement<Row, Dialect> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    ///
    /// Constructs a Select expression with a Where clause that includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row, Dialect>, next: GroupBy<Dialect>) -> XLQueryGroupByStatement<Row, Dialect> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a Where clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a Where clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row, Dialect>, next: Limit<Dialect>) -> XLQueryLimitStatement<Row, Dialect> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes a Having clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row, Dialect>, next: Having<Dialect>) -> XLQueryHavingStatement<Row, Dialect> {
        XLQueryHavingStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row, Dialect>, next: Limit<Dialect>) -> XLQueryLimitStatement<Row, Dialect> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    ///
    /// Constructs a Select expression with a Having clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row, Dialect>, next: OrderBy<Dialect>) -> XLQueryOrderByStatement<Row, Dialect> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a Having clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row, Dialect>, next: Limit<Dialect>) -> XLQueryLimitStatement<Row, Dialect> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    ///
    /// Constructs a Select expression with an OrderBy clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryOrderByStatement<Row, Dialect>, next: Limit<Dialect>) -> XLQueryLimitStatement<Row, Dialect> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    ///
    /// Constructs a Select expression with an Limit clause that includes an Offset clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryLimitStatement<Row, Dialect>, next: Offset<Dialect>) -> XLQueryOffsetStatement<Row, Dialect> {
        XLQueryOffsetStatement(components: accumulated.components.appending(next))
    }
}


///
/// Result builder used to construct a SQLite select query.
///
/// Every clause of the body must be a SQLite clause: a table of a model
/// declared for SQLite, and SQLite's expressions (issue #822). A helper that
/// builds a SQLite query with this builder keeps compiling unchanged.
///
public typealias XLQueryExpressionBuilder = XLDialectQueryExpressionBuilder<XLSQLiteDialect>


// MARK: - Schema

extension XLSchema {

    ///
    /// Constructs a common table expression on a schema.
    ///
    public func commonTableExpression<T>(alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, @XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaCommonTable where T: XLResult, T.XLModelDialect == Dialect {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema(parent: self)
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema), materialization: materialization)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a subquery in this schema using the query expression builder.
    ///
    /// The subquery's alias comes from this schema, and the body receives a
    /// schema nested in this one (see ``XLSchema/init(parent:)``).
    ///
    public func subqueryExpression<T>(alias: XLName? = nil, @XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaResult where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLSubqueryDependency(alias: alias, statement: statement(XLSchema(parent: self)))
        return T.makeSQLAnonymousResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a subquery in this schema whose columns can evaluate to NULL,
    /// for use on the nullable side of a `LEFT JOIN`.
    ///
    public func nullableSubqueryExpression<T>(alias: XLName? = nil, @XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaNullableNamedResult where T: XLResult, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLSubqueryDependency(alias: alias, statement: statement(XLSchema(parent: self)))
        return T.makeSQLAnonymousNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a scalar subquery in this schema using the query expression
    /// builder.
    ///
    public func subqueryExpression<T>(@XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> XLDialectExpression<Optional<T>, Dialect> where T: XLLiteral {
        XLDialectExpression(XLSubquery<T>(statement: statement(XLSchema(parent: self))))
    }

    ///
    /// Constructs a scalar subquery in this schema whose inner statement is
    /// already nullable.
    ///
    public func subqueryExpression<Wrapped>(@XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema) -> any XLDialectQueryStatement<Optional<Wrapped>, Dialect>) -> XLDialectExpression<Optional<Wrapped>, Dialect> where Wrapped: XLLiteral {
        XLDialectExpression(XLSubquery<Wrapped>(statement: statement(XLSchema(parent: self))))
    }
}


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

// MARK: - SQL

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

///
/// Constructs a select query statement in `dialect`.
///
/// The dialect is named once, where the query begins. The builder receives a
/// schema of `dialect`, which accepts only models declared for it, so every
/// column and every expression in the body carries the dialect, and an
/// operation the dialect does not have is a compile error at its call site
/// (issue #789). Every clause takes only the dialect's tables and
/// expressions (issue #822). The body is written exactly as for SQLite.
///
public func sql<Row, Dialect>(dialect: Dialect.Type, @XLDialectQueryExpressionBuilder<Dialect> builder: (XLSchema<Dialect>) -> any XLDialectQueryStatement<Row, Dialect>) -> any XLDialectQueryStatement<Row, Dialect> {
    let schema = XLSchema(dialect: dialect)
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
