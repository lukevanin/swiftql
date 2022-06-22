import Foundation



protocol SQLBuilder {
    var hashKey: HashKey { get }
    func sql() -> SQLToken
    func bind(statement: PreparedStatementContext) throws
    func setContext(_ context: SQLWriter)
}


protocol SQLStatement: SQLBuilder {
    
}


protocol SQLReader {
    associatedtype Entity
    func read(row: SQLRowProtocol) -> Entity
}


typealias SQLReadStatement = SQLStatement & SQLReader


struct AnySQLBuilder<Output>: SQLBuilder, SQLReader {
    
    typealias Reader = (SQLRowProtocol) -> Output

    var hashKey: HashKey {
        builder.hashKey
    }
    
    private let builder: SQLBuilder
    private let reader: Reader

    init<T>(_ c: Create<T>) where T: Table {
        self.builder = c
        self.reader = { row in
            fatalError("reader not implemented")
        }
    }

    init<T>(_ i: Insert<T>) where T: Table {
        self.builder = i
        self.reader = { row in
            #warning("TODO: Returns number of rows inserted")
            fatalError("reader not implemented")
        }
    }
    
    init<T>(_ u: Update<T>) where T: Table {
        self.builder = u // SQLSequenceBuilder(u, w)
        self.reader = { row in
            #warning("TODO: Returns number of rows updated")
            fatalError("reader not implemented")
        }
    }

    init<T>(_ s: Select<Output, T>, _ builders: SQLBuilder...) where T: Table {
        self.builder = SQLSequenceBuilder([s] + builders)
        self.reader = s.read
    }
    
    init<S>(_ builder: S) where S: SQLReadStatement, S.Entity == Output {
        self.builder = builder
        self.reader = builder.read
    }
    
    func sql() -> SQLToken {
        builder.sql()
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try builder.bind(statement: statement)
    }

    func read(row: SQLRowProtocol) -> Output {
        reader(row)
    }
    
    func setContext(_ context: SQLWriter) {
        builder.setContext(context)
    }
}


class SQLSequenceBuilder: SQLBuilder {

    lazy var hashKey: HashKey = {
        ListHashKey(separator: separator, values: builders.map { $0.hashKey })
    }()
    
    let separator: String
    let builders: [SQLBuilder]

    convenience init(separator: String = " ", _ builders: SQLBuilder...) {
        self.init(separator: separator, builders)
    }
    
    init(separator: String = " ", _ builders: [SQLBuilder]) {
        self.separator = separator
        self.builders = builders
    }

    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: separator,
            tokens: builders.map { $0.sql() }
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {
        try builders.forEach { builder in
            try builder.bind(statement: statement)
        }
    }
    
    func setContext(_ context: SQLWriter) {
        builders.forEach { builder in
            builder.setContext(context)
        }
    }
}


open class SQLWriter {
    
//    var hashKey: HashKey {
//        CompositeHashKey(
//            SymbolHashKey.select,
//            ListHashKey(
//                separator: ",",
//                values: fieldReferenceHashKeys
//            ),
//            SymbolHashKey.set,
//            ListHashKey(
//                separator: ",",
//                values: fieldAssignmentHashKeys
//            )
//        )
//    }
    
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

    var preparedStatement: PreparedStatementContext?

    private var tableCount = 0

    private(set) var fieldReferenceHashKeys = [HashKey]()
    private(set) var fieldAssignmentHashKeys = [HashKey]()
    
    private var fieldReferenceIdentifiers = [SQLQualifiedFieldIdentifier]()
    private var fieldAssignmentIdentifiers = [SQLQualifiedFieldIdentifier]()

    func addFieldReference(field: AnyField) {
        fieldReferenceHashKeys.append(field.hashKey)
        fieldReferenceIdentifiers.append(field.qualifiedName)
    }

    func addFieldAssignment(field: AnyField) {
        fieldAssignmentHashKeys.append(field.hashKey)
        fieldAssignmentIdentifiers.append(field.qualifiedName)
    }

    func schema<T>(table: T.Type) -> T.Schema where T: Table {
        defer {
            tableCount += 1
        }
        let alias = SQLIdentifier(table: tableCount)
        return T.Schema(name: T._name, alias: alias, context: self)
    }

    
//    private var currentAlias: Int = 0
//    private var currentFieldAlias: Int = 0
//    private var variableCount: Int = 0

//    func nextFieldAlias() -> SQLIdentifier {
//        defer {
//            currentFieldAlias += 1
//        }
//        return SQLIdentifier(stringLiteral: "f\(currentFieldAlias)")
//    }
    
//    func nextAlias() -> SQLIdentifier {
//        defer {
//            currentAlias += 1
//        }
//        return SQLIdentifier(stringLiteral: "t\(currentAlias)")
//    }
    
//    func nextVariable() -> SQLVariable {
//        defer {
//            variableCount += 1
//        }
//        return SQLVariable(index: variableCount + 1)
//    }
}


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
    
    let hashKey: HashKey = SymbolHashKey.variable

    func sql() -> SQLToken {
        return VariableSQLToken()
    }
    
    func bind(statement: PreparedStatementContext) throws {
        fatalError("not implemented")
    }
    
    func setContext(_ context: SQLWriter) {
        fatalError("not implemented")
    }
}


final public class Literal<T>: AnyLiteral where T: SQLFieldValue {
    fileprivate let value: T

    public init(_ value: T) {
        self.value = value
    }
    
    override func bind(statement: PreparedStatementContext) throws {
        try value.bind(context: statement)
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
        
        func sql() -> SQLToken {
            switch self {
            case .equal:
                return KeywordSQLToken(value: "==")
            case .and:
                return KeywordSQLToken(value: "AND")
            case .or:
                return KeywordSQLToken(value: "OR")
            }
        }
        
        func bind(statement: PreparedStatementContext) throws {

        }
        
        func setContext(_ context: SQLWriter) {
        
        }
    }
    
    lazy var hashKey: HashKey = {
        CompositeHashKey(lhs.hashKey, `operator`.hashKey, rhs.hashKey)
    }()
    
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
    
    func bind(statement: PreparedStatementContext) throws {

    }
    
    func setContext(_ context: SQLWriter) {
        
    }
}


#warning("TODO: Use strict typeing for aliases")
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


struct SQLQualifiedFieldIdentifier: SQLExpression {
    
    let hashKey: HashKey
    let table: SQLIdentifier
    let field: SQLIdentifier

    init(table: SQLIdentifier, field: SQLIdentifier) {
        self.table = table
        self.field = field
        self.hashKey = QualifiedIdentifierHashKey(table, field)
    }
    
    func sql() -> SQLToken {
        QualifiedIdentifierSQLToken(value: self)
    }
    
    func bind(statement: PreparedStatementContext) throws {

    }
    
    func setContext(_ context: SQLWriter) {

    }
}

