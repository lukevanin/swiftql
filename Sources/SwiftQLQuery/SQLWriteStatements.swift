//
//  SQLWriteStatements.swift
//  SwiftQL
//
//  Statements that change the database: UPDATE and its SET clause, INSERT and
//  REPLACE with their conflict handling, VALUES, CREATE TABLE, and DELETE.
//
//  Split out of SQLStatements.swift (issue #559). Named for what these
//  statements do rather than for the v1.4.4 milestone they arrived in, so as
//  not to collide with Statements/SQLDataChangingStatements.swift.
//
//  A write clause belongs to the dialect of the model it writes, so a
//  statement's result builder takes it only in that dialect (issue #822).
//

import Foundation


// MARK: - Update

///
/// Update statement.
///
public struct Update<Row>: XLEncodable, XLRowWritable {
    
    private let table: any XLEncodable
    
    public init<T>(_ table: T) where T: XLMetaWritableTable, T.Row == Row {
        self.table = table._table
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("UPDATE", expression: table.makeSQL)
    }
}


// MARK: - Set


///
/// Setting clause.
///
/// Specifies the values for specific columns in an update statement.
///
public struct Setting<Row>: XLEncodable {
    
    private let values: any XLEncodable
    
    public init(_ values: (inout Row.MetaUpdate) -> Void) where Row: XLTable {
        var meta = Row.MetaUpdate()
        values(&meta)
        self.values = meta
    }

    /// Infers `Row` from `table`, instead of restating it as an explicit
    /// generic argument (`Setting<Row>`). Swift cannot infer `Row` from the
    /// closure alone here — `Row.MetaUpdate` is a dependent associated type,
    /// and a `Setting { ... }` statement is type-checked before an earlier
    /// `Update(_:)` statement's own `Row` can flow across a result-builder
    /// statement boundary — so `table` stands in as the concrete witness.
    /// This initializer only infers from `table`; it does not verify that
    /// `table` is the same reference passed to the enclosing `Update(_:)`,
    /// though callers typically pass the same one.
    public init<T>(_ table: T, _ values: (inout Row.MetaUpdate) -> Void) where T: XLMetaWritableTable, T.Row == Row, Row: XLTable {
        _ = table // Only a type witness for inferring Row; never read.
        self.init(values)
    }

    public init<S>(_ values: S) where S: XLMetaUpdate, S.Row == Row {
        self.values = values
    }

    public func makeSQL(context: inout XLBuilder) {
        values.makeSQL(context: &context)
    }
}



// MARK: - Insert


///
/// Insert statement.
///
public struct Insert<Row>: XLEncodable, XLRowWritable {

    private let table: any XLEncodable

    private let target: XLInsertTarget

    package init(table: any XLEncodable, target: XLInsertTarget) {
        self.table = table
        self.target = target
    }

    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row {
        self.init(table: meta._dependency, target: .insert)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.insertTarget(target, table: table.makeSQL)
    }
}


// MARK: - On Conflict (upsert)


///
/// The action taken by an `ON CONFLICT` upsert clause when a candidate row
/// conflicts with an existing row.
///
public enum XLConflictResolution<Row> {

    ///
    /// Skip the conflicting candidate row without raising an error
    /// (`ON CONFLICT ... DO NOTHING`).
    ///
    case nothing

    ///
    /// Update the existing conflicting row (`ON CONFLICT ... DO UPDATE SET ...`),
    /// optionally constrained by a `WHERE` predicate that must hold for the
    /// update to apply.
    ///
    case update(Setting<Row>, filter: (any XLExpression)?)
}


///
/// On-conflict (upsert) clause.
///
/// Renders the SQLite `ON CONFLICT` clause that follows the values or select
/// source of an insert statement. A candidate row that conflicts with an
/// existing row on the named conflict target is either skipped
/// (``XLConflictResolution/nothing``) or updates the existing row
/// (``XLConflictResolution/update(_:filter:)``).
///
/// The conflict target is a list of column names identifying the uniqueness
/// constraint to resolve. SQLite requires unqualified column names here, so the
/// target is expressed with ``XLName`` values rather than qualified column
/// expressions. When computing updated values, the `excluded` pseudo table —
/// obtained through ``XLSchema/excluded(_:)`` — refers to the candidate row,
/// for example `row.value = excluded.value`.
///
public struct OnConflict<Row>: XLEncodable {

    private let targets: [XLName]

    private let resolution: XLConflictResolution<Row>

    internal init(
        targets: [XLName],
        resolution: XLConflictResolution<Row>
    ) {
        self.targets = targets
        self.resolution = resolution
    }

    ///
    /// Creates an `ON CONFLICT ... DO NOTHING` clause with an optional conflict
    /// target.
    ///
    public static func doNothing(on targets: XLName...) -> OnConflict {
        OnConflict(targets: targets, resolution: .nothing)
    }

    ///
    /// Creates an `ON CONFLICT (targets) DO UPDATE SET ...` clause.
    ///
    /// At least one conflict target is required: SQLite rejects `DO UPDATE`
    /// without a conflict target. Use ``doNothing(on:)`` for the targetless
    /// `ON CONFLICT DO NOTHING` form.
    ///
    public static func doUpdate(
        on firstTarget: XLName,
        _ otherTargets: XLName...,
        set values: @escaping (inout Row.MetaUpdate) -> Void
    ) -> OnConflict where Row: XLTable {
        OnConflict(
            targets: [firstTarget] + otherTargets,
            resolution: .update(Setting<Row>(values), filter: nil)
        )
    }

    ///
    /// Creates an `ON CONFLICT (targets) DO UPDATE SET ... WHERE ...` clause
    /// from a filter that belongs to the table's dialect. Used by the
    /// generated `doUpdate(on:_:set:where:)`, which takes only that dialect's
    /// expressions.
    ///
    @_spi(XLDialectSurface)
    public static func _dialectSurfaceDoUpdate(
        on targets: [XLName],
        set values: @escaping (inout Row.MetaUpdate) -> Void,
        where filter: any XLExpression
    ) -> OnConflict where Row: XLTable {
        OnConflict(
            targets: targets,
            resolution: .update(Setting<Row>(values), filter: filter)
        )
    }

    public func makeSQL(context: inout XLBuilder) {
        if targets.isEmpty {
            context.unaryOperator("ON CONFLICT") { _ in }
        }
        else {
            context.unaryPrefix("ON CONFLICT") { context in
                context.parenthesis { context in
                    context.list(separator: .list) { list in
                        for target in targets {
                            list.listItem { item in
                                item.name(target)
                            }
                        }
                    }
                }
            }
        }
        switch resolution {
        case .nothing:
            context.unaryOperator("DO NOTHING") { _ in }
        case .update(let setting, let filter):
            context.unaryPrefix("DO UPDATE", expression: setting.makeSQL)
            if let filter {
                context.unaryPrefix("WHERE", expression: filter.makeSQL)
            }
        }
    }
}


// MARK: - Values


///
/// Values clause.
///
/// Specifies the values for columns for an insert clause.
///
public struct Values<Row> {
    
    internal let values: any XLEncodable
    
    public init<M>(_ values: M) where M: XLMetaInsert, M.Row == Row {
        self.values = values
    }
    
    public init(_ values: Row) where Row: XLTable, Row.MetaInsert.Row == Row {
        self.values = Row.MetaInsert(values)
    }
}


// MARK: - Create


///
/// Create statement.
///
public struct Create<Table>: XLEncodable {
    
    private let meta: any XLEncodable
    
    public init<T>(_ meta: T) where T: XLMetaCreate, T.Table == Table {
        self.meta = meta
    }
    
    public func makeSQL(context: inout XLBuilder) {
        meta.makeSQL(context: &context)
    }
}


// MARK: - As


///
/// As clause.
///
/// Specifies a query to use to populate a table in a create statement.
///
public struct As<Table> {
    
    internal let queryStatement: any XLEncodable

    ///
    /// Populates a table from a query already built. SQLite's spelling of
    /// `As`, in SwiftQLSQLite, builds the query in its schema and calls this.
    /// Another dialect uses `init(dialect:builder:)`.
    ///
    package init(queryStatement: any XLEncodable) {
        self.queryStatement = queryStatement
    }

    ///
    /// Populates a table of `dialect` from a query in that dialect.
    ///
    /// The SQLite form infers the table from the query. Naming the dialect
    /// gives the builder's schema its type before the query is read, which
    /// the table's own dialect cannot do inside a result builder (issue
    /// #789).
    ///
    public init<Dialect>(dialect: Dialect.Type, @XLDialectQueryExpressionBuilder<Dialect> builder: (XLSchema<Dialect>) -> some XLDialectQueryStatement<Table, Dialect>) where Table: XLTable, Table.XLModelDialect == Dialect {
        let schema = XLSchema(dialect: dialect)
        self.queryStatement = builder(schema)
    }
}


// MARK: - Delete


///
/// Delete statement.
///
public struct Delete<Table>: XLEncodable {
    
    internal let name: any XLEncodable
    
    public init(_ table: Table) where Table: XLMetaWritableTable, Table.Row: XLTable {
        name = table._table
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("DELETE FROM") { builder in
            name.makeSQL(context: &builder)
        }
    }
}


// MARK: - Dialect


// A write clause names the model it writes, and the model names its dialect.

extension Update: XLDialectClause where Row: XLTable {
    public typealias Dialect = Row.XLModelDialect
}

extension Setting: XLDialectClause where Row: XLTable {
    public typealias Dialect = Row.XLModelDialect
}

extension Insert: XLDialectClause where Row: XLTable {
    public typealias Dialect = Row.XLModelDialect
}

extension Values: XLDialectClause where Row: XLTable {
    public typealias Dialect = Row.XLModelDialect
}

extension Delete: XLDialectClause where Table: XLMetaWritableTable {
    public typealias Dialect = Table.XLModelDialect
}
