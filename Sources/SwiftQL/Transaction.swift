import Foundation


protocol TransactionProtocol {
    associatedtype Database: DatabaseProtocol
    associatedtype Output
    func sql() -> SQLToken
    func execute(connection: DatabaseConnection<Database>, cached: Bool) async throws -> Output
}


struct StatementBuilder<Database, Output> where Database: DatabaseProtocol {
    
    typealias Builder = (Database.Schema) -> AnySQLBuilder<Output>

    private let builder: Builder

    init(builder: @escaping (Database.Schema) -> SQLWriteStatement) {
        self.builder = { schema in
            AnySQLBuilder(builder(schema))
        }
    }
    
    func statement(schema: Database.Schema) -> AnySQLBuilder<Output> {
        builder(schema)
    }
}

    
@resultBuilder class TransactionBuilder<D> where D: DatabaseProtocol {
    
    static func buildBlock(_ s: StatementBuilder<D, Void>...) -> [StatementBuilder<D, Void>] {
        s
    }
    
//    static func buildBlock<T>(_ i: Insert<T>) -> AnySQLBuilder<Void> where T: Table {
//        AnySQLBuilder(i)
//    }
//
//    static func buildBlock<T>(_ u: Update<T>) -> AnySQLBuilder<Void> where T: Table {
//        AnySQLBuilder(u)
//    }

    static func buildBlock<R, T>(_ f: From<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(f)
    }

//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, w, o)
//    }
}



struct WriteTransaction<Database>: TransactionProtocol where Database: DatabaseProtocol {
    
    typealias Builder = () -> [StatementBuilder<Database, Void>]

    private let builders: [StatementBuilder<Database, Void>]

    init(@TransactionBuilder<Database> builder: Builder) {
        self.builders = builder()
    }

    func sql() -> SQLToken {
        let schema = Database.Schema()
        return CompositeSQLToken(
            separator: "; ",
            tokens: builders.map { builder in
                builder.statement(schema: schema).sql()
            }
        )
    }

    func execute(connection: DatabaseConnection<Database>, cached: Bool = false) async throws {
        try await connection.transaction { [builders] transaction in
            for builder in builders {
                let statement = try connection.writeStatement(
                    cached: cached,
                    query: builder.statement
                )
                try statement.execute()
            }
        }
    }
}


struct ReadTransaction<Database, Output>: TransactionProtocol where Database: DatabaseProtocol {
    
    typealias Builder = (Database.Schema) -> AnySQLBuilder<Output>
    
    private let builder: Builder
    
    init<T>(builder: @escaping (Database.Schema) -> From<Output, T>) where T: Table {
        self.builder = { schema in
            AnySQLBuilder(builder(schema))
        }
    }

    func sql() -> SQLToken {
        let schema = Database.Schema()
        let statement = builder(schema)
        return statement.sql()
    }

    func execute(connection: DatabaseConnection<Database>, cached: Bool = false) async throws -> [Output] {
        try await connection.transaction { [builder] transaction in
            let statement = try connection.readStatement(
                cached: cached,
                query: builder
            )
            return try statement.execute()
        }
    }
}
