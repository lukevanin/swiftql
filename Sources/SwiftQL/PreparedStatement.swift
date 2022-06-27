import Foundation
import Combine


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


//class PreparedWriteSQL {
//
//    let builder: AnySQLBuilder<Void>
//    let statement: SQLPreparedStatementProtocol
//    let provider: SQLProviderProtocol
//
//    init(
//        builder: AnySQLBuilder<Void>,
//        statement: SQLPreparedStatementProtocol,
//        provider: SQLProviderProtocol
//    ) {
//        self.builder = builder
//        self.statement = statement
//        self.provider = provider
//    }
//
//    func string() -> String {
//        statement.sql()
//    }
//
//    @discardableResult func execute(context: SQLWriter) throws {
//        try statement.execute(
//            bind: { statement in
//                try context.bind(
//                    context: PreparedStatementContext(
//                        statement: statement
//                    )
//                )
//            },
//            read: { _ in }
//        )
//    }
//}


protocol PreparedSQLProtocol {
    associatedtype Output
    func sql() -> SQLToken
    func execute() throws -> Output
}
                                    

struct PreparedSQL<D, O> where D: DatabaseProtocol {
    
    typealias Builder = (D.Schema) -> AnySQLBuilder<O>
    
    typealias Reader = (SQLRowProtocol) -> Void

    let builder: Builder
    let statement: SQLPreparedStatementProtocol
    
    func sql() -> SQLToken {
        let schema = D.Schema()
        let statement = builder(schema)
        let sql = statement.sql()
        return sql
    }

    func execute(reader: Reader?) throws {
        try statement.execute(
            bind: { s in
                let context = PreparedStatementContext(statement: s)
                let schema = D.Schema(statement: context)
                let statement = builder(schema)
                try statement.bind()
            },
            read: reader
        )
    }
}


struct PreparedWriteSQL<D>: PreparedSQLProtocol where D: DatabaseProtocol {
    
    typealias Output = Void
    
    typealias Builder = (D.Schema) -> AnySQLBuilder<Void>

    private let preparedStatement: PreparedSQL<D, Void>
    
    init(builder: @escaping Builder, statement: SQLPreparedStatementProtocol) {
        self.preparedStatement = PreparedSQL(
            builder: builder,
            statement: statement
        )
    }
    
    func sql() -> SQLToken {
        preparedStatement.sql()
    }

    func execute() throws {
        try preparedStatement.execute(reader: nil)
    }
}


struct PreparedReadSQL<D, O>: PreparedSQLProtocol where D: DatabaseProtocol {
    
    typealias Builder = (D.Schema) -> AnySQLBuilder<O>

    private let builder: Builder
    private let preparedStatement: PreparedSQL<D, O>
    
    init(builder: @escaping Builder, statement: SQLPreparedStatementProtocol) {
        self.builder = builder
        self.preparedStatement = PreparedSQL(
            builder: builder,
            statement: statement
        )
    }
    
    func sql() -> SQLToken {
        preparedStatement.sql()
    }

    func execute() throws -> [O] {
        var output = [O]()
        try preparedStatement.execute { r in
            let schema = D.Schema(row: r)
            let statement = builder(schema)
            let item = statement.read()
            output.append(item)
        }
        return output
    }
}

