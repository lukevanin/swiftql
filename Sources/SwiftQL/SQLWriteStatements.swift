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
/// A conflict-resolution algorithm applied by an `INSERT OR ...` statement.
///
/// SQLite parses the algorithm as part of the `INSERT` keyword, immediately
/// before `INTO`. `replace` is the same algorithm reached by the standalone
/// `REPLACE` statement.
///
public enum XLInsertOrAction: String, CaseIterable, Sendable {
    case rollback = "ROLLBACK"
    case abort = "ABORT"
    case fail = "FAIL"
    case ignore = "IGNORE"
    case replace = "REPLACE"
}


///
/// Insert statement.
///
public struct Insert<Row>: XLEncodable, XLRowWritable {

    private let table: any XLEncodable

    private let keyword: String

    internal init(table: any XLEncodable, keyword: String) {
        self.table = table
        self.keyword = keyword
    }

    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row {
        self.init(table: meta._dependency, keyword: "INSERT INTO")
    }

    ///
    /// Creates an insert statement with an `OR` conflict-resolution clause.
    ///
    /// Renders `INSERT OR <action> INTO`. The algorithm applies to every
    /// uniqueness constraint violated while the statement runs.
    ///
    public init<T>(_ meta: T, or action: XLInsertOrAction) where T: XLMetaNamedResult, T.Row == Row {
        self.init(table: meta._dependency, keyword: "INSERT OR \(action.rawValue) INTO")
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix(keyword, expression: table.makeSQL)
    }
}


///
/// Replace statement.
///
/// `REPLACE INTO` is the SQLite shorthand for `INSERT OR REPLACE INTO`. A row
/// that would violate a uniqueness constraint is deleted before the new row is
/// inserted.
///
public struct Replace<Row>: XLEncodable, XLRowWritable {

    internal let insert: Insert<Row>

    public init<T>(_ meta: T) where T: XLMetaNamedResult, T.Row == Row {
        self.insert = Insert(table: meta._dependency, keyword: "REPLACE INTO")
    }

    public func makeSQL(context: inout XLBuilder) {
        insert.makeSQL(context: &context)
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
    /// Creates an `ON CONFLICT (targets) DO UPDATE SET ... WHERE ...` clause.
    ///
    /// At least one conflict target is required, because SQLite rejects
    /// `DO UPDATE` without a conflict target. The `WHERE` predicate constrains
    /// which conflicting rows are updated; rows that fail the predicate are
    /// left unchanged without raising an error.
    ///
    public static func doUpdate<B>(
        on firstTarget: XLName,
        _ otherTargets: XLName...,
        set values: @escaping (inout Row.MetaUpdate) -> Void,
        where filter: any XLExpression<B>
    ) -> OnConflict where Row: XLTable, B: XLBoolean {
        OnConflict(
            targets: [firstTarget] + otherTargets,
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
    
    public init(@XLQueryExpressionBuilder builder: (XLSchema) -> some XLQueryStatement<Table>) where Table: XLTable {
        let schema = XLSchema()
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
