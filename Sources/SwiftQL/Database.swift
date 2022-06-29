import Foundation
import Combine


public protocol DatabaseProtocol {
    associatedtype Schema: AnyDatabaseSchema
}


open class AnyDatabaseSchema {
    
    private let context: SQLWriter
    
    public required init(context: SQLWriter? = nil) {
        self.context = context ?? SQLWriter()
    }

    public func makeSchema<S, T>() -> S where S: TableSchemaOf<T>, T: Table {
        context.makeSchema()
    }
}


struct DatabaseTransaction<Database> where Database: DatabaseProtocol {
    
    let connection: DatabaseConnection<Database>
    let context: SQLWriter
    let schema: Database.Schema

    func readStatement<Output>(cached: Bool, builder: @escaping (Database.Schema) -> AnySQLBuilder<Output>) throws -> [Output] {
        let builder = builder(schema)
        let statement = PreparedReadSQL<Database, Output>(
            builder: builder,
            context: context,
            statement: try connection.getOrCreateStatement(
                cached: cached,
                builder: builder
            )
        )
        return try statement.execute()
    }

    func writeStatement(cached: Bool, query builders: @escaping (Database.Schema) -> [AnySQLBuilder<Void>]) throws {
        let builders = builders(schema)
        for builder in builders {
            let statement = PreparedWriteSQL<Database>(
                builder: builder,
                context: context,
                statement: try connection.getOrCreateStatement(
                    cached: cached,
                    builder: builder
                )
            )
            try statement.execute()
        }
    }
}


public final class DatabaseConnection<Database> where Database: DatabaseProtocol {
    
    typealias ReadBuilder<Output, T> = (Database.Schema) -> From<Output, T> where T: Table

    typealias WriteBuilder = (Database.Schema) -> [AnySQLBuilder<Void>]
    
    fileprivate var statements = [String : SQLPreparedStatementProtocol]()
    private let provider: SQLProviderProtocol
    
    static func temporary() -> DatabaseConnection {
        let fileURL = FileManager.default
            .urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )
            .first!
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        return DatabaseConnection(fileURL: fileURL)
    }
    
    convenience init(fileURL: URL) {
        let resource = SQLite.Resource(fileURL: fileURL)
        let connection = try! resource.connect()
        self.init(provider: connection)
    }

    init(provider: SQLProviderProtocol) {
        self.provider = provider
    }
    
    func execute(cached: Bool = false, @TransactionBuilder<Database> builders: @escaping WriteBuilder) async throws {
        let context = SQLWriter()
        let schema = Database.Schema(context: context)
        let transactionContext = DatabaseTransaction(
            connection: self,
            context: context,
            schema: schema
        )
        try await provider.transaction { _ in
            try transactionContext.writeStatement(cached: cached, query: builders)
        }
    }
    
    func execute<Output, Entity>(cached: Bool = false, builder: @escaping ReadBuilder<Output, Entity>) async throws -> [Output] where Entity: Table {
        let context = SQLWriter()
        let schema = Database.Schema(context: context)
        let transactionContext = DatabaseTransaction(
            connection: self,
            context: context,
            schema: schema
        )
        return try await provider.transaction { _ in
            try transactionContext.readStatement(cached: cached) { schema in
                AnySQLBuilder<Output>(from: builder(schema))
            }
        }
    }
    
    fileprivate func getOrCreateStatement<O>(cached: Bool, builder: AnySQLBuilder<O>) throws -> SQLPreparedStatementProtocol {
        if cached {
            return try getOrCreateCachedStatement(builder: builder)
        }
        else {
            return try createStatement(builder: builder)
        }
    }

    private func getOrCreateCachedStatement<O>(builder: AnySQLBuilder<O>) throws -> SQLPreparedStatementProtocol {
        let hashKey = builder.hashKey()
        let key = hashKey.rawValue
        if let preparedStatement = statements[key] {
            return preparedStatement
        }
        let preparedStatement = try createStatement(builder: builder)
        statements[key] = preparedStatement
        return preparedStatement
    }

    private func createStatement<O>(builder: AnySQLBuilder<O>) throws -> SQLPreparedStatementProtocol {
        let token = builder.sql()
        let sql = token.string()
        let preparedStatement = try provider.prepare(sql: sql)
        return preparedStatement
    }
}
