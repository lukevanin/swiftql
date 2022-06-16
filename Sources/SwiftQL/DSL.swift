import Foundation


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


@resultBuilder class OrderByQueryBuilder {
    
    static func buildBlock(_ terms: FieldOrder...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", terms)
    }
}

