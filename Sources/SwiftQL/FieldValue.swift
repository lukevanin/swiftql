import Foundation


public protocol SQLFieldValue: Hashable, Codable {
    
    static var defaultValue: Self { get }
    
    static var sqlDefinition: SQLToken { get }
    
    static var hashKey: HashKey { get }
    
    static func read(column: Int, row: SQLRowProtocol) -> Self
    
    func bind(context: PreparedStatementContext) throws
}


extension Bool: SQLFieldValue {
    public static let defaultValue: Bool = false
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")
    
    public static let hashKey: HashKey = SymbolHashKey.boolean
    
    public static func read(column: Int, row: SQLRowProtocol) -> Bool {
        row.readInt(column: column) == 0 ? false : true
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self ? 1 : 0)
    }
}


extension Int: SQLFieldValue {
    public static let defaultValue: Int = 0

    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")

    public static let hashKey: HashKey = SymbolHashKey.integer
    
    public static func read(column: Int, row: SQLRowProtocol) -> Int {
        row.readInt(column: column)
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension Double: SQLFieldValue {
    public static let defaultValue: Double = 0

    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "REAL")

    public static let hashKey: HashKey = SymbolHashKey.real
    
    public static func read(column: Int, row: SQLRowProtocol) -> Double {
        row.readDouble(column: column)
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension String: SQLFieldValue {
    public static let defaultValue: String = ""
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    public static let hashKey: HashKey = SymbolHashKey.text
    
    public static func read(column: Int, row: SQLRowProtocol) -> String {
        row.readString(column: column)
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}


extension URL: SQLFieldValue {
    public static let defaultValue: URL = URL(string: "http://")!
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    public static let hashKey: HashKey = SymbolHashKey.url
    
    public static func read(column: Int, row: SQLRowProtocol) -> URL {
        // TODO: Safe unwrap
        URL(string: row.readString(column: column))!
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self.absoluteString)
    }
}


extension Date: SQLFieldValue {
    public static let defaultValue: Date = Date(timeIntervalSince1970: 0)
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    public static let hashKey: HashKey = SymbolHashKey.date
    
    public static func read(column: Int, row: SQLRowProtocol) -> Date {
        SQLSyntax.date(from: row.readString(column: column))
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: SQLSyntax.string(from: self))
    }
}


extension UUID: SQLFieldValue {
    public static let defaultValue: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    public static let hashKey: HashKey = SymbolHashKey.uuid
    
    public static func read(column: Int, row: SQLRowProtocol) -> UUID {
        let d = row.readData(column: column)
        return UUID(
            uuid: (
                 d[0],  d[1],  d[2],  d[3],
                 d[4],  d[5],  d[6],  d[7],
                 d[8],  d[9], d[10], d[11],
                d[12], d[13], d[14], d[15]
            )
        )
    }
    
    public func bind(context: PreparedStatementContext) throws {
        let u = self.uuid
        try context.bind(
            value: Data([
                u.0,  u.1,  u.2,  u.3,
                u.4,  u.5,  u.6,  u.7,
                u.8,  u.9, u.10, u.11,
               u.12, u.13, u.14, u.15
           ])
        )
    }
}


extension Data: SQLFieldValue {
    public static let defaultValue: Data = Data()
    
    public static let sqlDefinition: SQLToken = KeywordSQLToken(value: "BLOB")

    public static let hashKey: HashKey = SymbolHashKey.data
    
    public static func read(column: Int, row: SQLRowProtocol) -> Data {
        row.readData(column: column)
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try context.bind(value: self)
    }
}
