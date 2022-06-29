import Foundation


struct From<Output, T>: SQLBuilder, SQLReader where T: Table {
    
    typealias Builder<S> = (S) -> AnySQLBuilder<Output>
    
    private let schema: TableSchema
    private let subquery: AnySQLBuilder<Output>

    init<S>(_ schema: S, @SelectQueryBuilder _ builder: Builder<S>) where S: TableSchemaOf<T> {
        self.schema = schema
        self.subquery = builder(schema)
    }
    
    func bind() {
        subquery.bind()
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.from,
            IdentifierHashKey(T._name)
        )
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "SELECT"),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: schema._context.fieldReferenceTokens
                ),
                KeywordSQLToken(value: "FROM"),
                IdentifierSQLToken(value: T._name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: schema._alias),
                subquery.sql()
            ]
        )
    }
    
    func read() -> Output {
        subquery.read()
    }
}


struct Join<R, T>: SQLBuilder, SQLReader where T: Table {
    
    typealias Builder<S> = (S) -> AnySQLBuilder<R>

    private let schema: TableSchema
    private let foreignKey: SQLQualifiedFieldIdentifier
    private let subquery: AnySQLBuilder<R>
    
    init<S, F>(_ schema: S, on constraint: Field<ForeignKey<F>>, @SelectQueryBuilder builder: @escaping Builder<S>) where S: TableSchemaOf<T>, F: Table {
        self.schema = schema
        self.foreignKey = constraint.qualifiedName
        self.subquery = builder(schema)
    }
    
    func bind() {
        subquery.bind()
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.join,
            IdentifierHashKey(T._name),
            IdentifierHashKey(schema._alias),
            foreignKey.hashKey()
        )
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
                QualifiedIdentifierSQLToken(value: foreignKey),
                subquery.sql()
            ]
        )
    }
    
    func read() -> R {
        subquery.read()
    }
}


struct Where: SQLStatement {
    
    private let expression: SQLExpression

    init(_ expression: () -> SQLExpression) {
        self.expression = expression()
    }
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.where,
            self.expression.hashKey()
        )
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
}


enum SQLOrder {
    case ascending
    case descending
}

extension SQLOrder: SQLExpression {
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
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
}


struct OrderBy: SQLStatement {
    
    private let builder: SQLBuilder
    
    init(@OrderByQueryBuilder _ builder: () -> SQLBuilder) {
        self.builder = builder()
    }
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.orderBy,
            builder.hashKey()
        )
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
}


public protocol RowProtocol {
    subscript<T>(field: Field<T>) -> T { get }
}


struct Select<R>: SQLBuilder, SQLReader {
    
    typealias Map = () -> R

    private let map: Map

    init(_ map: @escaping Map) {
        // Hash key of the contents of the map is stored in the SQL writer
        self.map = map
        _ = map()
    }
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        SymbolHashKey.select
    }

    func sql() -> SQLToken {
        NilSQLToken()
    }
    
    func read() -> R {
        map()
    }
}

extension Select where R: Table {
    init(_ schema: R.Schema) {
        self.init {
            R(schema: schema)
        }
    }
}


struct Create<T>: SQLWriteStatement where T: Table {
        
    // TODO: Pass closure to map entity variables to schema fields
    private var schema: TableSchema
    
    init<S>(_ schema: S) where S: TableSchemaOf<T> {
        self.schema = schema
    }
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.create,
            IdentifierHashKey(T._name),
            ListHashKey(
                separator: ",",
                values: schema._allFields.map { tableField in
                    tableField.hashKey
                }
            )
        )
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
                KeywordSQLToken(value: ")")
            ]
        )
    }
}


struct Insert<T>: SQLWriteStatement where T: Table {
    
    #warning("TODO: Split into separate INSERT/INTO/VALUES keywords")
    
    private let schema: T.Schema
    private let entity: T
    
    init(_ schema: T.Schema, _ entity: @autoclosure () -> T) {
        self.schema = schema
        self.entity = entity()
    }
    
    func bind() {
        entity._bind(schema: schema)
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.insert,
            IdentifierHashKey(T._name)
        )
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
}


struct Update<T>: SQLBuilder where T: Table {
    
    typealias Builder<S> = (S) -> SQLBuilder
    
    private let schema: TableSchema
    private let subquery: SQLBuilder
    
    init<S>(_ schema: S, @UpdateQueryBuilder _ builder: @escaping Builder<S>) where S: TableSchemaOf<T> {
        #warning("TODO: Return UpdateBuilder")
        self.schema = schema
        self.subquery = builder(schema)
    }
    
    func bind() {
        subquery.bind()
    }
    
    func hashKey() -> HashKey {
        CompositeHashKey(
            SymbolHashKey.update,
            IdentifierHashKey(T._name),
            subquery.hashKey()
        )
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                KeywordSQLToken(value: "UPDATE"),
                IdentifierSQLToken(value: T._name),
                KeywordSQLToken(value: "AS"),
                IdentifierSQLToken(value: schema._alias),
                KeywordSQLToken(value: "SET"),
                CompositeSQLToken(
                    separator: ", ",
                    tokens: schema._context.fieldAssignmentTokens.map { token in
                        CompositeSQLToken(
                            separator: " ",
                            tokens: [
                                token,
                                KeywordSQLToken(value: "="),
                                VariableSQLToken()
                            ]
                        )
                    }
                ),
                subquery.sql()
            ]
        )
    }
}


struct Set: SQLStatement {
    
    init(_ setter: () -> Void) {
        setter()
    }
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        SymbolHashKey.set
    }
    
    func sql() -> SQLToken {
        NilSQLToken()
    }
}


@resultBuilder class UpdateQueryBuilder {

    static func buildBlock(_ s: Set) -> SQLBuilder {
//        SQLSequenceBuilder(separator: ", ", s)
        s
    }
    
    static func buildBlock(_ s: Set, _ w: Where) -> SQLBuilder {
//        SQLSequenceBuilder(separator: ", ", s)
        AnySQLBuilder<Void>(s, w)
    }
}


@resultBuilder class SelectQueryBuilder {
    
    static func buildBlock<R, T>(_ j: Join<R, T>) -> AnySQLBuilder<R> where T: Table {
        AnySQLBuilder(j)
    }
        
    static func buildBlock<R>(_ s: Select<R>) -> AnySQLBuilder<R> {
        AnySQLBuilder(select: s)
    }
    
    static func buildBlock<R>(_ s: Select<R>, _ w: Where) -> AnySQLBuilder<R> {
        AnySQLBuilder(select: s, w)
    }
    
    static func buildBlock<R>(_ s: Select<R>, _ o: OrderBy) -> AnySQLBuilder<R> {
        AnySQLBuilder(select: s, o)
    }
    
    static func buildBlock<R>(_ s: Select<R>, _ w: Where, _ o: OrderBy) -> AnySQLBuilder<R> {
        AnySQLBuilder(select: s, w, o)
    }
}


@resultBuilder class OrderByQueryBuilder {
    
    static func buildBlock(_ terms: FieldOrder...) -> SQLBuilder {
        SQLSequenceBuilder(separator: ", ", builders: terms)
    }
}

