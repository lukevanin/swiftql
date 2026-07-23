//
//  GRDBSQLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


struct GRDBRowAdapter: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(row: GRDB.Row) {
        self.reader = XLSQLiteValueReader(
            values: row.databaseValues.map(\.sqliteDialectValue)
        )
    }
    
    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }
    
    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


struct GRDBValuesAdapter: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(values: [GRDB.DatabaseValue]) {
        self.reader = XLSQLiteValueReader(
            values: values.map(\.sqliteDialectValue)
        )
    }
    
    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }
    
    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


/// Package-scoped decoding seam shared by the GRDB adapter and performance harness.
///
/// Keeping the adapter and sequential column reader behind this type lets benchmarks exercise the
/// production decoding path without exposing GRDB implementation details as public SwiftQL API.
package struct GRDBRowDecoder<Output> {

    private let reader: any XLRowReadable<Output>

    package init(reader: any XLRowReadable<Output>) {
        self.reader = reader
    }

    package func decode(_ row: GRDB.Row) throws -> Output {
        try decode(values: row.databaseValues.map(\.sqliteDialectValue))
    }

    func decode(values: [XLSQLiteValue]) throws -> Output {
        try XLColumnValuesRowReader<Output>.withReader(
            XLSQLiteValueReader(values: values)
        ) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }
}


fileprivate struct BindingContext: XLBindingContext {

    var value: XLSQLiteValue = .null
    
    mutating func bindNull() {
        self.value = .null
    }
    
    mutating func bindInteger(value: Int) {
        self.value = .integer(Int64(value))
    }
    
    mutating func bindReal(value: Double) {
        self.value = .real(value)
    }
    
    mutating func bindText(value: String) {
        self.value = .text(value)
    }
    
    mutating func bindBlob(value: Data) {
        self.value = .blob(value)
    }
}


/// The connection access a row-returning request needs.
///
/// Ordinary select queries decode from a read snapshot. A `RETURNING`
/// statement mutates the database while returning rows, so it must decode
/// inside a write transaction instead.
enum GRDBRequestAccess {
    case read
    case write
}


/// Failures specific to a `RETURNING` (row-returning write) request.
public enum GRDBReturningRequestError: Error, Equatable, LocalizedError, Sendable {

    /// Live observation of a data-changing `RETURNING` statement is not
    /// supported, because each refresh would re-execute the mutation.
    case observationUnsupported

    public var errorDescription: String? {
        switch self {
        case .observationUnsupported:
            return "A data-changing RETURNING statement cannot be observed, because each observation refresh would re-execute the mutation. Fetch it instead."
        }
    }
}


struct GRDBRequest<Row>: XLRequest {

    private let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration

    private let logger: XLLogger?

    private let reader: any XLRowReadable<Row>

    private let access: GRDBRequestAccess

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    private let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler

    private var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    private var compatibilityBindingError: XLInvocationBindingError?

    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        reader: any XLRowReadable<Row>,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        access: GRDBRequestAccess = .read,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) {
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.reader = reader
        self.access = access
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
        self.compatibilityBindings = XLInvocationBindings(
            layout: logicalStatement.parameterLayout
        )
        self.compatibilityBindingError = parameterLayoutError
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = parameterLayout.slot(for: declaration.key) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterDeclarationNotInLayout(
                    declaration: declaration
                )
            }
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            }
            return
        }
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        let value = (context as! BindingContext).value
        do {
            compatibilityBindings = try replacingBinding(
                value,
                at: slot,
                in: compatibilityBindings
            )
        }
        catch let error as XLInvocationBindingError {
            if compatibilityBindingError == nil {
                compatibilityBindingError = error
            }
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }
    
    func fetchAll() throws -> [Row] {
        try fetchAll(bindings: compatibilityPacket())
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "fetchAll: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        return try decodeRows(packet: packet)
    }

    private func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>
    ) throws -> [Row] {
        var driver = executor.driver
        switch access {
        case .read:
            return try driver.withReadConnection { connection in
                try decodeRows(packet: packet, in: &connection)
            }
        case .write:
            return try driver.withTransaction { connection in
                try decodeRows(packet: packet, in: &connection)
            }
        }
    }

    private func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRow(packet: packet, in: &connection) { values in
            do {
                let item = try rowDecoder.decode(values: values)
                items.append(item)
                return .advance
            }
            catch {
                logger?.error("fetchAll : Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }
    
    func fetchOne() throws -> Row? {
        try fetchOne(bindings: compatibilityPacket())
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "fetchOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        var driver = executor.driver
        let values: [XLSQLiteValue]?
        switch access {
        case .read:
            values = try driver.withReadConnection { connection in
                try executor.fetchOne(packet: packet, in: &connection)
            }
        case .write:
            values = try driver.withTransaction { connection in
                try executor.fetchOne(packet: packet, in: &connection)
            }
        }
        guard let values else {
            return nil
        }
        return try GRDBRowDecoder(reader: reader).decode(values: values)
    }
    
    func publish() -> AnyPublisher<[Row], Error> {
        do {
            return publish(bindings: try compatibilityPacket())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        if access == .write {
            return Fail(error: GRDBReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            return publisher { database in
                logger?.debug(
                    "fetchAll: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                return try decodeRows(packet: packet, in: &connection)
            }
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publishOne() -> AnyPublisher<Row?, Error> {
        do {
            return publishOne(bindings: try compatibilityPacket())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        if access == .write {
            return Fail(error: GRDBReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            return publisher { database in
                logger?.debug(
                    "fetchOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                guard let values = try executor.fetchOne(
                    packet: packet,
                    in: &connection
                ) else {
                    return nil
                }
                return try GRDBRowDecoder(reader: reader).decode(values: values)
            }
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }
    
    private func publisher<T>(fetch: @escaping (Database) throws -> T) -> AnyPublisher<T, Error> {
        let makeSource = {
#if canImport(Combine)
            ValueObservation
                .tracking(fetch)
                .publisher(in: executor.driver.databasePool)
                .eraseToAnyPublisher()
#else
            GRDBOpenCombineValuePublisher { onError, onChange in
                ValueObservation
                    .tracking(fetch)
                    .start(
                        in: executor.driver.databasePool,
                        onError: onError,
                        onChange: onChange
                    )
            }
            .eraseToAnyPublisher()
#endif
        }

        switch liveQueryRetryPolicy {
        case .terminal:
            return makeSource()
        case .retryBusy:
            return makeGRDBLiveQueryRetryPublisher(
                policy: liveQueryRetryPolicy,
                scheduler: liveQueryRetryScheduler,
                makeSource: makeSource
            )
        }
    }

    private func compatibilityPacket() throws -> XLInvocationBindings<XLSQLiteValue> {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        return compatibilityBindings
    }
}


struct GRDBWriteRequest: XLWriteRequest {

    private let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    private let logger: XLLogger?
    
    private var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    private var compatibilityBindingError: XLInvocationBindingError?
    
    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil
    ) {
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.compatibilityBindings = XLInvocationBindings(
            layout: logicalStatement.parameterLayout
        )
        self.compatibilityBindingError = parameterLayoutError
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = parameterLayout.slot(for: declaration.key) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterDeclarationNotInLayout(
                    declaration: declaration
                )
            }
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            }
            return
        }
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        let value = (context as! BindingContext).value
        do {
            compatibilityBindings = try replacingBinding(
                value,
                at: slot,
                in: compatibilityBindings
            )
        }
        catch let error as XLInvocationBindingError {
            if compatibilityBindingError == nil {
                compatibilityBindingError = error
            }
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }
    
    func execute() throws {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        try execute(bindings: compatibilityBindings)
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        try executor.execute(bindings: packet)
    }
}


private extension XLParameterSlot {

    func acceptsLegacySet(_ declaration: XLParameterDeclaration) -> Bool {
        self.declaration == declaration || isRendererLegacyBindingWildcard
    }

    /// `XLBuilder.namedBinding` and `indexedBinding` predate typed parameter
    /// declarations. The renderer records this exact sentinel so the v1
    /// mutating `set` facade can still normalize a value for custom expressions
    /// that emit placeholders directly. Typed and contextual slots never take
    /// this path and continue to require an exact declaration match.
    private var isRendererLegacyBindingWildcard: Bool {
        valueTypeIdentifier == XLValueTypeIdentifier(
            rawValue: "swiftql.legacy-binding-value"
        )
            && valueTypeName == "SwiftQL.XLBindable"
            && nullability == .nullable
            && codecIdentity == nil
    }
}


private func replacingBinding(
    _ value: XLSQLiteValue,
    at slot: XLParameterSlot,
    in packet: XLInvocationBindings<XLSQLiteValue>
) throws -> XLInvocationBindings<XLSQLiteValue> {
    if value == .null, slot.nullability == .required {
        throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
    }
    return try XLInvocationBindings(
        layout: packet.layout,
        bindings: packet.bindings.filter { $0.slot.index != slot.index } + [
            XLInvocationBinding(slot: slot, value: value)
        ]
    )
}


/// Configures a GRDB-backed SwiftQL database before its connection pool is created.
public struct GRDBDatabaseBuilder {
    
    private let url: URL

    private var configuration: GRDB.Configuration

    private let codingConfiguration: XLValueCodingConfiguration

    private let formatter: XLiteFormatter
    
    private let logger: XLLogger?

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy
    
    /// Creates a database builder.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: configuration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Creates a database builder with an immutable value-coding snapshot.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and requests built from it.
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.url = url
        self.configuration = configuration
        self.codingConfiguration = codingConfiguration
        self.formatter = formatter
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
    }
    
    /// Registers a custom scalar function on every database connection created by the builder.
    ///
    /// - Parameter function: The custom function type to register.
    public mutating func addFunction<F>(_ function: F.Type) where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    function.definition.name,
                    argumentCount: Int(function.definition.numberOfArguments),
                    function: { values in
                        let reader = GRDBValuesAdapter(values: values)
                        return try F.execute(reader: reader)
                    }
                )
            )
        }
    }

    /// Registers a custom collating sequence on every database connection
    /// created by the builder.
    ///
    /// Name the same sequence in a query with `XLCollation(rawValue:)`. SQLite
    /// resolves collations at preparation, so an unregistered name fails with
    /// `no such collation sequence` rather than silently comparing differently.
    ///
    /// - Parameter name: Collation name, matched case-insensitively by SQLite.
    /// - Parameter compare: Ordering between two strings.
    public mutating func addCollation(
        _ name: String,
        compare: @escaping @Sendable (String, String) -> ComparisonResult
    ) {
        configuration.prepareDatabase { database in
            database.add(collation: DatabaseCollation(name, function: compare))
        }
    }

    /// Creates the configured database and its connection pool.
    public func build() throws -> GRDBDatabase {
        try GRDBDatabase(
            databasePool: try DatabasePool(
                path: url.path,
                configuration: configuration
            ),
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
}


/// A SwiftQL database adapter backed by a GRDB `DatabasePool`.
public struct GRDBDatabase: XLDatabase {
    
    /// The GRDB connection pool used to execute requests.
    public let databasePool: DatabasePool
    
    /// The encoder used to render SwiftQL statements.
    public let encoder: XLEncoder

    /// Explicit SQLite syntax and value contract used by this adapter.
    public let dialect: XLSQLiteDialect

    /// Immutable contextual value-coding policy captured by this database.
    public let codingConfiguration: XLValueCodingConfiguration

    /// Stable identity of the database transport used by this adapter.
    public let driverIdentifier: XLDriverIdentifier

    private let driver: GRDBDatabaseDriver
    
    private let logger: XLLogger?

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    private let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    
    /// Opens a GRDB-backed SQLite database.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: configuration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Opens a GRDB-backed SQLite database with a value-coding snapshot.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: try DatabasePool(
                path: url.path,
                configuration: configuration
            ),
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
    
    /// Wraps an existing GRDB database pool.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: XLValueCodingConfiguration(),
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Wraps an existing GRDB pool with a value-coding snapshot.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: .mainQueue
        )
    }

    init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: XLValueCodingConfiguration(),
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        let dialect = XLSQLiteDialect(
            identifierFormattingOptions: formatter.identifierFormattingOptions
        )
        let driver = GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: dialect
        )
        self.dialect = dialect
        self.codingConfiguration = codingConfiguration
        self.encoder = XLiteEncoder(dialect: dialect)
        self.databasePool = databasePool
        self.driverIdentifier = driver.driverIdentifier
        self.driver = driver
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
    }
    
    public func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    /// Prepares an immutable raw-value runtime handle for concurrent
    /// invocations of one rendered statement.
    ///
    /// The handle intentionally does not retain the typed v1 row-reader graph.
    /// Callers that need typed decoding can use `makeRequest(with:)`; static
    /// typed descriptors build on this raw execution seam separately.
    public func prepareInvocation(
        with statement: any XLEncodable
    ) -> GRDBPreparedInvocation {
        let encoding = encoder.makeSQL(statement)
        return GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: logicalStatement(for: encoding),
                parameterLayoutError: preparedParameterLayoutError(for: encoding),
                valueEncodingError: encoding.valueEncodingError
            )
        )
    }

    /// Prepares a database-independent static query descriptor against this
    /// database's dialect and immutable coding snapshot.
    ///
    /// Validation happens before a runtime handle is returned. Physical SQLite
    /// statements remain connection-owned and are created only while executing
    /// through the GRDB driver.
    public func prepareInvocation(
        with descriptor: XLStaticQueryDescriptor
    ) throws -> GRDBPreparedStaticQuery {
        try descriptor.statement.dialectRequirement.validate(
            dialect.descriptor
        )
        try validateStaticQueryStorage(descriptor)
        try validateStaticQueryCodecs(descriptor)

        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: descriptor.statement.dialectRequirement,
            sql: descriptor.statement.sql,
            entities: descriptor.statement.entities,
            parameterLayout: descriptor.statement.parameterLayout
        )
        let invocation = GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: statement
            )
        )
        return GRDBPreparedStaticQuery(
            descriptor: descriptor,
            invocation: invocation,
            codingConfiguration: codingConfiguration,
            dialect: dialect
        )
    }
    
    /// Creates a row-returning request for a `RETURNING` statement.
    ///
    /// Unlike an ordinary write request, the statement mutates the database and
    /// decodes the returned rows inside a single write transaction.
    public func makeRequest<Row>(with statement: XLReturningStatementOf<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest<Row>(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            access: .write,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    private func makeWriteRequest(with statement: any XLEncodable) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError
        )
    }

    /// Confirms that every contextual parameter retained by the rendered
    /// statement belongs to this database's immutable coding snapshot. A
    /// reference resolved by another database is accepted only when the same
    /// durable codec identity is registered for the same dialect.
    private func preparedParameterLayoutError(
        for encoding: XLEncoding
    ) -> XLInvocationBindingError? {
        if let parameterLayoutError = encoding.parameterLayoutError {
            return parameterLayoutError
        }

        for slot in encoding.parameterLayout.slots {
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                return .preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                return .preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                return .preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }
        return nil
    }

    private func validateStaticQueryCodecs(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for metadata in descriptor.parameters {
            let slot = metadata.slot
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw XLInvocationBindingError.preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw XLInvocationBindingError.preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw XLInvocationBindingError.preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }

        for slot in descriptor.results.slots {
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw GRDBStaticQueryError.resultCodecDialectMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw GRDBStaticQueryError.resultCodecUnavailable(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw GRDBStaticQueryError.resultCodecIdentityMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }
    }

    private func validateStaticQueryStorage(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for parameter in descriptor.parameters {
            guard XLSQLiteStorageClass(
                rawValue: parameter.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedParameterStorage(
                    identity: descriptor.identity,
                    parameter: parameter
                )
            }
        }

        for slot in descriptor.results.slots {
            guard XLSQLiteStorageClass(
                rawValue: slot.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedResultStorage(
                    identity: descriptor.identity,
                    slot: slot
                )
            }
        }
    }

    private func logicalStatement(for encoding: XLEncoding) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: encoding.dialectRequirement,
            sql: encoding.sql,
            entities: encoding.entities,
            parameterLayout: encoding.parameterLayout
        )
    }
}
