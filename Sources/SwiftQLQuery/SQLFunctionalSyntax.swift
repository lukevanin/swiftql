//
//  SQLFunctionalSyntax.swift
//
//
//  Created by Luke Van In on 2023/08/16.
//

import Foundation


// e.g. From, Join
public protocol XLTableStatement: XLQueryComponent {
    
}

// MARK: With (common table expression)


///
/// The scope of one statement, in which its tables, common tables, and
/// bindings are named.
///
/// `Dialect` is the dialect of the statement. A table, a common table, or a
/// subquery joins the scope only when its model is declared for that dialect:
/// `table(_:as:)` requires `T.XLModelDialect == Dialect`. Every column of the model
/// carries the dialect, so every expression composed in the statement does
/// too (issue #789).
///
/// A SQLite statement's scope is ``XLSQLiteSchema``, and `XLSchema()` creates
/// one. Another dialect's scope is created with ``init(dialect:)``, and the
/// `sql(dialect:)` entry point passes one to its builder.
///
public struct XLSchema<Dialect> where Dialect: XLSQLDialect {

    let commonTableNamespace: XLNamespace

    let tableNamespace: XLNamespace

    let parameterNamespace: XLNamespace

    ///
    /// Creates a schema for a top-level statement in `dialect`.
    ///
    public init(dialect: Dialect.Type) {
        commonTableNamespace = XLNamespace.common()
        tableNamespace = XLNamespace.table()
        parameterNamespace = XLNamespace.parameter()
    }

    ///
    /// Creates a schema for a scope nested inside `parent`, such as the body of
    /// a subquery or a common table expression.
    ///
    /// Automatically assigned table and common-table aliases skip every alias
    /// that `parent` or one of its ancestors has reserved, so the nested body
    /// never shadows a name that it can reference. Parameters are not scoped in
    /// SQL, so the nested schema shares the parameter namespace of `parent`, and
    /// an outer and an inner automatically named binding get distinct names.
    ///
    /// Explicit aliases are used as given.
    ///
    public init(parent: XLSchema) {
        commonTableNamespace = parent.commonTableNamespace.makeNestedNamespace()
        tableNamespace = parent.tableNamespace.makeNestedNamespace()
        parameterNamespace = parent.parameterNamespace
    }

    ///
    /// Constructs a named binding reference.
    ///
    /// > Tip: For most use cases this method is not needed and `XLNamedBindingReference` should
    /// be instantiated directly.
    ///
    public func binding<T>(of type: T.Type, as alias: XLName? = nil) -> XLNamedBindingReference<T> where T: XLLiteral {
        XLNamedBindingReference(
            name: parameterNamespace.makeAlias(alias: alias),
            // Only an automatically assigned name can collide by accident. A
            // caller that reuses an explicit name asks for one parameter.
            origin: alias == nil ? XLBindingOrigin(scope: parameterNamespace.bindingScope) : nil
        )
    }

    ///
    /// Constructs common table expression using a select query that returns an `SQLTable`.
    ///
    public func commonTable<T>(alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, statement: any XLDialectQueryStatement<T, Dialect>) -> T.MetaCommonTable where T: XLTable, T.XLModelDialect == Dialect {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let dependency = XLCommonTableDependency(alias: alias, statement: statement, materialization: materialization)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a common table expression with a select query that returns an `SQLResult`
    /// column set.
    ///
    /// - Parameter alias: Name used to refer to the common table expression, or
    ///   `nil` to allocate one automatically.
    /// - Parameter materialization: An optional `MATERIALIZED` / `NOT MATERIALIZED`
    ///   hint for SQLite's query planner (SQLite 3.35.0+). Defaults to
    ///   ``XLCommonTableMaterialization/unspecified``.
    /// - Parameter statement: Builds the common table's select query.
    ///
    public func commonTable<T>(alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaCommonTable where T: XLResult, T.XLModelDialect == Dialect {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema(parent: self)
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema), materialization: materialization)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
    
    ///
    /// Constructs a recursive common table expression using a select query that returns
    /// an `SQLResult`.
    ///
    /// The self-reference passed to `statement` is derived from the reserved
    /// alias alone through a value-semantic ``XLRecursiveCommonTableDraft``; no
    /// mutable completion cell is involved.
    ///
    public func recursiveCommonTable<T>(_ type: T.Type, alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, statement: (XLSchema, T.MetaCommonTable.Result.MetaNamedResult) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaCommonTable where T: XLResult, T.XLModelDialect == Dialect {
        makeRecursiveCommonTable(T.self, alias: alias, materialization: materialization, body: statement)
    }

    ///
    /// Constructs a recursive common table expression using a select query that returns an `SQLResult`.
    ///
    public func recursiveCommonTableExpression<T>(_ type: T.Type, alias: XLName? = nil, materialization: XLCommonTableMaterialization = .unspecified, @XLDialectQueryExpressionBuilder<Dialect> statement: (XLSchema, T.MetaCommonTable.Result.MetaNamedResult) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaCommonTable where T: XLResult, T.XLModelDialect == Dialect {
        makeRecursiveCommonTable(T.self, alias: alias, materialization: materialization, body: statement)
    }

    ///
    /// Shared alias-first construction for the recursive common table surface.
    ///
    /// Reserves an immutable alias, derives the self-reference from that alias
    /// alone, then completes the body through a value-semantic
    /// ``XLRecursiveCommonTableDraft``. No mutable completion cell is involved,
    /// and the rendered SQL is identical to the previous mechanism.
    ///
    private func makeRecursiveCommonTable<T>(
        _ type: T.Type,
        alias: XLName?,
        materialization: XLCommonTableMaterialization,
        body: (XLSchema, T.MetaCommonTable.Result.MetaNamedResult) -> any XLDialectQueryStatement<T, Dialect>
    ) -> T.MetaCommonTable where T: XLResult, T.XLModelDialect == Dialect {
        let reservedAlias = commonTableNamespace.makeAlias(alias: alias)
        let bodySchema = XLSchema(parent: self)
        var draft = XLRecursiveCommonTableDraft(
            alias: reservedAlias,
            layout: XLCompositeRecursiveCommonTableLayout<T>(schema: bodySchema)
        )
        let dependency = draft.completeWithNonThrowingBody { reference in
            body(bodySchema, reference)
        }
        return T.makeSQLCommonTable(
            namespace: commonTableNamespace,
            dependency: dependency.materialized(materialization)
        )
    }
    
    ///
    /// Creates a reference to an `SQLTable`.
    ///
    /// The table's model must be declared for this schema's dialect. A model
    /// declared for another dialect is a compile error here, which names both
    /// dialects.
    ///
    public func table<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNamedResult where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLResult`.
    ///
    public func table<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNamedResult where T: XLMetaCommonTable, T.Result.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Creates a reference to an `SQLTable` that can resolve to `NULL`.
    ///
    public func nullableTable<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNullableNamedResult where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLResult` that can resolve to `NULL`.
    ///
    public func nullableTable<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNullableNamedResult where T: XLMetaCommonTable, T.Result.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to the `excluded` pseudo table used inside an
    /// `ON CONFLICT ... DO UPDATE` clause.
    ///
    /// The columns of the returned reference render as `excluded.<column>` and
    /// resolve to the values of the candidate row that triggered the conflict,
    /// for example `row.value = excluded.value`.
    ///
    public func excluded<T>(_ table: T.Type) -> T.MetaNamedResult where T: XLTable, T.XLModelDialect == Dialect {
        return T.makeSQLNamedResult(
            namespace: tableNamespace,
            dependency: XLExcludedTableDependency()
        )
    }

    ///
    /// Creates a reference to an `SQLTable` that is the subject of a write operation.
    ///
    public func into<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaWritableTable where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLInsert(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLTable` that is used in a `From` clause in an `Insert` statement.
    ///
    public func from<T>(as alias: XLName? = nil, statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaNamedResult where T: XLTable, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let schema = XLSchema(parent: self)
        let dependency = XLUpdateFromTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a subquery in this schema with a select query statement that
    /// returns a column set.
    ///
    /// The subquery's alias comes from this schema, so an unnamed subquery
    /// never renders the alias of another source in the enclosing statement.
    /// The body receives a schema nested in this one (see
    /// ``init(parent:)``).
    ///
    public func subquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaNamedResult where T: XLResult, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLSubqueryDependency(alias: alias, statement: statement(XLSchema(parent: self)))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a subquery in this schema whose columns can evaluate to NULL,
    /// for use on the nullable side of a `LEFT JOIN`.
    ///
    /// The alias and the body schema are derived from this schema, as for
    /// ``subquery(alias:_:)``.
    ///
    public func nullableSubquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> T.MetaNullableNamedResult where T: XLResult, T.XLModelDialect == Dialect {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLSubqueryDependency(alias: alias, statement: statement(XLSchema(parent: self)))
        return T.makeSQLAnonymousNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Constructs a scalar subquery in this schema. The body receives a schema
    /// nested in this one, so its aliases and bindings do not collide with the
    /// enclosing statement.
    ///
    public func subquery<T>(_ statement: (XLSchema) -> any XLDialectQueryStatement<T, Dialect>) -> XLDialectExpression<Optional<T>, Dialect> where T: XLLiteral {
        XLDialectExpression(XLSubquery<T>(statement: statement(XLSchema(parent: self))))
    }

    ///
    /// Constructs a scalar subquery in this schema whose inner statement is
    /// already nullable, so the two sources of NULL collapse into one.
    ///
    public func subquery<Wrapped>(_ statement: (XLSchema) -> any XLDialectQueryStatement<Optional<Wrapped>, Dialect>) -> XLDialectExpression<Optional<Wrapped>, Dialect> where Wrapped: XLLiteral {
        XLDialectExpression(XLSubquery<Wrapped>(statement: statement(XLSchema(parent: self))))
    }

    ///
    /// Creates a reference to a table that is used in a Create statement.
    ///
    public func create<T>(_ table: T.Type) -> T.MetaCreate where T: XLTable, T.XLModelDialect == Dialect {
        return T.makeSQLCreate()
    }
}


// MARK: With


///
/// Specifies common table expressions used in a statement.
///
public func with<Dialect>(_ commonTables: any XLDialectCommonTable<Dialect>...) -> XLWithStatement<Dialect> {
    XLWithStatement(_dialectSurface: commonTables.map { $0.definition })
}


///
/// Specifies one common table of a model, in the dialect of its result, so
/// generic code that names a model's `MetaCommonTable` can pass it.
///
public func with<T>(_ commonTable: T) -> XLWithStatement<T.Result.XLModelDialect> where T: XLMetaCommonTable {
    XLWithStatement(_dialectSurface: [commonTable.definition])
}



// MARK: Result


///
/// Specifies the values for columns in a select statement.
///
@available(*, deprecated, message: "Use the .columns() method on the table object instead.")
public func result<T>(_ builder: () -> T) -> T.Row.MetaResult where T: XLRowReadable, T.Row: XLResult {
    let newNamespace = XLNamespace.table()
    let dependency = XLSelectResultDependency()
    let iterator = builder()
    return T.Row.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency, iterator: iterator.readRow)
}


///
/// Specifies the values for columns in a select statement.
///
@available(*, deprecated, message: "Use the .columns() method on the table object instead.")
public func result<T>(_ iterator: @escaping (XLRowReader) -> T) -> T.MetaResult where T: XLResult {
    let newNamespace = XLNamespace.table()
    let dependency = XLSelectResultDependency()
    return T.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency, iterator: iterator)
}


// MARK: Select

///
/// Constructs a select statement from a static row layout.
///
/// The layout's metadata already names its columns, so the statement does not
/// replay `readRow` to find them. The model initializer and codecs run only
/// when a row is decoded.
///
/// The statement's dialect is the layout's.
///
public func select<T>(_ layout: T) -> XLQuerySelectStatement<T.Row, T.XLModelDialect> where T: XLStaticRowReadable {
    makeQuery(select: Select(layout))
}


///
/// Constructs a select statement that returns a column set.
///
/// The statement's dialect is the dialect of the model the columns belong to.
///
public func select<T>(_ result: T) -> XLQuerySelectStatement<T.Row, T.XLModelDialect> where T: XLRowReadable & XLDialectBound {
    makeQuery(select: Select(result))
}


///
/// Constructs a select statement using an explicit Select expression.
///
private func makeQuery<T, Dialect>(select: Select<T, Dialect>) -> XLQuerySelectStatement<T, Dialect> {
    let components = XLQueryStatementComponents(select: select)
    return XLQuerySelectStatement(components: components)
}


// MARK: Update

///
/// Constructs an Update statement with a Set clause.
///
public func update<T, S>(_ table: T, set: S) -> XLUpdateSetStatement<T.Row, T.XLModelDialect> where T: XLMetaWritableTable, S: XLMetaUpdate, S.Row == T.Row {
    let components = XLUpdateStatementComponents(update: Update(table), components: [set])
    return XLUpdateSetStatement(components: components)
}

///
/// Constructs an Update statement.
///
public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row, T.XLModelDialect> where T: XLMetaWritableTable {
    let components = XLUpdateStatementComponents(update: Update(table))
    return XLUpdateTableStatement(components: components)
}


// MARK: Insert

///
/// Constructs an Insert statement.
///
public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row, T.XLModelDialect> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Insert(meta))
    return XLInsertTableStatement(components: components)
}


// MARK: Create

///
/// Constructs a Create statement.
///
public func create<T>(_ meta: T) -> XLCreateTableStatement<T.Table> where T: XLMetaCreate {
    let components = XLCreateTableStatementComponents(create: Create(meta))
    return XLCreateTableStatement(components: components)
}


// MARK: Delete

///
/// Constructs a Delete statement.
///
public func delete<T>(_ table: T) -> XLDeleteTableStatement<T, T.XLModelDialect> where T: XLMetaWritableTable, T.Row: XLTable {
    let components = XLDeleteStatementComponents(delete: Delete(table))
    return XLDeleteTableStatement(components: components)
}
