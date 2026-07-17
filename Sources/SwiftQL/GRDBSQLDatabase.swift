//
//  GRDBSQLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import OSLog
import GRDB
import Combine


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

    private let columnReader = XLColumnValuesRowReader<Output>()

    package init(reader: any XLRowReadable<Output>) {
        self.reader = reader
    }

    package func decode(_ row: GRDB.Row) throws -> Output {
        try decode(values: row.databaseValues.map(\.sqliteDialectValue))
    }

    func decode(values: [XLSQLiteValue]) throws -> Output {
        columnReader.reset(reader: XLSQLiteValueReader(values: values))
        return try reader.readRow(reader: columnReader)
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


struct GRDBRequest<Row>: XLRequest {

    private let driver: GRDBDatabaseDriver
    
    private let logger: XLLogger?
    
    private let logicalStatement: XLLogicalPreparedStatement
    
    private let reader: any XLRowReadable<Row>

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    private let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler

    private var arguments: [XLBindingKey: XLSQLiteValue] = [:]
    
    init(
        driver: GRDBDatabaseDriver,
        logger: XLLogger?,
        reader: any XLRowReadable<Row>,
        logicalStatement: XLLogicalPreparedStatement,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) {
        self.driver = driver
        self.logger = logger
        self.reader = reader
        self.logicalStatement = logicalStatement
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(named: reference.name.rawValue) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(named: reference.name.rawValue) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(named name: String, bind: (inout XLBindingContext) -> Void) {
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        arguments[.named(name)] = (context as! BindingContext).value
    }
    
    func fetchAll() throws -> [Row] {
        var driver = driver
        return try driver.withReadConnection { connection in
            try fetchAll(in: &connection)
        }
    }

    private func fetchAll(
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        logger?.debug("fetchAll: <<<\(logicalStatement.sql)>>> parameters: <<<\(arguments)>>>")
        let rows = try connection.fetchAll(boundStatement(in: &connection))

        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        for values in rows {
            do {
                let item = try rowDecoder.decode(values: values)
                items.append(item)
            }
            catch {
                logger?.error("fetchAll : Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }
    
    func fetchOne() throws -> Row? {
        var driver = driver
        return try driver.withReadConnection { connection in
            try fetchOne(in: &connection)
        }
    }

    private func fetchOne(
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> Row? {
        logger?.debug("fetchOne: <<<\(logicalStatement.sql)>>> parameters: <<<\(arguments)>>>")
        guard let values = try connection.fetchOne(boundStatement(in: &connection)) else {
            return nil
        }

        return try GRDBRowDecoder(reader: reader).decode(values: values)
    }
    
    func publish() -> AnyPublisher<[Row], Error> {
        publisher { database in
            var connection = driver.makeConnection(database)
            return try fetchAll(in: &connection)
        }
    }
    
    func publishOne() -> AnyPublisher<Row?, Error> {
        publisher { database in
            var connection = driver.makeConnection(database)
            return try fetchOne(in: &connection)
        }
    }
    
    private func publisher<T>(fetch: @escaping (Database) throws -> T) -> AnyPublisher<T, Error> {
        let makeSource = {
            ValueObservation
                .tracking(fetch)
                .publisher(in: driver.databasePool)
                .eraseToAnyPublisher()
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

    private func boundStatement(
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> GRDBPhysicalStatement {
        var statement = try connection.prepare(logicalStatement)
        for (key, value) in arguments {
            statement = try connection.bind(value, to: key, in: statement)
        }
        return statement
    }
}


struct GRDBWriteRequest: XLWriteRequest {

    private let driver: GRDBDatabaseDriver
    
    private let logger: XLLogger?
    
    private let logicalStatement: XLLogicalPreparedStatement
    
    private var arguments: [XLBindingKey: XLSQLiteValue] = [:]
    
    init(
        driver: GRDBDatabaseDriver,
        logger: XLLogger?,
        logicalStatement: XLLogicalPreparedStatement
    ) {
        self.driver = driver
        self.logger = logger
        self.logicalStatement = logicalStatement
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(named: reference.name.rawValue) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(named: reference.name.rawValue) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(named name: String, bind: (inout XLBindingContext) -> Void) {
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        arguments[.named(name)] = (context as! BindingContext).value
    }
    
    func execute() throws {
        var driver = driver
        try driver.withTransaction { connection in
            logger?.debug("execute: <<<\(logicalStatement.sql)>>> parameters: <<<\(arguments)>>>")
            var statement = try connection.prepare(logicalStatement)
            for (key, value) in arguments {
                statement = try connection.bind(value, to: key, in: statement)
            }
            try connection.execute(statement)
        }
    }
}


/// Configures a GRDB-backed SwiftQL database before its connection pool is created.
public struct GRDBDatabaseBuilder {
    
    private let url: URL

    private var configuration: GRDB.Configuration

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
        self.url = url
        self.configuration = configuration
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

    /// Creates the configured database and its connection pool.
    public func build() throws -> GRDBDatabase {
        try GRDBDatabase(
            databasePool: try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration),
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
            databasePool: try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration),
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
        let dialect = XLSQLiteDialect(
            identifierFormattingOptions: formatter.identifierFormattingOptions
        )
        let driver = GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: dialect
        )
        self.dialect = dialect
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
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
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
            logger: logger,
            logicalStatement: logicalStatement(for: encoding)
        )
    }

    private func logicalStatement(for encoding: XLEncoding) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: encoding.dialectRequirement,
            sql: encoding.sql,
            entities: encoding.entities
        )
    }
}
