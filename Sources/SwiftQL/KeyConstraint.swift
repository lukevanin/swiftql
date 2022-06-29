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
                KeywordSQLToken(value: "BLOB"),
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
    
    public static func read(context: ReadProtocol) throws -> PrimaryKey {
        PrimaryKey(try UUID.read(context: context))
    }
    
    public func bind(context: BindProtocol) throws {
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
                KeywordSQLToken(value: "BLOB"),
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
    
    public static func read(context: ReadProtocol) throws -> ForeignKey<T> {
        ForeignKey(try UUID.read(context: context))
    }
    
    public func bind(context: BindProtocol) throws {
        try uuid.bind(context: context)
    }
}

