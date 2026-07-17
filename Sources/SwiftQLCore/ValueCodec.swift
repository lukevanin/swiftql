import Foundation


/// A durable codec identity. Changing either component denotes a data migration.
public struct XLValueCodecKey: Hashable, Sendable, CustomStringConvertible {

    public let id: String

    public let version: UInt

    public init(id: String, version: UInt) {
        self.id = id
        self.version = version
    }

    public var stableIdentityComponents: [String] {
        [id, String(version)]
    }

    public var description: String {
        "\(id)@\(version)"
    }
}


/// A durable identity for a Swift value's persisted meaning.
public struct XLValueTypeIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// A durable identity for one dialect-owned storage representation.
public struct XLValueStorageIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// The stable value-and-dialect target exposed for default and fingerprint metadata.
public struct XLValueCodecTarget: Hashable, Sendable {

    public let valueTypeIdentifier: XLValueTypeIdentifier

    public let dialectIdentifier: XLDialectIdentifier

    public init(
        valueTypeIdentifier: XLValueTypeIdentifier,
        dialectIdentifier: XLDialectIdentifier
    ) {
        self.valueTypeIdentifier = valueTypeIdentifier
        self.dialectIdentifier = dialectIdentifier
    }
}


/// Stable metadata used by schema and query fingerprints.
public struct XLValueCodecIdentity: Hashable, Sendable {

    public let key: XLValueCodecKey

    public let valueTypeIdentifier: XLValueTypeIdentifier

    public let dialectIdentifier: XLDialectIdentifier

    public let storageIdentifier: XLValueStorageIdentifier

    public init(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        dialectIdentifier: XLDialectIdentifier,
        storageIdentifier: XLValueStorageIdentifier
    ) {
        self.key = key
        self.valueTypeIdentifier = valueTypeIdentifier
        self.dialectIdentifier = dialectIdentifier
        self.storageIdentifier = storageIdentifier
    }

    public var target: XLValueCodecTarget {
        XLValueCodecTarget(
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: dialectIdentifier
        )
    }

    public var stableIdentityComponents: [String] {
        key.stableIdentityComponents + [
            valueTypeIdentifier.rawValue,
            dialectIdentifier.rawValue,
            storageIdentifier.rawValue,
        ]
    }
}


/// The semantic location at which a value is encoded or decoded.
public enum XLValueCodingSite: String, Hashable, Sendable {
    case property
    case parameter
    case result
    case configuration
}


/// A stable path to a property, parameter, result, or configuration entry.
public struct XLValueCodingPath: Hashable, Sendable, CustomStringConvertible {

    public let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public init(_ component: String) {
        self.components = [component]
    }

    public var description: String {
        components.joined(separator: ".")
    }
}


/// Context passed to both halves of a value codec and retained in failures.
public struct XLValueCodingContext: Hashable, Sendable, CustomStringConvertible {

    public let site: XLValueCodingSite

    public let path: XLValueCodingPath

    public init(site: XLValueCodingSite, path: XLValueCodingPath) {
        self.site = site
        self.path = path
    }

    public var description: String {
        "\(site.rawValue):\(path)"
    }

    static let configurationDefaults = Self(
        site: .configuration,
        path: XLValueCodingPath("defaults")
    )
}


/// Identifies the precedence tier that selected, or failed to select, a codec.
public enum XLValueCodecSelectionSource: String, Hashable, Sendable {
    case explicit
    case query
    case configurationDefault
    case legacy
}


/// Per-use selectors layered over an immutable database coding configuration.
public struct XLValueCodecSelection: Hashable, Sendable {

    public let explicitCodecKey: XLValueCodecKey?

    public let queryCodecKey: XLValueCodecKey?

    public let legacyCodecKey: XLValueCodecKey?

    public init(
        explicitCodecKey: XLValueCodecKey? = nil,
        queryCodecKey: XLValueCodecKey? = nil,
        legacyCodecKey: XLValueCodecKey? = nil
    ) {
        self.explicitCodecKey = explicitCodecKey
        self.queryCodecKey = queryCodecKey
        self.legacyCodecKey = legacyCodecKey
    }
}


/// Deterministic failures from codec registration, selection, and conversion.
public enum XLValueCodecError: Error, Equatable, Sendable, LocalizedError {
    case duplicateCodec(key: XLValueCodecKey, context: XLValueCodingContext)
    case unknownCodec(
        key: XLValueCodecKey,
        source: XLValueCodecSelectionSource,
        context: XLValueCodingContext
    )
    case duplicateDefault(
        valueTypeIdentifier: String,
        dialect: XLDialectIdentifier,
        keys: [XLValueCodecKey],
        context: XLValueCodingContext
    )
    case valueTypeMismatch(
        codec: XLValueCodecKey,
        expected: String,
        actual: String,
        context: XLValueCodingContext
    )
    case dialectMismatch(
        codec: XLValueCodecKey,
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier,
        context: XLValueCodingContext
    )
    case dialectTypeMismatch(
        codec: XLValueCodecKey,
        expected: String,
        actual: String,
        context: XLValueCodingContext
    )
    case storageMismatch(
        codec: XLValueCodecKey,
        expected: XLValueStorageIdentifier,
        actual: XLValueStorageIdentifier,
        context: XLValueCodingContext
    )
    case missingCodec(
        valueType: String,
        dialect: XLDialectIdentifier,
        context: XLValueCodingContext
    )
    case ambiguousCodec(
        valueType: String,
        dialect: XLDialectIdentifier,
        candidates: [XLValueCodecKey],
        context: XLValueCodingContext
    )
    case unexpectedNull(codec: XLValueCodecKey, context: XLValueCodingContext)
    case encodingFailed(
        codec: XLValueCodecKey,
        context: XLValueCodingContext,
        message: String
    )
    case decodingFailed(
        codec: XLValueCodecKey,
        context: XLValueCodingContext,
        message: String
    )

    public var errorDescription: String? {
        switch self {
        case .duplicateCodec(let key, let context):
            return "Codec \(key) is registered more than once at \(context)."
        case .unknownCodec(let key, let source, let context):
            return "The \(source.rawValue) codec \(key) is not registered at \(context)."
        case .duplicateDefault(let valueType, let dialect, let keys, let context):
            return "Multiple default codecs \(keys.map(\.description).joined(separator: ", ")) target \(valueType) for \(dialect) at \(context)."
        case .valueTypeMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects \(expected), not \(actual), at \(context)."
        case .dialectMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects dialect \(expected), not \(actual), at \(context)."
        case .dialectTypeMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects dialect type \(expected), not \(actual), at \(context)."
        case .storageMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects storage \(expected), not \(actual), at \(context)."
        case .missingCodec(let valueType, let dialect, let context):
            return "No codec is selected for \(valueType) and \(dialect) at \(context)."
        case .ambiguousCodec(let valueType, let dialect, let candidates, let context):
            return "Codecs \(candidates.map(\.description).joined(separator: ", ")) are ambiguous for \(valueType) and \(dialect) at \(context)."
        case .unexpectedNull(let codec, let context):
            return "Nonoptional codec \(codec) received or produced SQL NULL at \(context)."
        case .encodingFailed(let codec, let context, let message):
            return "Codec \(codec) could not encode at \(context): \(message)"
        case .decodingFailed(let codec, let context, let message):
            return "Codec \(codec) could not decode at \(context): \(message)"
        }
    }
}


/// Paired throwing conversion between one Swift type and one dialect value model.
///
/// `Value` intentionally has no `Sendable` requirement. The codec itself remains
/// `Sendable` because its conversion behavior is held in `@Sendable` closures.
public struct XLValueCodec<Value, Dialect>: Sendable where Dialect: XLValueCodingDialect {

    public typealias Encode = @Sendable (
        _ value: Value,
        _ dialect: Dialect,
        _ context: XLValueCodingContext
    ) throws -> Dialect.Value

    public typealias Decode = @Sendable (
        _ value: Dialect.Value,
        _ dialect: Dialect,
        _ context: XLValueCodingContext
    ) throws -> Value

    public let identity: XLValueCodecIdentity

    private let encodeValue: Encode

    private let decodeValue: Decode

    public init(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        dialectIdentifier: XLDialectIdentifier,
        storageIdentifier: XLValueStorageIdentifier,
        encode: @escaping Encode,
        decode: @escaping Decode
    ) {
        self.identity = XLValueCodecIdentity(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: dialectIdentifier,
            storageIdentifier: storageIdentifier
        )
        self.encodeValue = encode
        self.decodeValue = decode
    }

    public var valueType: Value.Type {
        Value.self
    }

    public var dialectType: Dialect.Type {
        Dialect.self
    }

    public func encode(
        _ value: Value,
        using dialect: Dialect,
        context: XLValueCodingContext
    ) throws -> Dialect.Value {
        try validate(dialect, context: context)
        let encoded: Dialect.Value
        do {
            encoded = try encodeValue(value, dialect, context)
        }
        catch {
            throw XLValueCodecError.encodingFailed(
                codec: identity.key,
                context: context,
                message: String(describing: error)
            )
        }
        try validate(encoded, using: dialect, context: context)
        return encoded
    }

    public func decode(
        _ value: Dialect.Value,
        using dialect: Dialect,
        context: XLValueCodingContext
    ) throws -> Value {
        try validate(dialect, context: context)
        try validate(value, using: dialect, context: context)
        do {
            return try decodeValue(value, dialect, context)
        }
        catch {
            throw XLValueCodecError.decodingFailed(
                codec: identity.key,
                context: context,
                message: String(describing: error)
            )
        }
    }

    private func validate(
        _ dialect: Dialect,
        context: XLValueCodingContext
    ) throws {
        guard identity.dialectIdentifier == dialect.descriptor.identity else {
            throw XLValueCodecError.dialectMismatch(
                codec: identity.key,
                expected: identity.dialectIdentifier,
                actual: dialect.descriptor.identity,
                context: context
            )
        }
    }

    private func validate(
        _ value: Dialect.Value,
        using dialect: Dialect,
        context: XLValueCodingContext
    ) throws {
        guard !dialect.isNull(value) else {
            throw XLValueCodecError.unexpectedNull(
                codec: identity.key,
                context: context
            )
        }
        let actualStorage = dialect.stableStorageIdentifier(for: value)
        guard actualStorage == identity.storageIdentifier else {
            throw XLValueCodecError.storageMismatch(
                codec: identity.key,
                expected: identity.storageIdentifier,
                actual: actualStorage,
                context: context
            )
        }
    }
}


/// A typed codec selected once for one static property, parameter, or result slot.
///
/// Prepared handles can retain this immutable value and reuse it across
/// invocations or rows without repeating registry/default resolution.
public struct XLResolvedValueCodec<Value, Dialect>: Sendable
where Dialect: XLValueCodingDialect {

    public let identity: XLValueCodecIdentity

    public let context: XLValueCodingContext

    private let codec: _XLAnyValueCodec

    private let dialect: Dialect

    fileprivate init(
        codec: _XLAnyValueCodec,
        dialect: Dialect,
        context: XLValueCodingContext
    ) {
        self.identity = codec.identity
        self.context = context
        self.codec = codec
        self.dialect = dialect
    }

    public func encode(_ value: Value) throws -> Dialect.Value {
        let encoded = try codec.encode(value, dialect, context)
        guard let typed = encoded as? Dialect.Value else {
            throw XLValueCodecError.dialectTypeMismatch(
                codec: codec.identity.key,
                expected: String(reflecting: Dialect.Value.self),
                actual: String(reflecting: Swift.type(of: encoded)),
                context: context
            )
        }
        return typed
    }

    public func encodeOptional(_ value: Value?) throws -> Dialect.Value {
        guard let value else {
            return dialect.nullValue
        }
        return try encode(value)
    }

    public func decode(_ value: Dialect.Value) throws -> Value {
        let decoded = try codec.decode(value, dialect, context)
        guard let typed = decoded as? Value else {
            throw XLValueCodecError.valueTypeMismatch(
                codec: codec.identity.key,
                expected: codec.valueTypeName,
                actual: String(reflecting: Swift.type(of: decoded)),
                context: context
            )
        }
        return typed
    }

    public func decodeOptional(_ value: Dialect.Value) throws -> Value? {
        guard !dialect.isNull(value) else {
            return nil
        }
        return try decode(value)
    }
}


/// An immutable, process-local collection of contextual codecs.
public struct XLValueCodecRegistry: Sendable {

    fileprivate let codecs: [XLValueCodecKey: _XLAnyValueCodec]

    public init() {
        self.codecs = [:]
    }

    private init(codecs: [XLValueCodecKey: _XLAnyValueCodec]) {
        self.codecs = codecs
    }

    public var identities: [XLValueCodecIdentity] {
        codecs.values.map(\.identity).sorted { lhs, rhs in
            _xlCodecKeyIsOrdered(lhs.key, before: rhs.key)
        }
    }

    public func identity(for key: XLValueCodecKey) -> XLValueCodecIdentity? {
        codecs[key]?.identity
    }

    /// Returns a new registry snapshot containing `codec`.
    public func registering<Value, Dialect>(
        _ codec: XLValueCodec<Value, Dialect>
    ) throws -> Self where Dialect: XLValueCodingDialect {
        guard codecs[codec.identity.key] == nil else {
            throw XLValueCodecError.duplicateCodec(
                key: codec.identity.key,
                context: .configurationDefaults
            )
        }
        var copy = codecs
        copy[codec.identity.key] = _XLAnyValueCodec(codec)
        return Self(codecs: copy)
    }
}


/// Immutable database/query coding policy over a registry snapshot.
public struct XLValueCodingConfiguration: Sendable {

    public let registry: XLValueCodecRegistry

    public let defaultCodecKeys: [XLValueCodecKey]

    private let defaults: [_XLValueCodecTarget: XLValueCodecKey]

    public init(
        registry: XLValueCodecRegistry = XLValueCodecRegistry(),
        defaultCodecKeys: [XLValueCodecKey] = []
    ) throws {
        var groupedDefaults: [_XLValueCodecTarget: [XLValueCodecKey]] = [:]
        for key in defaultCodecKeys {
            guard let codec = registry.codecs[key] else {
                throw XLValueCodecError.unknownCodec(
                    key: key,
                    source: .configurationDefault,
                    context: .configurationDefaults
                )
            }
            groupedDefaults[codec.runtimeTarget, default: []].append(key)
        }

        let conflictingDefaults = groupedDefaults.values
            .map { $0.sorted(by: _xlCodecKeyIsOrdered) }
            .filter { $0.count > 1 }
            .sorted(by: _xlCodecKeyListIsOrdered)
        if let keys = conflictingDefaults.first,
           let identity = registry.codecs[keys[0]]?.identity {
            throw XLValueCodecError.duplicateDefault(
                valueTypeIdentifier: identity.valueTypeIdentifier.rawValue,
                dialect: identity.dialectIdentifier,
                keys: keys,
                context: .configurationDefaults
            )
        }

        var defaults: [_XLValueCodecTarget: XLValueCodecKey] = [:]
        for (target, keys) in groupedDefaults {
            guard let key = keys.first else {
                continue
            }
            defaults[target] = key
        }

        self.registry = registry
        self.defaultCodecKeys = defaultCodecKeys.sorted(by: _xlCodecKeyIsOrdered)
        self.defaults = defaults
    }

    public func codecIdentity<Value, Dialect>(
        for valueType: Value.Type,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLValueCodecIdentity where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: valueType,
            using: dialect,
            context: context,
            selection: selection
        ).identity
    }

    /// Resolves one static coding slot against this immutable configuration.
    ///
    /// Retain the returned value on a query descriptor or prepared handle and
    /// reuse it for each invocation or row.
    public func resolvedCodec<Value, Dialect>(
        for valueType: Value.Type,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLResolvedValueCodec<Value, Dialect>
    where Dialect: XLValueCodingDialect {
        let codec = try resolve(
            valueType: valueType,
            dialect: dialect,
            context: context,
            selection: selection
        )
        return XLResolvedValueCodec(
            codec: codec,
            dialect: dialect,
            context: context
        )
    }

    public func encode<Value, Dialect>(
        _ value: Value,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: Value.self,
            using: dialect,
            context: context,
            selection: selection
        ).encode(value)
    }

    public func encodeOptional<Value, Dialect>(
        _ value: Value?,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: Value.self,
            using: dialect,
            context: context,
            selection: selection
        ).encodeOptional(value)
    }

    public func decode<Value, Dialect>(
        _ valueType: Value.Type,
        from value: Dialect.Value,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> Value where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: valueType,
            using: dialect,
            context: context,
            selection: selection
        ).decode(value)
    }

    public func decodeOptional<Value, Dialect>(
        _ valueType: Value.Type,
        from value: Dialect.Value,
        using dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> Value? where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: valueType,
            using: dialect,
            context: context,
            selection: selection
        ).decodeOptional(value)
    }

    private func resolve<Value, Dialect>(
        valueType: Value.Type,
        dialect: Dialect,
        context: XLValueCodingContext,
        selection: XLValueCodecSelection
    ) throws -> _XLAnyValueCodec where Dialect: XLValueCodingDialect {
        let target = _XLValueCodecTarget(
            valueType,
            Dialect.self,
            dialectIdentifier: dialect.descriptor.identity
        )

        if let key = selection.explicitCodecKey {
            return try resolve(
                key,
                source: .explicit,
                target: target,
                dialect: dialect,
                context: context
            )
        }
        if let key = selection.queryCodecKey {
            return try resolve(
                key,
                source: .query,
                target: target,
                dialect: dialect,
                context: context
            )
        }
        if let key = defaults[target] {
            return try resolve(
                key,
                source: .configurationDefault,
                target: target,
                dialect: dialect,
                context: context
            )
        }
        if let key = selection.legacyCodecKey {
            return try resolve(
                key,
                source: .legacy,
                target: target,
                dialect: dialect,
                context: context
            )
        }

        let candidates = registry.codecs.values
            .filter { $0.runtimeTarget == target }
            .sorted { lhs, rhs in
                _xlCodecKeyIsOrdered(lhs.identity.key, before: rhs.identity.key)
            }
        switch candidates.count {
        case 0, 1:
            throw XLValueCodecError.missingCodec(
                valueType: String(reflecting: Value.self),
                dialect: dialect.descriptor.identity,
                context: context
            )
        default:
            throw XLValueCodecError.ambiguousCodec(
                valueType: String(reflecting: Value.self),
                dialect: dialect.descriptor.identity,
                candidates: candidates.map { $0.identity.key },
                context: context
            )
        }
    }

    private func resolve<Dialect>(
        _ key: XLValueCodecKey,
        source: XLValueCodecSelectionSource,
        target: _XLValueCodecTarget,
        dialect: Dialect,
        context: XLValueCodingContext
    ) throws -> _XLAnyValueCodec where Dialect: XLValueCodingDialect {
        guard let codec = registry.codecs[key] else {
            throw XLValueCodecError.unknownCodec(
                key: key,
                source: source,
                context: context
            )
        }
        return try validate(
            codec,
            target: target,
            dialect: dialect,
            context: context
        )
    }

    private func validate<Dialect>(
        _ codec: _XLAnyValueCodec,
        target: _XLValueCodecTarget,
        dialect: Dialect,
        context: XLValueCodingContext
    ) throws -> _XLAnyValueCodec where Dialect: XLValueCodingDialect {
        guard codec.runtimeTarget.valueType == target.valueType else {
            throw XLValueCodecError.valueTypeMismatch(
                codec: codec.identity.key,
                expected: codec.identity.valueTypeIdentifier.rawValue,
                actual: target.valueTypeName,
                context: context
            )
        }
        guard codec.identity.dialectIdentifier == dialect.descriptor.identity else {
            throw XLValueCodecError.dialectMismatch(
                codec: codec.identity.key,
                expected: codec.identity.dialectIdentifier,
                actual: dialect.descriptor.identity,
                context: context
            )
        }
        guard codec.runtimeTarget.dialectType == target.dialectType else {
            throw XLValueCodecError.dialectTypeMismatch(
                codec: codec.identity.key,
                expected: codec.dialectTypeName,
                actual: target.dialectTypeName,
                context: context
            )
        }
        return codec
    }
}


fileprivate struct _XLValueCodecTarget: Hashable, Sendable {

    let valueType: ObjectIdentifier

    let dialectType: ObjectIdentifier

    let dialectIdentifier: XLDialectIdentifier

    let valueTypeName: String

    let dialectTypeName: String

    init<Value, Dialect>(
        _ valueType: Value.Type,
        _ dialectType: Dialect.Type,
        dialectIdentifier: XLDialectIdentifier
    ) {
        self.valueType = ObjectIdentifier(valueType)
        self.dialectType = ObjectIdentifier(dialectType)
        self.dialectIdentifier = dialectIdentifier
        self.valueTypeName = String(reflecting: valueType)
        self.dialectTypeName = String(reflecting: dialectType)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.valueType == rhs.valueType
            && lhs.dialectType == rhs.dialectType
            && lhs.dialectIdentifier == rhs.dialectIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(valueType)
        hasher.combine(dialectType)
        hasher.combine(dialectIdentifier)
    }
}


fileprivate struct _XLAnyValueCodec: Sendable {

    let identity: XLValueCodecIdentity

    let runtimeTarget: _XLValueCodecTarget

    let valueTypeName: String

    let dialectTypeName: String

    let encode: @Sendable (
        _ value: Any,
        _ dialect: Any,
        _ context: XLValueCodingContext
    ) throws -> Any

    let decode: @Sendable (
        _ value: Any,
        _ dialect: Any,
        _ context: XLValueCodingContext
    ) throws -> Any

    init<Value, Dialect>(
        _ codec: XLValueCodec<Value, Dialect>
    ) where Dialect: XLValueCodingDialect {
        self.identity = codec.identity
        self.runtimeTarget = _XLValueCodecTarget(
            Value.self,
            Dialect.self,
            dialectIdentifier: codec.identity.dialectIdentifier
        )
        self.valueTypeName = String(reflecting: Value.self)
        self.dialectTypeName = String(reflecting: Dialect.self)
        self.encode = { value, dialect, context in
            guard let typedValue = value as? Value else {
                throw XLValueCodecError.valueTypeMismatch(
                    codec: codec.identity.key,
                    expected: codec.identity.valueTypeIdentifier.rawValue,
                    actual: String(reflecting: Swift.type(of: value)),
                    context: context
                )
            }
            guard let typedDialect = dialect as? Dialect else {
                throw XLValueCodecError.dialectTypeMismatch(
                    codec: codec.identity.key,
                    expected: String(reflecting: Dialect.self),
                    actual: String(reflecting: Swift.type(of: dialect)),
                    context: context
                )
            }
            return try codec.encode(typedValue, using: typedDialect, context: context)
        }
        self.decode = { value, dialect, context in
            guard let typedValue = value as? Dialect.Value else {
                throw XLValueCodecError.dialectTypeMismatch(
                    codec: codec.identity.key,
                    expected: String(reflecting: Dialect.Value.self),
                    actual: String(reflecting: Swift.type(of: value)),
                    context: context
                )
            }
            guard let typedDialect = dialect as? Dialect else {
                throw XLValueCodecError.dialectTypeMismatch(
                    codec: codec.identity.key,
                    expected: String(reflecting: Dialect.self),
                    actual: String(reflecting: Swift.type(of: dialect)),
                    context: context
                )
            }
            return try codec.decode(typedValue, using: typedDialect, context: context)
        }
    }
}


private func _xlCodecKeyIsOrdered(
    _ lhs: XLValueCodecKey,
    before rhs: XLValueCodecKey
) -> Bool {
    if lhs.id != rhs.id {
        return lhs.id < rhs.id
    }
    return lhs.version < rhs.version
}


private func _xlCodecKeyListIsOrdered(
    _ lhs: [XLValueCodecKey],
    before rhs: [XLValueCodecKey]
) -> Bool {
    for (left, right) in zip(lhs, rhs) {
        if left != right {
            return _xlCodecKeyIsOrdered(left, before: right)
        }
    }
    return lhs.count < rhs.count
}
