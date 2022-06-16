import Foundation



protocol SQLBuilder {
    var hashKey: HashKey { get }
    func sql(context: SQLWriter) -> SQLToken
    func bind(context: PreparedStatementContext) throws
}


protocol SQLStatement: SQLBuilder {
    
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


protocol SQLExpression: SQLBuilder {
}

func &&(lhs: SQLExpression, rhs: SQLExpression) -> SQLExpression {
    return BinaryExpression(operator: .and, lhs: lhs, rhs: rhs)
}


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

