//
//  GRDBDatabaseDriver.swift
//

import Foundation
import GRDB


/// GRDB transport for SQLite dialect values.
///
/// The driver is internal to the v1 compatibility facade. Public code depends
/// on the adapter-neutral contracts from `SwiftQLCore`.
struct GRDBDatabaseDriver: XLDatabaseDriver, Sendable {

    typealias Dialect = XLSQLiteDialect

    typealias Connection = GRDBDatabaseDriverConnection

    let driverIdentifier = XLDriverIdentifier(rawValue: "grdb")

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

    let databasePool: DatabasePool

    init(
        databasePool: DatabasePool,
        dialect: XLSQLiteDialect,
        databaseIdentifier: XLDatabaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    ) {
        self.databasePool = databasePool
        self.dialect = dialect
        self.databaseIdentifier = databaseIdentifier
    }

    mutating func withReadConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.read { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    mutating func withWriteConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.writeWithoutTransaction { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    mutating func withTransaction<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.write { database in
            var connection = makeConnection(database)
            return try operation(&connection)
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


/// Immutable, Sendable execution seam between prepared logical statements and
/// GRDB connections. Typed row decoding remains outside this value because the
/// legacy row-reader graph is not Sendable.
struct GRDBInvocationExecutor: Sendable {

    let driver: GRDBDatabaseDriver

    let logicalStatement: XLLogicalPreparedStatement

    let parameterLayoutError: XLInvocationBindingError?

    let valueEncodingError: XLSQLValueEncodingError?

    init(
        driver: GRDBDatabaseDriver,
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
        // buffer for the next row and the retained values stay intact. Either
        // way no `[[XLSQLiteValue]]` matrix is materialized.
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
