//
//  GRDBDatabaseDriver.swift
//

import Foundation
import GRDB


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
struct GRDBDatabaseDriver: XLDatabaseDriver, @unchecked Sendable {

    typealias Dialect = XLSQLiteDialect

    typealias Connection = GRDBDatabaseDriverConnection

    let driverIdentifier = XLDriverIdentifier(rawValue: "grdb")

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

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
        self.access = .pool(databasePool)
        self.dialect = dialect
        self.databaseIdentifier = databaseIdentifier
    }

    private init(
        access: Access,
        dialect: XLSQLiteDialect,
        databaseIdentifier: XLDatabaseIdentifier
    ) {
        self.access = access
        self.dialect = dialect
        self.databaseIdentifier = databaseIdentifier
    }

    ///
    /// Produces a driver pinned to `box`'s connection for the duration of one
    /// transaction scope. Every connection access on the returned driver
    /// reuses that connection directly instead of leasing one from the pool.
    ///
    /// Deliberately assigns a **fresh** `databaseIdentifier` rather than
    /// reusing this driver's own: a `@SQLQuery`/`@SQLQueries` render-once
    /// cache entry (``XLPreparedQueryCacheKey``) caches a fully-built
    /// `GRDBRequest`/`GRDBWriteRequest` — which closes over one specific
    /// driver — not just the rendered SQL text. Sharing the pool-backed
    /// database's identifier would let a declared query first populated
    /// outside a transaction permanently bind that entry to the pool driver
    /// (silently re-entering the pool from inside every later transaction
    /// instead of using the pinned connection), or let a declared query first
    /// populated *inside* one transaction hand a later, unrelated call a
    /// `GRDBRequest` bound to that transaction's already-invalidated pinned
    /// box. A fresh identifier per scope gives every transaction its own
    /// cache entry instead: one extra render the first time a declared query
    /// is used inside a given transaction, in exchange for never reusing a
    /// request built for a different connection.
    ///
    func pinned(to box: GRDBPinnedConnectionBox) -> GRDBDatabaseDriver {
        GRDBDatabaseDriver(
            access: .pinned(box),
            dialect: dialect,
            databaseIdentifier: XLDatabaseIdentifier(rawValue: UUID())
        )
    }

    mutating func withReadConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant()
            return try pool.read { database in
                var connection = makeConnection(database)
                return try operation(&connection)
            }
        case .pinned(let box):
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    mutating func withWriteConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant()
            return try pool.writeWithoutTransaction { database in
                var connection = makeConnection(database)
                return try operation(&connection)
            }
        case .pinned(let box):
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    mutating func withTransaction<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        switch access {
        case .pool(let pool):
            try preconditionNotRootReentrant()
            return try pool.write { database in
                var connection = makeConnection(database)
                return try operation(&connection)
            }
        case .pinned(let box):
            // Already running inside the one real transaction that the
            // owning `XLTransactionalDatabase.withTransaction(_:)` scope
            // opened with `databasePool.write`. A write statement executed
            // through the ordinary v1 request path calls this method once
            // per statement, so reuse the pinned connection directly instead
            // of asking GRDB for a second write access — GRDB's own writer
            // queue is not reentrant, and a second `databasePool.write` here
            // would deadlock instead of composing as a nested transaction.
            var connection = try box.connection(makeConnection: makeConnection)
            return try operation(&connection)
        }
    }

    ///
    /// Rejects "root-executor re-entry" (issue #284): any pool-mode
    /// connection access — read *or* write — issued through this driver's
    /// `databaseIdentifier` while a ``XLTransactionalDatabase/withTransaction(_:)``
    /// scope for that same identifier is already active on the calling
    /// thread. This is what protects a plain `SELECT` issued through the
    /// captured root database from inside an active transaction body, not
    /// just a second `withTransaction(_:)` call: GRDB's reader pool is not
    /// reentrant-locked with its writer, so a stray read like that would not
    /// crash or deadlock — it would just silently lease a different
    /// connection and return the database's last *committed* state, missing
    /// the transaction's own uncommitted writes, exactly the "lease another
    /// connection... and break the transaction boundary" hazard the hard
    /// constraints call out. See ``GRDBTransactionScopeTracker``.
    ///
    private func preconditionNotRootReentrant() throws {
        guard !GRDBTransactionScopeTracker.shared.isActive(databaseIdentifier) else {
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

    init(_ database: Database) {
        self.database = database
    }

    /// Invalidates the box. Called once, when the owning
    /// `databasePool.write` access is about to return (commit or rollback).
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
        guard let database else {
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
    /// Registered unconditionally on whatever physical connection is checked out immediately
    /// before every execution (see `boundStatement`), rather than once upfront. `DatabasePool`
    /// hands out any of several persistent reader connections, and a `Database.add(function:)`
    /// call only affects the one physical connection it runs on -- so there is no single "first
    /// use" moment this could register at once and be done. Re-registering on every execution
    /// costs one cheap `sqlite3_create_function` call and guarantees correctness regardless of
    /// which pooled connection served the request.
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
        var driver = driver
        return try driver.withReadConnection { connection in
            try fetchAll(packet: packet, in: &connection)
        }
    }

    func fetchAll(
        packet: XLInvocationBindings<XLSQLiteValue>,
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
        var driver = driver
        try driver.withReadConnection { connection in
            try forEachRow(
                packet: packet,
                in: &connection,
                body
            )
        }
    }

    func forEachRow(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try connection.forEachRow(
            boundStatement(packet: packet, in: &connection),
            body
        )
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> [XLSQLiteValue]? {
        let packet = try sqlitePacket(bindings)
        var driver = driver
        return try driver.withReadConnection { connection in
            try fetchOne(packet: packet, in: &connection)
        }
    }

    func fetchOne(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [XLSQLiteValue]? {
        try connection.fetchOne(boundStatement(packet: packet, in: &connection))
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        let packet = try sqlitePacket(bindings)
        var driver = driver
        try driver.withTransaction { connection in
            try execute(packet: packet, in: &connection)
        }
    }

    func execute(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws {
        try connection.execute(boundStatement(packet: packet, in: &connection))
    }

    func sqlitePacket(
        _ bindings: any XLInvocationBindingPacket
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        if let valueEncodingError {
            throw valueEncodingError
        }
        if let parameterLayoutError {
            throw parameterLayoutError
        }
        guard let packet = bindings as? XLInvocationBindings<XLSQLiteValue> else {
            throw XLRequestBindingError.incompatibleInvocationPacket(
                requestType: String(reflecting: Self.self),
                expectedDialect: XLSQLiteDialect.identity,
                expectedValueType: String(reflecting: XLSQLiteValue.self),
                actualPacketType: String(reflecting: type(of: bindings))
            )
        }
        guard packet.layout == parameterLayout else {
            throw XLInvocationBindingError.packetLayoutMismatch(
                expected: parameterLayout,
                actual: packet.layout
            )
        }
        let validatedPacket = try packet.validatingComplete()
        for binding in validatedPacket.bindings {
            if case .real(let value) = binding.value,
               let error = XLSQLValueEncodingError.bindingFailure(
                   for: value,
                   valueType: binding.slot.valueTypeName,
                   context: binding.slot.codingContext
               ) {
                throw error
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

    private func boundStatement(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> GRDBPhysicalStatement {
        connection.registerCustomFunctions(customFunctions)
        let packet = try sqlitePacket(packet)
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

    /// Executes a command with one immutable binding packet.
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
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
        return GRDBPhysicalStatement(
            logicalStatement: statement,
            connectionIdentifier: connectionIdentifier,
            statement: try database.cachedStatement(sql: statement.sql),
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

    mutating func execute(_ statement: GRDBPhysicalStatement) throws {
        try validateOwnership(of: statement)
        try statement.statement.execute(
            arguments: statementArguments(statement)
        )
    }

    /// Registers custom SQLite functions referenced by the statement about to execute on this
    /// connection's underlying physical connection.
    ///
    /// Unconditional and idempotent: SQLite's `sqlite3_create_function` simply replaces any
    /// existing registration for the same name and argument count, so calling this before every
    /// execution is correct however many times it runs, on however many distinct physical
    /// connections `DatabasePool` hands out over the connection's lifetime.
    func registerCustomFunctions(
        _ registrations: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) {
        for registration in registrations.values {
            database.add(function: registration.makeDatabaseFunction())
        }
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
}


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
/// Detects "root-executor re-entry" (issue #284): a second
/// `withTransaction(_:)` call, reached from inside an already-active body,
/// on the *original, unpinned* database value rather than the pinned scope
/// `body` was given.
///
/// `GRDBDatabaseDriver.isPinned` alone cannot catch this, because the
/// captured root database's own driver was never marked pinned — only the
/// scope handed to `body` was. And the crash this guards against cannot be
/// caught after the fact: GRDB's writer access is not reentrant, and a
/// reentrant `DatabasePool.write`/`writeWithoutTransaction` call traps with
/// an unconditional `fatalError` ("Database methods are not reentrant.")
/// before a single line of SwiftQL runs. This tracker must reject the call
/// *before* it reaches `databasePool.write` at all.
///
/// Scoped per-`Thread` rather than per-pool: `body` runs synchronously to
/// completion, so a call nested inside it is necessarily on the same thread
/// as the active scope. Two independent, concurrent `withTransaction(_:)`
/// calls from different threads are unrelated activations — each has its own
/// thread dictionary — and both must succeed, serialized safely by GRDB's own
/// writer queue.
///
/// Callers must enter `withActive(_:_:)` on the same thread that will run
/// `body` -- for the GRDB adapter, that means *inside* the
/// `databasePool.write(_:)` closure, not around it. GRDB dispatches that
/// closure onto its own writer thread, which is not necessarily the caller's
/// thread; marking active before calling `databasePool.write` would leave a
/// reentrant call made from inside `body` unable to see the marker, silently
/// defeating this guard.
final class GRDBTransactionScopeTracker: @unchecked Sendable {

    static let shared = GRDBTransactionScopeTracker()

    private let key = "swiftql.grdb.activeTransactionScopeDatabaseIdentifiers"

    private init() {}

    func isActive(_ databaseIdentifier: XLDatabaseIdentifier) -> Bool {
        activeIdentifiers.contains(databaseIdentifier)
    }

    /// Marks `databaseIdentifier` active on the calling thread for the
    /// duration of `body`, and always clears it again afterward — including
    /// when `body` throws.
    func withActive<Result>(
        _ databaseIdentifier: XLDatabaseIdentifier,
        _ body: () throws -> Result
    ) throws -> Result {
        var identifiers = activeIdentifiers
        identifiers.insert(databaseIdentifier)
        activeIdentifiers = identifiers
        defer {
            var identifiers = activeIdentifiers
            identifiers.remove(databaseIdentifier)
            activeIdentifiers = identifiers
        }
        return try body()
    }

    private var activeIdentifiers: Set<XLDatabaseIdentifier> {
        get {
            Thread.current.threadDictionary[key] as? Set<XLDatabaseIdentifier> ?? []
        }
        set {
            Thread.current.threadDictionary[key] = newValue
        }
    }
}
