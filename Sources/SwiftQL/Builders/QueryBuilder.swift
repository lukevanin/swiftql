//
//  QueryBuilder.swift
//
//
//  Created by Luke Van In on 2023/08/10.
//

import Foundation


///
/// QueryBuilder is used to construct select statements, when the structure of the query is not known at
/// compile time.
///
/// QueryBuilder provides greater flexibility over static queries which cannot normally change
/// once compiled. This flexibility comes with some caveats:
///
/// 1. QueryBuilder does not strictly enforce the integrity of the query. It is the programmer's responsibility to
/// ensure that the resulting query is valid.
/// 2. The SQL statement is generated each time the `build()` method is called, which incurs a small
/// runtime overhead. Static queries should be used where maximum efficiency is required.
///
public struct QueryBuilder<Row> {
    
    #warning("TODO: Rename AND and OR to requiredConstraint and optionalConstraint")
    
    enum InternalError: LocalizedError {
        case missingFromClause
        case missingLimitClause
    }
    
    private var commonTables: [XLCommonTableDependency] = []
    
    private var select: Select<Row>
    
    private var from: From?
    
    private var joins: [Join] = []
    
    private var whereAnd: [any XLExpression] = []
    
    private var whereOr: [any XLExpression] = []
    
    private var groupBy: [any XLExpression] = []
    
    private var orderBy: [any XLOrderingTerm] = []
    
    private var limit: (any XLExpression)?
    
    private var offset: (any XLExpression)?
    
    ///
    /// Create a query builder using a row definition. The row is typically defined using the row reader on
    /// a struct annotated with `@SQLTable` or `@SQLResult`.
    ///
    public init<T>(select result: T) where T: XLRowReadable, T.Row == Row {
        self.init(select: Select(result))
    }


    ///
    /// Creates a query builder using an expression. The expression should use one or more fields in one or
    /// more tables in the from clause.
    ///
    public init(select expression: any XLExpression<Row>) where Row: XLExpression & XLLiteral {
        self.init(select: Select(expression))
    }
    
    
    ///
    /// Creates a query builder from a select statement.
    ///
    public init(select: Select<Row>) {
        self.select = select
    }

    ///
    /// Creates a query using a common table expression.
    ///
    public func with<T>(_ commonTable: T) -> QueryBuilder where T: XLMetaCommonTable {
        copy {
            $0.commonTables.append(commonTable.definition)
        }
    }
    
    ///
    /// Adds a from clause to the query.
    ///
    public func from<T>(_ table: T) -> QueryBuilder where T: XLMetaNamedResult {
        copy {
            $0.from = From(table)
        }
    }

    ///
    /// Adds an inner join clause to the query.
    ///
    public func innerJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> QueryBuilder where T: XLMetaResult {
        copy {
            $0.joins.append(Join(kind: .innerJoin, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds an inner join clause to the query, using an optional field.
    ///
    public func innerJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> QueryBuilder where T: XLMetaResult {
        copy {
            $0.joins.append(Join(kind: .innerJoin, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> QueryBuilder where T: XLMetaNullableResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> QueryBuilder where T: XLMetaNullableResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> QueryBuilder where T: XLMetaNullableNamedResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds a left join to the query.
    ///
    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> QueryBuilder where T: XLMetaNullableNamedResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }
    
    ///
    /// Adds an and expression to the where clause.
    ///
    public func and(_ condition: any XLExpression<Bool>) -> QueryBuilder {
        copy {
            $0.whereAnd.append(condition)
        }
    }

    ///
    /// Adds an and expression to the where clause.
    ///
    public func and(_ condition: any XLExpression<Optional<Bool>>) -> QueryBuilder {
        copy {
            $0.whereAnd.append(condition)
        }
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    public func or(_ condition: any XLExpression<Bool>) -> QueryBuilder {
        copy {
            $0.whereOr.append(condition)
        }
    }

    ///
    /// Adds an or expression to the where clause.
    ///
    public func or(_ condition: any XLExpression<Optional<Bool>>) -> QueryBuilder {
        copy {
            $0.whereOr.append(condition)
        }
    }

    ///
    /// Adds a group by expression to the where clause.
    ///
    public func groupBy(_ expression: any XLExpression) -> QueryBuilder {
        copy {
            $0.groupBy.append(expression)
        }
    }
    
    ///
    /// Adds an order by expression to the where clause.
    ///
    public func orderBy(_ condition: any XLOrderingTerm) -> QueryBuilder {
        copy {
            $0.orderBy.append(condition)
        }
    }
    
    ///
    /// Adds a limit clause.
    ///
    public func limit(_ expression: any XLExpression) -> QueryBuilder {
        copy {
            $0.limit = expression
        }
    }
    
    ///
    /// Adds an offset clause.
    ///
    public func offset(_ expression: any XLExpression) -> QueryBuilder {
        copy {
            $0.offset = expression
        }
    }
    
    private func copy(modifier: (inout QueryBuilder) -> Void) -> QueryBuilder {
        var newInstance = QueryBuilder(select: select)
        newInstance.commonTables = commonTables
        newInstance.from = from
        newInstance.joins = joins
        newInstance.whereAnd = whereAnd
        newInstance.whereOr = whereOr
        newInstance.groupBy = groupBy
        newInstance.orderBy = orderBy
        newInstance.limit = limit
        newInstance.offset = offset
        modifier(&newInstance)
        return newInstance
    }
    
    ///
    /// Constructs the SQL query from the provided clauses.
    /// - Returns: A complete SQL select statement.
    /// - Throws: `InternalError.missingFromClause` if the from clause is missing.
    /// - Throws: `InternalError.missingLimitClause` if an offset term is specified without a
    /// limit expression.
    ///
    public func build() throws -> any XLQueryStatement<Row> {
        var statement = XLQueryStatementComponents(select: select)
        if !commonTables.isEmpty {
            statement.commonTables = commonTables
        }
        guard let from else {
            throw InternalError.missingFromClause
        }
        statement.components.append(from)
        statement.components.append(contentsOf: joins)
        if !whereAnd.isEmpty || !whereOr.isEmpty {
            var condition: (any XLExpression)!
            for term in whereAnd {
                if condition == nil {
                    condition = term
                }
                else {
                    condition = XLBinaryOperatorExpression<Bool>(op: "AND", lhs: condition, rhs: term)
                }
            }
            for term in whereOr {
                if condition == nil {
                    condition = term
                }
                else {
                    condition = XLBinaryOperatorExpression<Bool>(op: "OR", lhs: condition, rhs: term)
                }
            }
            if let condition {
                statement.components.append(Where(condition))
            }
        }
        if !groupBy.isEmpty {
            statement.components.append(GroupBy(groupBy))
        }
        if !orderBy.isEmpty {
            statement.components.append(OrderBy(terms: orderBy))
        }
        if let limit {
            statement.components.append(limit)
        }
        if let offset {
            guard limit != nil else {
                throw InternalError.missingLimitClause
            }
            statement.components.append(offset)
        }
        return AbstractXLQueryStatement(components: statement)
    }
}

