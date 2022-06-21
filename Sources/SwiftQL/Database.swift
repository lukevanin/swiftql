import Foundation
import Combine


public final class DatabaseConnection {
    
    static let shared: DatabaseConnection = {
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
        return DatabaseConnection(
            provider: connection
        )
    }()
    
    private var statements = [String : SQLPreparedStatementProtocol]()
    
    private let provider: SQLProviderProtocol
    
    init(provider: SQLProviderProtocol) {
        self.provider = provider
    }

    func statement<Output>(cached: Bool, query builder: AnySQLBuilder<Output>) throws -> PreparedSQL<Output> {
        let statement: SQLPreparedStatementProtocol
        if cached {
            statement = try getOrCreateCachedStatement(builder: builder)
        }
        else {
            statement = try createStatement(builder: builder)
        }
        return PreparedSQL(
            builder: builder,
            statement: statement,
            provider: provider
        )
    }
    
    private func getOrCreateCachedStatement(builder: SQLBuilder) throws -> SQLPreparedStatementProtocol {
        let hashKey = CompositeHashKey(
            builder.hashKey
        )
        let key = hashKey.rawValue
        if let statement = statements[key] {
            return statement
        }
        let statement = try createStatement(builder: builder)
        statements[key] = statement
        return statement
    }
    
    private func createStatement(builder: SQLBuilder) throws -> SQLPreparedStatementProtocol {
        let token = builder.sql()
        let sql = token.string()
        return try provider.prepare(sql: sql)
    }
    
    @discardableResult func transaction<T>(transaction: @escaping (SQLTransactionProtocol) throws -> T) async throws -> T {
        try await provider.transaction(transaction: transaction)
    }
}

extension DatabaseConnection {

//    func query<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (D.Schema) -> AnySQLBuilder<Output>) throws -> PreparedSQL<Output> {
//        let context = SQLWriter()
//        let schema = D.Schema(context: context)
//        let builder = statements(schema)
//        return try statement(cached: cached, query: builder, context: context)
//    }

//    @discardableResult func execute<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (D.Schema) -> AnySQLBuilder<Output>) throws -> [Output] {
//        try self.query(cached: cached, statements).execute()
//    }
    
//    @discardableResult func observe<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (D.Schema) -> AnySQLBuilder<Output>) throws -> AnyPublisher<Result<[Output], Error>, Error> {
//        try self.query(cached: cached, statements).observe()
//    }
    
//    @discardableResult func transaction<T>(transaction: @escaping (Self, SQLTransactionProtocol) throws -> T) async throws -> T {
//        try await transaction() { [unowned self] t in
//            try transaction(self, t)
//        }
//    }
}


//public protocol Database: AnyObject {
//    associatedtype Schema: DatabaseSchema
//}


final class Transaction<Output> {
    
    private lazy var statement: PreparedSQL<Output> = {
        try! connection.statement(cached: cached, query: self.builder)
    }()
    
    private let connection: DatabaseConnection
    private let cached: Bool
    private let builder: AnySQLBuilder<Output>
    
    init(
        connection: DatabaseConnection = .shared,
        cached: Bool = true,
        @TransactionQueryBuilder statements: () -> AnySQLBuilder<Output>
    ) throws {
        self.connection = connection
        self.cached = cached
        self.builder = statements()
        self.builder.setContext(SQLWriter())
    }
    
    func sql() -> String {
        builder.sql().string()
    }
}


public final class PreparedStatementContext {
    
    private let statement: SQLBindingProtocol
    private var index: Int = 1
    
    init(statement: SQLBindingProtocol) {
        self.statement = statement
    }
    
    func bind(value: Int) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    func bind(value: Double) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }

    func bind<V>(value: V) throws where V: StringProtocol {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    func bind<V>(value: V) throws where V: DataProtocol {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    private func nextIndex() -> Int {
        defer {
            index += 1
        }
        return index
    }
}


class PreparedSQL<Output> {
    
    let builder: AnySQLBuilder<Output>
    let statement: SQLPreparedStatementProtocol
    let provider: SQLProviderProtocol
    
    init(
        builder: AnySQLBuilder<Output>,
        statement: SQLPreparedStatementProtocol,
        provider: SQLProviderProtocol
    ) {
        self.builder = builder
        self.statement = statement
        self.provider = provider
    }
    
    func string() -> String {
        statement.sql()
    }
    
    @discardableResult func execute() throws -> [Output] {
        var output = [Output]()
        try statement.execute(
            bind: { statement in
                try builder.bind(
                    statement: PreparedStatementContext(
                        statement: statement
                    )
                )
            },
            read: { row in
                let item = builder.read(row: row)
                output.append(item)
            }
        )
        return output
    }
    
    func observe() -> AnyPublisher<Result<[Output], Error>, Error> {
        return ObservableStatement(statement: self, provider: provider).eraseToAnyPublisher()
    }
}
