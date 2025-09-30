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


#warning("TODO: Implement UPSERT (UPDATE OR INSERT)")


// MARK: With (common table expression)


public struct XLSchema {
    
    let commonTableNamespace = XLNamespace.common()

    let tableNamespace = XLNamespace.table()

    let parameterNamespace = XLNamespace.parameter()

    public init() {
        
    }
    
    public func binding<T>(of type: T.Type, as alias: XLName? = nil) -> XLNamedBindingReference<T> where T: XLLiteral {
        XLNamedBindingReference(name: parameterNamespace.makeAlias(alias: alias))
    }

    public func commonTable<T>(alias: XLName? = nil, statement: any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLTable {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let dependency = XLCommonTableDependency(alias: alias, statement: statement)
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
    
    public func commonTable<T>(alias: XLName? = nil, statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaCommonTable where T: XLResult {
        let alias = commonTableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLCommonTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLCommonTable(namespace: commonTableNamespace, dependency: dependency)
    }
    
    ///
    /// Note: Recursive common table requires heap allocation.
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
    /// Note: Recursive common table requires heap allocation.
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
    
    #warning("TODO: Add support for common table expression returning a raw (not wrapped) scalar value")

    public func table<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    public func table<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNamedResult where T: XLMetaCommonTable, T.Result: XLResult {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromCommonTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    public func nullableTable<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaNullableNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    #warning("TODO: Implement scalar method to create an XLExpression from a common table that returns a scalar value")

    public func nullableTable<T>(_ commonTable: T, as alias: XLName? = nil) -> T.Result.MetaNullableNamedResult where T: XLMetaCommonTable, T.Result: XLResult {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromCommonTableDependency(commonTable: commonTable.definition, alias: alias)
        return T.Result.makeSQLAnonymousNullableNamedResult(namespace: tableNamespace, dependency: dependency)
    }
    
    public func into<T>(_ table: T.Type, as alias: XLName? = nil) -> T.MetaWritableTable where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let dependency = XLFromTableDependency(qualifiedName: T.sqlTableName(), alias: alias)
        return T.makeSQLInsert(namespace: tableNamespace, dependency: dependency)
    }
    
    public func from<T>(as alias: XLName? = nil, statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNamedResult where T: XLTable {
        let alias = tableNamespace.makeAlias(alias: alias)
        let schema = XLSchema()
        let dependency = XLUpdateFromTableDependency(alias: alias, statement: statement(schema))
        return T.makeSQLAnonymousNamedResult(namespace: tableNamespace, dependency: dependency)
    }

    public func create<T>(_ table: T.Type) -> T.MetaCreate where T: XLTable {
        return T.makeSQLCreate()
    }
}



// MARK: With


public func with(_ commonTables: any XLMetaCommonTable...) -> XLWithStatement {
    XLWithStatement(commonTables.map { $0.definition })
}



// MARK: Result


#warning("TODO: Combine result and SQLReader into single method ")

public func result<T>(_ builder: () -> T) -> T.Row.MetaResult where T: XLRowReadable, T.Row: XLResult {
    let newNamespace = XLNamespace.table()
    let dependency = XLSelectResultDependency()
    let iterator = builder()
    return T.Row.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency, iterator: iterator.readRow)
}


public func result<T>(_ iterator: @escaping (XLRowReader) -> T) -> T.MetaResult where T: XLResult {
    let newNamespace = XLNamespace.table()
    let dependency = XLSelectResultDependency()
    return T.makeSQLAnonymousResult(namespace: newNamespace, dependency: dependency, iterator: iterator)
}


// MARK: Subquery


public func subquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLQueryStatement<T>) -> T.MetaNamedResult where T: XLResult {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.makeSQLAnonymousNamedResult(namespace: newNamespace, dependency: dependency)
}


public func subquery<T>(alias: XLName? = nil, _ statement: (XLSchema) -> any XLQueryStatement<T>) -> T.Basis.MetaNullableNamedResult where T: XLMetaNullable, T.Basis: XLResult {
    let newNamespace = XLNamespace.table()
    let schema = XLSchema()
    let alias = newNamespace.makeAlias(alias: alias)
    let dependency = XLSubqueryDependency(alias: alias, statement: statement(schema))
    return T.Basis.makeSQLAnonymousNullableNamedResult(namespace: newNamespace, dependency: dependency)
}


public func subquery<T>(_ statement: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    let schema = XLSchema()
    return XLSubquery(statement: statement(schema))
}


public func subquery<T>(_ statement: () -> any XLQueryStatement<T>) -> some XLExpression<Optional<T>> where T: XLLiteral {
    return XLSubquery(statement: statement())
}


// MARK: Select

public func select<T>(_ result: T) -> XLQuerySelectStatement<T.Row> where T: XLRowReadable {
    makeQuery(select: Select(result))
}


public func select<T>(_ expression: any XLExpression<T>) -> XLQuerySelectStatement<T> where T: XLExpression & XLLiteral {
    makeQuery(select: Select(expression))
}


private func makeQuery<T>(select: Select<T>) -> XLQuerySelectStatement<T> {
    let components = XLQueryStatementComponents(select: select)
    return XLQuerySelectStatement(components: components)
}


// MARK: Update

public func update<T, S>(_ table: T, set: S) -> XLUpdateSetStatement<T.Row> where T: XLMetaWritableTable, S: XLMetaUpdate, S.Row == T.Row {
    let components = XLUpdateStatementComponents(update: Update(table), components: [set])
    return XLUpdateSetStatement(components: components)
}

public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row> where T: XLMetaWritableTable {
    let components = XLUpdateStatementComponents(update: Update(table))
    return XLUpdateTableStatement(components: components)
}


// MARK: Insert

public func insert<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Insert(meta))
    return XLInsertTableStatement(components: components)
}


// MARK: Create

public func create<T>(_ meta: T) -> XLCreateTableStatement<T.Table> where T: XLMetaCreate {
    let components = XLCreateTableStatementComponents(create: Create(meta))
    return XLCreateTableStatement(components: components)
}


// MARK: Delete

public func delete<T>(_ table: T) -> XLDeleteTableStatement<T> where T: XLMetaWritableTable, T.Row: XLTable {
    let components = XLDeleteStatementComponents(delete: Delete(table))
    return XLDeleteTableStatement(components: components)
}




