import Foundation
import Combine


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



@propertyWrapper struct Field<T>: Codable, Equatable where T: SQLFieldValue {
    
    let name: String
    let wrappedValue: T
    
    init(_ wrappedValue: T? = nil, name: String) {
        self.wrappedValue = wrappedValue ?? T.defaultValue
        self.name = name
    }
}


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
