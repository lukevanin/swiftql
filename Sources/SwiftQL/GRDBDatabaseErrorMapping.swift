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
    /// `XLDatabaseError.underlying`.
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
        case SQLITE_INTERRUPT:
            self = .interrupted
        case SQLITE_ABORT:
            self = .aborted
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
}


///
/// Runs `body`, reporting a GRDB `DatabaseError` it throws as an
/// `XLDatabaseError`. Every other error passes through unchanged,
/// including the `CancellationError` GRDB throws for a cancelled task.
///
func xlMappingDatabaseErrors<Result>(
    driver: XLDriverIdentifier,
    _ body: () throws -> Result
) throws -> Result {
    do {
        return try body()
    }
    catch let error as DatabaseError {
        throw XLDatabaseError(error, driver: driver)
    }
}


///
/// Runs a scope that lends a connection to caller code, mapping only what
/// GRDB itself throws.
///
/// `body` runs the caller's code through the slot it is given. A scope maps
/// what GRDB throws around that code, such as a failing `BEGIN` or `COMMIT`,
/// but the caller's own error is the caller's: the driver contract rethrows
/// it as it was thrown, even when it happens to be a GRDB `DatabaseError`.
/// The error is kept beside the scope rather than wrapped, so no wrapper can
/// reach a caller.
///
/// The caller's code runs before this call returns, and this call's thread
/// waits for it: GRDB's synchronous accessors may run it on their own queue,
/// but only while this thread is blocked in `DispatchQueue.sync`, which
/// orders the slot's writes before its read. So the slot is a local: it
/// allocates nothing and takes no lock. A scope whose caller code could run
/// after its call returns must use the asynchronous form.
///
func xlMappingScopeErrors<Result>(
    driver: XLDriverIdentifier,
    _ body: (inout XLOperationErrorSlot) throws -> Result
) throws -> Result {
    var slot = XLOperationErrorSlot()
    do {
        return try body(&slot)
    }
    catch {
        throw xlMappedScopeError(error, operationError: slot.error, driver: driver)
    }
}


///
/// The asynchronous form of ``xlMappingScopeErrors(driver:_:)``.
///
/// GRDB runs the caller's code on its own executor, so the error is kept in
/// a locked `XLTransactionOperationError`, once per scope.
///
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
        throw xlMappedScopeError(error, operationError: operationError.recordedError, driver: driver)
    }
}


/// Where a synchronous scope keeps the error its caller's code threw.
struct XLOperationErrorSlot {

    /// The error the caller's code threw, or `nil` when it returned.
    private(set) var error: (any Error)?

    /// Runs the caller's code, keeping any error it throws before
    /// rethrowing it. Each run clears what an earlier run kept, as
    /// ``XLTransactionOperationError`` does.
    mutating func recording<Result>(_ operation: () throws -> Result) throws -> Result {
        error = nil
        do {
            return try operation()
        }
        catch {
            self.error = error
            throw error
        }
    }

    /// Keeps `error` as the one the caller's code threw.
    mutating func record(_ error: any Error) {
        self.error = error
    }
}


/// The error a scope reports when it threw `error`: the caller's own error
/// when its code threw one, otherwise `error`, as an `XLDatabaseError` when
/// it is a GRDB `DatabaseError`.
func xlMappedScopeError(
    _ error: any Error,
    operationError: (any Error)?,
    driver: XLDriverIdentifier
) -> any Error {
    if let operationError {
        return operationError
    }
    if let error = error as? DatabaseError {
        return XLDatabaseError(error, driver: driver)
    }
    return error
}
