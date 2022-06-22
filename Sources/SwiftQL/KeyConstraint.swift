import Foundation


protocol KeyProtocol: SQLFieldValue  {
    var uuid: UUID { get }
    init(_ uuid: UUID)
}


public struct PrimaryKey: KeyProtocol {
    
    public var uuidString: String {
        uuid.uuidString
    }
    
    public let uuid: UUID
    
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid)
    }
    
    public init() {
        self.init(UUID())
    }
    
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }
    
    public static var sqlDefinition: SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "TEXT"),
                KeywordSQLToken(value: "PRIMARY"),
                KeywordSQLToken(value: "KEY")
            ]
        )
    }
    
    public static var hashKey: HashKey {
        CompositeHashKey(
            SymbolHashKey.data,
            SymbolHashKey.primaryKey
        )
    }
    
    public static var defaultValue: PrimaryKey {
        PrimaryKey()
    }
    
    public static func read(column: Int, row: SQLRowProtocol) -> PrimaryKey {
        PrimaryKey(UUID.read(column: column, row: row))
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try uuid.bind(context: context)
    }
}


public struct ForeignKey<T>: KeyProtocol where T: Table {
    
    public var uuidString: String {
        uuid.uuidString
    }
    
    public let uuid: UUID
    
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid)
    }
    
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }
    
    public static var sqlDefinition: SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "TEXT"),
                KeywordSQLToken(value: "REFERENCES"),
                IdentifierSQLToken(value: T._name),
                KeywordSQLToken(value: "("),
                IdentifierSQLToken(value: SQLIdentifier(stringLiteral: "id")),
                KeywordSQLToken(value: ")")
            ]
        )
    }
    
    public static var hashKey: HashKey {
        CompositeHashKey(
            SymbolHashKey.data,
            SymbolHashKey.foreignKey
        )
    }
    
    public static var defaultValue: ForeignKey {
        ForeignKey(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
    
    public static func read(column: Int, row: SQLRowProtocol) -> ForeignKey<T> {
        ForeignKey(UUID.read(column: column, row: row))
    }
    
    public func bind(context: PreparedStatementContext) throws {
        try uuid.bind(context: context)
    }
}

