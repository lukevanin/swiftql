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


// MARK: - SQL

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
