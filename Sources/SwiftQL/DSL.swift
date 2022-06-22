import Foundation


class KeywordBuilder {
    
    fileprivate var context: SQLWriter!

    func setContext(_ context: SQLWriter) {
        self.context = context
    }
}


class TableKeywordBuilder<T>: KeywordBuilder where T: Table {
    
    fileprivate lazy var schema: T.Schema = context.schema(table: T.self)
}


final class From<R, T>: TableKeywordBuilder<T>, SQLReadStatement where T: Table {
    
    typealias Builder = (T.Schema) -> AnySQLBuilder<R>
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.from,
        IdentifierHashKey(T._name),
        ListHashKey(
            separator: ",",
            values: context.fieldReferenceHashKeys
        )
    )
    
    private lazy var subquery: AnySQLBuilder<R> = builder(schema)
    
    private let builder: Builder

    init(_ table: T.Type, @SelectQueryBuilder _ builder: @escaping Builder){
        self.builder = builder
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "SELECT"),
                CompositeSQLToken(
                    separator: " ",
                    tokens: context.fieldReferenceTokens
                ),
                KeywordSQLToken(value: "FROM"),
                IdentifierSQLToken(value: schema._name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: schema._alias),
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try subquery.bind(statement: statement)
    }
    
    func read(row: SQLRowProtocol) -> R {
        subquery.read(row: row)
    }
    
    override func setContext(_ context: SQLWriter) {
        super.setContext(context)
        subquery.setContext(context)
    }
}


final class Join<R, T>: TableKeywordBuilder<T>, SQLReadStatement where T: Table {
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.join,
        IdentifierHashKey(schema._name),
        IdentifierHashKey(schema._alias),
        constraint.hashKey
    )
    
    let constraint: Field<PrimaryKey>
    let subquery: AnySQLBuilder<R>
    
    init(_ table: T, on constraint: Field<PrimaryKey>, @SelectQueryBuilder builder: () -> AnySQLBuilder<R>) {
        self.constraint = constraint
        self.subquery = builder()
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "JOIN"),
                IdentifierSQLToken(value: schema._name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: schema._alias),
                KeywordSQLToken(value: "ON"),
                QualifiedIdentifierSQLToken(value: schema.$id.qualifiedName),
                KeywordSQLToken(value: "="),
                QualifiedIdentifierSQLToken(value: constraint.qualifiedName),
                subquery.sql()
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try subquery.bind(statement: statement)
    }
    
    func read(row: SQLRowProtocol) -> R {
        subquery.read(row: row)
    }
    
    override func setContext(_ context: SQLWriter) {
        super.setContext(context)
        subquery.setContext(context)
    }
}


final class Where: SQLStatement {
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.where,
        self.expression.hashKey
    )
    
    private let expression: SQLExpression

    init(_ expression: () -> SQLExpression) {
        self.expression = expression()
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "WHERE"),
                expression.sql()
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try expression.bind(statement: statement)
    }
    
    func setContext(_ context: SQLWriter) {
        expression.setContext(context)
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
    
    func sql() -> SQLToken {
        switch self {
        case .ascending:
            return KeywordSQLToken(value: "ASC")
        case .descending:
            return KeywordSQLToken(value: "DESC")
        }
    }
    
    func bind(statement: PreparedStatementContext) throws {

    }
    
    func setContext(_ context: SQLWriter) {
        
    }
}


final class OrderBy: SQLStatement {
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.orderBy,
        builder.hashKey
    )
    
    private let builder: SQLBuilder
    
    init(@OrderByQueryBuilder _ builder: () -> SQLBuilder) {
        self.builder = builder()
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "ORDER"),
                KeywordSQLToken(value: "BY"),
                builder.sql()
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try builder.bind(statement: statement)
    }
    
    func setContext(_ context: SQLWriter) {
        builder.setContext(context)
    }
}


final class Select<R, T>: TableKeywordBuilder<T>, SQLBuilder, SQLReader where T: Table {
    
    typealias Map = () -> R

    lazy var hashKey: HashKey = CompositeHashKey(SymbolHashKey.select)
    
    private let map: Map

    init(_ map: @autoclosure @escaping () -> R) {
        // Hash key of the contents of the map is stored in the SQL writer
        self.map = map
    }
    
    func sql() -> SQLToken {
        NilSQLToken()
//        CompositeSQLToken(
//            separator: " ",
//            tokens: [
//                KeywordSQLToken(value: "SELECT"),
//                CompositeSQLToken(
//                    separator: ",",
//                    tokens: context.fieldReferenceTokens
//                )
//            ]
//        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        // TODO: Support computed column values
    }
    
    func read(row: SQLRowProtocol) -> R {
        map()
    }
    
    override func setContext(_ context: SQLWriter) {
        
    }
}

extension Select where R: Table {
    convenience init(_ table: R.Schema) {
        self.init(R(table))
    }
}


final class Create<T>: TableKeywordBuilder<T>, SQLStatement where T: Table {
    
    lazy var  hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.create,
        IdentifierHashKey(schema._name),
        schema.hashKey,
        ListHashKey(
            separator: ",",
            values: schema._allFields.map { tableField in
                tableField.hashKey
            }
        )
    )
    
    // TODO: Pass closure to map entity variables to schema fields
    
    init(_ table: T.Type) {
        
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "CREATE"),
                KeywordSQLToken(value: "TABLE"),
                KeywordSQLToken(value: "IF"),
                KeywordSQLToken(value: "NOT"),
                KeywordSQLToken(value: "EXISTS"),
                IdentifierSQLToken(value: schema._name),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: schema._allFields.map { field in
                        field.sqlColumnDefinition()
                    }
                ),
                KeywordSQLToken(value: ")"),
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        // TODO: Support computed column values and default values
    }
}


final class Insert<T>: TableKeywordBuilder<T>, SQLStatement where T: Table {
    
    #warning("TODO: Split into separate INSERT/INTO/VALUES keywords")
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.insert,
        IdentifierHashKey(schema._name)
//        ListHashKey(
//            separator: ",",
//            values: schema._allFields.map { field in
//                field.hashKey // TODO: Pre-compute field hash keys
//            }
//        )
    )
    
//    private let name: SQLIdentifier
//    private let fields: [SQLIdentifier]
//    private let values: [SQLBuilder]
    private let entity: T
    
    init(_ entity: @autoclosure () -> T) {
//        let fields = schema._allFields
//        let fieldNames = fields.map { field in
//            field.name
//        }
//        let fieldValues = fields.map { $0 }
//        self.name = schema._name
//        self.fields = fieldNames
//        self.values = entity()._values()
        self.entity = entity()
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "INSERT"),
                KeywordSQLToken(value: "INTO"),
                IdentifierSQLToken(value: schema._name),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: schema._allFields.map { field in
                        IdentifierSQLToken(value: field.name)
                    }
                ),
                KeywordSQLToken(value: ")"),
                KeywordSQLToken(value: "VALUES"),
                KeywordSQLToken(value: "("),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: entity._values().map { value in
                        value.sql()
                    }
                ),
                KeywordSQLToken(value: ")")
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        #warning("TODO: Bind entity values")
//        try values.forEach { value in
//            try value.bind(context: context, statement: statement)
//        }
    }
}


final class Update<T>: TableKeywordBuilder<T>, SQLStatement where T: Table {
    
    typealias Builder = (T.Schema) -> SQLBuilder
    
    lazy var hashKey: HashKey = CompositeHashKey(
        SymbolHashKey.update,
        IdentifierHashKey(schema._name),
        ListHashKey(
            separator: ",",
            values: context.fieldAssignmentHashKeys
        )
    )
    
    private lazy var subquery: SQLBuilder = {
        builder(schema)
    }()
    
    private let builder: Builder
    
    init(_ t: T.Type, @UpdateQueryBuilder _ builder: @escaping Builder) {
        self.builder = builder
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "UPDATE"),
                IdentifierSQLToken(value: schema._name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: schema._alias),
                subquery.sql()
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try subquery.bind(statement: statement)
    }
    
    override func setContext(_ context: SQLWriter) {
        super.setContext(context)
        subquery.setContext(context)
    }
}


final class Set: KeywordBuilder, SQLStatement {
    
    lazy var hashKey: HashKey = SymbolHashKey.set
    
//    private let field: SQLQualifiedFieldIdentifier
//    private let value: SQLExpression
    
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

//    convenience init<V>(_ field: FieldReference<T, V>, _ value: V) where V: SQLFieldValue {
//        self.init(field: field, value: Literal(value))
//    }

//    private init<Kind>(field: FieldReference<T, Kind>, value: SQLExpression) where Kind: SQLFieldValue {
//        self.field = field.qualifiedName
//        self.value = value
//        self.hashKey = CompositeHashKey(
//            QualifiedIdentifierHashKey(field.qualifiedName),
//            SymbolHashKey.equality,
//            value.hashKey
//        )
//    }
    
    init(_ setter: () -> Void) {
        setter()
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "SET"),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: context.fieldAssignmentTokens.map { token in
                        CompositeSQLToken(
                            separator: " ",
                            tokens: [
                                token,
                                KeywordSQLToken(value: "="),
                                VariableSQLToken()
                            ]
                        )
                    }
                )
            ]
        )

//        CompositeSQLToken(
//            separator: " ",
//            tokens: [
//                QualifiedIdentifierSQLToken(value: field),
//                KeywordSQLToken(value: "="),
//                value.sql(context: context)
//            ]
//        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
//        try value.bind(context: context)
    }
}


@resultBuilder class TransactionQueryBuilder {
    
    static func buildBlock<T>(_ c: Create<T>) -> AnySQLBuilder<Void> where T: Table {
        AnySQLBuilder(c)
    }
    
    static func buildBlock<T>(_ i: Insert<T>) -> AnySQLBuilder<Void> where T: Table {
        AnySQLBuilder(i)
    }
    
    static func buildBlock<T>(_ u: Update<T>) -> AnySQLBuilder<Void> where T: Table {
        AnySQLBuilder(u)
    }

    static func buildBlock<R, T>(_ f: From<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(f)
    }

//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, w)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, w, o)
//    }
//
//    static func buildBlock<Row>(_ s: Select<Row>, _ f: From, _ j0: Join, _ j1: Join, _ j2: Join, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<Row> {
//        AnySQLBuilder(s, f, j0, j1, j2, w, o)
//    }
}


@resultBuilder class UpdateQueryBuilder {

    static func buildBlock(_ s: Set) -> SQLBuilder {
//        SQLSequenceBuilder(separator: ", ", s)
        s
    }
    
    static func buildBlock(_ s: Set, _ w: Where) -> SQLBuilder {
//        SQLSequenceBuilder(separator: ", ", s)
        SQLSequenceBuilder(s, w)
    }
}


@resultBuilder class SelectQueryBuilder {
    
    static func buildBlock<R, T>(_ j: Join<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(j)
    }
        
    static func buildBlock<R, T>(_ s: Select<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(s)
    }
}


@resultBuilder class OrderByQueryBuilder {
    
    static func buildBlock(_ terms: FieldOrder...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", terms)
    }
}

