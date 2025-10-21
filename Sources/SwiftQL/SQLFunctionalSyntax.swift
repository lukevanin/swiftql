//
//  XLQueryComposer.swift
//
//
//  Created by Luke Van In on 2023/08/16.
//

import Foundation


// e.g. From, Join
public protocol XLTableStatement: XLQueryComponent {
    
}

///
/// Returns a statement that selects rows matching the expression returned by the provided builder.
///
public func sqlQuery<Row>(builder: (XLSchema) -> some XLQueryStatement<Row>) -> any XLQueryStatement<Row> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that updates a row using the expression returned by the provided builder.
///
public func sqlUpdate<Row>(builder: (XLSchema) -> some XLUpdateStatement<Row>) -> any XLUpdateStatement<Row> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that inserts a row using the expression returned by the provided builder.
///
public func sqlInsert<Row>(builder: (XLSchema) -> some XLInsertStatement<Row>) -> any XLInsertStatement<Row> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that inserts a row into an `SQLTable`.
///
public func sqlInsert<Row>(_ row: Row) -> any XLInsertStatement where Row: XLTable, Row.MetaNamedResult.Row == Row, Row.MetaInsert.Row == Row {
    let schema = XLSchema()
    let table = schema.table(Row.self)
    return insert(table).values(Row.MetaInsert(row))
}


///
/// Returns a statement that creates a table using the expression returned by the provided builder.
///
public func sqlCreate<Row>(builder: (XLSchema) -> some XLCreateStatement<Row>) -> any XLCreateStatement<Row> {
    let schema = XLSchema()
    return builder(schema)
}


///
/// Returns a statement that creates a given `SQLTable`.
///
public func sqlCreate<T>(_ table: T.Type) -> any XLCreateStatement<T> where T: XLTable, T.MetaCreate.Table == T {
    let schema = XLSchema()
    let table = schema.create(T.self)
    return create(table)
}


// MARK: With (common table expression)


public struct XLSchema {
    
    let commonTableNamespace = XLNamespace.common()

    let tableNamespace = XLNamespace.table()

    let parameterNamespace = XLNamespace.parameter()

    public init() {
        
    }

    ///
    /// Constructs a named binding reference.
    ///
    /// > Tip: For most use cases this method is not needed and `XLNamedBindingReference` should
    /// be instantiated directly.
    ///
    public func binding<T>(of type: T.Type, as alias: XLName? = nil) -> XLNamedBindingReference<T> where T: XLLiteral {
        XLNamedBindingReference(name: parameterNamespace.makeAlias(alias: alias))
    }

    ///
    /// Constructs common table expression using a select query that returns an `SQLTable`.
    ///
    public func commonTable<T>(alias: XLName? = nil, statement: any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLTable {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let dependency = XLCommonTableDependency(alias: alias, statement: statement)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
    
    ///
    /// Constructs a common table expression with a select query that returns an `SQLResult`
    /// column set.
    ///
    public func commonTable<T>(alias: XLName? = nil, statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
    
    ///
    /// Constructs a recursive common table expression using a select query that returns
    /// an `SQLResult`.
    ///
    /// > Note: Recursive common table requires heap allocation.
    ///
    public func recursiveCommonTable<T>(_ type: T.Type, alias: XLName? = nil, statement: (XLSchema, T.MetaCommonTable.Result.MetaNamedResult) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let recursiveStatement = XLRecursiveCommonTableStatement()
        let dependency = XLCommonTableDependency(alias: alias, statement: recursiveStatement)
        let commonTable = T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
        let table = self.table(commonTable)
        recursiveStatement.statement = statement(schema, table)
        return commonTable
    }
    
    ///
    /// Constructs a recursive common table expression using a select query that returns an `SQLTable`.
    ///
    /// > Note: Recursive common table requires heap allocation.
    ///
    public func recursiveCommonTableExpression<T>(_ type: T.Type, alias: XLName? = nil, @XLQueryExpressionBuilder statement: (XLSchema, T.MetaCommonTable.Result.MetaNamedResult) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let recursiveStatement = XLRecursiveCommonTableStatement()
        let dependency = XLCommonTableDependency(alias: alias, statement: recursiveStatement)
        let commonTable = T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
        let table = self.table(commonTable)
        recursiveStatement.statement = statement(schema, table)
        return commonTable
    }
    
    ///
    /// Creates a reference to an `SQLTable`.
    ///
    public func table<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLResult`.
    ///
    public func table<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNamedResult where T: XLMetaCommonTable, T.Result: XLResult {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromCommonTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Creates a reference to an `SQLTable` that can resolve to `NULL`.
    ///
    public func nullableTable<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNullableNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLResult` that can resolve to `NULL`.
    ///
    public func nullableTable<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNullableNamedResult where T: XLMetaCommonTable, T.Result: XLResult {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromCommonTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLTable` that is the subject of a write operation.
    ///
    public func into<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaWritableTable where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLInsert(namespace: tableNamespace, dependency: dependency)
    }
    
    ///
    /// Creates a reference to an `SQLTable` that is used in a `From` clause in an `Insert` statement.
    ///
    public func from<T>(as alias: XLName? = nil, statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLUpdateFromTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    ///
    /// Creates a reference to a table that is used in a Create statement.
    ///
    public func create<T>(_ table: T.Type) -> T.MetaCreate where T: XLTable {
        return T.makeSQLCreate()
    }
}



// MARK: With


///
/// Specifies common table expressions used in a statement.
///
public func with(_ commonTables: any XLMetaCommonTable...) -> XLWithStatement {
    XLWithStatement(commonTables.map { $0.definition })
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


// MARK: Subquery

///
/// Constructs a subquery with a select query statement that returns a column set.
///
public func subquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNamedResult where T: XLResult {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNamedResult(namespace: newNamespace, dependency: dependency)
}


///
/// Constructs a subquery with a select query statement that returns a column set that can evaluate to NULL.
///
public func subquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLQueryStatement<T>) -> T.Basis.MetaNullableNamedResult where T: XLMetaNullable, T.Basis: XLResult {
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
public func subquery<T>(_ statement: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLSubquery(statement: statement(schema))
}


///
/// Constructs a subquery with a select query statement that returns a scalar value.
///
public func subquery<T>(_ statement: () -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    return XLSubquery(statement: statement())
}


// MARK: Select

///
/// Constructs a select statement that returns a column set.
///
public func select<T>(_ result: T) -> XLQuerySelectStatement<T.Row> where T: XLRowReadable {
    makeQuery(select: Select(result))
}


///
/// Constructs a select statement that returns a scalar value.
///
public func select<T>(_ expression: any XLExpression<T>) -> XLQuerySelectStatement<T> where T: XLExpression & XLLiteral {
    makeQuery(select: Select(expression))
}


///
/// Constructs a select statement using an explicit Select expression.
///
private func makeQuery<T>(select: Select<T>) -> XLQuerySelectStatement<T> {
    let components = XLQueryStatementComponents(select: select)
    return XLQuerySelectStatement(components: components)
}


// MARK: Update

///
/// Constructs an Update statement with a Set clause.
///
public func update<T, S>(_ table: T, set: S) -> XLUpdateSetStatement<T.Row> where T: XLMetaWritableTable, S: XLMetaUpdate, S.Row == T.Row {
    let components = XLUpdateStatementComponents(update: Update(table), components: [set])
    return XLUpdateSetStatement(components: components)
}

///
/// Constructs an Update statement.
///
public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row> where T: XLMetaWritableTable {
    let components = XLUpdateStatementComponents(update: Update(table))
    return XLUpdateTableStatement(components: components)
}


// MARK: Insert

///
/// Constructs an Insert statement.
///
public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
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
public func delete<T>(_ table: T) -> XLDeleteTableStatement<T> where T: XLMetaWritableTable, T.Row: XLTable {
    let components = XLDeleteStatementComponents(delete: Delete(table))
    return XLDeleteTableStatement(components: components)
}




