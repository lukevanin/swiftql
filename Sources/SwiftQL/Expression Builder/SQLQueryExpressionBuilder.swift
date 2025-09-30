//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/28.
//

import Foundation


// MARK: - Expression builder


///
/// Expression builder used by scalar SELECT statement. ie. Where a SELECT statement returns the result of a single expression.
///
@resultBuilder public struct XLScalarExpressionBuilder {
    
    public static func buildBlock<T>(_ component: some XLExpression<T>) -> some XLExpression<T> {
        component
    }
}


@resultBuilder public struct XLQueryExpressionBuilder {
    
    public static func buildPartialBlock(first: With) -> XLWithStatement {
        XLWithStatement(first.commonTables)
    }

    public static func buildPartialBlock<Row>(first: Select<Row>) -> XLQuerySelectStatement<Row> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(select: first))
    }
    
    
    // MARK: With
    
    public static func buildPartialBlock<Row>(accumulated: XLWithStatement, next: Select<Row>) -> XLQuerySelectStatement<Row> {
        XLQuerySelectStatement(components: XLQueryStatementComponents(commonTables: accumulated.commonTables, select: next))
    }

    
    // MARK: Union
    
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Union) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .union, query: accumulated)
    }
    
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: UnionAll) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .unionAll, query: accumulated)
    }
    
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Intersect) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .intersect, query: accumulated)
    }
    
    public static func buildPartialBlock<Statement>(accumulated: Statement, next: Except) -> XLQueryPartialUnion<Statement> where Statement: XLSimpleSelectQueryStatement {
        return XLQueryPartialUnion(kind: .except, query: accumulated)
    }

    public static func buildPartialBlock<Statement>(accumulated: XLQueryPartialUnion<Statement>, next: Select<Statement.Row>) -> XLQuerySelectStatement<Statement.Row> where Statement: XLSimpleSelectQueryStatement, Statement.Row: XLResult, Statement.Row.MetaResult: XLRowReadable, Statement.Row.MetaResult.Row == Statement.Row {
        let union = BooleanClause(kind: accumulated.kind, lhs: accumulated.query, rhs: next)
        return XLQuerySelectStatement(components: XLQueryStatementComponents(reader: union, components: [union]))
    }
    
    
    // MARK: Select
    
    public static func buildPartialBlock<Row>(accumulated: XLQuerySelectStatement<Row>, next: From) -> XLQueryTableStatement<Row> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: Table
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Join) -> XLQueryTableStatement<Row> {
        XLQueryTableStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Where) -> XLQueryWhereStatement<Row> {
        XLQueryWhereStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLQueryTableStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: Where
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: GroupBy) -> XLQueryGroupByStatement<Row> {
        XLQueryGroupByStatement(components: accumulated.components.appending(next))
    }

    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryWhereStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: GROUP BY
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: Having) -> XLQueryHavingStatement<Row> {
        XLQueryHavingStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryGroupByStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: HAVING
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row>, next: OrderBy) -> XLQueryOrderByStatement<Row> {
        XLQueryOrderByStatement(components: accumulated.components.appending(next))
    }
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryHavingStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }

    
    // MARK: ORDER BY
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryOrderByStatement<Row>, next: Limit) -> XLQueryLimitStatement<Row> {
        XLQueryLimitStatement(components: accumulated.components.appending(next))
    }
    
    
    // MARK: LIMIT
    
    public static func buildPartialBlock<Row>(accumulated: XLQueryLimitStatement<Row>, next: Offset) -> XLQueryOffsetStatement<Row> {
        XLQueryOffsetStatement(components: accumulated.components.appending(next))
    }
}


// MARK: - Schema

extension XLSchema {
    
    public func commonTableExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
}


// MARK: - Subquery

#warning("TODO: Overload sql function and infer subquery context from return type")

#warning("TODO: Add support for subqueries returning nullable tables and scalar values")

public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaResult where T: XLTable {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency)
}

public func subqueryExpression<T>(alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> T.Basis.MetaNullableResult where T: XLMetaNullable, T.Basis: XLTable {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.Basis.makeSQLAnonymousNullableResult(namespace: newNamespace, dependency: dependency)
}


public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLSubquery(statement: statement(schema))
}


public func subqueryExpression<T>(@XLQueryExpressionBuilder statement: () -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    return XLSubquery(statement: statement())
}

// MARK: - XL

///
///
///
public func sql<Row>(@XLQueryExpressionBuilder builder: (XLSchema) -> any XLQueryStatement<Row>) -> any XLQueryStatement<Row> {
    let schema = XLSchema()
    return builder(schema)
}
