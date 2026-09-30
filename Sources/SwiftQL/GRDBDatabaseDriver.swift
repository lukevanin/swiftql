//
//  GRDBDatabaseDriver.swift
//

import Foundation
import GRDB
import GRDBSQLite


/// GRDB transport for SQLite dialect values.
///
/// The driver is internal to the v1 compatibility facade. Public code depends
/// on the adapter-neutral contracts from `SwiftQLCore`.
///
/// A driver is either pool-backed (the default: every connection access
/// leases from the `DatabasePool`, exactly as before issue #284) or pinned to
/// one already-open connection for the duration of one
/// ``XLTransactionalDatabase/withTransaction(_:)`` scope. Pinned-mode
/// connection access never touches the pool, so it cannot re-enter it and
/// cannot deadlock waiting on a writer access the enclosing scope already
/// holds.
///
/// The driver conforms to the asynchronous ``XLDatabaseDriver`` contract, and
/// also keeps a blocking scope for the v1 request layer, which moves to the
/// asynchronous one with #681 and #682. Both share the connection type and
/// every connection primitive, so the two differ only in how the caller
/// waits. The blocking scope has its own names, `withBlocking...`, so that it
/// never shadows an asynchronous member: a concrete method outranks a
/// protocol extension method of the same name, and `try await` would then
/// quietly block a thread.
struct GRDBDatabaseDriver: XLDatabaseDriver, Sendable {

    typealias Dialect = XLSQLiteDialect

    typealias Connection = GRDBDatabaseDriverConnection

    let driverIdentifier = XLDriverIdentifier.grdb

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

    /// GRDB's own default: ``XLTransactionKind/immediate`` for a writable
    /// database, so a second writer conflicts at `BEGIN` rather than partway
    /// through a transaction, and ``XLTransactionKind/deferred`` for a
    /// read-only one, where GRDB notes SQLite can refuse a non-deferred
    /// transaction.
    let defaultTransactionKind: XLTransactionKind

    /// `defaultTransactionKind` as GRDB spells it, worked out once.
    private let grdbDefaultTransactionKind: Database.TransactionKind

    private enum Access {
        case pool(DatabasePool)
        case pinned(GRDBPinnedConnectionBox)
    }

    private let access: Access

    /// The pool backing this driver, or `nil` when pinned to one transaction
    /// scope's connection. `ValueObservation`-backed live queries need a
    /// stable pool to track, so a pinned-mode caller must fail explicitly
    /// instead of observing a connection that is about to be invalidated.
    var databasePool: DatabasePool? {
        if case .pool(let pool) = access {
            return pool
        }
        return nil
    }

    /// `true` once this driver has been pinned to one transaction scope's
    /// connection. Used to reject a nested `withTransaction(_:)` call before
    /// it touches the pool, instead of silently opening a second scope.
    var isPinned: Bool {
        if case .pinned = access {
            return true
        }
        return false
    }

    init(
        databasePool: DatabasePool,
        dialect: XLSQLiteDialect,
        databaseIdentifier: XLDatabaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    ) {
        let readOnly = databasePool.configuration.readonly
        self.init(
            access: .pool(databasePool),
            dialect: dialect,
            databaseIdentifier: databaseIdentifier,
            defaultTransactionKind: readOnly ? .deferred : .immediate,
            grdbDefaultTransactionKind: readOnly ? .deferred : .immediate
        )
    }

    private init(
        access: Access,
        dialect: XLSQLiteDialect,
        databaseIdentifier: XLDatabaseIdentifier,
        defaultTransactionKind: XLTransactionKind,
        grdbDefaultTransactionKind: Database.TransactionKind
    ) {
        self.access = access
        self.dialect = dialect
        self.databaseIdentifier = databaseIdentifier
        self.defaultTransactionKind = defaultTransactionKind
        self.grdbDefaultTransactionKind = grdbDefaultTransactionKind
    }

    ///
    /// Produces a driver pinned to `box`'s connection for the duration of one
    /// transaction scope. Every connection access on the returned driver
    /// reuses that connection directly instead of leasing one from the pool.
    ///
    /// Deliberately assigns a **fresh** `databaseIdentifier` rather than
    /// reusing this driver's own. A logical statement is validated against the
    /// identifier of the driver that runs it, and a distinct identifier per
    /// scope is how the render-once cache tells whether a cached `GRDBRequest`
    /// -- which closes over one specific driver -- is already bound to the
    /// calling driver. A request built for the pool driver must never run on,
    /// or re-enter the pool from, a transaction, and a request built inside one
    /// transaction must never reach that transaction's invalidated box later.
    ///
    /// The cache does not key on this identifier (issue #642). A scope uses the
    /// cache key of the database it was opened on, and the cache rebinds the
    /// shared request to the calling driver at call time (see
    /// `GRDBDatabase.bindRenderOnceRequest(_:)`), so a fresh identifier per
    /// scope adds no cache entry and costs no render.
    ///
    func pinned(to box: GRDBPinnedConnectionBox) -> GRDBDatabaseDriver {
        GRDBDatabaseDriver(
            access: .pinned(box),
            dialect: dialect,
            databaseIdentifier: XLDatabaseIdentifier(rawValue: UUID()),
            defaultTransactionKind: defaultTransactionKind,
            grdbDefaultTransactionKind: grdbDefaultTransactionKind
        )
    }

    func withBlockingReadConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant(.read)
            return try xlMappingScopeErrors(driver: driverIdentifier) { operationError in
                try pool.read { database in
                    try holding(.reader) {
                        var connection = makeConnection(database)
                        return try operationError.recording { try operation(&connection) }
                    }
                }
            }
        case .pinned(let box):
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    func withBlockingWriteConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant(.write)
            return try xlMappingScopeErrors(driver: driverIdentifier) { operationError in
                try pool.writeWithoutTransaction { database in
                    try holding(.writer(database)) {
                        var connection = makeConnection(database)
                        return try operationError.recording { try operation(&connection) }
                    }
                }
            }
        case .pinned(let box):
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    func withBlockingTransaction<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant(.write)
            return try xlMappingScopeErrors(driver: driverIdentifier) { operationError in
                try pool.writeWithoutTransaction { database in
                    try runTransaction(on: database, kind: grdbDefaultTransactionKind) {
                        var connection = makeConnection(database)
                        return try operationError.recording { try operation(&connection) }
                    }
                }
            }
        case .pinned(let box):
            // Already running inside the one real transaction that the
            // owning `XLTransactionalDatabase.withTransaction(_:)` scope
            // opened through `runTransaction(on:kind:_:)`. A write statement
            // executed through the ordinary v1 request path calls this
            // method once per statement, so reuse the pinned connection
            // directly instead of asking GRDB for a second write access —
            // GRDB's own writer queue is not reentrant, and a second write
            // access here would deadlock instead of composing as a nested
            // transaction.
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    // MARK: Asynchronous scope

    // GRDB's asynchronous accessors enqueue `operation` on the connection's
    // own serial executor and suspend the caller until it has run. They add
    // no thread hop beyond the one that confines a connection to its queue,
    // and none of them blocks the calling thread.

    func withReadConnection<Result: Sendable>(
        _ operation: @Sendable (inout GRDBDatabaseDriverConnection) throws -> Result
    ) async throws -> Result {
        let pool = try asynchronousPool(for: .read)
        return try await xlMappingScopeErrors(driver: driverIdentifier) { operationError in
            try await pool.read { database in
                try holding(.reader) {
                    var connection = makeConnection(database)
                    return try operationError.recording { try operation(&connection) }
                }
            }
        }
    }

    func withWriteConnection<Result: Sendable>(
        _ operation: @Sendable (inout GRDBDatabaseDriverConnection) throws -> Result
    ) async throws -> Result {
        let pool = try asynchronousPool(for: .write)
        return try await xlMappingScopeErrors(driver: driverIdentifier) { operationError in
            try await pool.writeWithoutTransaction { database in
                try holding(.writer(database)) {
                    var connection = makeConnection(database)
                    return try operationError.recording { try operation(&connection) }
                }
            }
        }
    }

    func withTransaction<Result: Sendable>(
        _ kind: XLTransactionKind,
        _ operation: @Sendable (inout GRDBDatabaseDriverConnection) throws -> Result
    ) async throws -> Result {
        let pool = try asynchronousPool(for: .write)
        let transactionKind = try grdbTransactionKind(kind)
        return try await xlMappingScopeErrors(driver: driverIdentifier) { operationError in
            try await pool.writeWithoutTransaction { database in
                try runTransaction(on: database, kind: transactionKind) {
                    var connection = makeConnection(database)
                    return try operationError.recording { try operation(&connection) }
                }
            }
        }
    }

    ///
    /// Runs `body` inside one transaction of `kind` on `database`, the writer
    /// connection. `withTransaction(_:)` on a database, and both transaction
    /// scopes here, open their transaction through this one path.
    ///
    /// The writer hold covers the whole transaction, commit included. While
    /// `body` runs, the connection is inside the transaction, and every root
    /// access from this thread is rejected. During the commit, GRDB runs its
    /// transaction observers on this thread; there only a root write is
    /// rejected. SQLite re-enables autocommit before it calls the commit hook
    /// that GRDB's `databaseWillCommit` runs from, so no connection state
    /// tells that callback apart from `databaseDidCommit`. A root read from
    /// either runs on a reader, as it did on 1.9, and sees what any other
    /// connection sees at that moment: the state before the commit in
    /// `databaseWillCommit`, and after it in `databaseDidCommit`.
    ///
    func runTransaction<Result>(
        on database: Database,
        kind: Database.TransactionKind? = nil,
        _ body: () throws -> Result
    ) throws -> Result {
        let kind = kind ?? grdbDefaultTransactionKind
        return try holding(.writer(database)) {
            var result: Result?
            // Every caller maps what this throws around `body`, such as a
            // failing `BEGIN` or `COMMIT`, with `xlMappingScopeErrors`, and
            // records `body`'s own error so it is rethrown unchanged.
            try database.inTransaction(kind) {
                result = try body()
                return .commit
            }
            // `inTransaction` returns only after `body` returned and the
            // transaction committed, so `result` is set.
            return result!
        }
    }

    ///
    /// Runs `body` with this database marked as held in the reentrancy
    /// tracker, for a pool-mode scope that holds a reader or the writer.
    ///
    /// `body` runs synchronously on the connection's queue, so a call it
    /// makes through the root database reaches `preconditionNotRootReentrant`
    /// on the same thread and throws, instead of asking GRDB for a connection
    /// kind it already holds and tripping GRDB's uncatchable "Database
    /// methods are not reentrant" precondition.
    ///
    private func holding<Result>(
        _ hold: GRDBTransactionScopeTracker.Hold,
        _ body: () throws -> Result
    ) throws -> Result {
        guard let pool = databasePool else {
            return try body()
        }
        return try GRDBTransactionScopeTracker.shared.withActive(pool, holding: hold, body)
    }

    ///
    /// The pool an asynchronous scope leases from, after the checks every
    /// asynchronous scope makes before it lends a connection.
    ///
    /// A pinned driver has no asynchronous scope. Its connection belongs to
    /// one synchronous ``XLTransactionalDatabase/withTransaction(_:)`` body,
    /// which cannot suspend, so reaching the connection from asynchronous code
    /// means the scope value has left that body. That is reported as
    /// ``XLTransactionScopeError/scopeEscaped`` rather than touching a GRDB
    /// `Database` off its writer queue.
    ///
    private func asynchronousPool(
        for access: GRDBTransactionScopeTracker.Access
    ) throws -> DatabasePool {
        try Task.checkCancellation()
        switch self.access {
        case .pool(let pool):
            try preconditionNotRootReentrant(access)
            return pool
        case .pinned:
            throw XLTransactionScopeError.scopeEscaped
        }
    }

    private func grdbTransactionKind(
        _ kind: XLTransactionKind
    ) throws -> Database.TransactionKind {
        switch kind {
        case .deferred:
            return .deferred
        case .immediate:
            return .immediate
        case .exclusive:
            return .exclusive
        default:
            throw XLDatabaseContractError.unsupportedTransactionKind(
                driver: driverIdentifier,
                kind: kind
            )
        }
    }

    ///
    /// Rejects "root-executor re-entry" (issue #284): a root access to this
    /// driver's pool while a scope in the same flow of control holds one of
    /// the pool's connections. This is what protects a plain `SELECT` issued
    /// through the captured root database from inside an active transaction
    /// body, not just a second `withTransaction(_:)` call: GRDB's reader pool
    /// is not reentrant-locked with its writer, so a stray read like that
    /// would not crash or deadlock — it would just silently lease a different
    /// connection and return the database's last *committed* state, missing
    /// the transaction's own uncommitted writes.
    ///
    /// A scope that holds only a reader or the writer rejects just the access
    /// GRDB would stop on the same thread. See ``GRDBTransactionScopeTracker``.
    ///
    func preconditionNotRootReentrant(
        _ access: GRDBTransactionScopeTracker.Access
    ) throws {
        guard let pool = databasePool else {
            return
        }
        guard !GRDBTransactionScopeTracker.shared.rejects(access, on: pool) else {
            throw XLTransactionScopeError.nestedTransactionUnsupported
        }
    }

    func makeConnection(_ database: Database) -> GRDBDatabaseDriverConnection {
        GRDBDatabaseDriverConnection(
            database: database,
            databaseIdentifier: databaseIdentifier,
            driverIdentifier: driverIdentifier,
            dialect: dialect
        )
    }
}


///
/// Holds the one physical connection lent to a
/// ``XLTransactionalDatabase/withTransaction(_:)`` scope for its entire
/// duration, and invalidates it the instant that scope's body returns.
///
/// GRDB's `Database` is explicitly *not* `Sendable` — it must only be used
/// from the serialized writer access that owns it (see
/// `GRDB/Core/Database.swift`'s `@available(*, unavailable) extension
/// Database: Sendable`). This box is created inside that writer access,
/// read only synchronously from the same dynamic extent by the transaction
/// body, and invalidated before that access returns; `@unchecked Sendable`
/// documents and contains that invariant instead of ever exposing `Database`
/// through public API.
///
/// Invalidation is what turns an escaped transaction-scoped value into a
/// predictable ``XLTransactionScopeError/scopeEscaped`` instead of a data
/// race or a crash: once `invalidate()` runs, every later `connection(...)`
/// call throws rather than touching a connection GRDB may already have
/// reused for unrelated work.
final class GRDBPinnedConnectionBox: @unchecked Sendable {

    private let lock = NSLock()
    private var database: Database?

    /// The thread that runs the body. GRDB confines `database` to it.
    private let thread = pthread_self()

    init(_ database: Database) {
        self.database = database
    }

    /// Invalidates the box. Called once, when the owning body returns,
    /// before the transaction commits or rolls back.
    ///
    /// Synchronized against `connection(makeConnection:)` so a scope value
    /// that escapes to another thread reads a consistent, already-invalidated
    /// `database` instead of racing this write -- a scope value used after
    /// its body returns must reliably throw `.scopeEscaped`, never trip a
    /// data race.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        database = nil
    }

    func connection(
        makeConnection: (Database) -> GRDBDatabaseDriverConnection
    ) throws -> GRDBDatabaseDriverConnection {
        lock.lock()
        let database = self.database
        lock.unlock()
        // A scope value used from another thread -- a task created in the
        // body, for example -- would touch `database` off GRDB's writer
        // queue, which GRDB stops with a precondition. It throws instead.
        guard let database, pthread_equal(thread, pthread_self()) != 0 else {
            throw XLTransactionScopeError.scopeEscaped
        }
        return makeConnection(database)
    }
}


/// Immutable, Sendable execution seam between prepared logical statements and
/// GRDB connections. Typed row decoding remains outside this value because the
/// legacy row-reader graph is not Sendable.
struct GRDBInvocationExecutor: Sendable {

    let driver: GRDBDatabaseDriver

    let logicalStatement: XLLogicalPreparedStatement

    let parameterLayoutError: XLInvocationBindingError?

    let valueEncodingError: XLSQLValueEncodingError?

    /// Custom scalar functions referenced by `logicalStatement`, keyed by their SQLite
    /// registration signature.
    ///
    /// Checked against whatever physical connection is checked out immediately before every
    /// execution (see `boundStatement`), rather than registered once upfront. `DatabasePool`
    /// hands out any of several persistent reader connections, and a `Database.add(function:)`
    /// call only affects the one physical connection it runs on -- so there is no single "first
    /// use" moment for the whole pool. Each function is installed on a connection the first time
    /// that connection needs it, and never again; see
    /// `GRDBDatabaseDriverConnection.registerCustomFunctions(_:)`.
    let customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]

    init(
        driver: GRDBDatabaseDriver,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:]
    ) {
        self.driver = driver
        self.logicalStatement = logicalStatement
        self.parameterLayoutError = parameterLayoutError
        self.valueEncodingError = valueEncodingError
        self.customFunctions = customFunctions
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
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [[XLSQLiteValue]] {
        try connection.fetchAll(boundStatement(packet: packet, in: &connection))
    }

    /// Visits normalized rows while the GRDB cursor remains inside its owning
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
        in connection: inout GRDBDatabaseDriverConnection,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try connection.forEachRow(
            boundStatement(packet: packet, in: &connection),
            body
        )
    }

    ///
    /// Prepares and binds one statement for `packet`, then lends a
    /// value-level row stepper scoped to the connection access that owns it.
    ///
    /// `operation` runs synchronously inside the same read (or, when
    /// `requiresWriteConnection` is `true`, write/transaction) connection
    /// access that creates the stepper, so the GRDB cursor the stepper
    /// closes over never escapes its owning database access -- the stepper
    /// closure is only valid for the duration of `operation`. `XLResultSet`
    /// is built directly on top of this seam.
    ///
    func withValuesStepper<Result>(
        packet: XLValidatedSQLitePacket,
        requiresWriteConnection: Bool,
        _ operation: (@escaping () throws -> [XLSQLiteValue]?) throws -> Result
    ) throws -> Result {
        let accessor: (inout GRDBDatabaseDriverConnection) throws -> Result = { connection in
            let statement = try self.boundStatement(packet: packet, in: &connection)
            // The statement stays marked in use for all of `operation`, which
            // can issue nested requests on this connection, and the mark is
            // removed on the same return or throw that closes the result set.
            // A nested request with the same SQL then prepares its own
            // statement instead of resetting this cursor (issue #641).
            return try GRDBOpenCursorStatements.shared.withOpenCursor(
                on: statement.statement
            ) {
                let stepper = try connection.makeValuesStepper(statement)
                return try operation(stepper)
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
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [XLSQLiteValue]? {
        try connection.fetchOne(boundStatement(packet: packet, in: &connection))
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
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> XLExecutionResult {
        try connection.execute(boundStatement(packet: packet, in: &connection))
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
            // full, because -1 then reads exactly its UTF-8 byte count.
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

    /// Internal rather than private so that `GRDBRequestPhaseConnection` can
    /// time this exact binding step on its own (issue #670).
    func boundStatement(
        packet: XLValidatedSQLitePacket,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> GRDBPhysicalStatement {
        try connection.registerCustomFunctions(customFunctions)
        var statement = try connection.prepare(logicalStatement)
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
        return statement
    }
}


/// An immutable, concurrency-safe GRDB runtime handle for one rendered SQL
/// statement.
///
/// This handle deliberately exposes normalized SQLite rows instead of
/// retaining SwiftQL's legacy row-reader graph, which is not `Sendable`.
/// Static, database-independent query identity and typed result metadata are
/// layered on top by the descriptor API rather than captured here.
public struct GRDBPreparedInvocation: Sendable {

    private let executor: GRDBInvocationExecutor

    init(executor: GRDBInvocationExecutor) {
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

    /// Visits normalized SQLite rows without exposing the GRDB cursor outside
    /// its owning connection. Package clients use this to decode typed results
    /// before advancing instead of first retaining a complete value matrix.
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


struct GRDBDatabaseDriverConnection:
    XLDatabaseDriverConnection,
    XLStreamingDatabaseDriverConnection
{

    typealias Dialect = XLSQLiteDialect

    typealias PhysicalStatement = GRDBPhysicalStatement

    let driverIdentifier: XLDriverIdentifier

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

    private let connectionIdentifier = UUID()

    private let database: Database

    init(
        database: Database,
        databaseIdentifier: XLDatabaseIdentifier,
        driverIdentifier: XLDriverIdentifier,
        dialect: XLSQLiteDialect
    ) {
        self.database = database
        self.databaseIdentifier = databaseIdentifier
        self.driverIdentifier = driverIdentifier
        self.dialect = dialect
    }

    mutating func preparePhysical(
        _ validatedStatement: XLValidatedLogicalPreparedStatement
    ) throws -> GRDBPhysicalStatement {
        let statement = validatedStatement.logicalStatement
        #if DEBUG
        let preparationCountBefore = GRDBStatementPreparationTestHooks.shared.isObserving
            ? liveStatementCount()
            : nil
        #endif
        // GRDB's cache hands back the same `Statement` instance for the same
        // SQL on this connection. When a SwiftQL cursor is still stepping
        // that instance -- a request nested inside a `withResultSet` callback
        // on a transaction scope -- opening a second cursor on it would reset
        // the outer cursor (issue #641). Prepare a private statement for the
        // nested request instead, and keep the cache for every other call.
        let database = database
        var physicalStatement = try mappingDatabaseErrors {
            try database.cachedStatement(sql: statement.sql)
        }
        if GRDBOpenCursorStatements.shared.contains(physicalStatement) {
            physicalStatement = try mappingDatabaseErrors {
                try database.makeStatement(sql: statement.sql)
            }
        }
        #if DEBUG
        if let preparationCountBefore, liveStatementCount() > preparationCountBefore {
            GRDBStatementPreparationTestHooks.shared.notifyPrepared(
                sql: statement.sql,
                databasePath: mainDatabasePath()
            )
        }
        #endif
        return GRDBPhysicalStatement(
            logicalStatement: statement,
            connectionIdentifier: connectionIdentifier,
            statement: physicalStatement,
            bindings: [:]
        )
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: GRDBPhysicalStatement
    ) throws -> GRDBPhysicalStatement {
        try validateOwnership(of: statement)
        if case .indexed(let index) = key, index < 0 {
            throw XLDatabaseContractError.bindFailure(
                driver: driverIdentifier,
                key: key,
                message: "Indexed binding positions must be zero or greater."
            )
        }
        if case .real(let real) = value,
           let error = XLSQLValueEncodingError.bindingFailure(
               for: real,
               valueType: String(reflecting: Double.self),
               context: XLValueCodingContext(
                   site: .parameter,
                   path: XLValueCodingPath(key.valueEncodingPathComponent)
               )
           ) {
            throw error
        }
        // Mirror the packet validation: GRDB binds text with the length -1,
        // so a value with U+0000 would be truncated (issue #657).
        if case .text(let text) = value, text.utf8.contains(0) {
            throw XLSQLValueEncodingError.nulCharacterInText(
                valueType: String(reflecting: String.self),
                context: XLValueCodingContext(
                    site: .parameter,
                    path: XLValueCodingPath(key.valueEncodingPathComponent)
                )
            )
        }
        var result = statement
        result.bindings[key] = value
        return result
    }

    /// Validates the complete logical packet against GRDB's physical
    /// placeholder table before execution. This moves missing, extra, or
    /// otherwise invalid driver arguments into the contextual bind boundary.
    func validateBindings(in statement: GRDBPhysicalStatement) throws {
        try validateOwnership(of: statement)
        try statement.statement.validateArguments(
            statementArguments(statement)
        )
    }

    mutating func fetchAll(
        _ statement: GRDBPhysicalStatement
    ) throws -> [[XLSQLiteValue]] {
        try collectAllRows(statement)
    }

    mutating func fetchOne(
        _ statement: GRDBPhysicalStatement
    ) throws -> [XLSQLiteValue]? {
        try collectFirstRow(statement)
    }

    mutating func forEachRow(
        _ statement: GRDBPhysicalStatement,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try validateOwnership(of: statement)
        // The callback's own error is the caller's, so it is kept aside
        // rather than mapped with the cursor's.
        try xlMappingScopeErrors(driver: driverIdentifier) { callbackError in
            try forEachRowUnmapped(statement) { values in
                try callbackError.recording { try body(values) }
            }
        }
    }

    /// `forEachRow(_:_:)` before its GRDB errors are mapped.
    private func forEachRowUnmapped(
        _ statement: GRDBPhysicalStatement,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        let cursor = try Row.fetchCursor(
            statement.statement,
            arguments: statementArguments(statement)
        )
        // One reusable normalization buffer for the whole fetch. RowCursor
        // reuses its row storage, and the streaming contract requires the
        // callback to consume (decode or copy) each row before advancing, so a
        // synchronous, non-retaining consumer (the typed decode path) reuses
        // this buffer's storage row-to-row instead of allocating a fresh
        // `[XLSQLiteValue]` per row. A consumer that retains the row (the eager
        // `collectAllRows`/`collectFirstRow` compatibility shims) keeps a second
        // reference, so `removeAll(keepingCapacity:)` copy-on-writes a fresh
        // buffer for the next row and the retained values stay intact. The typed
        // decode path (the hot path) therefore materializes no intermediate
        // matrix; the eager `collectAllRows`/`collectFirstRow` compatibility
        // shims still build only the result they already contract to return.
        var values: [XLSQLiteValue] = []
        // `body` can issue a nested request on the same connection, so mark
        // the statement in use until the loop ends; see
        // `GRDBOpenCursorStatements`.
        try GRDBOpenCursorStatements.shared.withOpenCursor(on: statement.statement) {
            while let row = try cursor.next() {
                values.removeAll(keepingCapacity: true)
                values.reserveCapacity(row.count)
                for databaseValue in row.databaseValues {
                    values.append(databaseValue.sqliteDialectValue)
                }
                if try body(values) == .stop {
                    return
                }
            }
        }
    }

    /// Steps every result row of `statement` without reading or normalizing a
    /// column, and returns the row count. This is `forEachRow(_:_:)` without
    /// its value loop, so the performance harness can time SQLite stepping
    /// apart from column materialization (issue #670).
    mutating func stepAllRows(_ statement: GRDBPhysicalStatement) throws -> Int {
        try validateOwnership(of: statement)
        return try mappingDatabaseErrors {
            let cursor = try Row.fetchCursor(
                statement.statement,
                arguments: statementArguments(statement)
            )
            var rowCount = 0
            try GRDBOpenCursorStatements.shared.withOpenCursor(on: statement.statement) {
                while try cursor.next() != nil {
                    rowCount += 1
                }
            }
            return rowCount
        }
    }

    /// The GRDB connection this value wraps. `GRDBRequestPhaseConnection` uses
    /// it for unmeasured work, such as a savepoint around one sample.
    var grdbDatabase: Database {
        database
    }

    ///
    /// Implements ``XLStreamingDatabaseDriverConnection/makeValuesStepper(_:)``
    /// for GRDB: takes one already-prepared physical statement and returns a
    /// value-level stepper that performs at most one additional SQLite step
    /// and value-normalization per call, returning `nil` once the underlying
    /// cursor is exhausted.
    ///
    /// This is the pull-based counterpart to `forEachRow(_:_:)`'s push-based
    /// callback: `XLResultSet.next()` needs to step exactly one row per call
    /// from outside code that already ran and returned, which a callback
    /// invoked once per row cannot express. The returned closure remains
    /// valid only for the lifetime of this connection's database access: it
    /// captures a GRDB row cursor bound to `database`, which must not survive
    /// the access that produced this connection. The caller must stop
    /// invoking the closure -- and release every reference to it -- no later
    /// than when that access returns.
    ///
    mutating func makeValuesStepper(
        _ statement: GRDBPhysicalStatement
    ) throws -> () throws -> [XLSQLiteValue]? {
        try validateOwnership(of: statement)
        let driver = driverIdentifier
        let cursor = try mappingDatabaseErrors {
            try Row.fetchCursor(
                statement.statement,
                arguments: statementArguments(statement)
            )
        }
        // Same reusable normalization buffer as forEachRow(_:_:) above, for
        // the same reason: the streaming contract requires the caller to
        // consume (decode or copy) each row's values before requesting the
        // next one.
        var values: [XLSQLiteValue] = []
        // Exhaustion and a thrown step error are both terminal: GRDB does not
        // document `Cursor.next()` as safe to call again after it throws, so
        // once this closure has returned `nil` or thrown once, every later
        // call keeps returning `nil` instead of stepping the cursor again.
        var isTerminal = false
        return {
            guard !isTerminal else {
                return nil
            }
            let row: Row?
            do {
                row = try xlMappingDatabaseErrors(driver: driver) {
                    try cursor.next()
                }
            }
            catch {
                isTerminal = true
                throw error
            }
            guard let row else {
                isTerminal = true
                return nil
            }
            values.removeAll(keepingCapacity: true)
            values.reserveCapacity(row.count)
            for databaseValue in row.databaseValues {
                values.append(databaseValue.sqliteDialectValue)
            }
            return values
        }
    }

    @discardableResult
    mutating func execute(_ statement: GRDBPhysicalStatement) throws -> XLExecutionResult {
        try validateOwnership(of: statement)
        let arguments = statementArguments(statement)
        let database = database
        return try mappingDatabaseErrors {
            let totalChangesBefore = database.totalChangesCount
            try statement.statement.execute(arguments: arguments)
            // `sqlite3_changes` keeps the count of the last INSERT, UPDATE,
            // or DELETE, so a statement that changed nothing, such as
            // `CREATE TABLE`, would report an earlier statement's count. The
            // total change count moves only when this statement changed rows.
            let changed = database.totalChangesCount != totalChangesBefore
            return XLExecutionResult(
                rowsAffected: changed ? database.changesCount : 0,
                access: statement.statement.isReadonly ? .read : .write
            )
        }
    }

    ///
    /// Runs `body`, reporting a GRDB `DatabaseError` it throws as an
    /// `XLDatabaseError` from this connection's driver (issue #679).
    ///
    private func mappingDatabaseErrors<Result>(
        _ body: () throws -> Result
    ) throws -> Result {
        try xlMappingDatabaseErrors(driver: driverIdentifier, body)
    }

    /// Installs the custom SQLite functions referenced by the statement about to execute, once per
    /// physical connection.
    ///
    /// This runs before every execution, because `DatabasePool` hands a statement to any of several
    /// persistent connections and `Database.add(function:)` affects only the one it runs on. It
    /// must not install the same definition twice on one connection, though. SQLite treats a second
    /// `sqlite3_create_function` for the same name and argument count as a modification: while a
    /// statement is active on the connection -- a result-set cursor inside a transaction -- it
    /// returns `SQLITE_BUSY`, which GRDB turns into a `fatalError`, and otherwise it expires every
    /// prepared statement on the connection (issue #640).
    ///
    /// What SwiftQL installed is therefore recorded on the physical connection itself; see
    /// `GRDBInstalledFunctionMarker`. The record lives and dies with the SQLite connection, so a
    /// closed reader or a reopened pool cannot leave a stale record that claims a function is
    /// installed on a new connection, and every `GRDBDatabase` over the same pool reads the same
    /// record. No table outside the connection is involved.
    ///
    /// A registration that defers to an existing one -- a function SwiftQL bundles rather than one
    /// the caller wrote, such as `XLCustomFunctionRegistration.bundledRegexp` -- is skipped when
    /// the application already provides that function. A `PRAGMA function_list` row counts as the
    /// application's only when SwiftQL recorded no installation of that signature on the
    /// connection: SwiftQL never installs a definition without recording it, so an unrecorded row
    /// cannot be SwiftQL's own. The bundled decision -- install or defer -- is recorded too, so the
    /// probe runs once per connection and signature rather than once per execution.
    ///
    /// A registration from the application's own ``XLCustomFunction`` keeps its separate record, so
    /// it still wins over a bundled function of the same signature: the bundled registration defers
    /// to it, and it installs over a bundled function that SwiftQL installed first. It also installs
    /// over a SQLite built-in of the same signature, such as `lower/1`, because the statement
    /// referenced the application's function. Those replacements are the installs that meet a
    /// function with the same name and argument count, and SQLite refuses them while a statement is
    /// active on the connection. They then throw `XLDatabaseContractError.prepareFailure` instead of
    /// reaching GRDB's `fatalError`; see `checkNoActiveStatementBlocksReplacing(_:)`. When the
    /// function already on the connection is a registered one that SwiftQL did not install -- the
    /// application's own, from ``GRDBDatabaseBuilder/addFunction(_:)``, a `prepareDatabase` hook, or
    /// an extension it loaded -- nothing is replaced: SwiftQL records it and uses it.
    ///
    /// The record is kept per signature, not per Swift type. Registrations that share a
    /// ``XLCustomFunctionRegistration/definition`` are interchangeable, as that property documents,
    /// so the first application ``XLCustomFunction`` installed for a signature serves every later
    /// statement on the connection that calls any type with that signature.
    ///
    /// - Throws: `XLDatabaseContractError.prepareFailure` when an install would replace a function
    ///   while a statement is active on the connection, or a preparation failure while reading a
    ///   marker.
    func registerCustomFunctions(
        _ registrations: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) throws {
        // A marker probe prepares a statement through GRDB, so a failure
        // there, such as `SQLITE_BUSY`, is reported as an `XLDatabaseError`.
        try mappingDatabaseErrors {
            try registerCustomFunctionsUnmapped(registrations)
        }
    }

    /// `registerCustomFunctions(_:)` before its GRDB errors are mapped.
    private func registerCustomFunctionsUnmapped(
        _ registrations: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) throws {
        for registration in registrations.values {
            let definition = registration.definition
            let customMarker = GRDBInstalledFunctionMarker(definition: definition, kind: .custom)
            guard registration.defersToExistingRegistration else {
                if try customMarker.isRecorded(in: database) {
                    continue
                }
                switch existingExactFunction(matching: definition) {
                case .absent:
                    break
                case .builtIn:
                    // Only a SQLite built-in answers this signature, such as `lower/1`. The
                    // statement referenced the application's own function, so it replaces the
                    // built-in on this connection, as it always has -- unless SQLite cannot
                    // right now.
                    try checkNoActiveStatementBlocksReplacing(definition)
                case .installedOnConnection:
                    let bundledImplementationMarker = GRDBInstalledFunctionMarker(
                        definition: definition,
                        kind: .bundledImplementation
                    )
                    guard try bundledImplementationMarker.isRecorded(in: database) else {
                        // The application installed this signature itself -- with
                        // `GRDBDatabaseBuilder.addFunction(_:)`, its own `prepareDatabase` hook,
                        // or an extension it loaded -- so the connection already has the
                        // application's function. Use it: replacing it would expire the
                        // connection's statements, and would fail inside an open cursor.
                        customMarker.record(in: database)
                        continue
                    }
                    // SwiftQL's own bundled implementation is installed, and the application's
                    // function wins over it, so replace it -- unless SQLite cannot right now.
                    try checkNoActiveStatementBlocksReplacing(definition)
                }
                database.add(function: registration.makeDatabaseFunction())
                customMarker.record(in: database)
                continue
            }
            let bundledMarker = GRDBInstalledFunctionMarker(definition: definition, kind: .bundled)
            if try bundledMarker.isRecorded(in: database) {
                continue
            }
            let applicationProvides = try customMarker.isRecorded(in: database)
                || hasFunction(matching: definition)
            if !applicationProvides {
                database.add(function: registration.makeDatabaseFunction())
                GRDBInstalledFunctionMarker(definition: definition, kind: .bundledImplementation)
                    .record(in: database)
            }
            bundledMarker.record(in: database)
        }
    }

    /// Whether this physical connection already has a SQLite function this registration would
    /// replace.
    ///
    /// SQLite keys a function on its name *and* its argument count, so a name test alone is
    /// wrong in both directions. An application that registers an unrelated `regexp/1` would
    /// block the bundled `regexp/2` the operator actually calls, and every statement using
    /// `REGEXP` would then fail with `no such function: regexp`. A row therefore has to match the
    /// name and either the exact argument count or `-1`, which is what `PRAGMA function_list`
    /// reports for a variadic function -- a variadic `regexp` can serve the two-argument call, so
    /// it counts as provided.
    ///
    /// Names are compared case-insensitively over ASCII, which is how SQLite itself compares
    /// them, and how the build validator's runtime capture compares them.
    ///
    /// A connection whose SQLite build omits the introspection pragmas answers nothing, which is
    /// read as "the application provides no such function". On such a build the bundled
    /// implementation is registered and does replace a caller's own, because nothing can observe
    /// that theirs is there. That is the better of the two failure modes: the alternative --
    /// treating an unanswerable probe as "already provided" -- would leave `REGEXP` unusable on
    /// every connection, including the overwhelming majority that registered nothing. SQLite has
    /// reported `PRAGMA function_list` since 3.30, and the package's supported builds all do.
    private func hasFunction(matching definition: XLCustomFunctionDefinition) -> Bool {
        let folded = sqliteASCIIFoldedFunctionName(definition.name)
        guard let rows = try? Row.fetchAll(database, sql: "PRAGMA function_list") else {
            return false
        }
        return rows.contains { row in
            guard let name = row["name"] as String?,
                  sqliteASCIIFoldedFunctionName(name) == folded
            else {
                return false
            }
            guard let argumentCount = row["narg"] as Int? else {
                // A build that reports no argument count cannot distinguish the overloads, so
                // treat the name as the whole answer rather than registering over the caller.
                return true
            }
            return argumentCount == definition.numberOfArguments || argumentCount == -1
        }
    }

    /// What already answers exactly `definition`'s signature on this physical connection.
    private enum ExistingFunction {
        /// Nothing: installing creates a new function, which SQLite always allows.
        case absent
        /// Only a SQLite built-in, such as `lower/1`.
        case builtIn
        /// A function registered on this connection: by the application's setup, by an extension
        /// it loaded, or by SwiftQL's own bundled install.
        case installedOnConnection
    }

    /// Reads `PRAGMA function_list` for rows with exactly `definition`'s name and argument count.
    ///
    /// `add(function:)` replaces only a function with the same name *and* the same argument count,
    /// so a variadic row does not count here. A row whose `builtin` column is `1` is one of SQLite's
    /// own functions; any other row was registered on the connection. When both exist -- the
    /// application overrode a built-in in its own setup -- the registered one is what SQLite calls,
    /// so it decides the answer. A build that reports no argument count or no `builtin` column
    /// reads as registered, the answer that never replaces the application's function.
    private func existingExactFunction(
        matching definition: XLCustomFunctionDefinition
    ) -> ExistingFunction {
        let folded = sqliteASCIIFoldedFunctionName(definition.name)
        guard let rows = try? Row.fetchAll(database, sql: "PRAGMA function_list") else {
            return .absent
        }
        var existing = ExistingFunction.absent
        for row in rows {
            guard let name = row["name"] as String?,
                  sqliteASCIIFoldedFunctionName(name) == folded
            else {
                continue
            }
            guard let argumentCount = row["narg"] as Int? else {
                // No argument count to tell the overloads apart: read the name as registered,
                // so the application's function is never replaced on a guess.
                return .installedOnConnection
            }
            guard argumentCount == definition.numberOfArguments else {
                continue
            }
            guard (row["builtin"] as Int?) == 1 else {
                return .installedOnConnection
            }
            existing = .builtIn
        }
        return existing
    }

    /// Throws when the function that answers `definition`'s signature -- SwiftQL's bundled
    /// implementation or a SQLite built-in -- cannot be replaced right now, because a statement is
    /// active on this connection.
    ///
    /// SQLite answers a replacement during an active statement with `SQLITE_BUSY`, and GRDB 6 calls
    /// `fatalError` on any failed `sqlite3_create_function_v2`, so it has to be refused before
    /// `add(function:)` runs. The way to get here is an application ``XLCustomFunction`` that
    /// reuses a bundled or built-in signature, called for the first time on a connection from
    /// inside a `withResultSet` callback.
    private func checkNoActiveStatementBlocksReplacing(
        _ definition: XLCustomFunctionDefinition
    ) throws {
        guard hasActiveStatement() else {
            return
        }
        throw XLDatabaseContractError.prepareFailure(
            driver: driverIdentifier,
            message: """
                Cannot install the application's XLCustomFunction \
                \(definition.name)/\(definition.numberOfArguments) over the existing function with \
                the same name and argument count (SwiftQL's bundled implementation or a SQLite \
                built-in) while a statement is active on this connection: SQLite cannot replace a \
                function until the statement finishes. Run a statement that uses the application's \
                function before opening the result set, or register it up front with \
                GRDBDatabaseBuilder.addFunction(_:).
                """
        )
    }

    /// Whether any statement on this physical connection has started stepping and not yet been
    /// reset -- the condition under which SQLite refuses to replace a function.
    private func hasActiveStatement() -> Bool {
        guard let connection = database.sqliteConnection else {
            return false
        }
        var statement = sqlite3_next_stmt(connection, nil)
        while let current = statement {
            if sqlite3_stmt_busy(current) != 0 {
                return true
            }
            statement = sqlite3_next_stmt(connection, current)
        }
        return false
    }

    #if DEBUG
    /// How many SQLite statements are prepared and not yet finalized on this
    /// physical connection. A statement preparation adds one, so tests read
    /// the difference to count preparations (issue #668).
    private func liveStatementCount() -> Int {
        guard let connection = database.sqliteConnection else {
            return 0
        }
        var count = 0
        var statement = sqlite3_next_stmt(connection, nil)
        while let current = statement {
            count += 1
            statement = sqlite3_next_stmt(connection, current)
        }
        return count
    }

    /// The path of this connection's main database file, or `nil` for an
    /// in-memory or temporary database. The preparation test hook filters by
    /// it (issue #668).
    private func mainDatabasePath() -> String? {
        guard
            let connection = database.sqliteConnection,
            let filename = sqlite3_db_filename(connection, "main"),
            filename.pointee != 0
        else {
            return nil
        }
        return String(cString: filename)
    }
    #endif

    ///
    /// Executes one row of a batch insert: `packet`'s values, bound by position
    /// to `statement` (issue #668).
    ///
    /// The batch prepares `statement` once, on this connection, inside the
    /// connection access that runs every row, and drops it when that access
    /// returns. Binding by position is correct because every slot of a batch
    /// statement is a named parameter in logical index order, which is exactly
    /// the positional table `statementArguments(_:)` builds for such a layout.
    /// This path skips that per-row dictionary. GRDB still checks the argument
    /// count against the statement's parameters before it binds.
    ///
    mutating func executeBatchRow(
        _ statement: GRDBPhysicalStatement,
        bindings packet: XLInvocationBindings<XLSQLiteValue>
    ) throws {
        try validateOwnership(of: statement)
        var arguments: [(any DatabaseValueConvertible)?] = []
        arguments.reserveCapacity(packet.bindings.count)
        for binding in packet.bindings {
            arguments.append(binding.value.databaseValue)
        }
        try mappingDatabaseErrors {
            try statement.statement.execute(arguments: StatementArguments(arguments))
        }
    }

    ///
    /// Runs `operation` on this connection inside a SQLite savepoint (issue
    /// #668).
    ///
    /// The savepoint is released when `operation` returns. When `operation`
    /// throws, every change it made is rolled back to the savepoint, the
    /// savepoint is released, and the original error is rethrown, so the
    /// savepoint is closed on every path out of this call. Must run inside an
    /// open transaction, which a pinned transaction scope always is.
    ///
    mutating func withSavepoint(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Void
    ) throws {
        var connection = self
        try xlMappingScopeErrors(driver: driverIdentifier) { operationError in
            try database.inSavepoint {
                try operationError.recording { try operation(&connection) }
                return .commit
            }
        }
        self = connection
    }

    private func validateOwnership(of statement: GRDBPhysicalStatement) throws {
        guard statement.connectionIdentifier == connectionIdentifier else {
            throw XLDatabaseContractError.prepareFailure(
                driver: driverIdentifier,
                message: "A physical statement cannot leave its owning connection."
            )
        }
    }

    private func statementArguments(
        _ statement: GRDBPhysicalStatement
    ) -> StatementArguments {
        let bindings = statement.bindings

        // Legacy direct driver clients predate static layouts. Preserve their
        // original argument construction when no layout metadata is present.
        guard !statement.logicalStatement.parameterLayout.isEmpty else {
            return legacyStatementArguments(bindings)
        }

        var physicalIndexByKey: [XLBindingKey: Int] = [:]
        var largestPhysicalIndex = 0

        for slot in statement.logicalStatement.parameterLayout.slots {
            let physicalIndex: Int
            switch slot.key {
            case .named:
                physicalIndex = largestPhysicalIndex + 1
            case .indexed(let zeroBasedIndex):
                physicalIndex = zeroBasedIndex + 1
            }
            physicalIndexByKey[slot.key] = physicalIndex
            largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
        }

        // SQLite's physical parameter table is positional even when the SQL
        // spells a placeholder by name. Supplying the complete table as one
        // positional array avoids two GRDB normalization hazards:
        //
        // - a named placeholder before `?NNN` must not shift `?NNN`; and
        // - distinct `:3` and `?3` placeholders must not collapse to the same
        //   GRDB argument name after their prefixes are stripped.
        //
        // Explicit-index gaps are real SQLite slots, so preserve them as NULL.
        var positional: [(any DatabaseValueConvertible)?] = Array(
            repeating: DatabaseValue.null,
            count: largestPhysicalIndex
        )
        for (key, value) in bindings {
            guard let physicalIndex = physicalIndexByKey[key] else {
                continue
            }
            positional[physicalIndex - 1] = value.databaseValue
        }

        return StatementArguments(positional)
    }

    private func legacyStatementArguments(
        _ bindings: [XLBindingKey: XLSQLiteValue]
    ) -> StatementArguments {
        var indexed: [Int: DatabaseValue] = [:]
        var named: [String: (any DatabaseValueConvertible)?] = [:]

        for (key, value) in bindings {
            switch key {
            case .indexed(let index):
                indexed[index] = value.databaseValue
            case .named(let name):
                named[name] = value.databaseValue
            }
        }

        let positional: [(any DatabaseValueConvertible)?]
        if let lastIndex = indexed.keys.max() {
            positional = (0 ... lastIndex).map { indexed[$0] ?? DatabaseValue.null }
        }
        else {
            positional = []
        }

        var arguments = StatementArguments(positional)
        _ = arguments.append(contentsOf: StatementArguments(named))
        return arguments
    }
}


struct GRDBPhysicalStatement {

    let logicalStatement: XLLogicalPreparedStatement

    fileprivate let connectionIdentifier: UUID

    fileprivate let statement: Statement

    fileprivate var bindings: [XLBindingKey: XLSQLiteValue]

    /// Whether this and `other` wrap the same GRDB statement instance. Tests
    /// use it to observe statement-cache reuse.
    func sharesGRDBStatement(with other: GRDBPhysicalStatement) -> Bool {
        statement === other.statement
    }
}


///
/// Records the GRDB statements that an open SwiftQL cursor is stepping
/// (issue #641).
///
/// GRDB's statement cache belongs to one physical connection and returns the
/// same `Statement` for the same SQL. Opening a cursor calls
/// `prepareExecution(withArguments:)`, which resets that statement. A nested
/// request with the same SQL on the same connection -- for example, a fetch
/// inside a `withResultSet` callback on a transaction scope -- would
/// therefore restart the outer cursor from the nested bindings, and the
/// outer iteration would silently repeat, skip, or never finish.
/// `GRDBDatabaseDriverConnection.preparePhysical` asks this record first and
/// prepares an uncached statement only when the cached one is in use, so the
/// ordinary path still uses the cache.
///
/// Keyed by statement identity, which also identifies the physical
/// connection, because a cached statement belongs to exactly one connection.
/// A key is recorded only while a cursor over the statement is open, and the
/// cursor retains the statement for that whole time, so a recorded
/// `ObjectIdentifier` cannot be reused by a different statement. The mark is
/// always removed when the cursor's scope returns or throws, so an abandoned
/// cursor or a throwing body cannot leave a statement marked.
///
final class GRDBOpenCursorStatements: @unchecked Sendable {

    static let shared = GRDBOpenCursorStatements()

    private let lock = NSLock()

    /// Open-cursor count per statement. A count, not a set, so that marking
    /// the same statement twice cannot unmark it early.
    private var openCursorCounts: [ObjectIdentifier: Int] = [:]

    private init() {}

    /// Whether a SwiftQL cursor is stepping `statement` now.
    func contains(_ statement: Statement) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return openCursorCounts[ObjectIdentifier(statement)] != nil
    }

    /// Marks `statement` in use for the duration of `body`, and always
    /// removes the mark afterward -- including when `body` throws.
    func withOpenCursor<Result>(
        on statement: Statement,
        _ body: () throws -> Result
    ) rethrows -> Result {
        let key = ObjectIdentifier(statement)
        lock.lock()
        openCursorCounts[key, default: 0] += 1
        lock.unlock()
        defer {
            lock.lock()
            if let count = openCursorCounts[key], count > 1 {
                openCursorCounts[key] = count - 1
            }
            else {
                openCursorCounts[key] = nil
            }
            lock.unlock()
        }
        return try body()
    }
}


#if DEBUG
///
/// Reports each SQLite statement that `GRDBDatabaseDriverConnection` prepares,
/// by its SQL text (issue #668).
///
/// Tests use it to prove that an operation prepared a statement once rather
/// than once per row. A GRDB statement-cache hit prepares nothing and is not
/// reported. It exists only in DEBUG builds, and the driver counts statements
/// only while an observer is attached, so release builds pay nothing.
///
/// The hook is process-wide, so each observer names the database file it
/// watches, and a preparation on any other file is not reported to it. Two
/// tests that run at the same time in one process -- `swift test --parallel`
/// runs test classes in separate processes -- therefore see only their own
/// database's preparations.
///
final class GRDBStatementPreparationTestHooks: @unchecked Sendable {

    private struct Observer {
        let databasePath: String
        let report: (String) -> Void
    }

    static let shared = GRDBStatementPreparationTestHooks()

    private let lock = NSLock()

    private var observers: [UUID: Observer] = [:]

    private init() {}

    var isObserving: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !observers.isEmpty
    }

    /// Calls `observer` with the SQL of every statement prepared on the
    /// database file at `databasePath` while `body` runs, and always detaches
    /// it afterward.
    func observe<Result>(
        databasePath: String,
        _ observer: @escaping (String) -> Void,
        during body: () throws -> Result
    ) rethrows -> Result {
        let identifier = UUID()
        lock.lock()
        observers[identifier] = Observer(
            databasePath: Self.canonicalPath(databasePath),
            report: observer
        )
        lock.unlock()
        defer {
            lock.lock()
            observers[identifier] = nil
            lock.unlock()
        }
        return try body()
    }

    func notifyPrepared(sql: String, databasePath: String?) {
        guard let databasePath else {
            return
        }
        let path = Self.canonicalPath(databasePath)
        lock.lock()
        let matching = observers.values.filter { $0.databasePath == path }
        lock.unlock()
        for observer in matching {
            observer.report(sql)
        }
    }

    /// Resolves symbolic links, so `/var/...` and `/private/var/...` name the
    /// same file.
    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
#endif


extension DatabaseValue {

    var sqliteDialectValue: XLSQLiteValue {
        switch storage {
        case .null:
            return .null
        case .int64(let value):
            return .integer(value)
        case .double(let value):
            return .real(value)
        case .string(let value):
            return .text(value)
        case .blob(let value):
            return .blob(value)
        }
    }
}


extension XLSQLiteValue {

    var databaseValue: DatabaseValue {
        switch self {
        case .null:
            return .null
        case .integer(let value):
            return value.databaseValue
        case .real(let value):
            return value.databaseValue
        case .text(let value):
            return value.databaseValue
        case .blob(let value):
            return value.databaseValue
        }
    }
}


private extension XLBindingKey {
    var valueEncodingPathComponent: String {
        switch self {
        case .named(let name):
            return name
        case .indexed(let index):
            return String(index)
        }
    }
}


///
/// Detects "root-executor re-entry" (issue #284): a call through the
/// *original, unpinned* database, reached from inside a scope that already
/// holds one of that database's connections.
///
/// `GRDBDatabaseDriver.isPinned` alone cannot catch this, because the
/// captured root database's own driver was never marked pinned — only the
/// scope handed to `body` was. And the crash this guards against cannot be
/// caught after the fact: GRDB's connection accesses are not reentrant, and
/// a reentrant call traps with an unconditional "Database methods are not
/// reentrant." before a single line of SwiftQL runs. This tracker must reject
/// the call *before* it reaches the pool at all.
///
/// Holds are keyed by the `DatabasePool`, not by a `GRDBDatabase`'s
/// identifier, because two databases can share one pool and GRDB's rule is
/// about the pool's connections.
///
/// A hold is scoped to the flow of control that took it, never to tasks it
/// creates. A task created inside a scope is concurrent work: its write
/// waits for the writer and runs after the scope, and its read sees
/// committed data, which is correct isolation for a separate task.
///
/// - A hold taken in synchronous code -- every scope today, including the
///   body of `withTransaction(_:)` on a database -- is kept per thread, in
///   thread-local storage. Nothing in a synchronous extent can suspend, so
///   the thread is exactly its flow of control, and GRDB's own rule is per
///   thread too. Tasks never inherit it.
/// - A transaction held across suspension points, as an asynchronous
///   transaction body will be (#681), is kept in a `@TaskLocal` (issue
///   #676), so a call after an `await` still sees it wherever the task
///   resumes. It records its owning task, so a task created inside it, which
///   inherits the task-local list, is not rejected.
///
/// Callers of the synchronous `withActive(_:holding:_:)` must enter it in the
/// same synchronous extent that runs `body` -- for the GRDB adapter, *inside*
/// the pool's `read`/`write` closure, not around it. GRDB may run that
/// closure on its own queue's thread.
final class GRDBTransactionScopeTracker: Sendable {

    static let shared = GRDBTransactionScopeTracker()

    @TaskLocal
    private static var asyncTransactions: [AsyncTransaction] = []

    /// What a synchronous scope holds. Each hold rejects exactly the root
    /// accesses from the same thread that GRDB would stop, plus a read that
    /// would miss uncommitted writes.
    ///
    /// Not `Sendable`: a hold stays on the thread that took it.
    enum Hold {
        /// One pooled reader. A root read is rejected: GRDB would stop a
        /// second read from this thread. A root write runs on GRDB's separate
        /// writer.
        case reader
        /// The writer, and the connection that holds it. A root write is
        /// rejected: GRDB would stop a second write from this thread. A root
        /// read is rejected while the connection is inside a transaction,
        /// because it would miss the uncommitted writes, and runs otherwise
        /// (see `runTransaction(on:kind:_:)` for the commit itself).
        case writer(Database)
    }

    /// The access a new root-database call asks for.
    enum Access: Sendable {
        case read
        case write
    }

    private init() {}

    /// Whether a root access to `pool` must be refused, because a scope in
    /// the same flow of control holds one of its connections.
    func rejects(_ access: Access, on pool: DatabasePool) -> Bool {
        let key = ObjectIdentifier(pool)
        if let holds = ThreadHolds.existing, holds.rejects(access, on: key) {
            return true
        }
        let transactions = Self.asyncTransactions
        guard !transactions.isEmpty else {
            return false
        }
        return withUnsafeCurrentTask { task in
            guard let task else {
                return false
            }
            return transactions.contains { transaction in
                transaction.pool == key
                    && transaction.isOpen
                    && transaction.owner == task
            }
        }
    }

    /// Marks `pool` as held on the calling thread for the duration of `body`,
    /// and always clears it again afterward -- including when `body` throws.
    func withActive<Result>(
        _ pool: DatabasePool,
        holding hold: Hold,
        _ body: () throws -> Result
    ) throws -> Result {
        let holds = ThreadHolds.current
        holds.push(ObjectIdentifier(pool), hold)
        defer { holds.pop() }
        return try body()
    }

    /// Marks `pool` as held by a transaction in the calling task for the
    /// duration of `body`, across every suspension point in it.
    ///
    /// This is the entry point for an asynchronous transaction body (#681).
    func withAsyncTransaction<Result>(
        on pool: DatabasePool,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Result
    ) async throws -> Result {
        // An async function always runs in a task, so `owner` is set.
        let owner = withUnsafeCurrentTask { $0 }
        let transaction = AsyncTransaction(ObjectIdentifier(pool), owner: owner)
        defer { transaction.close() }
        return try await Self.$asyncTransactions.withValue(Self.asyncTransactions + [transaction]) {
            try await body()
        }
    }

    /// One asynchronous transaction hold and the task that owns it.
    ///
    /// The owner is compared by identity: `UnsafeCurrentTask` equality
    /// compares the task pointers. The value is kept beyond the closure that
    /// produced it, which is safe here because it is only compared, never
    /// used to reach the task, and only while the hold is open, when the
    /// owner is still running `body`. The hold is closed when the owner's
    /// scope returns, so a task that later reuses the owner's address cannot
    /// match.
    private final class AsyncTransaction: @unchecked Sendable {

        let pool: ObjectIdentifier

        let owner: UnsafeCurrentTask?

        private let lock = NSLock()
        private var closed = false

        init(_ pool: ObjectIdentifier, owner: UnsafeCurrentTask?) {
            self.pool = pool
            self.owner = owner
        }

        var isOpen: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !closed
        }

        func close() {
            lock.lock()
            defer { lock.unlock() }
            closed = true
        }
    }

    ///
    /// The holds of one thread, innermost last.
    ///
    /// Only its own thread reads or writes it, so it needs no lock. It lives
    /// in pthread thread-local storage, which a task never inherits, and is
    /// released when its thread exits.
    ///
    private final class ThreadHolds {

        private var holds: [(pool: ObjectIdentifier, hold: Hold)] = []

        func push(_ pool: ObjectIdentifier, _ hold: Hold) {
            holds.append((pool, hold))
        }

        func pop() {
            holds.removeLast()
        }

        func rejects(_ access: Access, on pool: ObjectIdentifier) -> Bool {
            holds.contains { entry in
                guard entry.pool == pool else {
                    return false
                }
                switch entry.hold {
                case .reader:
                    return access == .read
                case .writer(let database):
                    return access == .write || Self.isInsideTransaction(database)
                }
            }
        }

        /// Whether `database` is inside a transaction, read from SQLite's
        /// autocommit flag. `Database.isInsideTransaction` asserts that it
        /// runs on the database's queue, and a check can run on this thread
        /// under another queue; the flag itself is safe to read on the thread
        /// that holds the connection.
        private static func isInsideTransaction(_ database: Database) -> Bool {
            guard let connection = database.sqliteConnection else {
                return false
            }
            return sqlite3_get_autocommit(connection) == 0
        }

        /// This thread's holds, or `nil` when it has never taken one. A
        /// check never allocates.
        static var existing: ThreadHolds? {
            pthread_getspecific(key).map { pointer in
                Unmanaged<ThreadHolds>.fromOpaque(pointer).takeUnretainedValue()
            }
        }

        /// This thread's holds, created on the first hold it takes.
        static var current: ThreadHolds {
            if let holds = existing {
                return holds
            }
            let holds = ThreadHolds()
            pthread_setspecific(key, Unmanaged.passRetained(holds).toOpaque())
            return holds
        }

        private static let key: pthread_key_t = {
            var key = pthread_key_t()
            let status = pthread_key_create(&key, releaseThreadHolds)
            precondition(status == 0, "pthread_key_create failed: \(status)")
            return key
        }()
    }
}


/// Releases one thread's `ThreadHolds` when the thread exits.
#if canImport(Darwin)
private func releaseThreadHolds(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<AnyObject>.fromOpaque(pointer).release()
}
#else
private func releaseThreadHolds(_ pointer: UnsafeMutableRawPointer?) {
    if let pointer {
        Unmanaged<AnyObject>.fromOpaque(pointer).release()
    }
}
#endif


///
/// A record, kept on one physical SQLite connection, that SwiftQL installed -- or, for a bundled
/// function, decided about -- one custom function signature there (issue #640).
///
/// The record is itself a zero-argument SQLite function, named from the signature and the kind of
/// registration. It is read by preparing a call to it: preparation succeeds only on a connection
/// where the marker was created. GRDB's per-connection statement cache keeps that statement, so
/// every later check is one dictionary lookup. A connection without the marker answers with
/// SQLite's "no such function" preparation error, which is the expected "not recorded" answer and
/// never reaches the caller; it is only seen until the marker is created.
///
/// Why on the connection rather than in a Swift table:
///
/// - GRDB closes and opens physical connections over a pool's life (a released reader, a
///   reopened pool), and a new connection can reuse an old one's address. A table keyed by
///   `ObjectIdentifier(Database)` or by the `sqlite3 *` pointer could then claim a function is
///   installed on a connection that never saw it. A SQLite function cannot outlive its connection.
/// - Two `GRDBDatabase` values can share one `DatabasePool`. A table owned by one of them cannot
///   see what the other installed; the connection sees both.
/// - Registration is per physical connection, so a process-global table would be the wrong scope.
///
/// Creating a function under a *new* name neither expires prepared statements nor fails while a
/// statement is active -- SQLite does either only when it replaces a definition with the same name
/// and argument count -- so a marker can be recorded inside an open cursor.
///
struct GRDBInstalledFunctionMarker {

    enum Kind: String {
        /// A bundled registration was decided on this connection: SwiftQL installed its
        /// implementation, or found the application's and deferred to it.
        case bundled
        /// SwiftQL installed its own bundled implementation on this connection. Read only the
        /// first time an application ``XLCustomFunction`` of the same signature runs there, to tell
        /// SwiftQL's implementation apart from one the application installed itself.
        case bundledImplementation
        /// The application's own ``XLCustomFunction`` is on this connection: SwiftQL installed it,
        /// or found that the application had already installed that signature itself.
        case custom
    }

    let name: String

    init(definition: XLCustomFunctionDefinition, kind: Kind) {
        // The name is always a plain SQL identifier, whatever the function's own name contains, and
        // stays well under SQLite's 255-byte limit on function names. SQLite folds function names
        // over ASCII, so the hash does too. A hash collision between two signatures used on one
        // connection would skip an install, which surfaces as "no such function", never a crash.
        let arity = definition.numberOfArguments < 0 ? "v" : String(definition.numberOfArguments)
        let foldedName = sqliteASCIIFoldedFunctionName(definition.name)
        self.name = "swiftql_installed_\(kind.rawValue)_\(arity)_\(Self.fnv1a64Hex(foldedName))"
    }

    /// Whether this marker exists on `database`'s physical connection.
    ///
    /// - Throws: Any preparation failure other than SQLite's "no such function", which is the
    ///   "not recorded" answer.
    func isRecorded(in database: Database) throws -> Bool {
        do {
            _ = try database.cachedStatement(sql: "SELECT \(name)()")
            return true
        }
        catch let error as DatabaseError
            where error.resultCode == .SQLITE_ERROR
            && (error.message ?? "").hasPrefix("no such function")
        {
            return false
        }
    }

    /// Creates this marker on `database`'s physical connection.
    func record(in database: Database) {
        database.add(
            function: DatabaseFunction(name, argumentCount: 0, pure: true) { _ in nil }
        )
    }

    /// 64-bit FNV-1a over UTF-8, as lowercase hexadecimal. Stable across processes and platforms,
    /// unlike `Hasher`, and needs no cryptography library on Linux.
    private static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}


/// Folds a SQLite function name the way SQLite folds one when it looks a
/// function up: over ASCII only.
///
/// Swift's `lowercased()` folds the whole of Unicode, so it would call two
/// names equal that SQLite keeps apart. The build validator's runtime capture
/// folds the same way, and the two have to agree: a name the validator treats
/// as a distinct function must not be read here as the application's own.
func sqliteASCIIFoldedFunctionName(_ value: String) -> String {
    String(decoding: value.utf8.map { byte in
        if byte >= 0x41, byte <= 0x5A {
            return byte + 0x20
        }
        return byte
    }, as: UTF8.self)
}
