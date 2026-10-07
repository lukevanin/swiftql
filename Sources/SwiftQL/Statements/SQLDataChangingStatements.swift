//
//  SQLDataChangingStatements.swift
//
//  Shared surface for the v1.4.4 data-changing statement features.
//

import Foundation


///
/// Constructs an `INSERT OR <action> INTO` statement.
///
public func insert<T>(_ meta: T, or action: XLInsertOrAction) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
    let components = XLInsertStatementComponents(insert: Insert(meta, or: action))
    return XLInsertTableStatement(components: components)
}


///
/// Constructs a `REPLACE INTO` statement.
///
public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
    let components = XLInsertStatementComponents(insert: Replace(meta).insert)
    return XLInsertTableStatement(components: components)
}


extension XLWithStatement where Dialect == XLSQLiteDialect {

    ///
    /// Constructs a `REPLACE INTO` statement scoped by the with clause's common
    /// table expressions.
    ///
    public func replace<T>(_ meta: T) -> XLInsertTableStatement<T.Row, XLSQLiteDialect> where T: XLMetaNamedResult, T.XLModelDialect == XLSQLiteDialect {
        XLInsertTableStatement(
            components: XLInsertStatementComponents(commonTables: commonTables, insert: Replace(meta).insert)
        )
    }
}


// MARK: - On Conflict (upsert)


///
/// An insert statement with a trailing `ON CONFLICT` upsert clause.
///
public struct XLInsertOnConflictStatement<Table, Dialect>: XLInsertStatement where Dialect: XLSQLDialect {

    public let components: XLInsertStatementComponents<Table>

    /// Creates the statement from components that belong to `Dialect`.
    @_spi(XLDialectSurface)
    public init(components: XLInsertStatementComponents<Table>) {
        self.components = components
    }
}


extension XLInsertTableValuesStatement where Table: XLTable, Table.XLModelDialect == Dialect {

    ///
    /// Appends an `ON CONFLICT` upsert clause to an inserted-values statement.
    ///
    public func onConflict(_ clause: OnConflict<Table>) -> XLInsertOnConflictStatement<Table, Dialect> {
        XLInsertOnConflictStatement(components: components.appending(clause))
    }
}


extension XLInsertTableValuesStatement where Table: XLTable, Table.XLModelDialect == Dialect {

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
    ) -> XLInsertOnConflictStatement<Table, Dialect> {
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
    ) -> XLInsertOnConflictStatement<Table, Dialect> {
        onConflict(
            OnConflict(targets: targets, resolution: .nothing)
        )
    }
}
