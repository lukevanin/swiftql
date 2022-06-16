import Foundation
import OSLog
import Combine


private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "swiftql")


protocol SQLStatement: SQLBuilder {
    
}


struct TableSchema<T> where T: Table {
    let fields: [AnyFieldSchema<T>]
    let fieldsByKeyPath: [AnyKeyPath: AnyFieldSchema<T>]
    
    init(fields: [AnyFieldSchema<T>]) {
        self.fields = fields
        self.fieldsByKeyPath = Dictionary<AnyKeyPath, AnyFieldSchema<T>>(
            uniqueKeysWithValues: fields.map { field in
                (field.keyPath, field)
            }
        )
    }
}

extension TableSchema {
    subscript<Value>(field keyPath: KeyPath<T, Value>) -> FieldSchema<T, Value> where Value: SQLFieldValue {
        fieldsByKeyPath[keyPath] as! FieldSchema<T, Value>
    }
}


class AnyFieldSchema<T> where T: Table {
    let identifier: SQLIdentifier
    let codingKey: CodingKey
    let hashKey: HashKey
    let sqlDefinition: SQLToken
    let keyPath: AnyKeyPath
    
    init(
        identifier: SQLIdentifier,
        codingKey: CodingKey,
        hashKey: HashKey,
        sqlDefinition: SQLToken,
        keyPath: AnyKeyPath
    ) {
        self.identifier = identifier
        self.codingKey = codingKey
        self.hashKey = hashKey
        self.sqlDefinition = sqlDefinition
        self.keyPath = keyPath
    }
}


final class FieldSchema<T, F>: AnyFieldSchema<T> where T: Table, F: SQLFieldValue {
    
    let typedKeyPath: WritableKeyPath<T, F>

    init(codingKey: CodingKey, keyPath: WritableKeyPath<T, F>) where F: SQLFieldValue {
        self.typedKeyPath = keyPath
        super.init(
            identifier: SQLIdentifier(stringLiteral: codingKey.stringValue),
            codingKey: codingKey,
            hashKey: F.hashKey,
            sqlDefinition: F.sqlDefinition,
            keyPath: keyPath
        )
    }
}


protocol Table: Identifiable, Equatable, Codable {
    var id: PrimaryKey { get }
    static var defaults: Self { get }
    static var schema: TableSchema<Self> { get }
}

extension Table {
    
    static var tableName: SQLIdentifier {
        SQLIdentifier(stringLiteral: String(describing: self))
    }
}


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


protocol SQLExpression: SQLBuilder {
}

func &&(lhs: SQLExpression, rhs: SQLExpression) -> SQLExpression {
    return BinaryExpression(operator: .and, lhs: lhs, rhs: rhs)
}


//struct SQLVariable {
//    let index: Int
//}


class AnyLiteral {
    
    let hashKey: HashKey = SymbolHashKey.variable

    func sql(context: SQLWriter) -> SQLToken {
        return VariableSQLToken()
    }
    
    func bind(context: PreparedStatementContext) throws {
        fatalError("throws")
    }
}


class Literal<T>: AnyLiteral, SQLExpression where T: SQLFieldValue {
    fileprivate let value: T

    init(_ value: T) {
        self.value = value
    }
    
    override func bind(context: PreparedStatementContext) throws {
        try value.bind(context: context)
    }
    
    override func sql(context: SQLWriter) -> SQLToken {
        VariableSQLToken()
    }
}



class BinaryExpression: SQLExpression {
    
    enum Operator: SQLBuilder {
        case equal
        case and
        case or
        
        var hashKey: HashKey {
            switch self {
            case .equal:
                return SymbolHashKey.equality
            case .and:
                return SymbolHashKey.and
            case .or:
                return SymbolHashKey.or
            }
        }
        
        func sql(context: SQLWriter) -> SQLToken {
            switch self {
            case .equal:
                return KeywordSQLToken(value: "==")
            case .and:
                return KeywordSQLToken(value: "AND")
            case .or:
                return KeywordSQLToken(value: "OR")
            }
        }
        
        func bind(context: PreparedStatementContext) throws {
            
        }
    }
    
    let hashKey: HashKey
    let `operator`: Operator
    let lhs: SQLExpression
    let rhs: SQLExpression
    
    init(operator: Operator, lhs: SQLExpression, rhs: SQLExpression) {
        self.hashKey = CompositeHashKey(lhs.hashKey, `operator`.hashKey, rhs.hashKey)
        self.operator = `operator`
        self.lhs = lhs
        self.rhs = rhs
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                lhs.sql(context: context),
                `operator`.sql(context: context),
                rhs.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        
    }
}


struct SQLIdentifier: Hashable, ExpressibleByStringLiteral {
    
    let value: String
    
    init(table: Int) {
        self.init(stringLiteral: "t\(table)")
    }
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    func field(_ field: Int) -> SQLIdentifier {
        SQLIdentifier(stringLiteral: "\(value)f\(field)")
    }
}


struct SQLQualifiedFieldIdentifier: SQLExpression {
    
    let hashKey: HashKey
    let table: SQLIdentifier
    let field: SQLIdentifier

    init(table: SQLIdentifier, field: SQLIdentifier) {
        self.table = table
        self.field = field
        self.hashKey = QualifiedIdentifierHashKey(table, field)
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        QualifiedIdentifierSQLToken(value: self)
    }
    
    func bind(context: PreparedStatementContext) throws {
        
    }
}



struct FieldOrder: SQLBuilder {
    
    let hashKey: HashKey
    let field: SQLQualifiedFieldIdentifier
    let order: SQLOrder
    
    init(field: SQLQualifiedFieldIdentifier, order: SQLOrder) {
        self.field = field
        self.order = order
        self.hashKey = CompositeHashKey(field.hashKey, order.hashKey)
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                QualifiedIdentifierSQLToken(value: field),
                order.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        
    }
}


//class AnyField {
//
//    lazy var qualifiedIdentifier = QualifiedFieldIdentifier(table: table, field: name)
//
//    lazy var qualifiedAlias = QualifiedFieldIdentifier(table: table, field: alias)
//
//    lazy var ascending = FieldOrder(field: qualifiedIdentifier, order: .ascending)
//
//    lazy var descending = FieldOrder(field: qualifiedIdentifier, order: .descending)
//
//    var hashKey: HashKey { fatalError() }
//
//    let table: SQLIdentifier
//    let name: SQLIdentifier
//    let alias: SQLIdentifier
//    private(set) var column: Int!
//
//    init(name: SQLIdentifier, table: BaseTableSchema) {
//        self.table = table.tableAlias
//        self.alias = table.alias(for: name)
//        self.name = name
//    }
//
//    func columnDefinition(context: SQLWriter) -> SQLToken {
//        fatalError()
//    }
//
//    func setColumn(_ index: Int) {
//        precondition(column == nil)
//        column = index
//    }
//}



@propertyWrapper struct Field<T>: Codable, Equatable where T: SQLFieldValue {
    
    let name: String
    let wrappedValue: T
    
    init(_ wrappedValue: T? = nil, name: String) {
        self.wrappedValue = wrappedValue ?? T.defaultValue
        self.name = name
    }
}


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


/*
class PrimaryKeyField<Kind>: AbstractField<Kind> where Kind: SQLFieldValue  {
    
    override var hashKey: HashKey {
        CompositeHashKey(
            IdentifierHashKey(name),
            Kind.hashKey,
            SymbolHashKey.primaryKey,
            SymbolHashKey.not,
            SymbolHashKey.null
        )
    }

    override func columnDefinition(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                IdentifierSQLToken(value: name),
                Kind.sqlDefinition,
                KeywordSQLToken(value: "PRIMARY"),
                KeywordSQLToken(value: "KEY"),
                KeywordSQLToken(value: "NOT"),
                KeywordSQLToken(value: "NULL")
            ]
        )
    }
}


class ForeignKeyField<Kind, Relation>: AbstractField<Kind> where Kind: SQLFieldValue & Hashable, Relation: TableSchema {
    
    override var hashKey: HashKey {
        CompositeHashKey(
            IdentifierHashKey(name),
            Kind.hashKey,
            SymbolHashKey.foreignKey,
            SymbolHashKey.not,
            SymbolHashKey.null,
            IdentifierHashKey(Relation.tableName),
            foreignField.hashKey
        )
    }

    let foreignField: PrimaryKeyField<Kind>
    
    init(name: SQLIdentifier, table: BaseTableSchema, field: KeyPath<Relation, PrimaryKeyField<Kind>>) {
        let foreignSchema = Relation(alias: SQLIdentifier(stringLiteral: "temp"))
        self.foreignField = foreignSchema[keyPath: field]
        super.init(name: name, table: table)
    }
    
    override func columnDefinition(context: SQLWriter) -> SQLToken {
        return CompositeSQLToken(
            separator: " ",
            tokens: [
                IdentifierSQLToken(value: name),
                Kind.sqlDefinition,
                KeywordSQLToken(value: "REFERENCES"),
                IdentifierSQLToken(value: Relation.tableName),
                KeywordSQLToken(value: "("),
                IdentifierSQLToken(value: foreignField.name),
                KeywordSQLToken(value: ")"),
                KeywordSQLToken(value: "NOT"),
                KeywordSQLToken(value: "NULL")
            ]
        )
    }
}


class Field<Kind>: AbstractField<Kind> where Kind: SQLFieldValue {
    
    override var hashKey: HashKey {
        CompositeHashKey(
            IdentifierHashKey(name),
            Kind.hashKey,
            SymbolHashKey.not,
            SymbolHashKey.null
        )
    }
    
    override func columnDefinition(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                IdentifierSQLToken(value: name),
                Kind.sqlDefinition,
                KeywordSQLToken(value: "NOT"),
                KeywordSQLToken(value: "NULL")
            ]
        )
    }
}
 
 */


class DatabaseSchema {
    
    private var tableCount = 0

    required init() {
        
    }
    
    func schema<T>(table: T.Type) -> T where T: Table {
        defer {
            tableCount += 1
        }
        let alias = SQLIdentifier(table: tableCount)
        let schema = TableReference(table: T.self, alias: alias)
        return schema
    }
}


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


class ObservableStatement<T>: Publisher {
    typealias Failure = Error
    
    typealias Output = Result<[T], Error>
    
    // TODO: Raise error when database connection is closed
    
    private var eventCancellable: AnyCancellable?
    private let statement: PreparedSQL<T>
    private let provider: SQLProviderProtocol
    private let subject: CurrentValueSubject<Output, Failure>
    
    init(statement: PreparedSQL<T>, provider: SQLProviderProtocol) {
        logger.debug("observable statement > init > start")
        self.statement = statement
        self.provider = provider
        self.subject = CurrentValueSubject(.success([]))
        

        // TODO: Attach to database event and re-run query when database transaction is committed.
        // TODO: Use async sequence instead of publisher to observe events.
        eventCancellable = provider.eventsPublisher.sink(
            receiveCompletion: { completion in
                
            },
            receiveValue: { [weak self] event in
                logger.debug("observable statement > event : \(event.rawValue)")
                if event == .commit {
                    self?.invalidate()
                }
            }
        )
        invalidate()
        logger.debug("observable statement > init > end")
    }
    
    deinit {
        logger.debug("observable statement > deinit")
        eventCancellable?.cancel()
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, S.Input == Output, S.Failure == Failure {
        subject.receive(subscriber: subscriber)
    }
    
    private func invalidate() {
        Task { [weak self] in
            guard let self = self else {
                return
            }
            try await self.provider.transaction { [weak self] transaction in
                guard let self = self else {
                    return
                }
                logger.debug("observable statement > invalidate")
                let value: Output
                do {
                    let result = try self.statement.execute()
                    value = .success(result)
                }
                catch {
                    value = .failure(error)
                }
                self.subject.send(value)
            }
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


class TableAlias {
    let alias: Int

    init(_ alias: Int) {
        self.alias = alias
    }
    
    var identifier: SQLIdentifier {
        SQLIdentifier(stringLiteral: "t\(alias)")
    }
}


///
/// Refers to a specific instance of a table used in a query.
///
struct TableReference<T> where T: Table {
    
    let name: SQLIdentifier
    let alias: SQLIdentifier
    
    init(name: SQLIdentifier, alias: SQLIdentifier) {
        self.name = name
        self.alias = alias
    }
    
    func fields() -> [TableFieldReference<T>] {
        // TODO: Pre-compute field hash keys
        T.schema.fields.map { field in
            TableFieldReference(table: self, field: field)
        }
    }
    
    subscript<F>(field keyPath: KeyPath<T, F>) -> FieldReference<T, F> where F: SQLFieldValue {
        FieldReference(table: self, field: T.schema[field: keyPath])
    }
    
    func values(entity: T) -> [SQLIdentifier : SQLBuilder] {
        var output = [SQLIdentifier : SQLBuilder]()
        for field in fields() {
            output[field.qualifiedName.field] = field.valueExpression(entity: entity)
        }
        return output
    }
    
    func read(row: SQLRow) -> T {
        var entity = T.defaults
        for field in fields() {
            field.read(row: row, entity: &entity)
        }
        return entity
    }
}

extension TableReference {
    
    init(table: T.Type, alias: SQLIdentifier) {
        self.init(name: T.tableName, alias: alias)
    }
}


protocol FieldReferenceProtocol {
    var qualifiedName: SQLQualifiedFieldIdentifier { get }
    var hashKey: HashKey { get }
    func sqlColumnDefinition() -> SQLToken
}


class TableFieldReference<T>: FieldReferenceProtocol where T: Table {
    
    let qualifiedName: SQLQualifiedFieldIdentifier
    let hashKey: HashKey
    let table: TableReference<T>
    let field: AnyFieldSchema<T>
    
    init(table: TableReference<T>, field: AnyFieldSchema<T>) {
        self.qualifiedName = SQLQualifiedFieldIdentifier(
            table: table.alias,
            field: field.identifier
        )
        self.hashKey = qualifiedName.hashKey
        self.table = table
        self.field = field
    }
    
    func sqlColumnDefinition() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                QualifiedIdentifierSQLToken(value: qualifiedName),
                KeywordSQLToken(value: "AS"),
                field.sqlDefinition
            ]
        )
    }
    
    func read(row: SQLRow, entity: inout T) {
        fatalError("not implemented")
    }
    
    func valueExpression(entity: T) -> SQLBuilder {
        fatalError("not implemented")
    }
}


class FieldReference<T, V>: TableFieldReference<T> where T: Table, V: SQLFieldValue {
    
    let typedField: FieldSchema<T, V>

    private var column: Int?

    init(table: TableReference<T>, field: FieldSchema<T, V>) {
        self.typedField = field
        super.init(table: table, field: field)
    }
    
    override func read(row: SQLRow, entity: inout T) {
        let value = row.field(self)
        entity[keyPath: typedField.typedKeyPath] = value
    }

    func setColumn(_ column: Int) {
        self.column = column
    }

    func readValue(row: SQLRowProtocol) -> V {
        V.read(column: column!, row: row)
    }

    func bind(entity: T, context: PreparedStatementContext) throws {
        let value = entity[keyPath: typedField.typedKeyPath]
        try value.bind(context: context)
    }
    
    override func valueExpression(entity: T) -> SQLBuilder {
        return Literal(entity[keyPath: typedField.typedKeyPath])
    }
}

extension FieldReference {
    
    static func ==(lhs: FieldReference, rhs: FieldReference) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: rhs.qualifiedName)
    }
}

extension FieldReference {
    static func ==(lhs: FieldReference, rhs: V) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
    }
}

//extension FieldReference where V == Bool {
//    static func ==(lhs: FieldReference, rhs: Bool) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
//    }
//}
//
//extension FieldReference where V == Int {
//    static func ==(lhs: FieldReference, rhs: Int) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
//    }
//}
//
//extension FieldReference where V == String {
//    static func ==(lhs: FieldReference, rhs: V) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
//    }
//}
//
//extension FieldReference where V == Data {
//
//    static func ==(lhs: FieldReference, rhs: V) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
//    }
//}

// TODO: FieldReference equatable for extended types (URL, UUID, and Date)



class From: SQLStatement {
    
    let hashKey: HashKey
    let tableName: SQLIdentifier
    let tableAlias: SQLIdentifier

    init<T>(_ table: TableReference<T>) where T: Table {
        self.tableName = table.name
        self.tableAlias = table.alias
        self.hashKey = CompositeHashKey(
            SymbolHashKey.from,
            IdentifierHashKey(tableName)
        )
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "FROM"),
                IdentifierSQLToken(value: tableName),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: tableAlias)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
    
    }
}


class Join: SQLStatement {
    
    typealias Tokenizer = (SQLWriter) -> SQLToken

    let hashKey: HashKey
    let tableName: SQLIdentifier
    let tableAlias: SQLIdentifier
    let on: SQLExpression
    
    init<T>(_ table: TableReference<T>, on: () -> SQLExpression) where T: Table {
        self.on = on()
        self.tableName = table.name
        self.tableAlias = table.alias
        self.hashKey = CompositeHashKey(
            SymbolHashKey.join,
            IdentifierHashKey(tableName),
            IdentifierHashKey(tableAlias),
            self.on.hashKey
        )
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "JOIN"),
                IdentifierSQLToken(value: tableName),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: tableAlias),
                KeywordSQLToken(value: "ON"),
                on.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try on.bind(context: context)
    }
}


class Where: SQLStatement {
    
    let hashKey: HashKey
    let expression: SQLExpression

    init(_ expression: () -> SQLExpression) {
        self.expression = expression()
        self.hashKey = CompositeHashKey(
            SymbolHashKey.where,
            self.expression.hashKey
        )
    }

    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "WHERE"),
                expression.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try expression.bind(context: context)
    }
}


enum SQLOrder {
    case ascending
    case descending
}

extension SQLOrder: SQLExpression {
    
    var hashKey: HashKey {
        switch self {
        case .ascending:
            return SymbolHashKey.ascending
        case .descending:
            return SymbolHashKey.descending
        }
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        switch self {
        case .ascending:
            return KeywordSQLToken(value: "ASC")
        case .descending:
            return KeywordSQLToken(value: "DESC")
        }
    }
    
    func bind(context: PreparedStatementContext) throws {
        
    }
}


class OrderBy: SQLStatement {
    
    let hashKey: HashKey
    private let builder: SQLBuilder
    
    init(@OrderByQueryBuilder _ builder: () -> SQLBuilder) {
        self.builder = builder()
        self.hashKey = CompositeHashKey(SymbolHashKey.orderBy, self.builder.hashKey)
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "ORDER"),
                KeywordSQLToken(value: "BY"),
                builder.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try builder.bind(context: context)
    }
}


class Select<Row>: SQLBuilder, SQLReader {
    
    typealias Map = (_ decoder: SQLRow) -> Row

    let hashKey: HashKey
    
    private let row: DefinitionSQLRow
    private let map: Map

    init(map: @escaping Map) {
        let row = DefinitionSQLRow()
        let _ = map(row)
        self.hashKey = CompositeHashKey(SymbolHashKey.select, row.hashKey)
        self.row = row
        self.map = map
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "SELECT"),
                row.token()
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        // TODO: Support computed column values
    }
    
    func read(row: SQLRow) -> Row {
        map(row)
    }
}

extension Select where Row: Table {
    convenience init(_ table: TableReference<Row>) {
        self.init { row in
            table.read(row: row)
        }
    }
}


class Create: SQLStatement {
    
    let hashKey: HashKey
    
    private let name: SQLIdentifier
    private let fields: [FieldReferenceProtocol]
    
    // TODO: Pass closure to map entity variables to schema fields
    
    init<T>(_ table: TableReference<T>) where T: Table {
        self.name = table.name
        self.fields = table.fields()
        self.hashKey = CompositeHashKey(
            SymbolHashKey.create,
            IdentifierHashKey(table.name),
            ListHashKey(
                separator: ",",
                values: T.schema.fields.map { tableField in
                    tableField.hashKey
                }
            )
        )
    }

    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "CREATE"),
                KeywordSQLToken(value: "TABLE"),
                KeywordSQLToken(value: "IF"),
                KeywordSQLToken(value: "NOT"),
                KeywordSQLToken(value: "EXISTS"),
                IdentifierSQLToken(value: name),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: fields.map { field in
                        field.sqlColumnDefinition()
                    }
                ),
                KeywordSQLToken(value: ")"),
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        // TODO: Support computed column values and default values
    }
}


class Insert: SQLStatement {
    
    #warning("TODO: Split into separate INSERT/INTO/VALUES keywords")
    
    let hashKey: HashKey
    
    private let name: SQLIdentifier
    private let fields: [SQLIdentifier]
    private let values: [SQLBuilder]
    
    init<T>(_ table: TableReference<T>, values entity: @autoclosure () -> T) where T: Table {
        let fields = table.fields()
        let fieldsNames = fields.map { $0.qualifiedName.field }
        let fieldValues = table.values(entity: entity())
        self.name = table.name
        self.fields = fieldsNames
        self.values = fieldsNames.map { fieldValues[$0]! }
        self.hashKey = CompositeHashKey(
            SymbolHashKey.insert,
            IdentifierHashKey(name),
            ListHashKey(
                separator: ",",
                values: fields.map { field in
                    field.hashKey // TODO: Pre-compute field hash keys
                }
            )
        )
    }

    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "INSERT"),
                KeywordSQLToken(value: "INTO"),
                IdentifierSQLToken(value: name),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: fields.map { field in
                        IdentifierSQLToken(value: field)
                    }
                ),
                KeywordSQLToken(value: ")"),
                KeywordSQLToken(value: "VALUES"),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: values.map { value in
                        value.sql(context: context)
                    }
                ),
                KeywordSQLToken(value: ")")
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try values.forEach { value in
            try value.bind(context: context)
        }
    }
}


class Update: SQLStatement {
    
    typealias Values = () -> SQLBuilder
    
    let hashKey: HashKey
    
    private let name: SQLIdentifier
    private let alias: SQLIdentifier
    private let values: SQLBuilder
    
    init<T>(_ table: TableReference<T>, @UpdateQueryBuilder values: Values) where T: Table {
        self.name = table.name
        self.alias = table.alias
        self.values = values()
        self.hashKey = CompositeHashKey(
            SymbolHashKey.update,
            IdentifierHashKey(table.name),
            self.values.hashKey
        )
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "UPDATE"),
                IdentifierSQLToken(value: name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: alias),
                KeywordSQLToken(value: "SET"),
                values.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try values.bind(context: context)
    }
}


class Set<T>: SQLStatement where T: Table {
    
    let hashKey: HashKey
    
    private let field: SQLQualifiedFieldIdentifier
    private let value: SQLExpression
    
    // TODO: Spport computed expressions

    // TODO: Support date, url

//    convenience init(_ field: FieldReference<T, Bool>, _ value: Bool) {
//        self.init(field: field, value: BooleanLiteral(value))
//    }
//
//    convenience init(_ field: FieldReference<T, Int>, _ value: Int) {
//        self.init(field: field, value: IntegerLiteral(Int(value)))
//    }
//
//    convenience init(_ field: FieldReference<T, Double>, _ value: Double) {
//        self.init(field: field, value: FloatingPointLiteral(value))
//    }
//
//    convenience init(_ field: FieldReference<T, String>, _ value: String) {
//        self.init(field: field, value: StringLiteral(value))
//    }
//
//    convenience init(_ field: FieldReference<T, Data>, _ value: Data) {
//        self.init(field: field, value: DataLiteral(value))
//    }

    convenience init<V>(_ field: FieldReference<T, V>, _ value: V) where V: SQLFieldValue {
        self.init(field: field, value: Literal(value))
    }

    private init<Kind>(field: FieldReference<T, Kind>, value: SQLExpression) where Kind: SQLFieldValue {
        self.field = field.qualifiedName
        self.value = value
        self.hashKey = CompositeHashKey(
            QualifiedIdentifierHashKey(field.qualifiedName),
            SymbolHashKey.equality,
            value.hashKey
        )
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                QualifiedIdentifierSQLToken(value: field),
                KeywordSQLToken(value: "="),
                value.sql(context: context)
            ]
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try value.bind(context: context)
    }
}


protocol HashKey {
    var rawValue: String { get }
}


func ==(lhs: HashKey, rhs: HashKey) -> Bool {
    lhs.rawValue == rhs.rawValue
}


struct IdentifierHashKey: HashKey {
    let rawValue: String
    
    init(_ value: SQLIdentifier) {
        self.rawValue = value.value
    }
}


struct QualifiedIdentifierHashKey: HashKey {
    let rawValue: String
    
    init(_ identifier: SQLQualifiedFieldIdentifier) {
        self.init(identifier.table, identifier.field)
    }
    
    init(_ context: SQLIdentifier, _ value: SQLIdentifier) {
        self.rawValue = IdentifierHashKey(context).rawValue + "." + IdentifierHashKey(value).rawValue
    }
}


enum SymbolHashKey: String, HashKey {
    case primaryKey = "pk"
    case foreignKey = "fk"
    case null = "nul"

    case and = "&"
    case or = "|"
    case not = "!"
    case equality = "="
    case variable = "?"
    
    case boolean = "b"
    case integer = "i"
    case real = "r"
    case text = "t"
    case data = "d"
    case date = "dte"
    case uuid = "uid"
    case url = "url"
    
    case ascending = "asc"
    case descending = "dsc"

    case create = "crt"
    case insert = "ins"
    case update = "upd"
    case select = "sel"
    case from = "frm"
    case join = "joi"
    case orderBy = "ord"
    case `where` = "whr"
}


struct ListHashKey: HashKey {
    let rawValue: String
    
    init(separator: String, values: [HashKey]) {
        self.rawValue = "(" + values.map { $0.rawValue }.joined(separator: separator) + ")"
    }
}


struct CompositeHashKey: HashKey {
    
    let rawValue: String
    
    init(_ values: HashKey...) {
        self.rawValue = values.map { $0.rawValue }.joined(separator: " ")
    }
}


protocol SQLBuilder {
    var hashKey: HashKey { get }
    func sql(context: SQLWriter) -> SQLToken
    func bind(context: PreparedStatementContext) throws
}


protocol SQLReader {
    associatedtype Entity
    func read(row: SQLRow) -> Entity
}


struct AnySQLBuilder<Output>: SQLBuilder, SQLReader {
    
    typealias Reader = (SQLRow) -> Output

    let hashKey: HashKey
    private let builder: SQLBuilder
    private let reader: Reader

    init(_ c: Create)  {
        self.builder = c
        self.hashKey = builder.hashKey
        self.reader = { row in
            fatalError()
        }
    }

    init(_ i: Insert) {
        self.builder = i
        self.hashKey = builder.hashKey
        self.reader = { row in
            #warning("TODO: Returns number of rows inserted")
            fatalError()
        }
    }
    
    init(_ u: Update, _ w: Where) {
        self.builder = SQLSequenceBuilder(u, w)
        self.hashKey = builder.hashKey
        self.reader = { row in
            #warning("TODO: Returns number of rows updated")
            fatalError()
        }
    }

    init(_ s: Select<Output>, _ builders: SQLBuilder...) {
        self.builder = SQLSequenceBuilder([s] + builders)
        self.hashKey = builder.hashKey
        self.reader = s.read
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        builder.sql(context: context)
    }
    
    func bind(context: PreparedStatementContext) throws {
        try builder.bind(context: context)
    }

    func read(row: SQLRow) -> Output {
        reader(row)
    }
}


class SQLSequenceBuilder: SQLBuilder {
    
    let hashKey: HashKey
    let separator: String
    let builders: [SQLBuilder]

    convenience init(separator: String = " ", _ builders: SQLBuilder...) {
        self.init(separator: separator, builders)
    }
    
    init(separator: String = " ", _ builders: [SQLBuilder]) {
        self.hashKey = ListHashKey(separator: separator, values: builders.map { $0.hashKey })
        self.separator = separator
        self.builders = builders
    }

    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: separator,
            tokens: builders.map { $0.sql(context: context) }
        )
    }
    
    func bind(context: PreparedStatementContext) throws {
        try builders.forEach { builder in
            try builder.bind(context: context)
        }
    }
}


private enum SQLSyntax {
    
    private static let dateFormatter = ISO8601DateFormatter()

    static func identifier(_ identifier: SQLIdentifier) -> String {
        "`\(identifier.value)`"
    }

    static func string<T>(_ value: T) -> String where T: StringProtocol {
        "'\(value)'"
    }

    static func blob<T>(_ value: T) -> String where T: DataProtocol {
        "x'\(value.hexEncodedString())'"
    }

    static func keyword(_ value: String) -> String {
        value.uppercased()
    }
    
    static func date(from string: String) -> Date {
        dateFormatter.date(from: string)!
    }
    
    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}


protocol SQLToken {
    func string() -> String
}

struct KeywordSQLToken: SQLToken {
    
    let value: String
    
    func string() -> String {
        SQLSyntax.keyword(value)
    }
}


struct IdentifierSQLToken: SQLToken {
    
    let value: SQLIdentifier
    
    func string() -> String {
        SQLSyntax.identifier(value)
    }
}


struct QualifiedIdentifierSQLToken: SQLToken {
    
    let value: SQLQualifiedFieldIdentifier
    
    func string() -> String {
        SQLSyntax.identifier(value.table) + "." + SQLSyntax.identifier(value.field)
    }
}


struct VariableSQLToken: SQLToken {
    
    func string() -> String {
        "?"
    }
}


struct CompositeSQLToken: SQLToken {
    
    let separator: String
    let tokens: [SQLToken]
    
    func string() -> String {
        tokens.map { $0.string() }.joined(separator: separator)
    }
}


class SQLWriter {
    
    private var currentAlias: Int = 0
    private var currentFieldAlias: Int = 0
    private var variableCount: Int = 0

    func nextFieldAlias() -> SQLIdentifier {
        defer {
            currentFieldAlias += 1
        }
        return SQLIdentifier(stringLiteral: "f\(currentFieldAlias)")
    }
    
    func nextAlias() -> SQLIdentifier {
        defer {
            currentAlias += 1
        }
        return SQLIdentifier(stringLiteral: "t\(currentAlias)")
    }
    
//    func nextVariable() -> SQLVariable {
//        defer {
//            variableCount += 1
//        }
//        return SQLVariable(index: variableCount + 1)
//    }
}


enum SQLCodableError: Error {
    case unsupportedBehaviour
}


final class SQLDefinitionDecoder: Decoder {
    
    var codingPath: [CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    let row: DefinitionSQLRow
    
    init(row: DefinitionSQLRow) {
        self.row = row
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(SQLDefinitionKeyedDecodingContainer(context: self))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw SQLCodableError.unsupportedBehaviour
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        // TODO: Support decoding single values
        throw SQLCodableError.unsupportedBehaviour
    }
}


struct SQLDefinitionKeyedDecodingContainer<Key>: KeyedDecodingContainerProtocol where Key: CodingKey {
    
    let context: SQLDefinitionDecoder
    
    var codingPath: [CodingKey] = []
    
    var allKeys: [Key] = []
    
    func contains(_ key: Key) -> Bool {
        return true
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        return true
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        return false
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return ""
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        return 0
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return 0
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return 0
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return 0
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return 0
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return 0
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return 0
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return 0
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return 0
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return 0
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return 0
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return 0
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        throw SQLCodableError.unsupportedBehaviour
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw SQLCodableError.unsupportedBehaviour
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw SQLCodableError.unsupportedBehaviour
    }
    
    func superDecoder() throws -> Decoder {
        return context
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        return context
    }
}


protocol SQLRow {
    func field<T, V>(_ field: FieldReference<T, V>) -> V where T: Table, V: SQLFieldValue
//    func field<T>(_ field: FieldReference<T, Bool>) -> Bool where T: Table
//    func field<T>(_ field: FieldReference<T, Int>) -> Int where T: Table
//    func field<T>(_ field: FieldReference<T, Double>) -> Double where T: Table
//    func field<T>(_ field: FieldReference<T, String>) -> String where T: Table
//    func field<T>(_ field: FieldReference<T, URL>) -> URL where T: Table
//    func field<T>(_ field: FieldReference<T, Date>) -> Date where T: Table
//    func field<T>(_ field: FieldReference<T, Data>) -> Data where T: Table
}


class DefinitionSQLRow: SQLRow {
    
    var fields = [FieldReferenceProtocol]()
    
    var hashKey: HashKey {
        ListHashKey(
            separator: ",",
            values: fields.map { field in
                field.hashKey
            }
        )
    }
    
    func field<T, V>(_ field: FieldReference<T, V>) -> V where T: Table, V: SQLFieldValue {
        field.setColumn(fields.count)
        fields.append(field)
        return V.defaultValue
    }
    
    func token() -> SQLToken {
        CompositeSQLToken(
            separator: ", ",
            tokens: fields.map { field in
                QualifiedIdentifierSQLToken(value: field.qualifiedName)
            }
        )
    }
}


struct ResultSQLRow: SQLRow {
    
    let row: SQLRowProtocol
  
    func field<T, V>(_ field: FieldReference<T, V>) -> V where T : Table, V : SQLFieldValue {
//        row.readInt(column: field.column) == 0 ? false : true
        field.readValue(row: row)
    }

//    func field(_ field: AbstractField<Bool>) -> Bool {
//        row.readInt(column: field.column) == 0 ? false : true
//    }
//
//    func field(_ field: AbstractField<Int>) -> Int {
//        row.readInt(column: field.column)
//    }
//
//    func field(_ field: AbstractField<Double>) -> Double {
//        row.readDouble(column: field.column)
//    }
//
//    func field(_ field: AbstractField<String>) -> String {
//        row.readString(column: field.column)
//    }
//
//    func field(_ field: AbstractField<URL>) -> URL {
//        // TODO: Return undefined URL
//        URL(string: row.readString(column: field.column))!
//    }
//
//    func field(_ field: AbstractField<Date>) -> Date {
//        SQLSyntax.date(row.readString(column: field.column))
//    }
//
//    func field(_ field: AbstractField<Data>) -> Data {
//        row.readData(column: field.column)
//    }

}


@resultBuilder class SelectQueryBuilder {
    
    static func buildBlock(_ c: Create) -> AnySQLBuilder<Void> {
        AnySQLBuilder(c)
    }
    
    static func buildBlock(_ i: Insert) -> AnySQLBuilder<Void> {
        AnySQLBuilder(i)
    }
    
    static func buildBlock(_ u: Update, _ w: Where) -> AnySQLBuilder<Void> {
        AnySQLBuilder(u, w)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, j2)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, w)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j, w)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, w)
    }
    
    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, j2, w)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, j2, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, w, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j, w, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, w, o)
    }

    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
        AnySQLBuilder(s, f, j0, j1, j2, w, o)
    }
}


@resultBuilder class UpdateQueryBuilder {
    
    static func buildBlock<T>(_ s: Set<T>...) -> SQLBuilder where T: Table {
        SQLSequenceBuilder(separator: ", ", s)
    }
}


@resultBuilder class OrderByQueryBuilder {
    
    static func buildBlock(_ terms: FieldOrder...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", terms)
    }
}

