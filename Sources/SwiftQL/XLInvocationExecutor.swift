//
//  XLInvocationExecutor.swift
//  SwiftQL
//
//  The driver-generic execution seam behind every request, write request,
//  result set, and prepared invocation (issue #682). Moved out of
//  GRDBDatabaseDriver.swift, where it was written against the GRDB driver.
//

import Foundation


/// The GRDB specialisation every GRDB-backed path builds on.
typealias GRDBInvocationExecutor = XLInvocationExecutor<GRDBDatabaseDriver>


/// Immutable, Sendable execution seam between prepared logical statements and
/// the connections a driver lends (issue #682). Typed row decoding remains
/// outside this value because the legacy row-reader graph is not Sendable.
///
/// Generic over any blocking driver of the SQLite dialect: invocation packets,
/// the legacy binding facade, and row decoding all carry SQLite values, and
/// making them dialect-parametric is issue #686.
struct XLInvocationExecutor<Driver: XLBlockingDatabaseDriver>: Sendable
    where Driver.Dialect == XLSQLiteDialect
{

    let driver: Driver

    let logicalStatement: XLLogicalPreparedStatement

    let parameterLayoutError: XLInvocationBindingError?

    let valueEncodingError: XLSQLValueEncodingError?

    init(
        driver: Driver,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil
    ) {
        self.driver = driver
        self.logicalStatement = logicalStatement
        self.parameterLayoutError = parameterLayoutError
        self.valueEncodingError = valueEncodingError
    }

    var parameterLayout: XLParameterLayout {
        logicalStatement.parameterLayout
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [[XLSQLiteValue]] {
        let packet = try sqlitePacket(bindings)
        return try driver.withBlockingReadConnection { connection in
            try fetchAll(packet: packet, in: &connection)
        }
    }

    func fetchAll(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection
    ) throws -> [[XLSQLiteValue]] {
        try withBoundStatement(packet: packet, in: &connection) { connection, statement in
            try connection.fetchAll(statement)
        }
    }

    /// Visits normalized rows while the driver's cursor remains inside its owning
    /// database access. The callback can stop SQLite stepping without exposing
    /// the cursor or retaining a complete normalized result matrix.
    func forEachRow(
        bindings: any XLInvocationBindingPacket,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        let packet = try sqlitePacket(bindings)
        try driver.withBlockingReadConnection { connection in
            try forEachRow(
                packet: packet,
                in: &connection,
                body
            )
        }
    }

    func forEachRow(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try withBoundStatement(packet: packet, in: &connection) { connection, statement in
            try connection.forEachRow(statement, body)
        }
    }

    /// Visits row handles while the driver's cursor remains inside its owning
    /// database access (issue #678). A typed decode reads each column from
    /// the handle, so no row is normalized into an array of values first.
    func forEachRowHandle(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection,
        _ body: (Driver.Connection.RowHandle) throws -> XLRowStreamControl
    ) throws {
        try withBoundStatement(packet: packet, in: &connection) { connection, statement in
            try connection.forEachRowHandle(statement, body)
        }
    }

    ///
    /// Prepares and binds one statement for `packet`, then lends a
    /// row-handle stepper scoped to the connection access that owns it
    /// (issue #678).
    ///
    /// `operation` runs synchronously inside the same read (or, when
    /// `requiresWriteConnection` is `true`, write/transaction) connection
    /// access that creates the stepper, so the cursor the stepper
    /// closes over never escapes its owning database access -- the stepper
    /// closure is only valid for the duration of `operation`, and each handle
    /// it returns only until it is called again. `XLResultSet` is built
    /// directly on top of this seam.
    ///
    func withRowHandleStepper<Result>(
        packet: XLValidatedSQLitePacket,
        requiresWriteConnection: Bool,
        _ operation: (@escaping () throws -> Driver.Connection.RowHandle?) throws -> Result
    ) throws -> Result {
        let accessor: (inout Driver.Connection) throws -> Result = { connection in
            try self.withBoundStatement(packet: packet, in: &connection) { connection, statement in
                try connection.withRowHandleStepper(statement, operation)
            }
        }
        if requiresWriteConnection {
            return try driver.withBlockingTransaction(accessor)
        }
        else {
            return try driver.withBlockingReadConnection(accessor)
        }
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> [XLSQLiteValue]? {
        let packet = try sqlitePacket(bindings)
        return try driver.withBlockingReadConnection { connection in
            try fetchOne(packet: packet, in: &connection)
        }
    }

    func fetchOne(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection
    ) throws -> [XLSQLiteValue]? {
        try withBoundStatement(packet: packet, in: &connection) { connection, statement in
            try connection.fetchOne(statement)
        }
    }

    @discardableResult
    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws -> XLExecutionResult {
        let packet = try sqlitePacket(bindings)
        return try driver.withBlockingTransaction { connection in
            try execute(packet: packet, in: &connection)
        }
    }

    /// Executes inside a transaction this executor opens for the call.
    @discardableResult
    func execute(
        packet: XLValidatedSQLitePacket
    ) throws -> XLExecutionResult {
        try driver.withBlockingTransaction { connection in
            try execute(packet: packet, in: &connection)
        }
    }

    @discardableResult
    func execute(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection
    ) throws -> XLExecutionResult {
        try withBoundStatement(packet: packet, in: &connection) { connection, statement in
            try connection.execute(statement)
        }
    }

    ///
    /// Checks `bindings` with ``sqlitePacket(_:)`` and logs the statement, as
    /// every request does before it takes a connection. The read and write
    /// requests, synchronous and asynchronous (issue #681), share it.
    ///
    /// - Parameter operation: The request method, named in the log line. It
    ///   is formatted only when there is a logger.
    ///
    func validatedPacket(
        _ bindings: any XLInvocationBindingPacket,
        for operation: @autoclosure () -> String,
        logger: XLLogger?
    ) throws -> XLValidatedSQLitePacket {
        let packet = try sqlitePacket(bindings)
        if let logger {
            logger.debug(
                "\(operation()): <<<\(logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        }
        return packet
    }

    /// Checks an invocation packet against this statement's parameter layout,
    /// and returns the evidence that it passed.
    ///
    /// Execution takes an ``XLValidatedSQLitePacket``, which cannot be built
    /// without the structural checks running, and this is the only place the
    /// semantic ones are applied -- so validation happens once per execution
    /// rather than the two or three times it used to (issue #561).
    func sqlitePacket(
        _ bindings: any XLInvocationBindingPacket
    ) throws -> XLValidatedSQLitePacket {
        if let valueEncodingError {
            throw valueEncodingError
        }
        if let parameterLayoutError {
            throw parameterLayoutError
        }
        let validatedPacket = try XLValidatedSQLitePacket(
            validating: bindings,
            matching: parameterLayout,
            requestType: Self.self
        )
        for binding in validatedPacket.bindings {
            if case .real(let value) = binding.value,
               let error = XLSQLValueEncodingError.bindingFailure(
                   for: value,
                   valueType: binding.slot.valueTypeName,
                   context: binding.slot.codingContext
               ) {
                throw error
            }
            // GRDB binds text with the length -1, so SQLite stores a value
            // only up to its first NUL. Reject U+0000 instead of storing a
            // truncated value (issue #657). A value without a NUL binds in
            // full, because -1 then reads exactly its UTF-8 byte count. The
            // rule applies to every driver (issue #682), so a value SwiftQL
            // accepts on one SQLite driver is never refused by another.
            if case .text(let value) = binding.value, value.utf8.contains(0) {
                throw XLSQLValueEncodingError.nulCharacterInText(
                    valueType: binding.slot.valueTypeName,
                    context: binding.slot.codingContext
                )
            }
            if let codecIdentity = binding.slot.codecIdentity,
               codecIdentity.dialectIdentifier != driver.dialect.descriptor.identity {
                throw XLInvocationBindingError.preparedCodecDialectMismatch(
                    slot: binding.slot,
                    codecIdentity: codecIdentity,
                    expectedDialectIdentifier: driver.dialect.descriptor.identity
                )
            }
            if driver.dialect.isNull(binding.value) {
                guard binding.slot.nullability == .nullable else {
                    throw XLInvocationBindingError.nullForRequiredParameter(
                        slot: binding.slot
                    )
                }
                continue
            }
            if let codecIdentity = binding.slot.codecIdentity {
                let actualStorage = driver.dialect.stableStorageIdentifier(
                    for: binding.value
                )
                guard actualStorage == codecIdentity.storageIdentifier else {
                    throw XLInvocationBindingError.dialectValueStorageMismatch(
                        slot: binding.slot,
                        expectedCodecIdentity: codecIdentity,
                        actualStorageIdentifier: actualStorage
                    )
                }
            }
        }
        return validatedPacket
    }

    ///
    /// Prepares and binds one statement for `packet`, lends it to `run`, then
    /// finalizes it on the same connection (issue #677).
    ///
    /// The statement is finalized however this ends: when `run` returns or
    /// throws, and when binding throws. `run` must not keep the statement.
    ///
    func withBoundStatement<Result>(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection,
        _ run: (inout Driver.Connection, Driver.Connection.PhysicalStatement) throws -> Result
    ) throws -> Result {
        // `prepare` installs the functions the statement calls first, on
        // whichever connection this is (issue #683).
        var statement = try connection.prepare(logicalStatement)
        defer {
            connection.finalizePhysical(statement)
        }
        // Bound in place, so that a binding failure partway finalizes the
        // statement with the values already bound to it.
        try bind(packet: packet, to: &statement, in: &connection)
        return try run(&connection, statement)
    }

    /// Binds every value of `packet` to a statement prepared from this
    /// executor's logical statement, then lets the connection check the
    /// arguments. When a value fails to bind, `statement` keeps the values
    /// bound before it.
    ///
    /// Internal rather than private so that `GRDBRequestPhaseConnection` can
    /// time this exact binding step on its own (issue #670).
    func bind(
        packet: XLValidatedSQLitePacket,
        to statement: inout Driver.Connection.PhysicalStatement,
        in connection: inout Driver.Connection
    ) throws {
        for binding in packet.bindings {
            do {
                statement = try connection.bindValidated(
                    binding.value,
                    to: binding.slot.key,
                    in: statement
                )
            }
            catch {
                throw XLInvocationBindingError.driverBindingFailed(
                    slot: binding.slot,
                    codecIdentity: binding.slot.codecIdentity,
                    context: binding.slot.codingContext,
                    message: String(describing: error)
                )
            }
        }
        do {
            try connection.validateBindings(in: statement)
        }
        catch {
            throw XLInvocationBindingError.driverArgumentValidationFailed(
                layout: packet.layout,
                message: String(describing: error)
            )
        }
    }
}


/// The execution members a prepared invocation forwards to, so that
/// ``XLPreparedInvocation`` does not carry its driver's type.
protocol XLPreparedValueInvocation: Sendable {

    var parameterLayout: XLParameterLayout { get }

    func fetchAll(bindings: any XLInvocationBindingPacket) throws -> [[XLSQLiteValue]]

    func forEachRow(
        bindings: any XLInvocationBindingPacket,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws

    func fetchOne(bindings: any XLInvocationBindingPacket) throws -> [XLSQLiteValue]?

    func execute(bindings: any XLInvocationBindingPacket) throws -> XLExecutionResult
}


extension XLInvocationExecutor: XLPreparedValueInvocation {}


/// An immutable, concurrency-safe runtime handle for one rendered SQL
/// statement, bound to the database that prepared it.
///
/// This handle deliberately exposes normalized SQLite rows instead of
/// retaining SwiftQL's legacy row-reader graph, which is not `Sendable`.
/// Static, database-independent query identity and typed result metadata are
/// layered on top by the descriptor API rather than captured here.
///
/// The handle does not name its driver (issue #682), so ``GRDBDatabase`` and
/// ``XLDriverDatabase`` prepare the same type.
public struct XLPreparedInvocation: Sendable {

    private let executor: any XLPreparedValueInvocation

    init(executor: any XLPreparedValueInvocation) {
        self.executor = executor
    }

    /// The static parameter slots shared by every invocation of this handle.
    public var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }

    /// Fetches all normalized SQLite rows for one immutable binding packet.
    public func fetchAllValues(
        bindings: any XLInvocationBindingPacket
    ) throws -> [[XLSQLiteValue]] {
        try executor.fetchAll(bindings: bindings)
    }

    /// Visits normalized SQLite rows without exposing the driver's cursor
    /// outside its owning connection. Package clients use this to decode typed
    /// results before advancing instead of first retaining a complete value
    /// matrix.
    package func forEachValueRow(
        bindings: any XLInvocationBindingPacket,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try executor.forEachRow(bindings: bindings, body)
    }

    /// Fetches the first normalized SQLite row for one immutable binding packet.
    public func fetchOneValues(
        bindings: any XLInvocationBindingPacket
    ) throws -> [XLSQLiteValue]? {
        try executor.fetchOne(bindings: bindings)
    }

    /// Executes a command with one immutable binding packet, and reports
    /// what it did.
    @discardableResult
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws -> XLExecutionResult {
        try executor.execute(bindings: bindings)
    }
}


/// The name this handle had before it stopped naming its driver (issue #682).
public typealias GRDBPreparedInvocation = XLPreparedInvocation
