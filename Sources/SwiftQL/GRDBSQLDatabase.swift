//
//  GRDBXLDatabase.swift
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
    
    func isNull(at index: Int) -> Bool {
        row.hasNull(atIndex: index)
    }
    
    func readInteger(at index: Int) -> Int {
        row[index]
    }
    
    func readReal(at index: Int) -> Double {
        row[index]
    }
    
    func readText(at index: Int) -> String {
        row[index]
    }
    
    func readBlob(at index: Int) -> Data {
        row[index]
    }
}


struct GRDBValuesAdapter: XLColumnReader {
    
    let values: [GRDB.DatabaseValue]
    
    func isNull(at index: Int) -> Bool {
        values[index].isNull
    }
    
    func readInteger(at index: Int) -> Int {
        Int.fromDatabaseValue(values[index])!
    }
    
    func readReal(at index: Int) -> Double {
        Double.fromDatabaseValue(values[index])!
    }
    
    func readText(at index: Int) -> String {
        String.fromDatabaseValue(values[index])!
    }
    
    func readBlob(at index: Int) -> Data {
        Data.fromDatabaseValue(values[index])!
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
    
    private let entities: Set<String>
    
    private let reader: any XLRowReadable<Row>

    private var arguments = StatementArguments()
    
    public init(databasePool: DatabasePool, logger: XLLogger?, reader: any XLRowReadable<Row>, sql: String, entities: Set<String>) {
        self.databasePool = databasePool
        self.logger = logger
        self.reader = reader
        self.sql = sql
        self.entities = entities
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
        return try databasePool.read { database in
            logger?.debug("fetchAll: <<<\(sql)>>> parameters: <<<\(arguments)>>>")
            let statement = try database.cachedStatement(sql: sql)
            let rows = try GRDB.Row.fetchAll(statement, arguments: arguments)
            
            let columnReader = XLColumnValuesRowReader<Row>()
            var items: [Row] = []
            
            for row in rows {
                columnReader.reset(reader: GRDBRowAdapter(row: row))
                do {
                    let item = try reader.readRow(reader: columnReader)
                    items.append(item)
                }
                catch {
                    logger?.error("fetchAll : Cannot decode entity: \(error)")
                }
            }
            return items
        }
    }
    
    func fetchOne() throws -> Row? {
        return try databasePool.read { database in
            logger?.debug("fetchOne: <<<\(sql)>>> parameters: <<<\(arguments)>>>")
            let statement = try database.cachedStatement(sql: sql)
            guard let row = try GRDB.Row.fetchOne(statement, arguments: arguments) else {
                return nil
            }
            
            let columnReader = XLColumnValuesRowReader<Row>()
            columnReader.reset(reader: GRDBRowAdapter(row: row))
            let item = try reader.readRow(reader: columnReader)
            return item
        }
    }
    
    func publish() -> AnyPublisher<[Row], Error> {
        publisher(fetch: fetchAll)
    }
    
    func publishOne() -> AnyPublisher<Row?, Error> {
        publisher(fetch: fetchOne)
    }
    
    private func publisher<T>(fetch: @escaping () throws -> T) -> AnyPublisher<T, Error> {
        let initialResult: T
        do {
            initialResult = try fetch()
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
        let initialPublisher = Just(initialResult)
            .setFailureType(to: Error.self)
        let resultsPublisher = NotificationCenter.default
            .sqlEntitiesChangedPublisher()
            .receive(on: DispatchQueue.global(qos: .utility))
            .filter { notification in
                guard let changedEntities = notification.userInfo?[String.XLEntities] as? Set<String> else {
                    return false
                }
                let changes = Set(changedEntities).intersection(entities)
                return !changes.isEmpty
            }
            .tryMap { _ in
                try fetch()
            }
        return Publishers.Merge(initialPublisher, resultsPublisher).eraseToAnyPublisher()
    }
}


struct GRDBWriteRequest: XLWriteRequest {
    
    private let databasePool: DatabasePool
    
    private let logger: XLLogger?
    
    private let sql: String
    
    private let entities: Set<String>
    
    private var arguments = StatementArguments()
    
    public init(databasePool: DatabasePool, logger: XLLogger?, sql: String, entities: Set<String>) {
        self.databasePool = databasePool
        self.logger = logger
        self.sql = sql
        self.entities = entities
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
            #warning("TODO: Return result")
            try statement.execute(arguments: arguments)
        }
        #warning("TODO: Only post entity change notification ")
        NotificationCenter.default.postSQLEntitiesChangedNotification(entities: entities)
        NotificationCenter.default.postSQLCommitNotification()
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
        return GRDBRequest(databasePool: databasePool, logger: logger, reader: statement, sql: encoding.sql, entities: encoding.entities)
    }
    
    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql, entities: encoding.entities)
    }
    
    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql, entities: encoding.entities)
    }
    
    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql, entities: [])
    }
    
    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(databasePool: databasePool, logger: logger, sql: encoding.sql, entities: encoding.entities)
    }
}
