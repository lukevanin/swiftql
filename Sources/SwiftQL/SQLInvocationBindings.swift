import Foundation


/// Request-facade failures that occur before a dialect-specific packet reaches
/// a database driver.
public enum XLRequestBindingError: Error, Equatable, Sendable, LocalizedError {

    case unsupportedInvocationBindings(
        requestType: String,
        layout: XLParameterLayout
    )

    case incompatibleInvocationPacket(
        requestType: String,
        expectedDialect: XLDialectIdentifier,
        expectedValueType: String,
        actualPacketType: String
    )

    case expressionNullabilityMismatch(
        key: XLBindingKey,
        parameterNullability: XLParameterNullability,
        literalType: String
    )

    public var errorDescription: String? {
        switch self {
        case .unsupportedInvocationBindings(let requestType, let layout):
            return "Request \(requestType) does not support an invocation packet with \(layout.count) parameters."
        case .incompatibleInvocationPacket(
            let requestType,
            let expectedDialect,
            let expectedValueType,
            let actualPacketType
        ):
            return "Request \(requestType) requires \(expectedValueType) values for dialect \(expectedDialect), not packet \(actualPacketType)."
        case .expressionNullabilityMismatch(
            let key,
            let parameterNullability,
            let literalType
        ):
            return "Parameter \(key) is \(parameterNullability.rawValue), but SQL expression type \(literalType) has different nullability."
        }
    }
}


/// A contextual runtime value paired with the literal type used by SQL
/// expression checking.
///
/// `Value` is converted by a resolved contextual codec. `Literal` describes
/// how the placeholder participates in the existing SwiftQL expression DSL.
/// For example, a `Date` encoded as SQLite text can use
/// `XLContextualBindingReference<Date, String, XLSQLiteDialect>` without making
/// `Date` conform to `XLLiteral`.
public struct XLContextualBindingReference<Value, Literal, Dialect>:
    XLBindingReference,
    Sendable
where Literal: XLLiteral, Dialect: XLValueCodingDialect {

    public typealias T = Literal

    public let declaration: XLParameterDeclaration

    private let codec: XLResolvedValueCodec<Value, Dialect>

    /// Creates an index-free contextual parameter declaration.
    ///
    /// SQL traversal assigns its logical index on first use. The resolved codec
    /// is retained as an immutable snapshot and reused for every invocation.
    public init(
        key: XLBindingKey,
        nullability: XLParameterNullability = .required,
        codec: XLResolvedValueCodec<Value, Dialect>
    ) {
        self.declaration = XLParameterDeclaration(
            key: key,
            valueTypeIdentifier: codec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Value.self),
            nullability: nullability,
            codecIdentity: codec.identity,
            codingContext: codec.context
        )
        self.codec = codec
    }

    public func makeSQL(context: inout XLBuilder) {
        Literal.wrapSQL(context: &context) { context in
            context.parameter(declaration)
        }
    }

    /// Resolves the renderer-assigned logical index without consulting a
    /// mutable registry or changing the selected codec.
    public func preparedParameter(
        in layout: XLParameterLayout
    ) throws -> XLPreparedParameter<Value, Dialect> {
        guard let slot = layout.slot(for: declaration.key) else {
            throw XLInvocationBindingError.parameterDeclarationNotInLayout(
                declaration: declaration
            )
        }

        let parameter = XLPreparedParameter(
            index: slot.index,
            key: declaration.key,
            nullability: declaration.nullability,
            codec: codec
        )
        guard parameter.slot == slot else {
            throw XLInvocationBindingError.parameterMetadataMismatch(
                expected: slot,
                actual: parameter.slot
            )
        }
        return parameter
    }

    /// Encodes a nonoptional runtime value for one rendered layout.
    public func encode(
        _ value: Value,
        in layout: XLParameterLayout
    ) throws -> XLInvocationBinding<Dialect.Value> {
        try preparedParameter(in: layout).encode(value)
    }

    /// Encodes an optional runtime value, retaining explicit SQL `NULL` as a
    /// present binding.
    public func encodeOptional(
        _ value: Value?,
        in layout: XLParameterLayout
    ) throws -> XLInvocationBinding<Dialect.Value> {
        try preparedParameter(in: layout).encodeOptional(value)
    }
}


extension GRDBDatabase {

    /// Resolves a named contextual parameter against this database's immutable
    /// coding snapshot.
    public func contextualBinding<Value, Literal>(
        _ valueType: Value.Type,
        expressedAs literalType: Literal.Type,
        named name: XLName,
        nullability: XLParameterNullability = .required,
        context: XLValueCodingContext? = nil,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLContextualBindingReference<Value, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        try contextualBinding(
            valueType,
            expressedAs: literalType,
            key: .named(name.rawValue),
            nullability: nullability,
            context: context,
            selection: selection
        )
    }

    /// Resolves an indexed contextual parameter against this database's
    /// immutable coding snapshot.
    public func contextualBinding<Value, Literal>(
        _ valueType: Value.Type,
        expressedAs literalType: Literal.Type,
        indexed index: Int,
        nullability: XLParameterNullability = .required,
        context: XLValueCodingContext? = nil,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLContextualBindingReference<Value, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        try contextualBinding(
            valueType,
            expressedAs: literalType,
            key: .indexed(index),
            nullability: nullability,
            context: context,
            selection: selection
        )
    }

    /// Resolves a contextual parameter for an explicit logical binding key.
    public func contextualBinding<Value, Literal>(
        _ valueType: Value.Type,
        expressedAs literalType: Literal.Type,
        key: XLBindingKey,
        nullability: XLParameterNullability = .required,
        context: XLValueCodingContext? = nil,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLContextualBindingReference<Value, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        let expressionIsOptional = literalType is any _XLOptionalLiteralType.Type
        guard expressionIsOptional == (nullability == .nullable) else {
            throw XLRequestBindingError.expressionNullabilityMismatch(
                key: key,
                parameterNullability: nullability,
                literalType: String(reflecting: literalType)
            )
        }
        let codingContext = context ?? XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(key.contextPathComponent)
        )
        let codec = try codingConfiguration.resolvedCodec(
            for: valueType,
            using: dialect,
            context: codingContext,
            selection: selection
        )
        try validateLiteralStorage(
            literalType,
            codecIdentity: codec.identity,
            context: codingContext
        )
        return XLContextualBindingReference(
            key: key,
            nullability: nullability,
            codec: codec
        )
    }

    private func validateLiteralStorage<Literal>(
        _ literalType: Literal.Type,
        codecIdentity: XLValueCodecIdentity,
        context: XLValueCodingContext
    ) throws where Literal: XLLiteral {
        guard let storageClass = sqliteStorageClass(for: literalType) else {
            return
        }
        let actual = XLValueStorageIdentifier(rawValue: storageClass.rawValue)
        guard codecIdentity.storageIdentifier == actual else {
            throw XLValueCodecError.storageMismatch(
                codec: codecIdentity.key,
                expected: codecIdentity.storageIdentifier,
                actual: actual,
                context: context
            )
        }
    }
}


func _xlLegacyParameterDeclaration<Value>(
    for type: Value.Type,
    key: XLBindingKey
) -> XLParameterDeclaration {
    let metadata = legacyValueMetadata(for: type)
    return XLParameterDeclaration(
        key: key,
        valueTypeIdentifier: metadata.identifier,
        valueTypeName: metadata.typeName,
        nullability: metadata.isOptional ? .nullable : .required,
        codecIdentity: nil,
        codingContext: XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(key.contextPathComponent)
        )
    )
}


private protocol _XLOptionalLiteralType {
    static var wrappedType: Any.Type { get }
}


extension Optional: _XLOptionalLiteralType {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}


private func sqliteStorageClass(
    for type: Any.Type
) -> XLSQLiteStorageClass? {
    if let optional = type as? any _XLOptionalLiteralType.Type {
        return sqliteStorageClass(for: optional.wrappedType)
    }
    if type == Bool.self || type == Int.self {
        return .integer
    }
    if type == Double.self {
        return .real
    }
    if type == String.self {
        return .text
    }
    if type == Data.self {
        return .blob
    }
    return nil
}


private func legacyValueMetadata(
    for type: Any.Type
) -> (identifier: XLValueTypeIdentifier, typeName: String, isOptional: Bool) {
    if let optional = type as? any _XLOptionalLiteralType.Type {
        let wrapped = legacyValueMetadata(for: optional.wrappedType)
        return (wrapped.identifier, wrapped.typeName, true)
    }

    let identifier: String
    if type == Bool.self {
        identifier = "swift.bool"
    }
    else if type == Int.self {
        identifier = "swift.int"
    }
    else if type == Double.self {
        identifier = "swift.double"
    }
    else if type == String.self {
        identifier = "swift.string"
    }
    else if type == Data.self {
        identifier = "foundation.data"
    }
    else {
        // v1 custom literals have no durable identifier contract. Keep one
        // explicit compatibility sentinel and retain the reflected spelling
        // only in the diagnostic `valueTypeName` field.
        identifier = "swiftql.v1.legacy-custom"
    }
    return (
        XLValueTypeIdentifier(rawValue: identifier),
        String(reflecting: type),
        false
    )
}


private extension XLBindingKey {
    var contextPathComponent: String {
        switch self {
        case .named(let name):
            return name
        case .indexed(let index):
            return String(index)
        }
    }
}
