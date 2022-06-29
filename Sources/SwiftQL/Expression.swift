import Foundation


protocol SQLBuilder {
    func bind() -> Void
    func hashKey() -> HashKey
    func sql() -> SQLToken
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
    
    func bind() {
        for builder in builders {
            builder.bind()
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
}


struct AnySQLBuilder<Output>: SQLBuilder {
    
    typealias Reader = () -> Output

    private let builders: [SQLBuilder]
    private let reader: Reader

    init<T>(from: From<Output, T>) where T: Table {
        self.builders = [from]
        self.reader = from.read
    }

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
    
    func bind() {
        for builder in builders {
            builder.bind()
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

    func read() -> Output {
        reader()
    }
}


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

    var readContext: ReadProtocol?
    var bindContext: BindProtocol?

    private var tableCount = 0
    private var referenceCount = 0
    private var assignmentCount = 0

    private(set) var fieldReferenceHashKeys = [HashKey]()
    private(set) var fieldAssignmentHashKeys = [HashKey]()
    
    private var fieldReferenceIdentifiers = [SQLQualifiedFieldIdentifier]()
    private var fieldAssignmentIdentifiers = [SQLQualifiedFieldIdentifier]()
    
    init(readContext: ReadProtocol? = nil, bindContext: BindProtocol? = nil) {
        self.readContext = readContext
        self.bindContext = bindContext
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
        if let readContext = readContext {
            return try! T.read(context: readContext)
        }
        else {
            addFieldReference(field: field)
            return T.defaultValue
        }
    }
    
    func setValue<T>(field: Field<T>, value: T) where T: SQLFieldValue {
        if let bindContext = bindContext {
            try! value.bind(context: bindContext)
        }
        else {
            addFieldAssignment(field: field, value: value)
        }
    }
}


typealias ExpressionBuilder = () -> SQLExpression


protocol SQLExpression: SQLBuilder {
}

func &&(lhs: SQLExpression, rhs: SQLExpression) -> SQLExpression {
    return BinaryExpression(operator: .and, lhs: { lhs }, rhs: { rhs })
}


public class AnyLiteral: SQLExpression {
    
    func bind() {

    }

    func hashKey() -> HashKey {
        SymbolHashKey.variable
    }

    func sql() -> SQLToken {
        VariableSQLToken()
    }
}


final public class Literal<T>: AnyLiteral where T: SQLFieldValue {

    fileprivate let value: T

    public init(_ value: T) {
        self.value = value
    }
    
    override func bind() {
        
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
        
        func bind() {
            
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
    
    func bind() {
        
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
    
    func bind() {
        
    }
    
    func hashKey() -> HashKey {
        QualifiedIdentifierHashKey(table, field)
    }

    func sql() -> SQLToken {
        QualifiedIdentifierSQLToken(value: self)
    }

    func hash(into hasher: inout Hasher) {
        table.hash(into: &hasher)
        field.hash(into: &hasher)
    }
    
    static func ==(lhs: SQLQualifiedFieldIdentifier, rhs: SQLQualifiedFieldIdentifier) -> Bool {
        lhs.table == rhs.table && lhs.field == rhs.field
    }
}

