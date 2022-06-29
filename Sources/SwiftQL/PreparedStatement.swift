import Foundation
import Combine


public protocol BindProtocol {
    func bind(value: Int64) throws
    func bind(value: Double) throws
    func bind(value: String) throws
    func bind(value: Data) throws
}


public protocol ReadProtocol {
    func readInt() throws -> Int64
    func readDouble() throws -> Double
    func readString() throws -> String
    func readData() throws -> Data
}


final class StatementBindContext: BindProtocol {
    
    private let statement: SQLBindingProtocol
    private var index: Int = 0
    
    init(statement: SQLBindingProtocol) {
        self.statement = statement
        reset()
    }
    
    func reset() {
        index = 0
    }
    
    func bind(value: Int64) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    func bind(value: Double) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }

    func bind(value: String) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    func bind(value: Data) throws {
        try statement.bind(variable: nextIndex(), value: value)
    }
    
    private func nextIndex() -> Int {
        defer {
            index += 1
        }
        return index + 1
    }
}


final class RowReadContext: ReadProtocol {
    
    private let row: SQLRowProtocol
    private var index: Int = 0
    
    init(row: SQLRowProtocol) {
        self.row = row
        reset()
    }
    
    func reset() {
        index = 0
    }
    
    func readInt() throws -> Int64 {
        row.readInt(column: nextIndex())
    }
    
    func readDouble() throws -> Double {
        row.readDouble(column: nextIndex())
    }
    
    func readString() throws -> String {
        row.readString(column: nextIndex())
    }
    
    func readData() throws -> Data {
        row.readData(column: nextIndex())
    }
    
    private func nextIndex() -> Int {
        defer {
            index += 1
        }
        return index
    }
}


protocol PreparedSQLProtocol {
    associatedtype Output
    func sql() -> SQLToken
    func execute() throws -> Output
}
                                    

struct PreparedWriteSQL<D>: PreparedSQLProtocol where D: DatabaseProtocol {
    
    let builder: AnySQLBuilder<Void>
    let context: SQLWriter
    let statement: SQLPreparedStatementProtocol
    
    func sql() -> SQLToken {
        builder.sql()
    }

    func execute() throws {
        try statement.execute(
            bind: { s in
                context.bindContext = StatementBindContext(statement: s)
                builder.bind()
            },
            read: nil
        )
    }
}


struct PreparedReadSQL<Database, Output>: PreparedSQLProtocol where Database: DatabaseProtocol {
    
    let builder: AnySQLBuilder<Output>
    let context: SQLWriter
    let statement: SQLPreparedStatementProtocol
    
    func sql() -> SQLToken {
        builder.sql()
    }

    func execute() throws -> [Output] {
        var output = [Output]()
        try statement.execute(
            bind: { s in
                context.bindContext = StatementBindContext(statement: s)
                builder.bind()
            },
            read: { r in
                context.readContext = RowReadContext(row: r)
                let item = builder.read()
                output.append(item)
            }
        )
        return output
    }
}
