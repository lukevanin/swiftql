import Foundation


protocol SQLFieldValue: Hashable, Codable {
    static var defaultValue: Self { get }
    
    static var sqlDefinition: SQLToken { get }
    
    static var hashKey: HashKey { get }
    
    static func read(column: Int, row: SQLRowProtocol) -> Self
    
    func bind(context: PreparedStatementContext) throws
}


extension Bool: SQLFieldValue {
    static let defaultValue: Bool = false
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")
    
    static let hashKey: HashKey = SymbolHashKey.boolean
    
    static func read(column: Int, row: SQLRowProtocol) -> Bool {
        row.readInt(column: column) == 0 ? false : true
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self ? 1 : 0)
    }
}


extension Int: SQLFieldValue {
    static let defaultValue: Int = 0

    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")

    static let hashKey: HashKey = SymbolHashKey.integer
    
    static func read(column: Int, row: SQLRowProtocol) -> Int {
        row.readInt(column: column)
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension Double: SQLFieldValue {
    static let defaultValue: Double = 0

    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "REAL")

    static let hashKey: HashKey = SymbolHashKey.real
    
    static func read(column: Int, row: SQLRowProtocol) -> Double {
        row.readDouble(column: column)
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension String: SQLFieldValue {
    static let defaultValue: String = ""
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.text
    
    static func read(column: Int, row: SQLRowProtocol) -> String {
        row.readString(column: column)
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension URL: SQLFieldValue {
    static let defaultValue: URL = URL(string: "http://")!
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.url
    
    static func read(column: Int, row: SQLRowProtocol) -> URL {
        // TODO: Safe unwrap
        URL(string: row.readString(column: column))!
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self.absoluteString)
    }
}


extension Date: SQLFieldValue {
    static let defaultValue: Date = Date(timeIntervalSince1970: 0)
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.date
    
    static func read(column: Int, row: SQLRowProtocol) -> Date {
        SQLSyntax.date(from: row.readString(column: column))
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: SQLSyntax.string(from: self))
    }
}


extension UUID: SQLFieldValue {
    static let defaultValue: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.uuid
    
    static func read(column: Int, row: SQLRowProtocol) -> UUID {
        // TODO: Safe unwrap
        UUID(uuidString: row.readString(column: column))!
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self.uuidString)
    }
}


extension Data: SQLFieldValue {
    static let defaultValue: Data = Data()
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "BLOB")

    static let hashKey: HashKey = SymbolHashKey.data
    
    static func read(column: Int, row: SQLRowProtocol) -> Data {
        row.readData(column: column)
    }
    
    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}
