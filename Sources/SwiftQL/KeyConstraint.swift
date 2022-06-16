import Foundation


protocol KeyProtocol: SQLFieldValue  {
    var uuid: UUID { get }
    init(_ uuid: UUID)
}


struct PrimaryKey: KeyProtocol {
    
    var uuidString: String {
        uuid.uuidString
    }
    
    let uuid: UUID
    
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid)
    }
    
    init() {
        self.init(UUID())
    }
    
    init(_ uuid: UUID) {
        self.uuid = uuid
    }
    
    static var sqlDefinition: SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "TEXT"),
                KeywordSQLToken(value: "PRIMARY"),
                KeywordSQLToken(value: "KEY")
            ]
        )
    }
    
    static var hashKey: HashKey {
        CompositeHashKey(
            SymbolHashKey.data,
            SymbolHashKey.primaryKey
        )
    }
    
    static var defaultValue: PrimaryKey {
        PrimaryKey()
    }
    
    static func read(column: Int, row: SQLRowProtocol) -> PrimaryKey {
        PrimaryKey(UUID.read(column: column, row: row))
    }
    
    func bind(context: PreparedStatementContext) throws {
        try uuid.bind(context: context)
    }
}


struct ForeignKey<T>: KeyProtocol {
    
    var uuidString: String {
        uuid.uuidString
    }
    
    let uuid: UUID
    
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid)
    }
    
    init(_ uuid: UUID) {
        self.uuid = uuid
    }
    
    static var sqlDefinition: SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "TEXT"),
                KeywordSQLToken(value: "FOREIGN"),
                KeywordSQLToken(value: "KEY")
            ]
        )
    }
    
    static var hashKey: HashKey {
        CompositeHashKey(
            SymbolHashKey.data,
            SymbolHashKey.foreignKey
        )
    }
    
    static var defaultValue: ForeignKey {
        ForeignKey(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
    
    static func read(column: Int, row: SQLRowProtocol) -> ForeignKey<T> {
        ForeignKey(UUID.read(column: column, row: row))
    }
    
    func bind(context: PreparedStatementContext) throws {
        try uuid.bind(context: context)
    }
}

