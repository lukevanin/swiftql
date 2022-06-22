import Foundation
import Combine


//MARK: Field


protocol FieldContainerProtocol {
    func getValue<V>(field: Field<V>) -> V where V: SQLFieldValue
    func setValue<V>(field: Field<V>, value: V) where V: SQLFieldValue
}


protocol FieldProtocol {
    var column: Int { get set }
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
    
    func sql() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                QualifiedIdentifierSQLToken(value: field),
                order.sql()
            ]
        )
    }
    
    func bind(statement: PreparedStatementContext) throws {

    }
    
    func setContext(_ context: SQLWriter) {
        
    }
}


public class AnyField {
    
    var ascending: FieldOrder {
        FieldOrder(field: qualifiedName, order: .ascending)
    }
    
    var descending: FieldOrder {
        FieldOrder(field: qualifiedName, order: .descending)
    }
    
    let hashKey: HashKey

    private var column: Int! {
        willSet {
            precondition(column == nil, "Column already defined")
        }
    }
    
    lazy var qualifiedName: SQLQualifiedFieldIdentifier = SQLQualifiedFieldIdentifier(
        table: table,
        field: name
    )
    private(set) var table: SQLIdentifier!
    let name: SQLIdentifier

    init(name: String, hashKey: HashKey) {
        self.name = SQLIdentifier(stringLiteral: name)
        self.hashKey = hashKey
    }

    func didAdd(to table: TableSchema) {
        self.table = table._alias
    }

    func sqlColumnDefinition() -> SQLToken {
        fatalError("not implemented")
    }
}


@propertyWrapper public final class Field<Value>: AnyField where Value: SQLFieldValue {
    
    public var projectedValue: Field {
        return self
    }

    @available(*, unavailable,
        message: "This @propertyWrapper can only be applied to classes"
    )
    public var wrappedValue: Value {
        get {
            fatalError()
        }
        set {
            fatalError()
        }
    }
    
    public init(wrappedValue: Value = Value.defaultValue, name: String) {
        super.init(name: name, hashKey: Value.hashKey)
    }
    
    override func sqlColumnDefinition() -> SQLToken {
        CompositeSQLToken(
            separator: " ",
            tokens: [
                IdentifierSQLToken(value: name),
                Value.sqlDefinition
            ]
        )
    }

    public static subscript<T>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Field>
    ) -> Value {
        get {
            let container = instance as! TableSchema
            let field = instance[keyPath: storageKeyPath]
            return container.getValue(field: field)
        }
        set {
            let container = instance as! TableSchema
            let field = instance[keyPath: storageKeyPath]
            container.setValue(field: field, value: newValue)
        }
    }
}


func ==<Value>(lhs: Field<Value>, rhs: Field<Value>) -> SQLExpression where Value: SQLFieldValue {
    BinaryExpression(operator: .equal, lhs: { lhs.qualifiedName }, rhs: { rhs.qualifiedName })
}


func ==<Value>(lhs: Field<Value>, rhs: Value) -> SQLExpression where Value: SQLFieldValue {
    BinaryExpression(operator: .equal, lhs: { lhs.qualifiedName }, rhs: { Literal(rhs) })
}



// MARK: Table


open class TableSchema {
    
    @Field(name: "id") public var id: PrimaryKey = .defaultValue
    
    var hashKey: HashKey {
        CompositeHashKey(
            IdentifierHashKey(_alias),
            ListHashKey(
                separator: ",",
                values: fields.map { field in
                    field.hashKey
                }
            )
        )
    }

    let _alias: SQLIdentifier
    let _name: SQLIdentifier
    private(set) var _allFields: [AnyField] = []

    internal var row: SQLRowProtocol?
    
    private var fields = [AnyField]()
    private var columns = [SQLIdentifier: Int]()

    private let context: SQLWriter

    required public init(name: SQLIdentifier, alias: SQLIdentifier, context: SQLWriter) {
        self._name = name
        self._alias = alias
        self.context = context
        let m = Mirror(reflecting: self)
        let customFields = m.children.compactMap { child in
            child.value as? AnyField
        }
        let fields = [$id].appending(contentsOf: customFields)
        fields.forEach { field in
            field.didAdd(to: self)
        }
        self._allFields = fields
    }
    
    func getValue<V>(field: Field<V>) -> V where V : SQLFieldValue {
        var column: Int! = columns[field.name]
        if column == nil {
            column = fields.count
            fields.append(field)
            columns[field.name] = column
//            let identifier = SQLQualifiedFieldIdentifier(
//                table: _alias,
//                field: field.name
//            )
            context.addFieldReference(field: field)
        }
        if let row = row {
            return V.read(column: column, row: row)
        }
        else {
            return V.defaultValue
        }
    }
    
    func setValue<V>(field: Field<V>, value: V) where V : SQLFieldValue {
        context.addFieldAssignment(field: field)
    }
    
    func sqlFields() -> SQLToken {
        CompositeSQLToken(
            separator: ", ",
            tokens: fields.map { field in
                field.sqlColumnDefinition()
            }
        )
    }
}

//open class TableSchema<T>: AnyTableSchema where T: Table {
//
//}
//
//extension TableSchema {
//    subscript<Value>(field keyPath: KeyPath<T, Value>) -> FieldSchema<T, Value> where Value: SQLFieldValue {
//        fieldsByKeyPath[keyPath] as! FieldSchema<T, Value>
//    }
//}


public protocol Table: Identifiable, Equatable, Codable {
    associatedtype Schema: TableSchema
    var id: PrimaryKey { get }
    init(_ schema: Schema)
    func _values() -> [AnyLiteral]
}

extension Table {
    static var _name: SQLIdentifier {
        SQLIdentifier(stringLiteral: String(describing: self).lowercased())
    }
}


open class DatabaseSchema {
    
}



//@propertyWrapper final class SchemaFactory<S, T> where S: TableSchema<T>, T: Table {
//
//    @available(*, unavailable,
//        message: "This propertyWrapper can only be applied to classes"
//    )
//    var wrappedValue: S? {
//        get { fatalError() }
//        set { fatalError() }
//    }
//
//    init(wrappedValue: S? = nil) {
//
//    }
//
//    static subscript<I>(
//        _enclosingInstance instance: I,
//        wrapped wrappedKeyPath: ReferenceWritableKeyPath<I, S>,
//        storage storageKeyPath: ReferenceWritableKeyPath<I, SchemaFactory>
//    ) -> S {
//        get {
//            let database = instance as! DatabaseSchema
//            return database.schema(table: S.self)
//        }
//    }
//
//}


///
/// Refers to a specific instance of a table used in a query.
///
//struct TableReference<T> where T: Table {
//
//    let name: SQLIdentifier
//    let alias: SQLIdentifier
//
//    init(name: SQLIdentifier, alias: SQLIdentifier) {
//        self.name = name
//        self.alias = alias
//    }
//
//    func fields() -> [TableFieldReference<T>] {
//        // TODO: Pre-compute field hash keys
//        T.schema.fields.map { field in
//            TableFieldReference(table: self, field: field)
//        }
//    }
//
//    subscript<F>(field keyPath: KeyPath<T, F>) -> FieldReference<T, F> where F: SQLFieldValue {
//        FieldReference(table: self, field: T.schema[field: keyPath])
//    }
//
//    func values(entity: T) -> [SQLIdentifier : SQLBuilder] {
//        var output = [SQLIdentifier : SQLBuilder]()
//        for field in fields() {
//            output[field.qualifiedName.field] = field.valueExpression(entity: entity)
//        }
//        return output
//    }
//
//    func read(row: SQLRow) -> T {
//        var entity = T.defaults
//        for field in fields() {
//            field.read(row: row, entity: &entity)
//        }
//        return entity
//    }
//}

//extension TableReference {
//
//    init(table: T.Type, alias: SQLIdentifier) {
//        self.init(name: T.tableName, alias: alias)
//    }
//}


//protocol FieldReferenceProtocol {
//    var qualifiedName: SQLQualifiedFieldIdentifier { get }
//    var hashKey: HashKey { get }
//    func sqlColumnDefinition() -> SQLToken
//}


//class TableFieldReference<T>: FieldReferenceProtocol where T: Table {
//
//    let qualifiedName: SQLQualifiedFieldIdentifier
//    let hashKey: HashKey
//    let table: TableReference<T>
//    let field: AnyFieldSchema<T>
//
//    init(table: TableReference<T>, field: AnyFieldSchema<T>) {
//        self.qualifiedName = SQLQualifiedFieldIdentifier(
//            table: table.alias,
//            field: field.identifier
//        )
//        self.hashKey = qualifiedName.hashKey
//        self.table = table
//        self.field = field
//    }
//
//    func sqlColumnDefinition() -> SQLToken {
//        CompositeSQLToken(
//            separator: " ",
//            tokens: [
//                QualifiedIdentifierSQLToken(value: qualifiedName),
//                KeywordSQLToken(value: "AS"),
//                field.sqlDefinition
//            ]
//        )
//    }
//
//    func read(row: SQLRowProtocol, entity: inout T) {
//        fatalError("not implemented")
//    }
//
//    func valueExpression(entity: T) -> SQLBuilder {
//        fatalError("not implemented")
//    }
//}


//class FieldReference<T, V>: TableFieldReference<T> where T: Table, V: SQLFieldValue {
//
//    let typedField: FieldSchema<T, V>
//
//    private var column: Int?
//
//    init(table: TableReference<T>, field: FieldSchema<T, V>) {
//        self.typedField = field
//        super.init(table: table, field: field)
//    }
//
//    override func read(row: SQLRowProtocol, entity: inout T) {
//        let value = row.field(self)
//        entity[keyPath: typedField.typedKeyPath] = value
//    }
//
//    func setColumn(_ column: Int) {
//        self.column = column
//    }
//
//    func readValue(row: SQLRowProtocol) -> V {
//        V.read(column: column!, row: row)
//    }
//
//    func bind(entity: T, context: PreparedStatementContext) throws {
//        let value = entity[keyPath: typedField.typedKeyPath]
//        try value.bind(context: context)
//    }
//
//    override func valueExpression(entity: T) -> SQLBuilder {
//        return Literal(entity[keyPath: typedField.typedKeyPath])
//    }
//}

//extension FieldReference {
//
//    static func ==(lhs: FieldReference, rhs: FieldReference) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: rhs.qualifiedName)
//    }
//}

//extension FieldReference {
//    static func ==(lhs: FieldReference, rhs: V) -> SQLExpression {
//        BinaryExpression(operator: .equal, lhs: lhs.qualifiedName, rhs: Literal(rhs))
//    }
//}

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
