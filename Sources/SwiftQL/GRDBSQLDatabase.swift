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
    
    let row: GRDB.Row
    
    func isNull(at index: Int) throws -> Bool {
        try databaseValue(at: index, expectedType: nil).isNull
    }
    
    func readInteger(at index: Int) throws -> Int {
        try read(Int.self, at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try read(Double.self, at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try read(String.self, at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try read(Data.self, at: index)
    }

    private func read<Value>(_ type: Value.Type, at index: Int) throws -> Value where Value: DatabaseValueConvertible {
        let expectedType = String(describing: type)
        return try decode(
            databaseValue: databaseValue(at: index, expectedType: expectedType),
            as: type,
            at: index
        )
    }

    private func databaseValue(at index: Int, expectedType: String?) throws -> DatabaseValue {
        guard index >= 0 && index < row.count else {
            throw XLColumnReadError(
                index: index,
                expectedType: expectedType,
                failure: .indexOutOfBounds(valueCount: row.count)
            )
        }
        let values = row.databaseValues
        let valueIndex = values.index(values.startIndex, offsetBy: index)
        return values[valueIndex]
    }
}


struct GRDBValuesAdapter: XLColumnReader {
    
    let values: [GRDB.DatabaseValue]
    
    func isNull(at index: Int) throws -> Bool {
        try databaseValue(at: index, expectedType: nil).isNull
    }
    
    func readInteger(at index: Int) throws -> Int {
        try read(Int.self, at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try read(Double.self, at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try read(String.self, at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try read(Data.self, at: index)
    }

    private func read<Value>(_ type: Value.Type, at index: Int) throws -> Value where Value: DatabaseValueConvertible {
        let expectedType = String(describing: type)
        return try decode(
            databaseValue: databaseValue(at: index, expectedType: expectedType),
            as: type,
            at: index
        )
    }

    private func databaseValue(at index: Int, expectedType: String?) throws -> DatabaseValue {
        guard values.indices.contains(index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: expectedType,
                failure: .indexOutOfBounds(valueCount: values.count)
            )
        }
        return values[index]
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
        columnReader.reset(reader: GRDBRowAdapter(row: row))
        return try reader.readRow(reader: columnReader)
    }
}


private func decode<Value>(databaseValue: DatabaseValue, as type: Value.Type, at index: Int) throws -> Value where Value: DatabaseValueConvertible {
    let expectedType = String(describing: type)
    guard !databaseValue.isNull else {
        throw XLColumnReadError(
            index: index,
            expectedType: expectedType,
            failure: .nullValue
        )
    }
    guard let value = Value.fromDatabaseValue(databaseValue) else {
        throw XLColumnReadError(
            index: index,
            expectedType: expectedType,
            failure: .typeMismatch(actualType: databaseValue.storageClassName)
        )
    }
    return value
}


private extension DatabaseValue {
    var storageClassName: String {
        switch storage {
        case .null:
            return "NULL"
        case .int64:
            return "INTEGER"
        case .double:
            return "REAL"
        case .string:
            return "TEXT"
        case .blob:
            return "BLOB"
        }
    }
}


fileprivate struct BindingContext: XLBindingContext {
    
    var value: DatabaseValueConvertible?
    
    mutating func bindNull() {
        self.value = nil
    }
    
    mutating func bindInteger(value: Int) {
        self.value = value
    }
    
    mutating func bindReal(value: Double) {
        self.value = value
    }
    
    mutating func bindText(value: String) {
        self.value = value
    }
    
    mutating func bindBlob(value: Data) {
        self.value = value
    }
}


struct GRDBRequest<Row>: XLRequest {
    
    private let databasePool: DatabasePool
    
    private let logger: XLLogger?
    
    private let sql: String
    
    private let reader: any XLRowReadable<Row>

    private var arguments = StatementArguments()
    
    public init(databasePool: DatabasePool, logger: XLLogger?, reader: any XLRowReadable<Row>, sql: String) {
        self.databasePool = databasePool
        self.logger = logger
        self.reader = reader
        self.sql = sql
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
        arguments = arguments &+ [name: (context as! BindingContext).value]
    }
    
    func fetchAll() throws -> [Row] {
        try databasePool.read { database in
            try fetchAll(in: database)
        }
    }

    private func fetchAll(in database: Database) throws -> [Row] {
        logger?.debug("fetchAll: <<<\(sql)>>> parameters: <<<\(arguments)>>>")
        let statement = try database.cachedStatement(sql: sql)
        let rows = try GRDB.Row.fetchAll(statement, arguments: arguments)

        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        for row in rows {
            do {
                let item = try rowDecoder.decode(row)
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
        try databasePool.read { database in
            try fetchOne(in: database)
        }
    }

    private func fetchOne(in database: Database) throws -> Row? {
        logger?.debug("fetchOne: <<<\(sql)>>> parameters: <<<\(arguments)>>>")
        let statement = try database.cachedStatement(sql: sql)
        guard let row = try GRDB.Row.fetchOne(statement, arguments: arguments) else {
            return nil
        }

        return try GRDBRowDecoder(reader: reader).decode(row)
    }
    
    func publish() -> AnyPublisher<[Row], Error> {
        publisher(fetch: fetchAll(in:))
    }
    
    func publishOne() -> AnyPublisher<Row?, Error> {
        publisher(fetch: fetchOne(in:))
    }
    
    private func publisher<T>(fetch: @escaping (Database) throws -> T) -> AnyPublisher<T, Error> {
        ValueObservation
            .tracking(fetch)
            .publisher(in: databasePool)
            .eraseToAnyPublisher()
    }
}


struct GRDBWriteRequest: XLWriteRequest {
    
    private let databasePool: DatabasePool
    
    private let logger: XLLogger?
    
    private let sql: String
    
    private var arguments = StatementArguments()
    
    public init(databasePool: DatabasePool, logger: XLLogger?, sql: String) {
        self.databasePool = databasePool
        self.logger = logger
        self.sql = sql
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
        arguments = arguments &+ [name: (context as! BindingContext).value]
    }
    
    func execute() throws {
        try databasePool.write { database in
            logger?.debug("execute: <<<\(sql)>>> parameters: <<<\(arguments)>>>")
            let statement = try database.cachedStatement(sql: sql)
            try statement.execute(arguments: arguments)
        }
    }
}


public struct GRDBDatabaseBuilder {
    
    private let url: URL

    private var configuration: GRDB.Configuration

    private let formatter: XLiteFormatter
    
    private let logger: XLLogger?
    
    public init(url: URL, configuration: GRDB.Configuration, formatter: XLiteFormatter = XLiteFormatter(), logger: XLLogger?) throws {
        self.url = url
        self.configuration = configuration
        self.formatter = formatter
        self.logger = logger
    }
    
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

    public func build() throws -> GRDBDatabase {
        try GRDBDatabase(
            databasePool: try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration),
            formatter: formatter,
            logger: logger
        )
    }
}


public struct GRDBDatabase: XLDatabase {
    
    public let databasePool: DatabasePool
    
    public let encoder: XLEncoder
    
    private let logger: XLLogger?
    
    public init(
        url: URL,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?
    ) throws {
        try self.init(
            databasePool: try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration),
            formatter: formatter,
            logger: logger
        )
    }
    
    public init(databasePool: DatabasePool, formatter: XLiteFormatter, logger: XLLogger?) throws {
        self.encoder = XLiteEncoder(formatter: formatter)
        self.databasePool = databasePool
        self.logger = logger
    }
    
    public func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(databasePool: databasePool, logger: logger, reader: statement, sql: encoding.sql)
    }
    
    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql)
    }
    
    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql)
    }
    
    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql)
    }
    
    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql)
    }
}
