//
//  XLSchema.swift
//  
//
//  Created by Luke Van In on 2023/08/10.
//

import Foundation


public struct XLQueryBuilder<Row> {
    
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
    
    public init<T>(select result: T) where T: XLRowReadable, T.Row == Row {
        self.init(select: Select(result))
    }


    public init(select expression: any XLExpression<Row>) where Row: XLExpression & XLLiteral {
        self.init(select: Select(expression))
    }
    
    
    public init(select: Select<Row>) {
        self.select = select
    }
    
    private func copy(modifier: (inout XLQueryBuilder) -> Void) -> XLQueryBuilder {
        var newInstance = XLQueryBuilder(select: select)
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

    public func with<T>(_ commonTable: T) -> XLQueryBuilder where T: XLMetaCommonTable {
        copy {
            $0.commonTables.append(commonTable.definition)
        }
    }
    
    public func from<T>(_ table: T) -> XLQueryBuilder where T: XLMetaNamedResult {
        copy {
            $0.from = From(table)
        }
    }

    public func innerJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> XLQueryBuilder where T: XLMetaResult {
        copy {
            $0.joins.append(Join(kind: .innerJoin, table: table, constraint: constraint))
        }
    }

    public func innerJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> XLQueryBuilder where T: XLMetaResult {
        copy {
            $0.joins.append(Join(kind: .innerJoin, table: table, constraint: constraint))
        }
    }

    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> XLQueryBuilder where T: XLMetaNullableResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> XLQueryBuilder where T: XLMetaNullableResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Bool>) -> XLQueryBuilder where T: XLMetaNullableNamedResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }

    public func leftJoin<T>(_ table: T, on constraint: any XLExpression<Optional<Bool>>) -> XLQueryBuilder where T: XLMetaNullableNamedResult {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, constraint: constraint))
        }
    }
    
    public func and(_ condition: any XLExpression<Bool>) -> XLQueryBuilder {
        copy {
            $0.whereAnd.append(condition)
        }
    }

    public func and(_ condition: any XLExpression<Optional<Bool>>) -> XLQueryBuilder {
        copy {
            $0.whereAnd.append(condition)
        }
    }

    public func or(_ condition: any XLExpression<Bool>) -> XLQueryBuilder {
        copy {
            $0.whereOr.append(condition)
        }
    }

    public func or(_ condition: any XLExpression<Optional<Bool>>) -> XLQueryBuilder {
        copy {
            $0.whereOr.append(condition)
        }
    }

    public func groupBy(_ expression: any XLExpression) -> XLQueryBuilder {
        copy {
            $0.groupBy.append(expression)
        }
    }
    
    public func orderBy(_ condition: any XLOrderingTerm) -> XLQueryBuilder {
        copy {
            $0.orderBy.append(condition)
        }
    }
    
    public func limit(_ expression: any XLExpression) -> XLQueryBuilder {
        copy {
            $0.limit = expression
        }
    }
    
    public func offset(_ expression: any XLExpression) -> XLQueryBuilder {
        copy {
            $0.offset = expression
        }
    }
    
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

