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
    case unsupportedTransactionKind(driver: XLDriverIdentifier, kind: XLTransactionKind)
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
        case .unsupportedTransactionKind(let driver, let kind):
            return "Driver \(driver) does not support \(kind) transactions."
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

    ///
    /// Takes one already-prepared physical statement and returns a
    /// value-level stepper that performs at most one additional SQLite step
    /// and value-normalization per call, returning `nil` once the underlying
    /// cursor is exhausted.
    ///
    /// Both exhaustion and a thrown step error are terminal: once the
    /// returned closure has returned `nil` or thrown once, every later call
    /// must keep returning `nil` rather than stepping the cursor again.
    ///
    /// This is the pull-based counterpart to `forEachRow(_:_:)`: a caller
    /// outside the connection access (``XLResultSet/next()``) needs to step
    /// exactly one row per call from code that already ran and returned,
    /// which a callback invoked once per row cannot express. The returned
    /// closure remains valid only for the lifetime of the connection access
    /// that produced it; implementations must not let the physical cursor it
    /// closes over survive that access, and callers must stop invoking the
    /// closure (and release every reference to it) no later than when that
    /// access returns.
    ///
    mutating func makeValuesStepper(
        _ statement: PhysicalStatement
    ) throws -> () throws -> [Dialect.Value]?
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


/// How a transaction acquires its locks when it begins.
///
/// The three kinds are SQLite's, and they describe *when* a transaction claims
/// the right to write, not an isolation level:
///
/// - ``deferred`` claims nothing at `BEGIN`. The first read takes a read lock
///   and the first write upgrades it, which can fail with a busy error if
///   another writer got there first.
/// - ``immediate`` claims the right to write at `BEGIN`, so a conflict with
///   another writer surfaces at `BEGIN` rather than partway through the
///   transaction. This is the default.
/// - ``exclusive`` also keeps readers out where the journal mode allows it.
///   Under WAL it behaves like ``immediate``.
///
/// A kind is a value rather than a closed enum so a driver for another
/// database can describe its own. A driver that cannot honour a kind throws
/// ``XLDatabaseContractError/unsupportedTransactionKind(driver:kind:)`` before
/// it lends a connection.
public struct XLTransactionKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let deferred = XLTransactionKind(rawValue: "deferred")

    public static let immediate = XLTransactionKind(rawValue: "immediate")

    public static let exclusive = XLTransactionKind(rawValue: "exclusive")

    public var description: String {
        rawValue
    }
}


/// A database or pool that lends connection-owned execution contexts.
///
/// The driver contract is "async scope, synchronous cursor"
/// (`Research/AsyncDriverContractFeasibility.md`). Each scope method suspends
/// the caller until a connection is available, then runs `operation`
/// synchronously on it. `operation` cannot suspend, so a
/// ``XLDatabaseDriverConnection/PhysicalStatement`` or cursor it creates
/// cannot outlive the access that owns it. The connection primitives stay
/// synchronous for the same reason.
///
/// A driver is a `Sendable` value, and its scope methods do not mutate it.
/// One driver can be shared by any number of tasks; the driver, not the
/// caller, serializes access to each connection. `operation` is `@Sendable`
/// because the driver may run it on its own executor rather than the
/// caller's.
///
/// Every scope method checks for cancellation before it lends a connection,
/// and throws `CancellationError` without running `operation` when the
/// calling task is already cancelled. Once `operation` starts it runs to
/// completion.
public protocol XLDatabaseDriver: Sendable {

    associatedtype Dialect: XLSQLDialect

    associatedtype Connection: XLDatabaseDriverConnection where Connection.Dialect == Dialect

    var driverIdentifier: XLDriverIdentifier { get }

    var databaseIdentifier: XLDatabaseIdentifier { get }

    var dialect: Dialect { get }

    /// Runs `operation` on a connection that reads a consistent snapshot.
    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result

    /// Runs `operation` on the connection that writes, outside a transaction.
    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result

    /// Runs `operation` inside one transaction of the given kind, on the
    /// connection that writes.
    ///
    /// The transaction commits when `operation` returns, and rolls back when
    /// it throws. The error `operation` threw is rethrown unchanged.
    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result
}


extension XLDatabaseDriver {

    /// Runs `operation` inside one ``XLTransactionKind/immediate`` transaction.
    public func withTransaction<Result: Sendable>(
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result {
        try await withTransaction(.immediate, operation)
    }

    /// Wraps transport transaction failures while preserving structured errors.
    ///
    /// An error thrown by `operation`, a ``XLDatabaseContractError``, and a
    /// `CancellationError` are rethrown unchanged. Any other failure is
    /// reported as ``XLDatabaseContractError/transactionFailure(driver:message:)``.
    public func withValidatedTransaction<Result: Sendable>(
        _ kind: XLTransactionKind = .immediate,
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result {
        do {
            return try await withTransaction(kind) { connection in
                try XLTransactionOperationFailure.tagging {
                    try operation(&connection)
                }
            }
        }
        catch {
            throw XLTransactionOperationFailure.validatedTransactionError(
                error,
                driver: driverIdentifier
            )
        }
    }
}


/// Carries an error thrown by a transaction's own operation past the driver,
/// so ``XLDatabaseDriver/withValidatedTransaction(_:_:)`` can tell it apart
/// from a failure of the transaction itself.
///
/// The operation's error is wrapped rather than recorded in a captured
/// variable, because the operation is `@Sendable` and may run on another
/// executor. A driver that replaces the error it is given loses the tag, and
/// the replacement is then reported as a transaction failure, which is what
/// it is.
package struct XLTransactionOperationFailure: Error {

    package let underlying: any Error

    /// Runs `operation`, tagging any error it throws.
    package static func tagging<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        do {
            return try operation()
        }
        catch {
            throw XLTransactionOperationFailure(underlying: error)
        }
    }

    /// The error a validated transaction reports for `error`.
    package static func validatedTransactionError(
        _ error: any Error,
        driver: XLDriverIdentifier
    ) -> any Error {
        if let operationFailure = error as? XLTransactionOperationFailure {
            return operationFailure.underlying
        }
        if error is XLDatabaseContractError || error is CancellationError {
            return error
        }
        return XLDatabaseContractError.transactionFailure(
            driver: driver,
            message: String(describing: error)
        )
    }
}
