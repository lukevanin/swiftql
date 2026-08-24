//
//  SQLStaticSelectField.swift
//  SwiftQL
//
//  One selected value, fully described: the expression that produces it, the
//  storage it arrives in, and the codec that decodes it.
//
//  Split out of SQLStaticRowLayout.swift (issue #559).
//

import Foundation


public protocol XLStaticSelectFieldProtocol<FieldValue, FieldDialect>: XLStaticRowFieldSource {
    // `FieldValue`/`FieldDialect` are inherited from `XLStaticRowFieldSource`,
    // not redeclared -- redeclaring the constrained `FieldDialect` here would
    // just restate its `XLValueCodingDialect` bound.

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

    let identity: XLQuerySlotIdentity
    let valueTypeIdentifier: XLValueTypeIdentifier
    let valueTypeName: String
    let nullability: XLParameterNullability
    let codingContext: XLValueCodingContext
    let dialect: Dialect
    let decodeValue: (Dialect.Value) throws -> Value
    let encodeValue: (Value) throws -> Dialect.Value
    let field: XLStaticRowField?

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

    func validate(
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
    let expression: any XLEncodable
    let validateValue: (Dialect.Value) throws -> Void

    init(
        expression: any XLEncodable,
        metadata: XLStaticRowField,
        validate: @escaping (Dialect.Value) throws -> Void
    ) {
        self.expression = expression
        self.metadata = metadata
        self.validateValue = validate
    }
}


/// A contiguous, ordered run of one or more positioned static result slots
/// contributed by a single generated stored property.
///
/// An ordinary scalar property (any `XLStaticSelectFieldProtocol` value, such
/// as one returned by `XLValueCodingConfiguration.staticResultField` or
/// `XLStaticSelectField.intrinsic`) contributes exactly one slot. A nested
/// composite property -- a stored property whose type is itself an
/// `@SQLTable`/`@SQLResult` type -- contributes every one of that nested
/// type's own flattened slots, continuing directly after the slots
/// contributed by the properties declared before it, and re-aliased with a
/// prefix derived from its own property alias so every SQL output column
/// keeps a unique name. Generated `staticRowLayout(using:...)` factories
/// obtain one of these per property from `XLStaticRowFieldSource.grouped(at:
/// alias:)` and concatenate their `fields`, `read(from:)`, and `encode(_:)`
/// results in declaration order.
public struct XLStaticFieldGroup<Value, Dialect>
where Dialect: XLValueCodingDialect {

    /// The flattened, positioned slots contributed by this property, in
    /// declaration order.
    public let fields: [XLAnyStaticSelectField<Dialect>]

    let decodeValue: (XLRowReader) throws -> Value
    let encodeValue: (Value) throws -> [Dialect.Value]

    /// The number of flat SQL result slots this property contributes. A
    /// scalar property contributes exactly one slot; a nested composite
    /// property contributes as many slots as its own flattened layout.
    public var count: Int {
        fields.count
    }

    public init(
        fields: [XLAnyStaticSelectField<Dialect>],
        decode: @escaping (XLRowReader) throws -> Value,
        encode: @escaping (Value) throws -> [Dialect.Value]
    ) {
        self.fields = fields
        self.decodeValue = decode
        self.encodeValue = encode
    }

    /// Decodes this property's value from its positioned slot(s).
    public func read(from reader: XLRowReader) throws -> Value {
        try decodeValue(reader)
    }

    /// Encodes this property's value into its positioned slot(s), in
    /// declaration order.
    public func encode(_ value: Value) throws -> [Dialect.Value] {
        try encodeValue(value)
    }
}


/// A source of one generated property's contribution to a static row layout:
/// either a single scalar slot, or every flattened slot of a nested
/// composite value.
///
/// Conformances: every `XLStaticSelectFieldProtocol` value (through the
/// default implementation below, so any existing scalar field continues to
/// work unchanged), and `XLStaticRowLayout` (so a nested `@SQLTable`/
/// `@SQLResult` property can be contributed by passing another generated
/// type's own `staticRowLayout(using:...)` result). The generated factory
/// never has to decide which case applies -- Swift resolves the matching
/// conformance for whatever value the caller passes.
public protocol XLStaticRowFieldSource<FieldValue, FieldDialect> {
    associatedtype FieldValue
    associatedtype FieldDialect: XLValueCodingDialect

    /// Positions this property's slot(s) starting at `index`, aliased using
    /// `alias`. A nested composite property re-aliases each of its own
    /// flattened slots as `"\(alias)_\(nestedAlias)"`.
    func grouped(at index: Int, alias: String) throws -> XLStaticFieldGroup<FieldValue, FieldDialect>
}


extension XLStaticSelectFieldProtocol {
    /// The default scalar contribution: exactly one positioned slot.
    ///
    /// `XLStaticSelectFieldProtocol` itself declares conformance to
    /// `XLStaticRowFieldSource` (rather than each conforming type declaring
    /// it individually), so every existing `XLStaticSelectFieldProtocol`
    /// conformer -- including custom types declared outside this module
    /// before `XLStaticRowFieldSource` existed -- automatically satisfies it
    /// too via this one default implementation. A generated
    /// `staticRowLayout(using:...)` factory constrained to
    /// `XLStaticRowFieldSource` remains source-compatible with every prior
    /// scalar field type.
    public func grouped(
        at index: Int,
        alias: String
    ) throws -> XLStaticFieldGroup<FieldValue, FieldDialect> {
        let positioned = positioned(at: index, alias: alias)
        let erasedField = try positioned.erased()
        return XLStaticFieldGroup(
            fields: [erasedField],
            decode: { reader in try positioned.read(from: reader) },
            encode: { value in [try positioned.encode(value)] }
        )
    }
}


extension XLAnyStaticSelectField {
    /// Reflows this already-positioned field's index and alias so it can be
    /// spliced into an enclosing composite property's flattened slot range.
    /// The field's identity, type metadata, and codec selection are
    /// unchanged -- only its logical SQL position and output alias move.
    func _swiftQLNested(
        atOffset offset: Int,
        aliasPrefix: String
    ) -> Self {
        let originalResult = metadata.result
        let shiftedResult = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(originalResult.index.rawValue + offset),
            identity: originalResult.identity,
            valueTypeIdentifier: originalResult.valueTypeIdentifier,
            valueTypeName: originalResult.valueTypeName,
            nullability: originalResult.nullability,
            codecIdentity: originalResult.codecIdentity,
            storageIdentifier: originalResult.storageIdentifier,
            codingContext: originalResult.codingContext
        )
        let shiftedField = XLStaticRowField(
            alias: "\(aliasPrefix)_\(metadata.alias)",
            result: shiftedResult
        )
        return Self(
            expression: expression,
            metadata: shiftedField,
            validate: validateValue
        )
    }
}


/// Offsets logical result indices by a fixed amount, so a nested composite
/// property's own zero-based layout can decode directly from its enclosing
/// layout's flat row without rebuilding any of its fields.
