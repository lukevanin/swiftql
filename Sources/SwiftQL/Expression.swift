import Foundation


protocol SQLBuilder {
    func prepare()
    func hashKey() -> HashKey
    func sql() -> SQLToken
    func bind() throws
}


protocol SQLStatement: SQLBuilder {
    
}


protocol SQLReader {
    associatedtype Entity
    func read() -> Entity
}


protocol SQLWriteStatement: SQLStatement {
    
}


protocol SQLReadStatement: SQLStatement, SQLReader {
    
}


struct SQLSequenceBuilder: SQLBuilder {
    
    var separator: String = ", "
    let builders: [SQLBuilder]
    
    func prepare() {
        for builder in builders {
            builder.prepare()
        }
    }
    
    func hashKey() -> HashKey {
        ListHashKey(
            separator: ", ",
            values: builders.map { builder in
                builder.hashKey()
            }
        )
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: ", ",
            tokens: builders.map { builder in
                builder.sql()
            }
        )
    }
    
    func bind() throws {
        for builder in builders {
            try builder.bind()
        }
    }
}


struct AnySQLBuilder<Output>: SQLBuilder {
    
    typealias Reader = () -> Output

    private let builders: [SQLBuilder]
    private let reader: Reader

    init(select: Select<Output>, _ builders: SQLStatement...) {
        self.builders = [select] + builders
        self.reader = select.read
    }

    init(_ builders: SQLBuilder...) {
        self.builders = builders
        self.reader = {
            fatalError("reader not implemented")
        }
    }

    init(_ builders: [SQLBuilder]) {
        self.builders = builders
        self.reader = {
            fatalError("reader not implemented")
        }
    }

    init<S>(_ builder: S) where S: SQLBuilder & SQLReader, S.Entity == Output {
        self.builders = [builder]
        self.reader = builder.read
    }
    
    func prepare() {
        for builder in builders {
            builder.prepare()
        }
    }
    
    func hashKey() -> HashKey {
        ListHashKey(
            separator: " ",
            values: builders.map { builder in
                builder.hashKey()
            }
        )
    }
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: builders.map { builder in
                builder.sql()
            }
        )
    }

    func bind() throws {
        for builder in builders {
            try builder.bind()
        }
    }
    
    func read() -> Output {
        reader()
    }
}


//struct SQLWriteStatements {
//
//    let builders: [SQLBuilder]
//
//    init(_ builders: SQLBuilder...) {
//        self.init(builders)
//    }
//
//    init(_ builders: [SQLBuilder]) {
//        self.builders = builders
//    }
//
//    func execute(connection: DatabaseConnection, cached: Bool) {
//        for builder in builders {
//            let statement = try connection.statement(
//                cached: cached,
//                query: builder
//            )
//            try statement.execute()
//        }
//    }
//
//}


//struct SQLReadStatements<Output> {
//
//    let builders: [Select<Output>]
//
//    init(_ builders: Select<Output>...) {
//        self.init(builders)
//    }
//    
//    init(_ builders: [Select<Output>]) {
//        self.builders = builders
//    }
//    
//    func execute(connection: DatabaseConnection, cached: Bool) -> [Output] {
//        var output = [Output]()
//        for builder in builders {
//            let statement = try connection.readStatement(
//                cached: cached,
//                query: builder
//            )
//            let results = try statement.execute()
//            output.append(contentsOf: results)
//        }
//        return output
//    }
//}


public final class SQLWriter {
    
    var fieldReferenceTokens: [SQLToken] {
        fieldReferenceIdentifiers.map { fieldIdentifier in
            QualifiedIdentifierSQLToken(value: fieldIdentifier)
        }
    }
    
    var fieldAssignmentTokens: [SQLToken] {
        fieldAssignmentIdentifiers.map { fieldIdentifier in
            QualifiedIdentifierSQLToken(value: fieldIdentifier)
        }
    }

    private let row: SQLRowProtocol?
    private let statement: PreparedStatementContext?

    private var tableCount = 0
    private var referenceCount = 0
    private var assignmentCount = 0

    private(set) var fieldReferenceHashKeys = [HashKey]()
    private(set) var fieldAssignmentHashKeys = [HashKey]()
    
    private var fieldReferenceIdentifiers = [SQLQualifiedFieldIdentifier]()
    private var fieldAssignmentIdentifiers = [SQLQualifiedFieldIdentifier]()
    
    init(row: SQLRowProtocol? = nil, statement: PreparedStatementContext? = nil) {
        self.row = row
        self.statement = statement
    }

    private func addFieldReference(field: AnyField) {
        fieldReferenceHashKeys.append(field.hashKey)
        fieldReferenceIdentifiers.append(field.qualifiedName)
    }

    private func addFieldAssignment<Value>(field: AnyField, value: Value) where Value: SQLFieldValue {
        fieldAssignmentHashKeys.append(field.hashKey)
        fieldAssignmentIdentifiers.append(field.qualifiedName)
    }

    func makeSchema<S, T>() -> S where S: TableSchemaOf<T>, T: Table {
        defer {
            tableCount += 1
        }
        let alias = SQLIdentifier(table: tableCount)
        return S(name: T._name, alias: alias, context: self)
    }
    
    func getValue<T>(field: Field<T>) -> T where T: SQLFieldValue {
        defer {
            referenceCount += 1
        }
        addFieldReference(field: field)
        if let row = row {
            return T.read(column: referenceCount, row: row)
        }
        else {
            return T.defaultValue
        }
    }
    
    func setValue<T>(field: Field<T>, value: T) where T: SQLFieldValue {
        defer {
            assignmentCount += 1
        }
        addFieldAssignment(field: field, value: value)
        if let statement = statement {
            try! value.bind(context: statement)
        }
    }
    
//    subscript<T>(field: Field<T>) -> T where T : SQLFieldValue {
//        addFieldReference(field: field)
//        return T.defaultValue
//    }
    
//    func readValue<Value>(column: Int, field: Field<Value>) -> Value where Value: SQLFieldValue {
//        if let row = row {
//            return Value.read(column: column, row: row)
//        }
//        else {
//            addFieldReference(field: field)
//            return Value.defaultValue
//        }
//    }
}


//class SQLReadContext<Output>: SQLWriter {
//    
//    typealias Reader = () -> Output
//
//    var reader: Reader!
//    
//    func read(row: SQLRowProtocol) -> Output {
//        self.row = row
//        return reader()
//    }
//}


//protocol SQLRow {
//    func field<V>(_ field: inout Field<V>) -> V where V: SQLFieldValue
//    func field<T>(_ field: FieldReference<T, Bool>) -> Bool where T: Table
//    func field<T>(_ field: FieldReference<T, Int>) -> Int where T: Table
//    func field<T>(_ field: FieldReference<T, Double>) -> Double where T: Table
//    func field<T>(_ field: FieldReference<T, String>) -> String where T: Table
//    func field<T>(_ field: FieldReference<T, URL>) -> URL where T: Table
//    func field<T>(_ field: FieldReference<T, Date>) -> Date where T: Table
//    func field<T>(_ field: FieldReference<T, Data>) -> Data where T: Table
//}


//class DefinitionSQLRow {
//
//    var fields = [FieldReferenceProtocol]()
//
//    var hashKey: HashKey {
//        ListHashKey(
//            separator: ",",
//            values: fields.map { field in
//                field.hashKey
//            }
//        )
//    }
//
//    func field<V>(_ field: Field<V>) where V: SQLFieldValue {
//        field.setColumn(fields.count)
//        fields.append(field)
//    }
//
//    func token() -> SQLToken {
//        CompositeSQLToken(
//            separator: ", ",
//            tokens: fields.map { field in
//                QualifiedIdentifierSQLToken(value: field.qualifiedName)
//            }
//        )
//    }
//}


//struct ResultSQLRow {
//
//    let row: SQLRowProtocol
//
//    func field<T, V>(_ field: FieldReference<T, V>) -> V where T : Table, V : SQLFieldValue {
////        row.readInt(column: field.column) == 0 ? false : true
//        field.readValue(row: row)
//    }

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

//}


typealias ExpressionBuilder = () -> SQLExpression


protocol SQLExpression: SQLBuilder {
}

func &&(lhs: SQLExpression, rhs: SQLExpression) -> SQLExpression {
    return BinaryExpression(operator: .and, lhs: { lhs }, rhs: { rhs })
}


public class AnyLiteral: SQLExpression {

    func prepare() {
        
    }
    
    func hashKey() -> HashKey {
        SymbolHashKey.variable
    }

    func sql() -> SQLToken {
        VariableSQLToken()
    }
    
    func bind() throws {
        fatalError("not implemented")
    }
}


final public class Literal<T>: AnyLiteral where T: SQLFieldValue {
    fileprivate let value: T

    public init(_ value: T) {
        self.value = value
    }
    
    override func bind() throws {
//        try value.bind()
    }

    override func sql() -> SQLToken {
        VariableSQLToken()
    }
}



final class BinaryExpression: SQLExpression {
    
    enum Operator: SQLBuilder {
        case equal
        case and
        case or

        func prepare() {
            
        }
        
        func hashKey() -> HashKey {
            switch self {
            case .equal:
                return SymbolHashKey.equality
            case .and:
                return SymbolHashKey.and
            case .or:
                return SymbolHashKey.or
            }
        }
        
        func sql() -> SQLToken {
            switch self {
            case .equal:
                return KeywordSQLToken(value: "=")
            case .and:
                return KeywordSQLToken(value: "AND")
            case .or:
                return KeywordSQLToken(value: "OR")
            }
        }

        func bind() throws {

        }
    }
    
    private lazy var lhs: SQLExpression = {
        lhsBuilder()
    }()
    
    private lazy var rhs: SQLExpression = {
        rhsBuilder()
    }()
    
    let `operator`: Operator
    let lhsBuilder: ExpressionBuilder
    let rhsBuilder: ExpressionBuilder
    
    init(operator: Operator, lhs: @escaping ExpressionBuilder, rhs: @escaping ExpressionBuilder) {
        self.operator = `operator`
        self.lhsBuilder = lhs
        self.rhsBuilder = rhs
    }
    
    func prepare() {
        
    }

    func hashKey() -> HashKey {
        CompositeHashKey(
            lhs.hashKey(),
            `operator`.hashKey(),
            rhs.hashKey()
        )
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                lhs.sql(),
                `operator`.sql(),
                rhs.sql()
            ]
        )
    }
    
    func bind() throws {

    }
}


#warning("TODO: Use strict typing for aliases")
//struct TableAlias {
//    let alias: Int
//
//    init(_ alias: Int) {
//        self.alias = alias
//    }
//
//    var identifier: SQLIdentifier {
//        SQLIdentifier(stringLiteral: "t\(alias)")
//    }
//}


public struct SQLIdentifier: Hashable, ExpressibleByStringLiteral {
    
    let value: String
    
    init(table: Int) {
        self.init(stringLiteral: "t\(table)")
    }
    
    public init(stringLiteral value: String) {
        self.value = value
    }
}


struct SQLQualifiedFieldIdentifier: SQLExpression, Hashable {
    
    let table: SQLIdentifier
    let field: SQLIdentifier

    init(table: SQLIdentifier, field: SQLIdentifier) {
        self.table = table
        self.field = field
    }
    
    func prepare() {
        
    }

    func hashKey() -> HashKey {
        QualifiedIdentifierHashKey(table, field)
    }

    func sql() -> SQLToken {
        QualifiedIdentifierSQLToken(value: self)
    }

    func bind() throws {

    }
    
    func hash(into hasher: inout Hasher) {
        table.hash(into: &hasher)
        field.hash(into: &hasher)
    }
    
    static func ==(lhs: SQLQualifiedFieldIdentifier, rhs: SQLQualifiedFieldIdentifier) -> Bool {
        lhs.table == rhs.table && lhs.field == rhs.field
    }
}

