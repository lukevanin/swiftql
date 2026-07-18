import Foundation


/// Deterministic failures while declaring or using a value-free query capture.
public enum XLQueryCaptureError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedLiteralStorage(
        identity: XLQuerySlotIdentity,
        literalType: String
    )
    case unsupportedIntrinsicValue(
        identity: XLQuerySlotIdentity,
        valueType: String,
        literalType: String
    )
    case optionalInputType(
        identity: XLQuerySlotIdentity,
        valueType: String
    )
    case nonFiniteReal(
        identity: XLQuerySlotIdentity,
        value: String
    )
    case dialectMismatch(
        identity: XLQuerySlotIdentity,
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier
    )
    case storageMismatch(
        identity: XLQuerySlotIdentity,
        expected: XLValueStorageIdentifier,
        actual: XLValueStorageIdentifier
    )
    case codecSelectionFailed(
        identity: XLQuerySlotIdentity,
        valueType: String,
        expectedDialect: XLDialectIdentifier,
        expectedStorage: XLValueStorageIdentifier,
        selection: XLQueryCodecSelection,
        candidates: [XLValueCodecKey],
        context: XLValueCodingContext,
        detail: String
    )
    case descriptorMetadataMismatch(
        query: XLQueryIdentity,
        identity: XLQuerySlotIdentity,
        expectedSlot: XLParameterSlot,
        expectedStorage: XLValueStorageIdentifier,
        actualDeclaration: XLParameterDeclaration,
        actualStorage: XLValueStorageIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .unsupportedLiteralStorage(let identity, let literalType):
            return "Query capture \(identity) uses \(literalType), whose SQLite storage representation is not statically known."
        case .unsupportedIntrinsicValue(let identity, let valueType, let literalType):
            return "Query capture \(identity) cannot intrinsically bind \(valueType) as \(literalType); select a contextual codec."
        case .optionalInputType(let identity, let valueType):
            return "Query capture \(identity) uses optional input type \(valueType); declare a nonoptional input and express SQL NULL through an optional literal capture."
        case .nonFiniteReal(let identity, let value):
            return "Query capture \(identity) cannot bind non-finite Double value \(value) because SQLite may normalize it to SQL NULL."
        case .dialectMismatch(let identity, let expected, let actual):
            return "Query capture \(identity) expected dialect \(expected), but received \(actual)."
        case .storageMismatch(let identity, let expected, let actual):
            return "Query capture \(identity) requires storage \(expected), not \(actual)."
        case .codecSelectionFailed(
            let identity,
            let valueType,
            let expectedDialect,
            let expectedStorage,
            let selection,
            let candidates,
            let context,
            let detail
        ):
            let selectionDescription: String
            switch selection {
            case .inferred:
                selectionDescription = "inferred selection"
            case .explicit(let key):
                selectionDescription = "explicit codec \(key)"
            case .query(let key):
                selectionDescription = "query codec \(key)"
            }
            let candidateDescription = candidates.isEmpty
                ? "no candidate codecs"
                : "candidate codecs \(candidates.map(\.description).joined(separator: ", "))"
            return "Query capture \(identity) could not select a codec for \(valueType) using storage \(expectedStorage) for expected dialect \(expectedDialect) at \(context). Selection: \(selectionDescription); \(candidateDescription). \(detail)"
        case .descriptorMetadataMismatch(
            let query,
            let identity,
            let expectedSlot,
            let expectedStorage,
            let actualDeclaration,
            let actualStorage
        ):
            let expectedCodec = expectedSlot.codecIdentity?.key.description
                ?? "intrinsic"
            let actualCodec = actualDeclaration.codecIdentity?.key.description
                ?? "intrinsic"
            return "Static query \(query) expects capture \(identity) with codec \(expectedCodec) and storage \(expectedStorage), but the supplied capture declares codec \(actualCodec) and storage \(actualStorage)."
        }
    }
}


enum _XLQueryCaptureEncoding<Input, Dialect>: Sendable
where Dialect: XLValueCodingDialect {
    case contextual
    case intrinsic(@Sendable (Input) throws -> Dialect.Value)
}


/// A stable, value-free bridge from a Swift input type to one immutable static
/// query parameter.
///
/// The capture stores declaration metadata and, for intrinsic values, a
/// stateless conversion function. It never retains an invocation value,
/// database, registry, mutable argument table, or prepared statement.
public struct XLQueryCapture<Input, Literal, Dialect>:
    XLBindingReference,
    Sendable
where Literal: XLLiteral, Dialect: XLValueCodingDialect {

    public typealias T = Literal

    public let identity: XLQuerySlotIdentity

    public let declaration: XLParameterDeclaration

    public let storageIdentifier: XLValueStorageIdentifier

    public let dialectIdentifier: XLDialectIdentifier

    let encoding: _XLQueryCaptureEncoding<Input, Dialect>

    /// Creates a pure contextual capture from durable codec metadata.
    ///
    /// This initializer performs no registry lookup. Dialect integrations
    /// should validate `storageIdentifier` against `Literal` before calling it.
    package init(
        identity: XLQuerySlotIdentity,
        dialectIdentifier: XLDialectIdentifier,
        storageIdentifier: XLValueStorageIdentifier,
        codecIdentity: XLValueCodecIdentity,
        context: XLValueCodingContext? = nil
    ) throws {
        let expectedNullability = _xlLiteralNullability(Literal.self)
        guard !(Input.self is any _XLOptionalLiteralType.Type) else {
            throw XLQueryCaptureError.optionalInputType(
                identity: identity,
                valueType: String(reflecting: Input.self)
            )
        }
        guard codecIdentity.dialectIdentifier == dialectIdentifier else {
            throw XLQueryCaptureError.dialectMismatch(
                identity: identity,
                expected: dialectIdentifier,
                actual: codecIdentity.dialectIdentifier
            )
        }
        guard codecIdentity.storageIdentifier == storageIdentifier else {
            throw XLQueryCaptureError.storageMismatch(
                identity: identity,
                expected: storageIdentifier,
                actual: codecIdentity.storageIdentifier
            )
        }
        let codingContext = context ?? XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(identity.path)
        )
        self.identity = identity
        self.storageIdentifier = storageIdentifier
        self.dialectIdentifier = dialectIdentifier
        self.declaration = XLParameterDeclaration(
            key: .named(_xlQueryCaptureBindingName(identity)),
            valueTypeIdentifier: codecIdentity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Input.self),
            nullability: expectedNullability,
            codecIdentity: codecIdentity,
            codingContext: codingContext
        )
        self.encoding = .contextual
    }

    init(
        identity: XLQuerySlotIdentity,
        dialectIdentifier: XLDialectIdentifier,
        storageIdentifier: XLValueStorageIdentifier,
        valueTypeIdentifier: XLValueTypeIdentifier,
        nullability: XLParameterNullability,
        context: XLValueCodingContext,
        intrinsicEncoder: @escaping @Sendable (Input) throws -> Dialect.Value
    ) {
        self.identity = identity
        self.storageIdentifier = storageIdentifier
        self.dialectIdentifier = dialectIdentifier
        self.declaration = XLParameterDeclaration(
            key: .named(_xlQueryCaptureBindingName(identity)),
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: String(reflecting: Input.self),
            nullability: nullability,
            codecIdentity: nil,
            codingContext: context
        )
        self.encoding = .intrinsic(intrinsicEncoder)
    }

    public func makeSQL(context: inout XLBuilder) {
        Literal.wrapSQL(context: &context) { context in
            context.parameter(declaration)
        }
    }

    /// Returns the renderer-assigned metadata used to build a static query
    /// descriptor. Repeated references to this capture resolve to one slot.
    public func staticQueryParameter(
        in encoding: XLEncoding
    ) throws -> XLStaticQueryParameterMetadata {
        if let error = encoding.valueEncodingError {
            throw error
        }
        if let error = encoding.parameterLayoutError {
            throw error
        }
        guard encoding.dialectRequirement.identity == dialectIdentifier else {
            throw XLQueryCaptureError.dialectMismatch(
                identity: identity,
                expected: dialectIdentifier,
                actual: encoding.dialectRequirement.identity
            )
        }
        let layout = encoding.parameterLayout
        guard let slot = layout.slot(for: declaration.key) else {
            throw XLInvocationBindingError.parameterDeclarationNotInLayout(
                declaration: declaration
            )
        }
        guard slot.declaration == declaration else {
            throw XLInvocationBindingError.parameterMetadataMismatch(
                expected: slot,
                actual: declaration.slot(at: slot.index)
            )
        }
        return XLStaticQueryParameterMetadata(
            identity: identity,
            slot: slot,
            storageIdentifier: storageIdentifier
        )
    }
}


extension XLQueryCapture where Dialect == XLSQLiteDialect {

    /// Creates a codec-free capture for SQLite's intrinsic Swift value types:
    /// `Bool`, `Int`, `Double`, `String`, and `Data`.
    public static func intrinsic(
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        guard !(Input.self is any _XLOptionalLiteralType.Type) else {
            throw XLQueryCaptureError.optionalInputType(
                identity: identity,
                valueType: String(reflecting: Input.self)
            )
        }
        let literalStorage = try _xlRequiredSQLiteStorage(
            for: Literal.self,
            identity: identity
        )
        let inputStorage = sqliteStorageClass(for: Input.self)
        let literalValueType = _xlUnwrappedLiteralType(Literal.self)
        guard inputStorage == literalStorage,
              literalValueType == Input.self else {
            throw XLQueryCaptureError.unsupportedIntrinsicValue(
                identity: identity,
                valueType: String(reflecting: Input.self),
                literalType: String(reflecting: Literal.self)
            )
        }
        let metadata = legacyValueMetadata(for: Input.self)
        let inputTypeName = String(reflecting: Input.self)
        let literalTypeName = String(reflecting: Literal.self)
        let codingContext = context ?? XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(identity.path)
        )
        let encoder: @Sendable (Input) throws -> XLSQLiteValue = { value in
            if let value = value as? Bool {
                return .integer(value ? 1 : 0)
            }
            if let value = value as? Int {
                return .integer(Int64(value))
            }
            if let value = value as? Double {
                if let error = XLSQLValueEncodingError.bindingFailure(
                    for: value,
                    valueType: inputTypeName,
                    context: codingContext
                ) {
                    throw error
                }
                return .real(value)
            }
            if let value = value as? String {
                return .text(value)
            }
            if let value = value as? Data {
                return .blob(value)
            }
            throw XLQueryCaptureError.unsupportedIntrinsicValue(
                identity: identity,
                valueType: inputTypeName,
                literalType: literalTypeName
            )
        }
        return Self(
            identity: identity,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: literalStorage.rawValue
            ),
            valueTypeIdentifier: metadata.identifier,
            nullability: _xlLiteralNullability(Literal.self),
            context: codingContext,
            intrinsicEncoder: encoder
        )
    }
}


extension XLValueCodingConfiguration {

    /// Declares a contextual SQLite capture without requiring a live database.
    /// The returned token retains only durable metadata from this immutable
    /// configuration snapshot; it does not retain the configuration itself.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        expressedAs literalType: Literal.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: XLSQLiteDialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        guard !(Input.self is any _XLOptionalLiteralType.Type) else {
            throw XLQueryCaptureError.optionalInputType(
                identity: identity,
                valueType: String(reflecting: Input.self)
            )
        }
        let storageClass = try _xlRequiredSQLiteStorage(
            for: literalType,
            identity: identity
        )
        let storage = XLValueStorageIdentifier(rawValue: storageClass.rawValue)
        let codingContext = context ?? XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(identity.path)
        )
        let codecIdentity: XLValueCodecIdentity
        do {
            codecIdentity = try self.codecIdentity(
                for: inputType,
                using: dialect,
                context: codingContext,
                requiringStorage: storage,
                selection: selection
            )
        }
        catch let error as XLQueryCodecSelectionError {
            throw XLQueryCaptureError.codecSelectionFailed(
                identity: identity,
                valueType: String(reflecting: Input.self),
                expectedDialect: dialect.descriptor.identity,
                expectedStorage: storage,
                selection: selection,
                candidates: _xlQueryCaptureCodecCandidates(from: error),
                context: codingContext,
                detail: _xlQueryCaptureErrorDetail(error)
            )
        }
        catch let error as XLValueCodecError {
            throw XLQueryCaptureError.codecSelectionFailed(
                identity: identity,
                valueType: String(reflecting: Input.self),
                expectedDialect: dialect.descriptor.identity,
                expectedStorage: storage,
                selection: selection,
                candidates: _xlQueryCaptureCodecCandidates(from: error),
                context: codingContext,
                detail: _xlQueryCaptureErrorDetail(error)
            )
        }
        return try XLQueryCapture(
            identity: identity,
            dialectIdentifier: dialect.descriptor.identity,
            storageIdentifier: storage,
            codecIdentity: codecIdentity,
            context: codingContext
        )
    }

    /// Declares a contextual SQLite capture whose literal type, nullability,
    /// and storage contract are inferred from a typed SQL expression.
    ///
    /// The expression is only a declaration-time type witness. It is neither
    /// rendered nor retained. Its associated `Literal` supplies SQL
    /// nullability and SQLite storage; `selection` resolves matching codec
    /// candidates.
    ///
    /// Use ``queryCapture(_:expressedAs:identifiedBy:using:context:selection:)``
    /// when no representative expression is available.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        matching _: any XLExpression<Literal>,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: XLSQLiteDialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        try queryCapture(
            inputType,
            expressedAs: Literal.self,
            identifiedBy: identity,
            using: dialect,
            context: context,
            selection: selection
        )
    }
}


extension GRDBDatabase {

    /// Declares a contextual capture using this database's immutable coding
    /// configuration. Selection is constrained by `Literal`'s SQLite storage
    /// representation before a default or unique candidate can be inferred.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        expressedAs literalType: Literal.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        try codingConfiguration.queryCapture(
            inputType,
            expressedAs: literalType,
            identifiedBy: identity,
            using: dialect,
            context: context,
            selection: selection
        )
    }

    /// Declares a contextual capture using a typed SQL expression as the
    /// source of literal type, nullability, and SQLite storage metadata.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        matching expression: any XLExpression<Literal>,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLSQLiteDialect>
    where Literal: XLLiteral {
        try codingConfiguration.queryCapture(
            inputType,
            matching: expression,
            identifiedBy: identity,
            using: dialect,
            context: context,
            selection: selection
        )
    }
}


private func _xlLiteralNullability(_ type: Any.Type) -> XLParameterNullability {
    type is any _XLOptionalLiteralType.Type ? .nullable : .required
}


private func _xlUnwrappedLiteralType(_ type: Any.Type) -> Any.Type {
    if let optional = type as? any _XLOptionalLiteralType.Type {
        return optional.wrappedType
    }
    return type
}


private func _xlRequiredSQLiteStorage(
    for type: Any.Type,
    identity: XLQuerySlotIdentity
) throws -> XLSQLiteStorageClass {
    guard let storage = sqliteStorageClass(for: type) else {
        throw XLQueryCaptureError.unsupportedLiteralStorage(
            identity: identity,
            literalType: String(reflecting: type)
        )
    }
    return storage
}


private func _xlQueryCaptureBindingName(
    _ identity: XLQuerySlotIdentity
) -> String {
    var bytes: [UInt8] = []
    _xlAppendUInt64(UInt64(identity.path.count), to: &bytes)
    for component in identity.path {
        let canonical = Array(
            component.precomposedStringWithCanonicalMapping.utf8
        )
        _xlAppendUInt64(UInt64(canonical.count), to: &bytes)
        bytes.append(contentsOf: canonical)
    }
    let digits = Array("0123456789abcdef".utf8)
    var encoded: [UInt8] = Array("__swiftql_capture_".utf8)
    encoded.reserveCapacity(encoded.count + bytes.count * 2)
    for byte in bytes {
        encoded.append(digits[Int(byte >> 4)])
        encoded.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: encoded, as: UTF8.self)
}


private func _xlAppendUInt64(_ value: UInt64, to bytes: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
        bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
}


private func _xlQueryCaptureCodecCandidates(
    from error: Error
) -> [XLValueCodecKey] {
    let candidates: [XLValueCodecKey]
    if let error = error as? XLQueryCodecSelectionError {
        switch error {
        case .missingCodecForStorage:
            candidates = []
        case .ambiguousCodecForStorage(_, _, _, let candidates, _):
            return _xlOrderedQueryCaptureCodecCandidates(candidates)
        }
    }
    else if let error = error as? XLValueCodecError {
        switch error {
        case .unknownCodec(let key, _, _),
             .storageMismatch(let key, _, _, _):
            candidates = [key]
        case .duplicateDefault(_, _, let keys, _),
             .ambiguousCodec(_, _, let keys, _):
            candidates = keys
        default:
            candidates = []
        }
    }
    else {
        candidates = []
    }
    return _xlOrderedQueryCaptureCodecCandidates(candidates)
}


private func _xlOrderedQueryCaptureCodecCandidates(
    _ candidates: [XLValueCodecKey]
) -> [XLValueCodecKey] {
    candidates.sorted { lhs, rhs in
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.version < rhs.version
    }
}


private func _xlQueryCaptureErrorDetail(_ error: Error) -> String {
    if let description = (error as? LocalizedError)?.errorDescription {
        return description
    }
    return String(describing: error)
}
