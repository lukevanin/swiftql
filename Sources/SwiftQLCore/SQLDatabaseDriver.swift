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

    /// Runs a statement that returns no rows, and reports what it did
    /// (issue #679).
    @discardableResult
    mutating func execute(_ statement: PhysicalStatement) throws -> XLExecutionResult

    /// Returns a statement that has run to its prepared state, so that it
    /// can be bound and run again on this connection (issue #677).
    ///
    /// SwiftQL calls this between two runs of one statement, such as the
    /// rows of a batch insert, and then binds every parameter again. The
    /// returned statement has no open cursor and no bound values.
    ///
    /// The default implementation returns `statement` unchanged, which is
    /// correct for a connection that resets a statement itself before it
    /// runs it.
    mutating func resetPhysical(_ statement: PhysicalStatement) throws -> PhysicalStatement

    /// Tells the connection that SwiftQL is done with a statement it
    /// prepared (issue #677).
    ///
    /// SwiftQL calls this once for every statement it prepares, on the
    /// connection access that prepared it, after the statement's last run,
    /// and also when binding or running it threw. The statement is not used
    /// again. A connection that caches statements returns it to its cache; a
    /// connection that does not releases it.
    ///
    /// Code outside SwiftQL that calls ``prepare(_:)`` may never call this,
    /// so a connection must still release a statement that is never
    /// finalized, at the latest when the access that prepared it ends.
    ///
    /// The default implementation does nothing, which is correct for a
    /// connection that releases a statement when its last reference goes.
    mutating func finalizePhysical(_ statement: PhysicalStatement)

    /// Makes each function a statement calls available on this connection
    /// before the statement is prepared (issue #683).
    ///
    /// ``prepare(_:)`` calls this with the statement's
    /// ``XLLogicalPreparedStatement/requiredFunctions``. The connection builds
    /// its own function object from each registration's
    /// ``XLCustomFunctionRegistration/makeEvaluator``. Whether a function is
    /// already on the connection is the connection's to decide: a
    /// registration that ``XLCustomFunctionRegistration/defersToExistingRegistration``
    /// keeps a function the connection already provides for its signature,
    /// and any other registration is installed so the statement calls it.
    /// Installing the same registration twice on one connection must be
    /// harmless.
    ///
    /// The default implementation installs nothing. The statement then
    /// prepares as it would have before this requirement existed: a function
    /// the connection already has, loaded as an extension or registered when
    /// it opened, resolves, and a missing one fails at preparation.
    mutating func installRequiredFunctions(
        _ functions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) throws

    /// Checks that every parameter of a bound statement has a value, before
    /// the statement runs (issue #682).
    ///
    /// SwiftQL calls this after binding a statement's whole invocation packet,
    /// and reports a failure as
    /// `XLInvocationBindingError.driverArgumentValidationFailed`. A connection
    /// whose database can tell missing or extra arguments apart from a failed
    /// execution checks them here. The default implementation checks nothing,
    /// so a missing argument surfaces when the statement runs.
    func validateBindings(in statement: PhysicalStatement) throws

    /// Visits a statement's result rows one at a time, stopping as soon as
    /// `body` returns ``XLRowStreamControl/stop`` (issue #682).
    ///
    /// The rows come from a cursor that belongs to this connection access.
    /// `body` runs synchronously, so the cursor cannot outlive the access, and
    /// it must consume, decode or copy each row before returning, because the
    /// connection may reuse a row's storage for the next one. The cursor's
    /// resources are released when this returns or throws.
    ///
    /// The default implementation fetches every row with ``fetchAll(_:)``,
    /// then visits them. A connection that can step a cursor overrides it, so
    /// a large result is never held in memory at once.
    mutating func forEachRow(
        _ statement: PhysicalStatement,
        _ body: ([Dialect.Value]) throws -> XLRowStreamControl
    ) throws

    /// Lends a stepper over a statement's result rows for the duration of
    /// `body` (issue #682).
    ///
    /// Each call to the stepper returns the next row, or `nil` once the rows
    /// are exhausted. Exhaustion and a thrown error are terminal: every later
    /// call returns `nil`. The stepper is valid only while `body` runs, so a
    /// cursor it steps never outlives this connection access, and `body` must
    /// not keep it.
    ///
    /// The default implementation fetches every row with ``fetchAll(_:)``,
    /// then steps through them. A connection that can step a cursor overrides
    /// it, so each call performs at most one database step.
    mutating func withValuesStepper<Result>(
        _ statement: PhysicalStatement,
        _ body: (@escaping () throws -> [Dialect.Value]?) throws -> Result
    ) throws -> Result
}


extension XLDatabaseDriverConnection {

    /// Installs nothing, so a connection written before this requirement
    /// keeps working: the functions a statement calls must already be on the
    /// connection, as they always had to be for it.
    public mutating func installRequiredFunctions(
        _ functions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) throws {}

    /// Checks nothing. A missing or extra argument surfaces when the
    /// statement runs.
    public func validateBindings(in statement: PhysicalStatement) throws {}

    /// Fetches every row with ``fetchAll(_:)``, then visits them until `body`
    /// stops.
    public mutating func forEachRow(
        _ statement: PhysicalStatement,
        _ body: ([Dialect.Value]) throws -> XLRowStreamControl
    ) throws {
        for row in try fetchAll(statement) {
            if try body(row) == .stop {
                return
            }
        }
    }

    /// Fetches every row with ``fetchAll(_:)``, then lends a stepper over
    /// them.
    public mutating func withValuesStepper<Result>(
        _ statement: PhysicalStatement,
        _ body: (@escaping () throws -> [Dialect.Value]?) throws -> Result
    ) throws -> Result {
        let rows = try fetchAll(statement)
        let stepper = XLEagerRowStepper(rows)
        return try body(stepper.next)
    }
}


/// Steps through rows already in memory, for the default
/// ``XLDatabaseDriverConnection/withValuesStepper(_:_:)``.
private final class XLEagerRowStepper<Value> {

    private var iterator: IndexingIterator<[[Value]]>

    init(_ rows: [[Value]]) {
        iterator = rows.makeIterator()
    }

    func next() -> [Value]? {
        iterator.next()
    }
}


/// What a row callback passed to
/// ``XLDatabaseDriverConnection/forEachRow(_:_:)`` asks for next.
public enum XLRowStreamControl: Sendable {

    /// Step to the next row.
    case advance

    /// Stop stepping. No later row is read.
    case stop
}


/// The `*Validated` helpers report a transport failure as a structured
/// ``XLDatabaseContractError``. An ``XLDatabaseError`` is already structured,
/// so it passes through unchanged, and so does a `CancellationError`: a
/// driver may interrupt a statement because its task was cancelled, and that
/// is not a failure of the statement.
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

    /// Validates a logical statement, installs the functions it calls, then
    /// dispatches physical preparation.
    public mutating func prepare(
        _ statement: XLLogicalPreparedStatement
    ) throws -> PhysicalStatement {
        try validate(statement)
        // SQLite resolves a function when it prepares a statement, so the
        // functions the statement calls go on the connection first.
        try installRequiredFunctions(statement.requiredFunctions)
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
        catch {
            if xlIsStructuredDriverError(error) {
                throw error
            }
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
        catch {
            if xlIsStructuredDriverError(error) {
                throw error
            }
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
        catch {
            if xlIsStructuredDriverError(error) {
                throw error
            }
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
        catch {
            if xlIsStructuredDriverError(error) {
                throw error
            }
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }

    @discardableResult
    public mutating func executeValidated(
        _ statement: PhysicalStatement
    ) throws -> XLExecutionResult {
        do {
            return try execute(statement)
        }
        catch {
            if xlIsStructuredDriverError(error) {
                throw error
            }
            throw XLDatabaseContractError.executeFailure(
                driver: driverIdentifier,
                message: String(describing: error)
            )
        }
    }
}


/// Whether `error` is already structured, so a validated helper rethrows it
/// unchanged rather than flattening it into a contract error's text: an
/// ``XLDatabaseContractError``, an ``XLDatabaseError``, or a
/// `CancellationError`.
func xlIsStructuredDriverError(_ error: any Error) -> Bool {
    error is XLDatabaseContractError
        || error is XLDatabaseError
        || error is CancellationError
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
///   transaction. The GRDB driver uses it by default.
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
/// calling task is already cancelled. A driver may also interrupt
/// `operation` when the task is cancelled while it runs: the statement in
/// progress, or the next one, then throws, and a transaction rolls back. The
/// GRDB adapter does this. Code outside the database that `operation` updates
/// must not assume every statement in it ran.
public protocol XLDatabaseDriver: Sendable {

    associatedtype Dialect: XLSQLDialect

    associatedtype Connection: XLDatabaseDriverConnection where Connection.Dialect == Dialect

    var driverIdentifier: XLDriverIdentifier { get }

    var databaseIdentifier: XLDatabaseIdentifier { get }

    var dialect: Dialect { get }

    /// The kind ``withTransaction(_:)`` uses when the caller names none.
    ///
    /// Each driver chooses its own, because the kinds a database honours are
    /// the database's: SQLite's ``XLTransactionKind/immediate`` means nothing
    /// to a server database. It must be a kind the driver honours.
    var defaultTransactionKind: XLTransactionKind { get }

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

    /// Runs `operation` inside one transaction of the driver's
    /// ``defaultTransactionKind``.
    public func withTransaction<Result: Sendable>(
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result {
        try await withTransaction(defaultTransactionKind, operation)
    }

    /// Wraps transport transaction failures while preserving structured errors.
    ///
    /// An error thrown by `operation`, a ``XLDatabaseContractError``, an
    /// ``XLDatabaseError``, a `CancellationError`, and a driver's own typed
    /// refusal to lend a connection are rethrown unchanged. Any other failure is reported as
    /// ``XLDatabaseContractError/transactionFailure(driver:message:)``.
    ///
    /// A `nil` kind uses the driver's ``defaultTransactionKind``.
    public func withValidatedTransaction<Result: Sendable>(
        _ kind: XLTransactionKind? = nil,
        _ operation: @Sendable (inout Connection) throws -> Result
    ) async throws -> Result {
        let operationError = XLTransactionOperationError()
        do {
            return try await withTransaction(kind ?? defaultTransactionKind) { connection in
                try operationError.recording {
                    try operation(&connection)
                }
            }
        }
        catch {
            throw operationError.validatedError(for: error, driver: driverIdentifier)
        }
    }
}


/// An error a driver throws when it refuses to lend a connection at all, such
/// as a scope used after it ended or a re-entrant call.
///
/// ``XLDatabaseDriver/withValidatedTransaction(_:_:)`` rethrows a conforming
/// error unchanged: no transaction began, so it is not a transaction failure,
/// and callers catch it by its own type. A driver declares its own refusal
/// errors by conforming them to this protocol.
public protocol XLDriverScopeRefusal: Error {}


/// Records the error a validated transaction's own operation threw, so
/// ``XLDatabaseDriver/withValidatedTransaction(_:_:)`` can tell it apart from
/// a failure of the transaction itself. A driver's scopes can use it the same
/// way, to report their own failures in a portable form while rethrowing the
/// operation's error unchanged (issue #679).
///
/// The error is recorded beside the transaction rather than wrapped, so the
/// driver's `withTransaction(_:_:)` sees exactly the error the operation
/// threw and can match it in its own `catch` clauses. The record is locked
/// because the operation is `@Sendable` and may run on the driver's executor.
package final class XLTransactionOperationError: @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: (any Error)?

    package init() {}

    /// Runs `operation`, recording any error it throws before rethrowing it.
    ///
    /// A driver may run the operation more than once, retrying after a busy
    /// error, so each run clears what an earlier run recorded.
    package func recording<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        lock.lock()
        recorded = nil
        lock.unlock()
        do {
            return try operation()
        }
        catch {
            lock.lock()
            recorded = error
            lock.unlock()
            throw error
        }
    }

    /// The error the operation's last run threw, or `nil` when it returned.
    package var recordedError: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// The error a validated transaction reports when its transaction threw
    /// `error`: the operation's own error when its last run threw one,
    /// otherwise `error` itself when it is structured, otherwise a
    /// transaction failure.
    ///
    /// The operation's error wins whatever the driver threw, as it did
    /// before the contract became asynchronous: a driver may wrap or bridge
    /// the error it rethrows, and the caller still gets its own back. The
    /// one case this misreports is a driver that retries after the
    /// operation threw and then fails before running it again; the earlier
    /// run's error is reported then.
    package func validatedError(
        for error: any Error,
        driver: XLDriverIdentifier
    ) -> any Error {
        if let operationError = recordedError {
            return operationError
        }
        if xlIsStructuredDriverError(error) || error is any XLDriverScopeRefusal {
            return error
        }
        return XLDatabaseContractError.transactionFailure(
            driver: driver,
            message: String(describing: error)
        )
    }
}
