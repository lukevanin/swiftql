//
//  SQLDataChangingStatements.swift
//
//  Shared surface for the v1.4.4 data-changing statement features: insert
//  conflict handling (`ON CONFLICT`), and `RETURNING` clauses on insert,
//  update, and delete statements.
//

import Foundation


// MARK: - Returning


///
/// A data-changing statement that returns rows through a `RETURNING` clause.
///
/// A returning statement is both encodable and row-readable, so it executes
/// through the row-returning request path rather than the plain write path.
///
public protocol XLReturningStatement<Row>: XLEncodable, XLRowReadable {
    associatedtype Row
}


///
/// A data-changing statement (`INSERT`, `UPDATE`, or `DELETE`) extended with a
/// `RETURNING` clause.
///
/// The base statement renders its complete SQL, then the returning clause
/// appends `RETURNING <columns>`. Rows are decoded with the returning clause's
/// reader.
///
public struct XLReturningStatementOf<Row>: XLReturningStatement {

    private let base: any XLEncodable

    private let returning: Returning<Row>

    internal init(base: any XLEncodable, returning: Returning<Row>) {
        self.base = base
        self.returning = returning
    }

    public func makeSQL(context: inout XLBuilder) {
        base.makeSQL(context: &context)
        returning.makeSQL(context: &context)
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try returning.readRow(reader: reader)
    }
}


extension XLInsertStatement {

    ///
    /// Appends a `RETURNING` clause that returns a column set for every inserted
    /// row.
    ///
    public func returning<T>(_ result: T) -> XLReturningStatementOf<T.Row> where T: XLRowReadable {
        XLReturningStatementOf(base: self, returning: Returning(result))
    }

    ///
    /// Appends a `RETURNING` clause that returns a scalar value for every
    /// inserted row.
    ///
    public func returning<T>(_ expression: any XLExpression<T>) -> XLReturningStatementOf<T> {
        XLReturningStatementOf(base: self, returning: Returning(expression))
    }
}


extension XLUpdateStatement {

    ///
    /// Appends a `RETURNING` clause that returns a column set for every updated
    /// row.
    ///
    public func returning<T>(_ result: T) -> XLReturningStatementOf<T.Row> where T: XLRowReadable {
        XLReturningStatementOf(base: self, returning: Returning(result))
    }

    ///
    /// Appends a `RETURNING` clause that returns a scalar value for every
    /// updated row.
    ///
    public func returning<T>(_ expression: any XLExpression<T>) -> XLReturningStatementOf<T> {
        XLReturningStatementOf(base: self, returning: Returning(expression))
    }
}


extension XLDeleteStatement {

    ///
    /// Appends a `RETURNING` clause that returns a column set for every deleted
    /// row.
    ///
    public func returning<T>(_ result: T) -> XLReturningStatementOf<T.Row> where T: XLRowReadable {
        XLReturningStatementOf(base: self, returning: Returning(result))
    }

    ///
    /// Appends a `RETURNING` clause that returns a scalar value for every
    /// deleted row.
    ///
    public func returning<T>(_ expression: any XLExpression<T>) -> XLReturningStatementOf<T> {
        XLReturningStatementOf(base: self, returning: Returning(expression))
    }
}


// MARK: - On Conflict (upsert)


///
/// An insert statement with a trailing `ON CONFLICT` upsert clause.
///
public struct XLInsertOnConflictStatement<Table>: XLInsertStatement {

    public let components: XLInsertStatementComponents<Table>
}


extension XLInsertTableValuesStatement {

    ///
    /// Appends an `ON CONFLICT` upsert clause to an inserted-values statement.
    ///
    public func onConflict(_ clause: OnConflict<Table>) -> XLInsertOnConflictStatement<Table> {
        XLInsertOnConflictStatement(components: components.appending(clause))
    }
}


extension XLInsertTableValuesStatement where Table: XLTable {

    ///
    /// Appends an `ON CONFLICT (targets) DO UPDATE SET ...` upsert clause.
    ///
    /// At least one conflict target is required, because SQLite rejects
    /// `DO UPDATE` without a conflict target. Use ``onConflictDoNothing(_:)``
    /// for the targetless `ON CONFLICT DO NOTHING` form.
    ///
    public func onConflict(
        _ firstTarget: XLName,
        _ otherTargets: XLName...,
        doUpdate values: @escaping (inout Table.MetaUpdate) -> Void
    ) -> XLInsertOnConflictStatement<Table> {
        onConflict(
            OnConflict(
                targets: [firstTarget] + otherTargets,
                resolution: .update(Setting<Table>(values), filter: nil)
            )
        )
    }

    ///
    /// Appends an `ON CONFLICT (targets) DO NOTHING` upsert clause.
    ///
    public func onConflictDoNothing(
        _ targets: XLName...
    ) -> XLInsertOnConflictStatement<Table> {
        onConflict(
            OnConflict(targets: targets, resolution: .nothing)
        )
    }
}


// MARK: - Functional entry points


///
/// Constructs a `REPLACE INTO` statement.
///
public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Replace(meta).insert)
    return XLInsertTableStatement(components: components)
}


///
/// Constructs an `INSERT OR <action> INTO` statement.
///
public func insert<T>(_ meta: T, or action: XLInsertOrAction) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
    let components = XLInsertStatementComponents(insert: Insert(meta, or: action))
    return XLInsertTableStatement(components: components)
}


extension XLWithStatement {

    ///
    /// Constructs an `UPDATE` statement scoped by the with clause's common table
    /// expressions.
    ///
    public func update<T>(_ table: T) -> XLUpdateTableStatement<T.Row> where T: XLMetaWritableTable {
        XLUpdateTableStatement(
            components: XLUpdateStatementComponents(commonTables: commonTables, update: Update(table))
        )
    }

    ///
    /// Constructs a `REPLACE INTO` statement scoped by the with clause's common
    /// table expressions.
    ///
    public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row> where T: XLMetaNamedResult {
        XLInsertTableStatement(
            components: XLInsertStatementComponents(commonTables: commonTables, insert: Replace(meta).insert)
        )
    }
}
