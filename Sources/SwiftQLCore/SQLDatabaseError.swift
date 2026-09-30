//
//  SQLDatabaseError.swift
//  SwiftQLCore
//
//  Issue #679: what running a statement returns, and the portable error a
//  driver reports when the database refuses or fails a statement, so neither
//  a caller nor SwiftQL's own retry policy has to reach for a driver's types.
//

import Foundation


///
/// Whether a statement makes direct changes to the database, as the database
/// reports it.
///
/// For SQLite this is `sqlite3_stmt_readonly`. SQLite reports transaction
/// control (`BEGIN`, `COMMIT`, `SAVEPOINT`, `RELEASE`) and some maintenance
/// statements, such as `REINDEX`, `ATTACH`, and many `PRAGMA`s, as `.read`,
/// because they make no direct change to table content, even though a
/// `COMMIT` makes earlier writes permanent.
///
public enum XLStatementAccess: Hashable, Sendable {

    /// The database reports that the statement makes no direct change.
    case read

    /// The statement can change the database's content or schema.
    case write
}


///
/// What one execution of a statement did (issue #679).
///
/// It does not report an inserted row's id: SQLite offers no reliable way to
/// tell whether a statement set one. To learn a new row's id, add a
/// `RETURNING` clause to the insert and fetch it.
///
public struct XLExecutionResult: Hashable, Sendable {

    /// The rows the statement itself inserted, updated, or deleted.
    ///
    /// Rows changed by triggers are not counted, and neither are rows a view's
    /// `INSTEAD OF` trigger changes. A statement that changes no rows, such as
    /// `CREATE TABLE`, reports zero.
    ///
    /// The GRDB driver reads the count when the statement returns. A
    /// statement run outside a transaction commits as it finishes, and GRDB
    /// calls its transaction observers' `databaseDidCommit` before it
    /// returns, so a write made there is counted instead. SwiftQL's own
    /// requests execute inside a transaction and are not affected.
    public let rowsAffected: Int

    /// Whether the statement makes direct changes to the database, as
    /// ``XLStatementAccess`` describes.
    public let access: XLStatementAccess

    public init(
        rowsAffected: Int,
        access: XLStatementAccess
    ) {
        self.rowsAffected = rowsAffected
        self.access = access
    }
}


///
/// The portable category of a database failure (issue #679).
///
/// A driver maps its native result code to one of these, so a caller or a
/// retry policy can classify a failure without the driver's own error type.
/// ``XLDatabaseError/nativeCode`` keeps the exact code.
///
public enum XLDatabaseErrorCode: Hashable, Sendable {

    /// Another connection holds a lock the statement needs. Retrying later
    /// can succeed.
    case busy

    /// A lock inside the same connection or shared cache conflicts.
    case locked

    /// A constraint failed: `UNIQUE`, `NOT NULL`, `CHECK`, `FOREIGN KEY`, or
    /// a primary key.
    case constraint

    /// The database, or the connection, is read-only.
    case readOnly

    /// The statement was interrupted, for example because the database was
    /// interrupted or suspended.
    case interrupted

    /// The statement's transaction was rolled back before it finished: by a
    /// conflict clause such as `OR ROLLBACK`, by a trigger's
    /// `RAISE(ROLLBACK, ...)`, or after an interruption ended it. SQLite
    /// reports this as `SQLITE_ABORT`.
    case aborted

    /// The database or its disk is full.
    case full

    /// The database file is corrupt.
    case corrupt

    /// The operating system reported an I/O error.
    case ioError

    /// The file is not a database.
    case notADatabase

    /// A string, blob, or row is larger than the database allows.
    case tooBig

    /// The driver was used in a way its database library does not allow.
    case misuse

    /// Any other failure, such as a syntax error or a missing table.
    case other
}


///
/// A failure the database reported while preparing, running, or committing a
/// statement (issue #679).
///
/// Drivers throw this instead of their own error type, so
/// `catch let error as XLDatabaseError where error.code == .constraint`
/// works whichever driver runs the statement. ``underlying`` keeps the
/// driver's original error for diagnostics.
///
public struct XLDatabaseError: Error, LocalizedError, CustomStringConvertible {

    /// The portable category of the failure.
    public let code: XLDatabaseErrorCode

    /// The driver's own code for the failure. For SQLite, this is the
    /// extended result code, such as `SQLITE_CONSTRAINT_UNIQUE` (2067).
    public let nativeCode: Int32

    /// The database's message, when it gave one.
    public let message: String?

    /// The SQL of the statement that failed, when there was one.
    public let sql: String?

    /// The driver that reported the failure.
    public let driver: XLDriverIdentifier

    /// The driver's original error.
    public let underlying: any Error

    public init(
        code: XLDatabaseErrorCode,
        nativeCode: Int32,
        message: String?,
        sql: String?,
        driver: XLDriverIdentifier,
        underlying: any Error
    ) {
        self.code = code
        self.nativeCode = nativeCode
        self.message = message
        self.sql = sql
        self.driver = driver
        self.underlying = underlying
    }

    public var description: String {
        var text = "Driver \(driver) reported \(code) (code \(nativeCode))"
        if let message {
            text += ": \(message)"
        }
        if let sql {
            text += " - while executing `\(sql)`"
        }
        return text
    }

    public var errorDescription: String? {
        description
    }
}
