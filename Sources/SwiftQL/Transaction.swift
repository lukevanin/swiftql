import Foundation


@resultBuilder class TransactionBuilder<D> where D: DatabaseProtocol {

    static func buildBlock(_ s: SQLWriteStatement...) -> [AnySQLBuilder<Void>] {
        s.map { AnySQLBuilder($0) }
    }

    static func buildBlock<R, T>(_ f: From<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(f)
    }
}


struct WriteTransaction<Database> where Database: DatabaseProtocol {
    
    typealias Builder = (Database.Schema) -> [AnySQLBuilder<Void>]

    private let builder: Builder

    init(@TransactionBuilder<Database> builder: @escaping Builder) {
        self.builder = builder
    }
    
    func execute(cached: Bool, context: DatabaseTransaction<Database>) throws {
        try context.writeStatement(cached: cached, query: builder)
    }
}


struct ReadTransaction<Database, Output> where Database: DatabaseProtocol {
    
    typealias Builder = (Database.Schema) -> AnySQLBuilder<Output>
    
    private let builder: Builder
    
    init<T>(builder: @escaping (Database.Schema) -> From<Output, T>) where T: Table {
        self.builder = { schema in
            AnySQLBuilder(from: builder(schema))
        }
    }
    
    func execute(cached: Bool, context: DatabaseTransaction<Database>) throws -> [Output] {
        try context.readStatement(cached: cached, builder: builder)
    }
}
