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
/// The builder carries its dialect, and takes only that dialect's tables and
/// expressions (issue #822). ``QueryBuilder`` is the builder for SQLite. The
/// methods that take an expression are declared by each dialect's surface,
/// from scripts/dialect-surface/Templates/QueryBuilder.swift.template.
///
public struct XLDialectQueryBuilder<Row, Dialect> where Dialect: XLSQLDialect {

    enum InternalError: LocalizedError {
        case missingFromClause
        case missingLimitClause
    }

    private var commonTables: [XLCommonTableDependency] = []

    private var select: Select<Row, Dialect>

    private var from: From<Dialect>?

    private var joins: [Join<Dialect>] = []

    /// The where terms in call order, each with the operator that joins it to
    /// the terms before it. The first term's operator is not used.
    private var whereTerms: [(op: String, condition: any XLExpression)] = []

    private var groupBy: [any XLExpression] = []

    private var orderBy: [any XLOrderingTerm<Dialect>] = []

    private var limit: Limit<Dialect>?

    private var offset: Offset<Dialect>?

    ///
    /// Create a query builder using a row definition. The row is typically defined using the row reader on
    /// a struct annotated with `@SQLTable` or `@SQLResult`.
    ///
    public init<T>(select result: T) where T: XLRowReadable & XLDialectBound, T.Row == Row, T.XLModelDialect == Dialect {
        self.init(select: Select(result))
    }

    ///
    /// Creates a query builder from a static row layout. The layout's metadata
    /// names the columns, so no `readRow` replay runs.
    ///
    public init<T>(select layout: T) where T: XLStaticRowReadable, T.Row == Row, T.XLModelDialect == Dialect {
        self.init(select: Select(layout))
    }

    ///
    /// Creates a query builder from a select statement.
    ///
    public init(select: Select<Row, Dialect>) {
        self.select = select
    }

    ///
    /// Creates a query using a common table expression.
    ///
    public func with<T>(_ commonTable: T) -> XLDialectQueryBuilder where T: XLDialectCommonTable, T.XLModelDialect == Dialect {
        copy {
            $0.commonTables.append(commonTable.definition)
        }
    }

    ///
    /// Adds a from clause to the query.
    ///
    public func from<T>(_ table: T) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.from = From(table)
        }
    }

    ///
    /// Adds a from clause whose table can resolve to `NULL`, for use as the
    /// left-hand table of a `RIGHT JOIN` or either side of a `FULL OUTER JOIN`.
    ///
    public func from<T>(_ table: T) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.from = From(table)
        }
    }

    ///
    /// Adds an inner join whose constraint is a `USING (columns...)` clause.
    ///
    public func innerJoin<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.joins.append(Join(kind: .innerJoin, table: table, using: [firstColumn] + otherColumns))
        }
    }

    ///
    /// Adds a left join whose constraint is a `USING (columns...)` clause.
    ///
    public func leftJoin<T>(_ table: T, using firstColumn: XLName, _ otherColumns: XLName...) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.joins.append(Join(kind: .leftJoin, table: table, using: [firstColumn] + otherColumns))
        }
    }

    ///
    /// Adds a natural (inner) join, which implicitly matches every shared column.
    ///
    public func naturalJoin<T>(_ table: T) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.joins.append(Join(kind: .naturalJoin, table: table, constraint: nil))
        }
    }

    ///
    /// Adds a natural left join, whose joined table can resolve to `NULL`.
    ///
    public func naturalLeftJoin<T>(_ table: T) -> XLDialectQueryBuilder where T: XLMetaNullableNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.joins.append(Join(kind: .naturalLeftJoin, table: table, constraint: nil))
        }
    }

    ///
    /// Adds a cross join to the query, returning every combination of rows.
    ///
    public func crossJoin<T>(_ table: T) -> XLDialectQueryBuilder where T: XLMetaNamedResult, T.XLModelDialect == Dialect {
        copy {
            $0.joins.append(Join(kind: .crossJoin, table: table, constraint: nil))
        }
    }

    ///
    /// Adds an order by expression to the where clause.
    ///
    public func orderBy(_ condition: any XLOrderingTerm<Dialect>) -> XLDialectQueryBuilder {
        copy {
            $0.orderBy.append(condition)
        }
    }

    ///
    /// Adds a join of `kind` on a table and a constraint that belong to
    /// `Dialect`. Used by the generated join methods.
    ///
    @_spi(XLDialectSurface)
    public func _dialectSurfaceJoin(_ kind: Join<Dialect>.Kind, table: any XLEncodable, constraint: any XLExpression) -> XLDialectQueryBuilder {
        copy {
            $0.joins.append(Join(kind: kind, table: table, constraint: constraint))
        }
    }

    ///
    /// Adds a where term that belongs to `Dialect`, joined by `op` (`AND` or
    /// `OR`). Used by the generated `and(_:)` and `or(_:)`.
    ///
    @_spi(XLDialectSurface)
    public func _dialectSurfaceWhereTerm(_ op: String, condition: any XLExpression) -> XLDialectQueryBuilder {
        copy {
            $0.whereTerms.append((op: op, condition: condition))
        }
    }

    ///
    /// Adds a group by expression that belongs to `Dialect`. Used by the
    /// generated `groupBy(_:)`.
    ///
    @_spi(XLDialectSurface)
    public func _dialectSurfaceGroupBy(_ expression: any XLExpression) -> XLDialectQueryBuilder {
        copy {
            $0.groupBy.append(expression)
        }
    }

    ///
    /// Sets the limit to an expression that belongs to `Dialect`. Used by the
    /// generated `limit(_:)`.
    ///
    @_spi(XLDialectSurface)
    public func _dialectSurfaceLimit(_ expression: any XLExpression) -> XLDialectQueryBuilder {
        copy {
            $0.limit = Limit(_dialectSurface: expression)
        }
    }

    ///
    /// Sets the offset to an expression that belongs to `Dialect`. Used by
    /// the generated `offset(_:)`.
    ///
    @_spi(XLDialectSurface)
    public func _dialectSurfaceOffset(_ expression: any XLExpression) -> XLDialectQueryBuilder {
        copy {
            $0.offset = Offset(_dialectSurface: expression)
        }
    }

    private func copy(modifier: (inout XLDialectQueryBuilder) -> Void) -> XLDialectQueryBuilder {
        var newInstance = self
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
    public func build() throws -> any XLDialectQueryStatement<Row, Dialect> {
        var statement = XLQueryStatementComponents(select: select)
        if !commonTables.isEmpty {
            statement.commonTables = commonTables
        }
        guard let from else {
            throw InternalError.missingFromClause
        }
        statement.components.append(from)
        statement.components.append(contentsOf: joins)
        // Fold the terms in call order (issue #657). Before v1.8.1 every `and`
        // term folded first and every `or` term folded after them, so
        // `and(a).or(b).and(c)` rendered `((a AND c) OR b)`.
        var condition: (any XLExpression)?
        for term in whereTerms {
            if let current = condition {
                condition = XLBinaryOperatorExpression<Bool>(op: term.op, lhs: current, rhs: term.condition)
            }
            else {
                condition = term.condition
            }
        }
        if let condition {
            statement.components.append(Where<Dialect>(_dialectSurface: condition))
        }
        if !groupBy.isEmpty {
            statement.components.append(GroupBy<Dialect>(_dialectSurface: groupBy))
        }
        if !orderBy.isEmpty {
            statement.components.append(OrderBy<Dialect>(terms: orderBy))
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
        return AbstractXLQueryStatement<Row, Dialect>(components: statement)
    }
}


///
/// QueryBuilder constructs SQLite select statements when the structure of the
/// query is not known at compile time.
///
/// It takes only SQLite tables and expressions. See
/// ``XLDialectQueryBuilder`` for another dialect.
///
public typealias QueryBuilder<Row> = XLDialectQueryBuilder<Row, XLSQLiteDialect>
