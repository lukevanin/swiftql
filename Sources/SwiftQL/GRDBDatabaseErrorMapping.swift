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
        case SQLITE_INTERRUPT:
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
    /// ``XLDatabaseError``, or a GRDB `DatabaseError` that GRDB raised outside
    /// a SwiftQL connection, such as while it starts an observation.
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
/// An error thrown by the operation a driver scope runs, carried through GRDB
/// so the scope rethrows it unchanged.
///
/// A scope maps only what GRDB itself throws, such as a failing `BEGIN`. An
/// operation's own error is the caller's, and the driver contract rethrows it
/// as it was thrown, even when it happens to be a GRDB `DatabaseError`.
///
struct GRDBOperationError: Error {
    let error: any Error
}


/// Runs a scope's operation, marking any error it throws as the operation's.
func xlMarkingOperationErrors<Result>(
    _ operation: () throws -> Result
) throws -> Result {
    do {
        return try operation()
    }
    catch {
        throw GRDBOperationError(error: error)
    }
}


///
/// Runs `body`, reporting a GRDB `DatabaseError` it throws as an
/// ``XLDatabaseError``. An error marked by
/// ``xlMarkingOperationErrors(_:)`` is rethrown as the operation threw it,
/// and every other error passes through unchanged, including the
/// `CancellationError` GRDB throws for a cancelled task.
///
func xlMappingDatabaseErrors<Result>(
    driver: XLDriverIdentifier,
    _ body: () throws -> Result
) throws -> Result {
    do {
        return try body()
    }
    catch let error as GRDBOperationError {
        throw error.error
    }
    catch let error as DatabaseError {
        throw XLDatabaseError(error, driver: driver)
    }
}


/// The asynchronous form of ``xlMappingDatabaseErrors(driver:_:)``.
func xlMappingDatabaseErrors<Result: Sendable>(
    driver: XLDriverIdentifier,
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> Result
) async throws -> Result {
    do {
        return try await body()
    }
    catch let error as GRDBOperationError {
        throw error.error
    }
    catch let error as DatabaseError {
        throw XLDatabaseError(error, driver: driver)
    }
}
