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
    
    let field: SQLQualifiedFieldIdentifier
    let order: SQLOrder
    
    init(field: SQLQualifiedFieldIdentifier, order: SQLOrder) {
        self.field = field
        self.order = order
    }

    func bind() {
    }

    func hashKey() -> HashKey {
        CompositeHashKey(
            field.hashKey(),
            order.hashKey()
        )
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
}


public class AnyField {
    
    var ascending: FieldOrder {
        FieldOrder(field: qualifiedName, order: .ascending)
    }
    
    var descending: FieldOrder {
        FieldOrder(field: qualifiedName, order: .descending)
    }
    
    let hashKey: HashKey

    private(set) var column: Int!
    
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
    
    func setColumn(_ column: Int) {
        precondition(self.column == nil, "Column already defined")
        self.column = column
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
    let _context: SQLWriter

    private(set) var _allFields: [AnyField] = []

    private var fields = [AnyField]()
    
    required public init(name: SQLIdentifier, alias: SQLIdentifier, context: SQLWriter) {
        self._name = name
        self._alias = alias
        self._context = context
        #warning("TODO: Auto-generate fields")
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
        _context.getValue(field: field)
    }
    
    func setValue<V>(field: Field<V>, value: V) where V : SQLFieldValue {
        _context.setValue(field: field, value: value)
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

open class TableSchemaOf<T>: TableSchema where T: Table {

}


public protocol Table: Identifiable, Equatable, Codable {
    associatedtype Schema: TableSchema
    var id: PrimaryKey { get }
    init(schema: Schema)
    func _values() -> [AnyLiteral]
    func _bind(schema: Schema)
}

extension Table {
    static var _name: SQLIdentifier {
        SQLIdentifier(stringLiteral: String(describing: self).lowercased())
    }
}
