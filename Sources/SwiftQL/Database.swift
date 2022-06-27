import Foundation
import Combine


public protocol DatabaseProtocol {
    associatedtype Schema: AnyDatabaseSchema
}


open class AnyDatabaseSchema {
    
    private let context: SQLWriter
    
    public required init(row: SQLRowProtocol? = nil, statement: PreparedStatementContext? = nil) {
        self.context = SQLWriter(row: row, statement: statement)
    }

    public func makeSchema<S, T>() -> S where S: TableSchemaOf<T>, T: Table {
        context.makeSchema()
    }
}


public final class DatabaseConnection<D> where D: DatabaseProtocol {
    
    typealias Builder<O> = (D.Schema) -> AnySQLBuilder<O>
    
    private var statements = [String : SQLPreparedStatementProtocol]()
    private let provider: SQLProviderProtocol
    
    convenience init() {
        let fileURL = FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .first!
            .appendingPathComponent("database", isDirectory: false)
            .appendingPathExtension("sqlite")
        let resource = SQLite.Resource(
            fileURL: fileURL
        )
        let connection = try! resource.connect()
        self.init(provider: connection)
    }

    init(provider: SQLProviderProtocol) {
        self.provider = provider
    }
    
    func execute(cached: Bool = false, transaction: WriteTransaction<D>) async throws {
        try await transaction.execute(connection: self, cached: cached)
    }
    
    func execute<Output>(cached: Bool = false, transaction: ReadTransaction<D, Output>) async throws -> [Output] {
        try await transaction.execute(connection: self, cached: cached)
    }

    func readStatement<O>(cached: Bool, query builder: @escaping Builder<O>) throws -> PreparedReadSQL<D, O> {
        let preparedStatement = try getOrCreateStatement(cached: cached, builder: builder)
        return PreparedReadSQL(
            builder: builder,
            statement: preparedStatement
        )
    }

    func writeStatement(cached: Bool, query builder: @escaping Builder<Void>) throws -> PreparedWriteSQL<D> {
        let preparedStatement = try getOrCreateStatement(cached: cached, builder: builder)
        return PreparedWriteSQL(
            builder: builder,
            statement: preparedStatement
        )
    }
    
    private func getOrCreateStatement<O>(cached: Bool, builder: Builder<O>) throws -> SQLPreparedStatementProtocol {
        if cached {
            return try getOrCreateCachedStatement(builder: builder)
        }
        else {
            return try createStatement(builder: builder)
        }
    }

    private func getOrCreateCachedStatement<O>(builder: Builder<O>) throws -> SQLPreparedStatementProtocol {
        let schema = D.Schema()
        let statement = builder(schema)
        let hashKey = statement.hashKey()
        let key = hashKey.rawValue
        if let preparedStatement = statements[key] {
            return preparedStatement
        }
        let preparedStatement = try createStatement(builder: builder)
        statements[key] = preparedStatement
        return preparedStatement
    }

    private func createStatement<O>(builder: Builder<O>) throws -> SQLPreparedStatementProtocol {
        let schema = D.Schema()
        let statement = builder(schema)
        let token = statement.sql()
        let sql = token.string()
        let preparedStatement = try provider.prepare(sql: sql)
        return preparedStatement
    }
    
    @discardableResult internal func transaction<T>(transaction: @escaping (SQLTransactionProtocol) throws -> T) async throws -> T {
        try await provider.transaction(transaction: transaction)
    }
}
