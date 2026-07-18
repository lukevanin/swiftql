import Foundation


/// Failures at the dialect, driver, physical-statement, or decoding boundary.
public enum XLDatabaseContractError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedDialectValue(
        dialect: XLDialectIdentifier,
        storageType: String
    )
    case driverMismatch(
        expectedDatabase: XLDatabaseIdentifier,
        actualDatabase: XLDatabaseIdentifier,
        driver: XLDriverIdentifier
    )
    case dialectMismatch(
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier
    )
    case capabilityMismatch(
        dialect: XLDialectIdentifier,
        required: XLDialectCapabilities,
        available: XLDialectCapabilities
    )
    case versionMismatch(
        dialect: XLDialectIdentifier,
        minimum: XLDialectVersion,
        actual: XLDialectVersion?
    )
    case prepareFailure(driver: XLDriverIdentifier, message: String)
    case bindFailure(driver: XLDriverIdentifier, key: XLBindingKey?, message: String)
    case executeFailure(driver: XLDriverIdentifier, message: String)
    case transactionFailure(driver: XLDriverIdentifier, message: String)
    case decodeFailure(dialect: XLDialectIdentifier, column: Int?, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDialectValue(let dialect, let storageType):
            return "Dialect \(dialect) does not support storage type \(storageType)."
        case .driverMismatch(let expectedDatabase, let actualDatabase, let driver):
            return "Statement for database \(expectedDatabase) cannot execute on \(driver) database \(actualDatabase)."
        case .dialectMismatch(let expected, let actual):
            return "Statement requires dialect \(expected), but the driver provides \(actual)."
        case .capabilityMismatch(let dialect, let required, let available):
            return "Dialect \(dialect) requires capabilities \(required.rawValue), but only \(available.rawValue) are available."
        case .versionMismatch(let dialect, let minimum, let actual):
            return "Dialect \(dialect) requires version \(minimum) or later, but provides \(actual?.description ?? "no version")."
        case .prepareFailure(let driver, let message):
            return "Driver \(driver) could not prepare the statement: \(message)"
        case .bindFailure(let driver, let key, let message):
            return "Driver \(driver) could not bind\(key.map { " \($0)" } ?? " a value"): \(message)"
        case .executeFailure(let driver, let message):
            return "Driver \(driver) could not execute the statement: \(message)"
        case .transactionFailure(let driver, let message):
            return "Driver \(driver) could not complete the transaction: \(message)"
        case .decodeFailure(let dialect, let column, let message):
            return "Dialect \(dialect) could not decode\(column.map { " column \($0)" } ?? " a value"): \(message)"
        }
    }
}


/// A physical connection that prepares and executes statements for one dialect.
///
/// `PhysicalStatement` is intentionally connection-owned and is not required to
/// be `Sendable`. A logical statement must be validated before preparation.
public protocol XLDatabaseDriverConnection {

    associatedtype Dialect: XLSQLDialect

    associatedtype PhysicalStatement

    var driverIdentifier: XLDriverIdentifier { get }

    var databaseIdentifier: XLDatabaseIdentifier { get }

    var dialect: Dialect { get }

    /// Creates a physical statement after the public wrapper has validated the
    /// logical database and dialect requirements.
    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> PhysicalStatement

    mutating func bind(
        _ value: Dialect.Value,
        to key: XLBindingKey,
        in statement: PhysicalStatement
    ) throws -> PhysicalStatement

    mutating func fetchAll(_ statement: PhysicalStatement) throws -> [[Dialect.Value]]

    mutating func fetchOne(_ statement: PhysicalStatement) throws -> [Dialect.Value]?

    mutating func execute(_ statement: PhysicalStatement) throws
}


/// Package-scoped control returned by one streamed-row callback.
///
/// The callback is synchronous so a driver cursor and its owning connection
/// cannot escape through this value.
package enum XLRowStreamControl: Sendable {
    case advance
    case stop
}


/// Package-internal incremental row execution for database-driver adapters.
///
/// This refines the public v1 connection contract without adding a new public
/// requirement. Implementations must keep the physical cursor inside the
/// current connection access, copy or normalize every value before advancing,
/// stop immediately when requested, and release cursor resources on return or
/// throw.
package protocol XLStreamingDatabaseDriverConnection:
    XLDatabaseDriverConnection
{
    mutating func forEachRow(
        _ statement: PhysicalStatement,
        _ body: ([Dialect.Value]) throws -> XLRowStreamControl
    ) throws
}


extension XLStreamingDatabaseDriverConnection {

    /// Compatibility collection layered over the incremental execution seam.
    package mutating func collectAllRows(
        _ statement: PhysicalStatement
    ) throws -> [[Dialect.Value]] {
        var rows: [[Dialect.Value]] = []
        try forEachRow(statement) { row in
            rows.append(row)
            return .advance
        }
        return rows
    }

    /// Compatibility first-row lookup that does not step later rows.
    package mutating func collectFirstRow(
        _ statement: PhysicalStatement
    ) throws -> [Dialect.Value]? {
        var first: [Dialect.Value]?
        try forEachRow(statement) { row in
            first = row
            return .stop
        }
        return first
    }
}


extension XLDatabaseDriverConnection {

    /// Rejects database and dialect requirement mismatches before preparation.
    public func validate(_ statement: XLLogicalPreparedStatement) throws {
        guard statement.databaseIdentifier == databaseIdentifier else {
            throw XLDatabaseContractError.driverMismatch(
                expectedDatabase: statement.databaseIdentifier,
                actualDatabase: databaseIdentifier,
                driver: driverIdentifier
            )
        }
        try statement.dialectRequirement.validate(dialect.descriptor)
    }

    /// Validates a logical statement before dispatching physical preparation.
    public mutating func prepare(
        _ statement: XLLogicalPreparedStatement
    ) throws -> PhysicalStatement {
        try validate(statement)
        return try preparePhysical(
            XLValidatedLogicalPreparedStatement(statement)
        )
    }

    /// Validates the logical statement, then creates a connection-owned statement.
    public mutating func prepareValidated(
        _ statement: XLLogicalPreparedStatement
    ) throws -> PhysicalStatement {
        try validate(statement)
        do {
            return try prepare(statement)
        }
        catch let error as XLDatabaseContractError {
            throw error
        }
        catch {
            throw XLDatabaseContractError.prepareFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }

    /// Binds one dialect value while preserving logical parameter context.
    public mutating func bindValidated(
        _ value: Dialect.Value,
        to key: XLBindingKey,
        in statement: PhysicalStatement
    ) throws -> PhysicalStatement {
        do {
            return try bind(value, to: key, in: statement)
        }
        catch let error as XLDatabaseContractError {
            throw error
        }
        catch {
            throw XLDatabaseContractError.bindFailure(
                driver: driverIdentifier,
                key: key,
                message: String(describing: error)
            )
        }
    }

    public mutating func fetchAllValidated(
        _ statement: PhysicalStatement
    ) throws -> [[Dialect.Value]] {
        do {
            return try fetchAll(statement)
        }
        catch let error as XLDatabaseContractError {
            throw error
        }
        catch {
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }

    public mutating func fetchOneValidated(
        _ statement: PhysicalStatement
    ) throws -> [Dialect.Value]? {
        do {
            return try fetchOne(statement)
        }
        catch let error as XLDatabaseContractError {
            throw error
        }
        catch {
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }

    public mutating func executeValidated(_ statement: PhysicalStatement) throws {
        do {
            try execute(statement)
        }
        catch let error as XLDatabaseContractError {
            throw error
        }
        catch {
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }
}


/// A database or pool that lends connection-owned execution contexts.
public protocol XLDatabaseDriver {

    associatedtype Dialect: XLSQLDialect

    associatedtype Connection: XLDatabaseDriverConnection where Connection.Dialect == Dialect

    var driverIdentifier: XLDriverIdentifier { get }

    var databaseIdentifier: XLDatabaseIdentifier { get }

    var dialect: Dialect { get }

    mutating func withReadConnection<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result

    mutating func withWriteConnection<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result

    mutating func withTransaction<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result
}


extension XLDatabaseDriver {

    /// Wraps transport transaction failures while preserving structured errors.
    public mutating func withValidatedTransaction<Result>(
        _ operation: (inout Connection) throws -> Result
    ) throws -> Result {
        var operationError: Error?
        do {
            return try withTransaction { connection in
                do {
                    return try operation(&connection)
                }
                catch {
                    operationError = error
                    throw error
                }
            }
        }
        catch {
            if let operationError {
                throw operationError
            }
            if let contractError = error as? XLDatabaseContractError {
                throw contractError
            }
            throw XLDatabaseContractError.transactionFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }
}
