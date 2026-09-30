//
//  GRDBDatabaseErrorMapping.swift
//  SwiftQL
//
//  Issue #679: the GRDB driver reports a database failure as the portable
//  `XLDatabaseError`, never as GRDB's `DatabaseError`. The connection maps
//  what its statements throw, and the driver's scopes map what GRDB throws
//  around them, such as a `BEGIN` or `COMMIT` that fails.
//

import Foundation
import GRDB
import GRDBSQLite


extension XLDriverIdentifier {

    /// The GRDB driver's identifier.
    static let grdb = XLDriverIdentifier(rawValue: "grdb")
}


extension XLDatabaseError {

    /// The portable form of a GRDB database error, keeping the original as
    /// ``XLDatabaseError/underlying``.
    init(_ error: DatabaseError, driver: XLDriverIdentifier) {
        self.init(
            code: XLDatabaseErrorCode(sqlitePrimaryResultCode: error.resultCode.rawValue),
            nativeCode: error.extendedResultCode.rawValue,
            message: error.message,
            sql: error.sql,
            driver: driver,
            underlying: error
        )
    }
}


extension XLDatabaseErrorCode {

    /// The portable category of a SQLite primary result code.
    init(sqlitePrimaryResultCode code: Int32) {
        switch code {
        case SQLITE_BUSY:
            self = .busy
        case SQLITE_LOCKED:
            self = .locked
        case SQLITE_CONSTRAINT:
            self = .constraint
        case SQLITE_READONLY:
            self = .readOnly
        case SQLITE_INTERRUPT, SQLITE_ABORT:
            // GRDB treats both as an interruption: `SQLITE_ABORT` is what a
            // statement or `COMMIT` reports when `interrupt()` or a suspended
            // database rolls its transaction back.
            self = .interrupted
        case SQLITE_FULL:
            self = .full
        case SQLITE_CORRUPT:
            self = .corrupt
        case SQLITE_IOERR:
            self = .ioError
        case SQLITE_NOTADB:
            self = .notADatabase
        case SQLITE_TOOBIG:
            self = .tooBig
        case SQLITE_MISUSE:
            self = .misuse
        default:
            self = .other
        }
    }

    ///
    /// The portable category of `error` when it is a database failure: an
    /// ``XLDatabaseError``, or a GRDB `DatabaseError` classified as the driver
    /// would map it.
    ///
    static func of(_ error: any Error) -> XLDatabaseErrorCode? {
        if let error = error as? XLDatabaseError {
            return error.code
        }
        if let error = error as? DatabaseError {
            return XLDatabaseErrorCode(sqlitePrimaryResultCode: error.resultCode.rawValue)
        }
        return nil
    }
}


///
/// Runs `body`, reporting a GRDB `DatabaseError` it throws as an
/// ``XLDatabaseError``. Every other error passes through unchanged,
/// including the `CancellationError` GRDB throws for a cancelled task.
///
func xlMappingDatabaseErrors<Result>(
    driver: XLDriverIdentifier,
    _ body: () throws -> Result
) throws -> Result {
    try xlMappingScopeErrors(driver: driver) { _ in try body() }
}


///
/// Runs a scope that lends a connection to caller code, mapping only what
/// GRDB itself throws.
///
/// `body` runs the caller's code through the recorder it is given. A scope
/// maps what GRDB throws around that code, such as a failing `BEGIN` or
/// `COMMIT`, but the caller's own error is the caller's: the driver contract
/// rethrows it as it was thrown, even when it happens to be a GRDB
/// `DatabaseError`. The error is recorded beside the scope rather than
/// wrapped, as ``XLTransactionOperationError`` documents, so no wrapper can
/// reach a caller.
///
func xlMappingScopeErrors<Result>(
    driver: XLDriverIdentifier,
    _ body: (XLTransactionOperationError) throws -> Result
) throws -> Result {
    let operationError = XLTransactionOperationError()
    do {
        return try body(operationError)
    }
    catch {
        throw operationError.mappedError(for: error, driver: driver)
    }
}


/// The asynchronous form of ``xlMappingScopeErrors(driver:_:)``.
func xlMappingScopeErrors<Result: Sendable>(
    driver: XLDriverIdentifier,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (XLTransactionOperationError) async throws -> Result
) async throws -> Result {
    let operationError = XLTransactionOperationError()
    do {
        return try await body(operationError)
    }
    catch {
        throw operationError.mappedError(for: error, driver: driver)
    }
}


extension XLTransactionOperationError {

    /// The error a scope reports when it threw `error`: the caller's own
    /// error when its code threw one, otherwise `error`, as an
    /// ``XLDatabaseError`` when it is a GRDB `DatabaseError`.
    func mappedError(for error: any Error, driver: XLDriverIdentifier) -> any Error {
        if let recorded = recordedError {
            return recorded
        }
        if let error = error as? DatabaseError {
            return XLDatabaseError(error, driver: driver)
        }
        return error
    }
}
