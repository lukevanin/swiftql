import Foundation


/// Failures while positioning, encoding, or decoding an operational static
/// row layout.
public enum XLStaticRowLayoutError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case fieldNotPositioned(identity: XLQuerySlotIdentity)
    case unsupportedSQLiteStorage(
        identity: XLQuerySlotIdentity,
        storageType: String
    )
    case expressionStorageTypeMismatch(
        identity: XLQuerySlotIdentity,
        expectedStorageType: String,
        expressionType: String
    )
    case valueCountMismatch(expected: Int, actual: Int)
    case nullForRequiredField(field: XLStaticRowField)
    case storageMismatch(
        field: XLStaticRowField,
        actual: XLValueStorageIdentifier
    )
    case descriptorResultsMismatch(
        expected: XLStaticQueryResultMetadata,
        actual: XLStaticQueryResultMetadata
    )

    public var errorDescription: String? {
        switch self {
        case .fieldNotPositioned(let identity):
            return "Static result slot \(identity) must be positioned by its generated row-layout factory before use."
        case .unsupportedSQLiteStorage(let identity, let storageType):
            return "Static result slot \(identity) uses storage carrier \(storageType), whose SQLite storage class is not statically known."
        case .expressionStorageTypeMismatch(
            let identity,
            let expectedStorageType,
            let expressionType
        ):
            return "Static result slot \(identity) requires an expression typed as storage carrier \(expectedStorageType), but received \(expressionType)."
        case .valueCountMismatch(let expected, let actual):
            return "Static row layout expected \(expected) values, but received \(actual)."
        case .nullForRequiredField(let field):
            return "Static row property/result slot '\(field.alias)' (\(field.result.identity), codec \(Self.codecDescription(field))) received SQL NULL but is required."
        case .storageMismatch(let field, let actual):
            return "Static row property/result slot '\(field.alias)' (\(field.result.identity), codec \(Self.codecDescription(field))) requires storage \(field.result.storageIdentifier), not \(actual)."
        case .descriptorResultsMismatch(let expected, let actual):
            return Self.descriptorResultsMismatchDescription(
                expected: expected,
                actual: actual
            )
        }
    }

    private static func codecDescription(_ field: XLStaticRowField) -> String {
        field.result.codecIdentity?.key.description ?? "intrinsic/none"
    }

    private static func descriptorResultsMismatchDescription(
        expected: XLStaticQueryResultMetadata,
        actual: XLStaticQueryResultMetadata
    ) -> String {
        let sharedCount = min(expected.slots.count, actual.slots.count)
        for position in 0..<sharedCount {
            let expectedSlot = expected.slots[position]
            let actualSlot = actual.slots[position]
            guard expectedSlot != actualSlot else {
                continue
            }
            return descriptorResultsMismatchDescription(
                position: position,
                expected: expectedSlot,
                actual: actualSlot,
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }

        if expected.slots.count > sharedCount {
            return descriptorResultsMismatchDescription(
                position: sharedCount,
                expected: expected.slots[sharedCount],
                actual: nil,
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }
        if actual.slots.count > sharedCount {
            return descriptorResultsMismatchDescription(
                position: sharedCount,
                expected: nil,
                actual: actual.slots[sharedCount],
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }

        return "Typed static query result metadata does not match its row layout, but no differing result slot could be identified."
    }

    private static func descriptorResultsMismatchDescription(
        position: Int,
        expected: XLStaticQueryResultSlot?,
        actual: XLStaticQueryResultSlot?,
        expectedCount: Int,
        actualCount: Int
    ) -> String {
        [
            "Typed static query result metadata does not match its row layout.",
            "First differing result position \(position):",
            "expected descriptor slot \(slotDescription(expected));",
            "actual layout slot \(slotDescription(actual)).",
            "Result counts: expected \(expectedCount), actual \(actualCount).",
        ].joined(separator: " ")
    }

    private static func slotDescription(
        _ slot: XLStaticQueryResultSlot?
    ) -> String {
        guard let slot else {
            return "<missing>"
        }
        let codec: String
        if let identity = slot.codecIdentity {
            codec = "\(identity.key.description) { " + [
                "value type: \(identity.valueTypeIdentifier)",
                "dialect: \(identity.dialectIdentifier)",
                "storage: \(identity.storageIdentifier)",
            ].joined(separator: ", ") + " }"
        }
        else {
            codec = "intrinsic/none"
        }
        return "{ " + [
            "index: \(slot.index)",
            "identity: \(slot.identity)",
            "type: \(slot.valueTypeName) [\(slot.valueTypeIdentifier)]",
            "nullability: \(slot.nullability.rawValue)",
            "codec: \(codec)",
            "storage: \(slot.storageIdentifier)",
            "coding context: \(slot.codingContext.site.rawValue):\(slot.codingContext.path)",
        ].joined(separator: ", ") + " }"
    }
}


/// One typed projected expression and its immutable result-codec behavior.
///
/// A field created by a value-coding configuration is value-free. It retains
/// an expression, stable descriptor metadata, and stateless conversion
/// closures, but never a model instance, database, SQL reader, or invocation
/// value. Generated row-layout factories assign its declaration position and
/// SQL alias.
public protocol XLStaticSelectFieldProtocol<FieldValue, FieldDialect> {
    associatedtype FieldValue
    associatedtype FieldDialect: XLValueCodingDialect

    func positioned(at index: Int, alias: String) -> Self
    func erased() throws -> XLAnyStaticSelectField<FieldDialect>
    func read(from reader: XLRowReader) throws -> FieldValue
    func encode(_ value: FieldValue) throws -> FieldDialect.Value
}


/// One storage-typed projected expression and its immutable result-codec
/// behavior. The concrete `Storage` parameter remains available to callers
/// even though generated row-layout factories accept the protocol abstraction.
public struct XLStaticSelectField<Value, Storage, Dialect>
where Storage: XLLiteral, Dialect: XLValueCodingDialect {

    /// The selected SQL expression retyped to this field's intrinsic storage
    /// carrier. Callers can pass it directly to storage-inferred APIs such as
    /// `queryCapture(_:matching:identifiedBy:selection:)`.
    public let expression: any XLExpression<Storage>

    /// The durable storage contract shared by result and parameter metadata.
    public let storageIdentifier: XLValueStorageIdentifier

    /// The codec selector retained when this field was declared.
    public let codecSelection: XLQueryCodecSelection

    /// The exact codec selected for this field, or `nil` for intrinsic fields.
    public let selectedCodecIdentity: XLValueCodecIdentity?

    private let identity: XLQuerySlotIdentity
    private let valueTypeIdentifier: XLValueTypeIdentifier
    private let valueTypeName: String
    private let nullability: XLParameterNullability
    private let codingContext: XLValueCodingContext
    private let dialect: Dialect
    private let decodeValue: (Dialect.Value) throws -> Value
    private let encodeValue: (Value) throws -> Dialect.Value
    private let field: XLStaticRowField?

    init(
        expression: any XLExpression<Storage>,
        identity: XLQuerySlotIdentity,
        valueTypeIdentifier: XLValueTypeIdentifier,
        valueTypeName: String,
        nullability: XLParameterNullability,
        codecIdentity: XLValueCodecIdentity?,
        codecSelection: XLQueryCodecSelection,
        storageIdentifier: XLValueStorageIdentifier,
        codingContext: XLValueCodingContext,
        dialect: Dialect,
        decode: @escaping (Dialect.Value) throws -> Value,
        encode: @escaping (Value) throws -> Dialect.Value,
        field: XLStaticRowField? = nil
    ) {
        self.expression = expression
        self.identity = identity
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.selectedCodecIdentity = codecIdentity
        self.codecSelection = codecSelection
        self.storageIdentifier = storageIdentifier
        self.codingContext = codingContext
        self.dialect = dialect
        self.decodeValue = decode
        self.encodeValue = encode
        self.field = field
    }

    /// Assigns the generated declaration position and SQL result alias.
    public func positioned(at index: Int, alias: String) -> Self {
        let result = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(index),
            identity: identity,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: selectedCodecIdentity,
            storageIdentifier: storageIdentifier,
            codingContext: codingContext
        )
        return Self(
            expression: expression,
            identity: identity,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: selectedCodecIdentity,
            codecSelection: codecSelection,
            storageIdentifier: storageIdentifier,
            codingContext: codingContext,
            dialect: dialect,
            decode: decodeValue,
            encode: encodeValue,
            field: XLStaticRowField(alias: alias, result: result)
        )
    }

    /// Type-erases this positioned field for storage in a heterogeneous row
    /// layout.
    public func erased() throws -> XLAnyStaticSelectField<Dialect> {
        guard let field else {
            throw XLStaticRowLayoutError.fieldNotPositioned(
                identity: identity
            )
        }
        return XLAnyStaticSelectField(
            expression: expression,
            metadata: field,
            validate: { value in
                try validate(value, field: field)
            }
        )
    }

    /// Decodes this field from its generated logical result index.
    public func read(from reader: XLRowReader) throws -> Value {
        guard let field else {
            throw XLStaticRowLayoutError.fieldNotPositioned(
                identity: identity
            )
        }
        let value = try reader.dialectValue(
            at: field.result.index.rawValue,
            using: dialect
        )
        try validate(value, field: field)
        return try decodeValue(value)
    }

    /// Encodes one property value with the field's selected codec.
    public func encode(_ value: Value) throws -> Dialect.Value {
        guard let field else {
            throw XLStaticRowLayoutError.fieldNotPositioned(
                identity: identity
            )
        }
        let encoded = try encodeValue(value)
        try validate(encoded, field: field)
        return encoded
    }

    private func validate(
        _ value: Dialect.Value,
        field: XLStaticRowField
    ) throws {
        if dialect.isNull(value) {
            guard field.result.nullability == .nullable else {
                throw XLStaticRowLayoutError.nullForRequiredField(field: field)
            }
            return
        }
        let actual = dialect.stableStorageIdentifier(for: value)
        guard actual == field.result.storageIdentifier else {
            throw XLStaticRowLayoutError.storageMismatch(
                field: field,
                actual: actual
            )
        }
    }
}


extension XLStaticSelectField: XLStaticSelectFieldProtocol {
    public typealias FieldValue = Value
    public typealias FieldDialect = Dialect
}


/// The expression-bearing, type-erased half of one static row field.
///
/// Its public metadata is driver-neutral. The retained expression is used only
/// for SQL rendering and introduces no GRDB dependency into descriptor APIs.
public struct XLAnyStaticSelectField<Dialect>
where Dialect: XLValueCodingDialect {
    public let metadata: XLStaticRowField
    fileprivate let expression: any XLEncodable
    fileprivate let validateValue: (Dialect.Value) throws -> Void

    fileprivate init(
        expression: any XLEncodable,
        metadata: XLStaticRowField,
        validate: @escaping (Dialect.Value) throws -> Void
    ) {
        self.expression = expression
        self.metadata = metadata
        self.validateValue = validate
    }
}


/// A row reader whose projection is available structurally without executing
/// its decoding closure.
public protocol XLStaticRowReadable<Row>: XLRowReadable, XLEncodable {
    associatedtype Row
    var metadata: XLStaticRowMetadata { get }
}


/// An operational typed row layout paired with driver-neutral structural
/// metadata.
///
/// Construction validates only immutable field metadata. The model
/// initializer in `decode` runs exclusively when a database row is decoded;
/// it is never called while building a `Select` or static query descriptor.
public struct XLStaticRowLayout<Row, Dialect>:
    XLStaticRowReadable
where Dialect: XLValueCodingDialect {

    public let metadata: XLStaticRowMetadata

    private let fields: [XLAnyStaticSelectField<Dialect>]
    private let decodeRow: (XLRowReader) throws -> Row
    private let encodeRow: (Row) throws -> [Dialect.Value]

    public init(
        fields: [XLAnyStaticSelectField<Dialect>],
        decode: @escaping (XLRowReader) throws -> Row,
        encode: @escaping (Row) throws -> [Dialect.Value]
    ) throws {
        self.metadata = try XLStaticRowMetadata(
            fields: fields.map(\.metadata)
        )
        self.fields = fields
        self.decodeRow = decode
        self.encodeRow = encode
    }

    public func makeSQL(context: inout XLBuilder) {
        context.list(separator: ", ") { list in
            for field in fields {
                list.listItem { builder in
                    builder.alias(
                        XLName(field.metadata.alias),
                        expression: { expressionBuilder in
                            if field.expression is any XLQueryStatement {
                                expressionBuilder.parenthesis(
                                    contents: field.expression.makeSQL
                                )
                            }
                            else {
                                field.expression.makeSQL(
                                    context: &expressionBuilder
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try decodeRow(reader)
    }

    /// Decodes one complete ordered row of dialect values.
    public func decode(_ values: [Dialect.Value]) throws -> Row {
        guard values.count == metadata.fields.count else {
            throw XLStaticRowLayoutError.valueCountMismatch(
                expected: metadata.fields.count,
                actual: values.count
            )
        }
        try validate(values)
        let reader = _XLStaticDialectValuesRowReader(
            values: values,
            dialect: Dialect.self
        )
        return try decodeRow(reader)
    }

    /// Encodes every property in declaration order using the exact codecs
    /// retained by this layout.
    public func encode(_ row: Row) throws -> [Dialect.Value] {
        let values = try encodeRow(row)
        guard values.count == metadata.fields.count else {
            throw XLStaticRowLayoutError.valueCountMismatch(
                expected: metadata.fields.count,
                actual: values.count
            )
        }
        try validate(values)
        return values
    }

    private func validate(_ values: [Dialect.Value]) throws {
        for (field, value) in zip(fields, values) {
            try field.validateValue(value)
        }
    }
}


/// A typed static descriptor whose operational row layout is proven to match
/// the structural result contract used by stable query identity.
///
/// This API is database-driver independent and contains no GRDB types.
public struct XLTypedStaticQueryDescriptor<Row, Dialect>
where Dialect: XLValueCodingDialect {
    public let descriptor: XLStaticQueryDescriptor
    public let layout: XLStaticRowLayout<Row, Dialect>

    public init(
        descriptor: XLStaticQueryDescriptor,
        layout: XLStaticRowLayout<Row, Dialect>
    ) throws {
        guard descriptor.results == layout.metadata.results else {
            throw XLStaticRowLayoutError.descriptorResultsMismatch(
                expected: descriptor.results,
                actual: layout.metadata.results
            )
        }
        self.descriptor = descriptor
        self.layout = layout
    }
}


extension XLValueCodingConfiguration {

    /// Creates a required contextual SQLite result field. `Storage` is a type
    /// witness for the selected SQL expression's intrinsic storage carrier;
    /// no value or `sqlDefault()` call is required.
    public func staticResultField<Value, Storage>(
        _ valueType: Value.Type,
        selecting expression: any XLEncodable,
        storedAs storageType: Storage.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: XLSQLiteDialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLStaticSelectField<Value, Storage, XLSQLiteDialect>
    where Storage: XLLiteral {
        let storage = try _xlStaticSQLiteStorage(
            storageType,
            identity: identity
        )
        let codingContext = context ?? XLValueCodingContext(
            site: .property,
            path: XLValueCodingPath(identity.path)
        )
        let codec = try resolvedCodec(
            for: valueType,
            using: dialect,
            context: codingContext,
            requiringStorage: storage,
            selection: selection
        )
        let storageExpression = try _xlStaticStorageExpression(
            expression,
            as: storageType,
            identity: identity
        )
        return XLStaticSelectField(
            expression: storageExpression,
            identity: identity,
            valueTypeIdentifier: codec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Value.self),
            nullability: .required,
            codecIdentity: codec.identity,
            codecSelection: selection,
            storageIdentifier: storage,
            codingContext: codingContext,
            dialect: dialect,
            decode: codec.decode,
            encode: codec.encode
        )
    }

    /// Creates a nullable contextual SQLite result field. Optionality belongs
    /// to the field contract; the same nonoptional codec is reused for present
    /// values while SQL `NULL` maps to and from `nil`.
    public func staticResultField<Value, Storage>(
        _ valueType: Value?.Type,
        selecting expression: any XLEncodable,
        storedAs storageType: Storage?.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: XLSQLiteDialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLStaticSelectField<Value?, Storage?, XLSQLiteDialect>
    where Storage: XLLiteral {
        let storage = try _xlStaticSQLiteStorage(
            Storage.self,
            identity: identity
        )
        let codingContext = context ?? XLValueCodingContext(
            site: .property,
            path: XLValueCodingPath(identity.path)
        )
        let codec = try resolvedCodec(
            for: Value.self,
            using: dialect,
            context: codingContext,
            requiringStorage: storage,
            selection: selection
        )
        let storageExpression = try _xlStaticStorageExpression(
            expression,
            as: storageType,
            identity: identity
        )
        return XLStaticSelectField(
            expression: storageExpression,
            identity: identity,
            valueTypeIdentifier: codec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Value?.self),
            nullability: .nullable,
            codecIdentity: codec.identity,
            codecSelection: selection,
            storageIdentifier: storage,
            codingContext: codingContext,
            dialect: dialect,
            decode: codec.decodeOptional,
            encode: codec.encodeOptional
        )
    }
}


extension XLStaticSelectField
where Dialect == XLSQLiteDialect, Value: XLLiteral, Storage == Value {

    /// Creates a codec-free field for an intrinsic v1 literal whose SQLite
    /// storage class is statically known. This never calls `sqlDefault()`.
    public static func intrinsic(
        selecting expression: any XLExpression<Value>,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: XLSQLiteDialect = XLSQLiteDialect(),
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        let storage = try _xlStaticSQLiteStorage(
            Value.self,
            identity: identity
        )
        let metadata = legacyValueMetadata(for: Value.self)
        let codingContext = context ?? XLValueCodingContext(
            site: .property,
            path: XLValueCodingPath(identity.path)
        )
        return Self(
            expression: expression,
            identity: identity,
            valueTypeIdentifier: metadata.identifier,
            valueTypeName: metadata.typeName,
            nullability: metadata.isOptional ? .nullable : .required,
            codecIdentity: nil,
            codecSelection: .inferred,
            storageIdentifier: storage,
            codingContext: codingContext,
            dialect: dialect,
            decode: { value in
                try Value(
                    reader: XLSQLiteValueReader(values: [value]),
                    at: 0
                )
            },
            encode: { value in
                var context: any XLBindingContext = _XLStaticLiteralBindingContext()
                value.bind(context: &context)
                let encoded = (context as! _XLStaticLiteralBindingContext).value
                if case .real(let real) = encoded,
                   let error = XLSQLValueEncodingError.bindingFailure(
                       for: real,
                       valueType: metadata.typeName,
                       context: codingContext
                   ) {
                    throw error
                }
                return encoded
            }
        )
    }
}


private final class _XLStaticDialectValuesRowReader<Dialect>: XLRowReader
where Dialect: XLValueCodingDialect {
    let values: [Dialect.Value]

    init(values: [Dialect.Value], dialect _: Dialect.Type) {
        self.values = values
    }

    func column<Value>(
        _ expression: any XLExpression<Value>,
        alias: XLName
    ) throws -> Value where Value: XLLiteral {
        throw XLStaticRowReadError.staticLayoutRequired(
            valueType: String(reflecting: Value.self),
            alias: alias.rawValue
        )
    }

    func dialectValue<RequestedDialect>(
        at index: Int,
        using _: RequestedDialect
    ) throws -> RequestedDialect.Value
    where RequestedDialect: XLValueCodingDialect {
        guard values.indices.contains(index) else {
            throw XLStaticRowLayoutError.valueCountMismatch(
                expected: index + 1,
                actual: values.count
            )
        }
        guard let value = values[index] as? RequestedDialect.Value else {
            throw XLStaticRowReadError.dialectValueTypeMismatch(
                index: index,
                expected: String(reflecting: RequestedDialect.Value.self),
                actual: String(reflecting: Dialect.Value.self)
            )
        }
        return value
    }
}


private struct _XLStaticLiteralBindingContext: XLBindingContext {
    var value: XLSQLiteValue = .null

    mutating func bindNull() { value = .null }
    mutating func bindInteger(value: Int) { self.value = .integer(Int64(value)) }
    mutating func bindReal(value: Double) { self.value = .real(value) }
    mutating func bindText(value: String) { self.value = .text(value) }
    mutating func bindBlob(value: Data) { self.value = .blob(value) }
}


private func _xlStaticSQLiteStorage(
    _ type: Any.Type,
    identity: XLQuerySlotIdentity
) throws -> XLValueStorageIdentifier {
    guard let storage = sqliteStorageClass(for: type) else {
        throw XLStaticRowLayoutError.unsupportedSQLiteStorage(
            identity: identity,
            storageType: String(reflecting: type)
        )
    }
    return XLValueStorageIdentifier(rawValue: storage.rawValue)
}


private func _xlStaticStorageExpression<Storage>(
    _ expression: any XLEncodable,
    as storageType: Storage.Type,
    identity: XLQuerySlotIdentity
) throws -> any XLExpression<Storage> {
    if let retypable = expression as? any XLStaticStorageRetypableExpression {
        return retypable.staticStorageExpression(as: storageType)
    }
    guard let typed = expression as? any XLExpression<Storage> else {
        throw XLStaticRowLayoutError.expressionStorageTypeMismatch(
            identity: identity,
            expectedStorageType: String(reflecting: Storage.self),
            expressionType: String(reflecting: type(of: expression))
        )
    }
    return typed
}
