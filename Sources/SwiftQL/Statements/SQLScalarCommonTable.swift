//
//  SQLScalarCommonTable.swift
//
//
//  Direct-scalar common table expressions (issue #43).
//
//  A scalar common table projects a single value column and is referenced and
//  decoded as a bare `Value` — no boxed `@SQLResult` / `SQLScalarResult` wrapper.
//  The single column is named through an explicit, dialect-rendered CTE column
//  list (`cte(value) AS (...)`), so the body's own column labels are untouched.
//
//  The recursive form reuses the alias-first construction lifecycle from #205 by
//  adopting `XLRecursiveCommonTableReferenceLayout` with a one-column reference,
//  which is exactly the extension point #205 kept generic for this feature.
//

import Foundation


///
/// A scalar common table expression: a CTE whose result is a single typed value
/// column, referenced and decoded directly as `Value`.
///
public struct XLScalarCommonTable<Value> where Value: XLLiteral {

    /// The renderable common-table definition, carrying the explicit one-column
    /// list (`alias(column) AS (...)`).
    public let definition: XLCommonTableDependency

    /// The stable one-column alias exposed by references to this common table.
    public let columnAlias: XLName

    init(definition: XLCommonTableDependency, columnAlias: XLName) {
        self.definition = definition
        self.columnAlias = columnAlias
    }
}


///
/// A `FROM`-able reference to a scalar common table, exposing its single column
/// as a typed ``value`` expression.
///
public struct XLScalarCommonTableReference<Value>: XLMetaNamedResult where Value: XLLiteral {

    public typealias Row = Value

    public let _namespace: XLNamespace

    public let _dependency: XLNamedTableDeclaration

    /// The scalar common table's single column, typed as `Value`.
    public let value: XLColumnReference<Value>

    init(cteAlias: XLName, tableAlias: XLName, columnAlias: XLName) {
        let commonTable = XLCommonTableDependency(
            alias: cteAlias,
            statement: XLAliasOnlyCommonTableBody()
        )
        let dependency = XLFromTableDependency(commonTable: commonTable, alias: tableAlias)
        self._namespace = .table()
        self._dependency = dependency
        self.value = XLColumnReference(dependency: dependency, as: columnAlias)
    }

    public func makeSQL(context: inout XLBuilder) {
        _dependency.makeSQL(context: &context)
    }
}


///
/// Reference layout for the recursive scalar common table surface.
///
/// Derives a one-column ``XLScalarCommonTableReference`` self-reference from the
/// reserved alias alone, allocating the reference's table alias from the body
/// schema so it participates in the same alias sequence as the recursive body's
/// other tables.
///
struct XLScalarRecursiveCommonTableLayout<Value>: XLRecursiveCommonTableReferenceLayout where Value: XLLiteral {

    let schema: XLSchema
    let columnAlias: XLName

    var resultColumns: [XLName] { [columnAlias] }

    func makeReference(cteAlias: XLName) -> XLScalarCommonTableReference<Value> {
        let tableAlias = schema.tableNamespace.makeAlias(alias: nil)
        return XLScalarCommonTableReference(
            cteAlias: cteAlias,
            tableAlias: tableAlias,
            columnAlias: columnAlias
        )
    }
}


extension XLCommonTableDependency {

    /// Returns a copy of this dependency carrying the given explicit CTE column
    /// list.
    func withColumns(_ columns: [XLName]) -> XLCommonTableDependency {
        var copy = self
        copy.columns = columns
        return copy
    }
}


extension XLSchema {

    ///
    /// Constructs a scalar common table expression from a query that selects a
    /// single value.
    ///
    /// The body's single column is exposed under `column` (default `value`)
    /// through an explicit `cte(column) AS (...)` list, so the body's own column
    /// labels are left unchanged.
    ///
    public func scalarCommonTable<Value>(
        _ type: Value.Type,
        alias: XLName? = nil,
        column: XLName = "value",
        materialization: XLCommonTableMaterialization = .unspecified,
        statement: (XLSchema) -> any XLQueryStatement<Value>
    ) -> XLScalarCommonTable<Value> where Value: XLLiteral {
        let cteAlias = commonTableNamespace.makeAlias(alias: alias)
        let bodySchema = XLSchema()
        let dependency = XLCommonTableDependency(
            alias: cteAlias,
            statement: statement(bodySchema),
            materialization: materialization,
            columns: [column]
        )
        return XLScalarCommonTable(definition: dependency, columnAlias: column)
    }

    ///
    /// Constructs a recursive scalar common table expression.
    ///
    /// The self-reference passed to `statement` exposes the scalar column as
    /// `value` and is derived from the reserved alias alone through the
    /// value-semantic recursive construction lifecycle.
    ///
    public func recursiveScalarCommonTable<Value>(
        _ type: Value.Type,
        alias: XLName? = nil,
        column: XLName = "value",
        materialization: XLCommonTableMaterialization = .unspecified,
        statement: (XLSchema, XLScalarCommonTableReference<Value>) -> any XLQueryStatement<Value>
    ) -> XLScalarCommonTable<Value> where Value: XLLiteral {
        let cteAlias = commonTableNamespace.makeAlias(alias: alias)
        let bodySchema = XLSchema()
        var draft = XLRecursiveCommonTableDraft(
            alias: cteAlias,
            layout: XLScalarRecursiveCommonTableLayout<Value>(schema: bodySchema, columnAlias: column)
        )
        let dependency = draft.completeWithNonThrowingBody { reference in
            statement(bodySchema, reference)
        }
        return XLScalarCommonTable(
            definition: dependency.materialized(materialization).withColumns([column]),
            columnAlias: column
        )
    }

    ///
    /// Constructs a scalar common table expression using the query expression
    /// builder (`sql { }`-style body).
    ///
    public func scalarCommonTableExpression<Value>(
        _ type: Value.Type,
        alias: XLName? = nil,
        column: XLName = "value",
        materialization: XLCommonTableMaterialization = .unspecified,
        @XLQueryExpressionBuilder statement: (XLSchema) -> any XLQueryStatement<Value>
    ) -> XLScalarCommonTable<Value> where Value: XLLiteral {
        scalarCommonTable(
            type,
            alias: alias,
            column: column,
            materialization: materialization,
            statement: statement
        )
    }

    ///
    /// Constructs a recursive scalar common table expression using the query
    /// expression builder.
    ///
    public func recursiveScalarCommonTableExpression<Value>(
        _ type: Value.Type,
        alias: XLName? = nil,
        column: XLName = "value",
        materialization: XLCommonTableMaterialization = .unspecified,
        @XLQueryExpressionBuilder statement: (XLSchema, XLScalarCommonTableReference<Value>) -> any XLQueryStatement<Value>
    ) -> XLScalarCommonTable<Value> where Value: XLLiteral {
        recursiveScalarCommonTable(
            type,
            alias: alias,
            column: column,
            materialization: materialization,
            statement: statement
        )
    }

    ///
    /// Creates a `FROM`-able reference to a scalar common table.
    ///
    public func table<Value>(
        _ scalarCommonTable: XLScalarCommonTable<Value>,
        as alias: XLName? = nil
    ) -> XLScalarCommonTableReference<Value> where Value: XLLiteral {
        let tableAlias = tableNamespace.makeAlias(alias: alias)
        return XLScalarCommonTableReference(
            cteAlias: scalarCommonTable.definition.alias,
            tableAlias: tableAlias,
            columnAlias: scalarCommonTable.columnAlias
        )
    }
}


///
/// Specifies a scalar common table expression used in a statement.
///
public func with<Value>(_ scalarCommonTable: XLScalarCommonTable<Value>) -> XLWithStatement where Value: XLLiteral {
    XLWithStatement([scalarCommonTable.definition])
}


extension With {

    ///
    /// Specifies a scalar common table expression.
    ///
    public init<Value>(_ scalarCommonTable: XLScalarCommonTable<Value>) where Value: XLLiteral {
        self.init(scalarCommonTable.definition)
    }
}


extension XLExpression {

    ///
    /// Tests whether the expression appears in a scalar common table.
    ///
    public func `in`<Value>(_ scalarCommonTable: XLScalarCommonTable<Value>) -> some XLExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias)
    }

    ///
    /// Tests whether the expression does not appear in a scalar common table.
    ///
    public func notIn<Value>(_ scalarCommonTable: XLScalarCommonTable<Value>) -> some XLExpression<Bool> where Value: XLLiteral {
        XLInTableExpression(lhs: self, rhs: scalarCommonTable.definition.alias, negated: true)
    }
}


extension QueryBuilder {

    ///
    /// Adds a scalar common table expression to the query.
    ///
    public func with<Value>(_ scalarCommonTable: XLScalarCommonTable<Value>) -> QueryBuilder where Value: XLLiteral {
        with(commonTableDefinition: scalarCommonTable.definition)
    }
}
