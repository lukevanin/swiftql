import Foundation
import Combine


class DatabaseConnection {
    
    private var statements = [String : SQLPreparedStatementProtocol]()
    
    let provider: SQLProviderProtocol
    
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
        return PreparedSQL(builder: builder, statement: statement, provider: provider)
    }
    
    private func getOrCreateCachedStatement(builder: SQLBuilder) throws -> SQLPreparedStatementProtocol {
        let key = builder.hashKey.rawValue
        if let statement = statements[key] {
            return statement
        }
        let statement = try createStatement(builder: builder)
        statements[key] = statement
        return statement
    }
    
    private func createStatement(builder: SQLBuilder) throws -> SQLPreparedStatementProtocol {
        let context = SQLWriter()
        let token = builder.sql(context: context)
        let sql = token.string()
        return try provider.prepare(sql: sql)
    }
}


protocol Database: AnyObject {
    associatedtype Schema: DatabaseSchema
    
    var connection: DatabaseConnection { get }
}

extension Database {

    func query<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (Self.Schema) -> AnySQLBuilder<Output>) throws -> PreparedSQL<Output> {
        let schema = Schema()
        let builder = statements(schema)
        return try connection.statement(cached: cached, query: builder)
    }

    @discardableResult func execute<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (Self.Schema) -> AnySQLBuilder<Output>) throws -> [Output] {
        try self.query(cached: cached, statements).execute()
    }
    
    @discardableResult func observe<Output>(cached: Bool = true, @SelectQueryBuilder _ statements: (Self.Schema) -> AnySQLBuilder<Output>) throws -> AnyPublisher<Result<[Output], Error>, Error> {
        try self.query(cached: cached, statements).observe()
    }
    
    @discardableResult func transaction<T>(transaction: @escaping (Self, SQLTransactionProtocol) throws -> T) async throws -> T {
        try await connection.provider.transaction() { [unowned self] t in
            try transaction(self, t)
        }
    }
}


class PreparedStatementContext {
    
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
    
    init(builder: AnySQLBuilder<Output>, statement: SQLPreparedStatementProtocol, provider: SQLProviderProtocol) {
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
            bind: { context in
                try builder.bind(context: PreparedStatementContext(statement: context))
            },
            read: { row in
                let item = builder.read(row: ResultSQLRow(row: row))
                output.append(item)
            }
        )
        return output
    }
    
    func observe() -> AnyPublisher<Result<[Output], Error>, Error> {
        return ObservableStatement(statement: self, provider: provider).eraseToAnyPublisher()
    }
}
