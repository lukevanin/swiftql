//
//  SQLDataChangingStatements.swift
//
//  Shared surface for the v1.4.4 data-changing statement features.
//

import Foundation


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
