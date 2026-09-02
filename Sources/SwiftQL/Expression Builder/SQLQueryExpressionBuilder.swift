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
    
    public static func buildBlock<T>(_ component: some XLExpression<T>) -> some XLExpression<T> {
        component
    }
}


///
/// Result builder used to construct a select query.
///
@resultBuilder public struct XLQueryExpressionBuilder {
    
    ///
    /// Constructs a With expression.
    ///
    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    ///
    /// Constructs a Select expression.
    ///
    public static func buildPartialBlock<Row>(first: Select<Row>) -> XLQuerySelectStatement<Row> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(select: first))
    }
    
    
    // MARK: With
    
    ///
    /// Constructs a Select expression with a With clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement, next: Select<Row>) -> XLQuerySelectStatement<Row> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: accumulated.commonTables, select: next))
    }

    
    // MARK: Union
    
    ///
    /// Constructs a Union expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Union) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .union, query: accumulated)
    }
    
    ///
    /// Constructs a UnionAll expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: UnionAll) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .unionAll, query: accumulated)
    }
    
    ///
    /// Constructs an Intersect expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Intersect) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .intersect, query: accumulated)
    }
    
    ///
    /// Constructs an Except expression.
    ///
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Except) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .except, query: accumulated)
    }

    ///
    /// Constructs a Select expression with a partial union.
    ///
    public static func buildPartialBlock<Statement>(accumulated: XLQueryPartialUnion<Statement>, next: Select<Statement.Row>) -> XLQuerySelectStatement<Statement.Row> where Statement: XLSimpleSelectQueryStatement {
        let union = BooleanClause(kind: accumulated.kind, lhs: accumulated.query.components, rhs: next)
        return XLQuerySelectStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    
    // MARK: Select
    
    ///
    /// Constructs a Select expression with a From clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQuerySelectStatement<Row>, next: From) -> XLQueryTableStatement<Row> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    ///
    /// Constructs a Select expression with a From clause that includes a Join clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Join) -> XLQueryTableStatement<Row> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a Where clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Where) -> XLQueryWhereStatement<Row> {
        XLQueryWhereStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a From clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    ///
    /// Constructs a Select expression with a Where clause that includes a GroupBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    ///
    /// Constructs a Select expression with a Where clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a Where clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes a Having clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: Having) -> XLQueryHavingStatement<Row> {
        XLQueryHavingStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a GroupBy clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    ///
    /// Constructs a Select expression with a Having clause that includes an OrderBy clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    ///
    /// Constructs a Select expression with a Having clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    ///
    /// Constructs a Select expression with an OrderBy clause that includes a Limit clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryOrderByStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    ///
    /// Constructs a Select expression with an Limit clause that includes an Offset clause.
    ///
    public static func buildPartialBlock<Row>(accumulated: XLQueryLimitStatement<Row>, next: Offset) -> XLQueryOffsetStatement<Row> {
        XLQueryOffsetStatement(components: accumulated.components.appending(next))
    }
}


// MARK: - Schema

extension XLSchema {

    ///
    /// Constructs a common table expression on a schema.
    ///
    public func commonTableExpression<T>(alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema), materialization: materialization)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
}


// MARK: - Subquery

///
/// Constructs a subquery.
///
public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaResult where T: XLTable {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency)
}

///
/// Constructs a subquery that returns a nullable table.
///
public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.Basis.MetaNullableResult where T: XLMetaNullable, T.Basis: XLTable {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.Basis.makeSQLAnonymousNullableResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery that returns an optional scalar value.
///
public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLSubquery(statement: statement(schema))
}


///
/// Constructs a subquery that returns a scalar value.
///
public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: () -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    return XLSubquery(statement: statement())
}


///
/// Constructs a scalar subquery whose inner statement is already nullable, so
/// the subquery's own nullability does not nest a second `Optional`.
///
public func subqueryExpression<Wrapped>(@XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    let schema = XLSchema()
    return XLSubquery<Wrapped>(statement: statement(schema))
}


public func subqueryExpression<Wrapped>(@XLQueryExpressionBuilder statement: () -> any XLQueryStatement<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    XLSubquery<Wrapped>(statement: statement())
}


///
/// Constructs a subquery whose columns can evaluate to NULL, for use on the
/// nullable side of a `LEFT JOIN`.
///
public func nullableSubqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNullableNamedResult where T: XLResult {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNullableNamedResult(namespace: newNamespace, dependency: dependency)
}

// MARK: - SQL

///
/// Constructs a select query statement.
///
public func sql<Row>(@XLQueryExpressionBuilder builder: (XLSchema) -> any XLQueryStatement<Row>) -> any XLQueryStatement<Row> {
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

@_disfavoredOverload
public func sql<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaResult where T: XLTable {
    subqueryExpression(alias: alias, statement: statement)
}

@_disfavoredOverload
public func sql<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.Basis.MetaNullableResult where T: XLMetaNullable, T.Basis: XLTable {
    subqueryExpression(alias: alias, statement: statement)
}

@_disfavoredOverload
public func sql<T>(@XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<T>(@XLQueryExpressionBuilder statement: () -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<Wrapped>(@XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    subqueryExpression(statement: statement)
}

@_disfavoredOverload
public func sql<Wrapped>(@XLQueryExpressionBuilder statement: () -> any XLQueryStatement<Optional<Wrapped>>) -> some XLExpression<Optional<Wrapped>> where Wrapped: XLLiteral {
    subqueryExpression(statement: statement)
}
#endif
