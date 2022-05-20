import Foundation
import OSLog
import Combine


private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "swiftql")


protocol SQLStatement: SQLBuilder {
    
}


protocol TableSchema {
    
    associatedtype Entity

    static var tableName: SQLIdentifier { get }

    var tableFields: [AnyField] { get }
    
    var tableAlias: SQLIdentifier { get }
    
    init(alias: SQLIdentifier)

    func entity(from row: SQLRow) -> Entity
    
    func values(entity: Entity) -> [SQLIdentifier : SQLExpression]
}


class BaseTableSchema {
    
    let tableAlias: SQLIdentifier
    
    private var fieldAliases = [SQLIdentifier : SQLIdentifier]()

    required init(alias: SQLIdentifier) {
        self.tableAlias = alias
    }
    
    func alias(for field: SQLIdentifier) -> SQLIdentifier {
        if let alias = fieldAliases[field] {
            return alias
        }
        let index = fieldAliases.count
        let alias = tableAlias.field(index)
        fieldAliases[field] = alias
        return alias
    }
}


protocol SQLFieldValue: Hashable {
    static var defaultValue: Self { get }
    
    static var sqlDefinition: SQLToken { get }
    
    static var hashKey: HashKey { get }
}


extension Bool: SQLFieldValue {
    static let defaultValue: Bool = false
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")
    
    static let hashKey: HashKey = SymbolHashKey.boolean
}


extension Int: SQLFieldValue {
    static let defaultValue: Int = 0

    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "INT")

    static let hashKey: HashKey = SymbolHashKey.integer
}


extension Double: SQLFieldValue {
    static let defaultValue: Double = 0

    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "REAL")

    static let hashKey: HashKey = SymbolHashKey.real
}


extension String: SQLFieldValue {
    static let defaultValue: String = ""
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.text
}


extension URL: SQLFieldValue {
    static let defaultValue: URL = URL(string: "http://")!
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.url
}


extension Date: SQLFieldValue {
    static let defaultValue: Date = Date(timeIntervalSince1970: 0)
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.date
}

extension UUID: SQLFieldValue {
    static let defaultValue: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "TEXT")

    static let hashKey: HashKey = SymbolHashKey.uuid
}


extension Data: SQLFieldValue {
    static let defaultValue: Data = Data()
    
    static let sqlDefinition: SQLToken = KeywordSQLToken(value: "BLOB")

    static let hashKey: HashKey = SymbolHashKey.data
}


protocol SQLExpression: SQLBuilder {
}

func &&(lhs: SQLExpression, rhs: SQLExpression) -> SQLExpression {
    return BinaryExpression(operator: .and, lhs: lhs, rhs: rhs)
}


struct SQLVariable {
    let index: Int
}


class Literal<T> where T: SQLFieldValue {
    fileprivate let value: T

    let hashKey: HashKey = SymbolHashKey.variable

    init(_ value: T) {
        self.value = value
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        return VariableSQLToken()
    }
}

final class IntegerLiteral: Literal<Int>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value)
    }
}

final class FloatingPointLiteral: Literal<Double>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value)
    }
}

final class StringLiteral: Literal<String>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value)
    }
}

final class DataLiteral: Literal<Data>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value)
    }
}

final class BooleanLiteral: Literal<Bool>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value ? 1 : 0)
    }
}

final class URLLiteral: Literal<URL>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value.absoluteString)
    }
}

final class DateLiteral: Literal<Date>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: SQLSyntax.dateFormatter.string(from: value))
    }
}

final class UUIDLiteral: Literal<UUID>, SQLExpression {

    func bind(context: PreparedStatementContext) throws {
        try context.bind(value: value.uuidString)
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


struct QualifiedFieldIdentifier: SQLExpression {
    
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
    let field: QualifiedFieldIdentifier
    let order: SQLOrder
    
    init(field: QualifiedFieldIdentifier, order: SQLOrder) {
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


class AnyField {
    
    lazy var qualifiedIdentifier = QualifiedFieldIdentifier(table: table, field: name)

    lazy var qualifiedAlias = QualifiedFieldIdentifier(table: table, field: alias)

    lazy var ascending = FieldOrder(field: qualifiedIdentifier, order: .ascending)
    
    lazy var descending = FieldOrder(field: qualifiedIdentifier, order: .descending)
    
    var hashKey: HashKey { fatalError() }

    let table: SQLIdentifier
    let name: SQLIdentifier
    let alias: SQLIdentifier
    private(set) var column: Int!

    init(name: SQLIdentifier, table: BaseTableSchema) {
        self.table = table.tableAlias
        self.alias = table.alias(for: name)
        self.name = name
    }
    
    func columnDefinition(context: SQLWriter) -> SQLToken {
        fatalError()
    }
    
    func setColumn(_ index: Int) {
        precondition(column == nil)
        column = index
    }
}


class AbstractField<Kind>: AnyField where Kind: SQLFieldValue {

}

extension AbstractField where Kind: Equatable {
    
    static func ==(lhs: AbstractField, rhs: AbstractField) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedIdentifier, rhs: rhs.qualifiedIdentifier)
    }
}

extension AbstractField where Kind == Bool {
    static func ==(lhs: AbstractField, rhs: Kind) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedIdentifier, rhs: BooleanLiteral(rhs))
    }
}

extension AbstractField where Kind == Int {
    static func ==(lhs: AbstractField, rhs: Kind) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedIdentifier, rhs: IntegerLiteral(rhs))
    }
}

extension AbstractField where Kind == String {
    static func ==(lhs: AbstractField, rhs: Kind) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedIdentifier, rhs: StringLiteral(rhs))
    }
}

extension AbstractField where Kind == Data {
    
    static func ==(lhs: AbstractField, rhs: Kind) -> SQLExpression {
        BinaryExpression(operator: .equal, lhs: lhs.qualifiedIdentifier, rhs: DataLiteral(rhs))
    }
}


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


class DatabaseSchema {
    
    private var tableCount = 0

    required init() {
        
    }
    
    func schema<Schema>(table: Schema.Type) -> Schema where Schema: TableSchema {
        defer {
            tableCount += 1
        }
        let alias = SQLIdentifier(table: tableCount)
        let schema = Schema(alias: alias)
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


class Table<Schema> where Schema: TableSchema {
    
    let name: SQLIdentifier
    
    init(name: SQLIdentifier) {
        self.name = name
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


class From: SQLStatement {
    
    let hashKey: HashKey
    let tableName: SQLIdentifier
    let tableAlias: SQLIdentifier

    init<Schema>(_ table: Schema) where Schema: TableSchema {
        self.tableName = Schema.tableName
        self.tableAlias = table.tableAlias
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
    
    init<Schema>(_ table: Schema, on: () -> SQLExpression) where Schema: TableSchema {
        self.on = on()
        self.tableName = Schema.tableName
        self.tableAlias = table.tableAlias
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
    
    typealias Builder = (DefinitionSQLRow) -> Void
    typealias Map = (_ row: SQLRow) -> Row

    let hashKey: HashKey
    
    private let row: DefinitionSQLRow
    private let map: Map

    convenience init<Schema>(_ schema: Schema) where Schema: TableSchema, Schema.Entity == Row {
        self.init(
            builder: { row in
                let _ = schema.entity(from: row)
            },
            map: schema.entity
        )
    }

    convenience init(_ map: @escaping Map) {
        self.init(
            builder: { row in
                let _ = map(row)
            },
            map: map
        )
    }

    init(builder: Builder, map: @escaping Map) {
        let row = DefinitionSQLRow()
        builder(row)
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


class Create: SQLStatement {
    
    let hashKey: HashKey
    
    private let name: SQLIdentifier
    private let fields: [AnyField]
    
    // TODO: Pass closure to map entity variables to schema fields
    
    init<Schema>(_ table: Schema) where Schema: TableSchema {
        self.name = Schema.tableName
        self.fields = table.tableFields
        self.hashKey = CompositeHashKey(
            SymbolHashKey.create,
            IdentifierHashKey(Schema.tableName),
            ListHashKey(
                separator: ",",
                values: table.tableFields.map { tableField in
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
                        field.columnDefinition(context: context)
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
    
    let hashKey: HashKey
    
    private let name: SQLIdentifier
    private let fields: [SQLIdentifier]
    private let values: [SQLBuilder]
    
    init<Schema>(_ table: Schema, _ entity: Schema.Entity) where Schema: TableSchema {
        let fields = table.tableFields.map { $0.name }
        let fieldValues = table.values(entity: entity)
        self.name = Schema.tableName
        self.fields = fields
        self.values = fields.map { fieldValues[$0]! }
        self.hashKey = CompositeHashKey(
            SymbolHashKey.insert,
            IdentifierHashKey(name),
            ListHashKey(
                separator: ",",
                values: table.tableFields.map { field in field.hashKey }
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
    
    init<Schema>(_ table: Schema, @UpdateQueryBuilder values: Values) where Schema: TableSchema {
        self.name = Schema.tableName
        self.alias = table.tableAlias
        self.values = values()
        self.hashKey = CompositeHashKey(
            SymbolHashKey.update,
            IdentifierHashKey(Schema.tableName),
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


class Set: SQLStatement {
    
    let hashKey: HashKey
    
    private let field: SQLIdentifier
    private let value: SQLExpression
    
    // TODO: Spport computed expressions

    // TODO: Support date, url

    convenience init(_ field: AbstractField<Bool>, _ value: Bool) {
        self.init(field: field, value: BooleanLiteral(value))
    }
    
    convenience init(_ field: AbstractField<Int>, _ value: Int) {
        self.init(field: field, value: IntegerLiteral(Int(value)))
    }
    
    convenience init(_ field: AbstractField<Double>, _ value: Double) {
        self.init(field: field, value: FloatingPointLiteral(value))
    }

    convenience init(_ field: AbstractField<String>, _ value: String) {
        self.init(field: field, value: StringLiteral(value))
    }
    
    convenience init(_ field: AbstractField<Data>, _ value: Data) {
        self.init(field: field, value: DataLiteral(value))
    }

    private init<Kind>(field: AbstractField<Kind>, value: SQLExpression) where Kind: SQLFieldValue {
        self.field = field.name
        self.value = value
        self.hashKey = CompositeHashKey(
        )
    }
    
    func sql(context: SQLWriter) -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                IdentifierSQLToken(value: field),
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
    
    static let dateFormatter = ISO8601DateFormatter()

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
    
    static func date(_ string: String) -> Date {
        dateFormatter.date(from: string)!
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
    
    let value: QualifiedFieldIdentifier
    
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
    
    func nextVariable() -> SQLVariable {
        defer {
            variableCount += 1
        }
        return SQLVariable(index: variableCount + 1)
    }
}


protocol SQLRow {
    
    func field(_ field: AbstractField<Bool>) -> Bool
    func field(_ field: AbstractField<Int>) -> Int
    func field(_ field: AbstractField<Double>) -> Double
    func field(_ field: AbstractField<String>) -> String
    func field(_ field: AbstractField<URL>) -> URL
    func field(_ field: AbstractField<Date>) -> Date
    func field(_ field: AbstractField<Data>) -> Data
}


final class DefinitionSQLRow: SQLRow {
    
    private var fields = [AnyField]()
    
    var hashKey: HashKey {
        ListHashKey(
            separator: ",",
            values: fields.map { field in
                field.qualifiedIdentifier.hashKey
            }
        )
    }
    
    func field(_ field: AbstractField<Bool>) -> Bool {
        field.setColumn(fields.count)
        fields.append(field)
        return Bool.defaultValue
    }

    func field(_ field: AbstractField<Int>) -> Int {
        field.setColumn(fields.count)
        fields.append(field)
        return Int.defaultValue
    }
    
    func field(_ field: AbstractField<Double>) -> Double {
        field.setColumn(fields.count)
        fields.append(field)
        return Double.defaultValue
    }
    
    func field(_ field: AbstractField<String>) -> String {
        field.setColumn(fields.count)
        fields.append(field)
        return String.defaultValue
    }
    
    func field(_ field: AbstractField<URL>) -> URL {
        field.setColumn(fields.count)
        fields.append(field)
        return URL.defaultValue
    }
    
    func field(_ field: AbstractField<Date>) -> Date {
        field.setColumn(fields.count)
        fields.append(field)
        return Date.defaultValue
    }

    func field(_ field: AbstractField<Data>) -> Data {
        field.setColumn(fields.count)
        fields.append(field)
        return Data.defaultValue
    }

    func token() -> SQLToken {
        CompositeSQLToken(
            separator: ", ",
            tokens: fields.map { field in
                QualifiedIdentifierSQLToken(value: field.qualifiedIdentifier)
            }
        )
    }
}


struct ResultSQLRow: SQLRow {
    
    let row: SQLRowProtocol
    
    func field(_ field: AbstractField<Bool>) -> Bool {
        row.readInt(column: field.column) == 0 ? false : true
    }

    func field(_ field: AbstractField<Int>) -> Int {
        row.readInt(column: field.column)
    }
    
    func field(_ field: AbstractField<Double>) -> Double {
        row.readDouble(column: field.column)
    }
    
    func field(_ field: AbstractField<String>) -> String {
        row.readString(column: field.column)
    }
    
    func field(_ field: AbstractField<URL>) -> URL {
        // TODO: Return undefined URL
        URL(string: row.readString(column: field.column))!
    }
    
    func field(_ field: AbstractField<Date>) -> Date {
        SQLSyntax.date(row.readString(column: field.column))
    }

    func field(_ field: AbstractField<Data>) -> Data {
        row.readData(column: field.column)
    }

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
    
    static func buildBlock(_ s: Set...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", s)
    }
}


@resultBuilder class OrderByQueryBuilder {
    
    static func buildBlock(_ terms: FieldOrder...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", terms)
    }
}

