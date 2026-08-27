//
//  ValueCodecRegistry.swift
//  SwiftQLCore
//
//  The immutable set of codecs a database was configured with, and the
//  defaults it resolves an unannotated value through.
//
//  Split out of ValueCodec.swift (issue #559).
//

import Foundation


public struct XLValueCodecRegistry: Sendable {

    /// Internal rather than `fileprivate`: the registry and the codec it
    /// erases were split into separate files (issue #559), and `fileprivate`
    /// is file-scoped.
    let codecs: [XLValueCodecKey: _XLAnyValueCodec]

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

    /// Selects stable query codec metadata after constraining candidates to
    /// the storage representation required by the SQL expression.
    public func codecIdentity<Value, Dialect>(
        for valueType: Value.Type,
        using dialect: Dialect,
        context: XLValueCodingContext,
        requiringStorage storage: XLValueStorageIdentifier,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLValueCodecIdentity where Dialect: XLValueCodingDialect {
        try resolvedCodec(
            for: valueType,
            using: dialect,
            context: context,
            requiringStorage: storage,
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

    /// Resolves a query parameter codec after filtering by the SQL
    /// expression's stable storage contract.
    ///
    /// This overload deliberately has no legacy fallback. For inference, a
    /// matching configuration default wins; otherwise exactly one registered
    /// codec for the runtime type, dialect, and storage is required.
    public func resolvedCodec<Value, Dialect>(
        for valueType: Value.Type,
        using dialect: Dialect,
        context: XLValueCodingContext,
        requiringStorage storage: XLValueStorageIdentifier,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLResolvedValueCodec<Value, Dialect>
    where Dialect: XLValueCodingDialect {
        let codec = try resolveQueryCodec(
            valueType: valueType,
            dialect: dialect,
            context: context,
            storage: storage,
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

    private func resolveQueryCodec<Value, Dialect>(
        valueType: Value.Type,
        dialect: Dialect,
        context: XLValueCodingContext,
        storage: XLValueStorageIdentifier,
        selection: XLQueryCodecSelection
    ) throws -> _XLAnyValueCodec where Dialect: XLValueCodingDialect {
        let target = _XLValueCodecTarget(
            valueType,
            Dialect.self,
            dialectIdentifier: dialect.descriptor.identity
        )

        let selected: _XLAnyValueCodec
        switch selection {
        case .explicit(let key):
            selected = try resolve(
                key,
                source: .explicit,
                target: target,
                dialect: dialect,
                context: context
            )
        case .query(let key):
            selected = try resolve(
                key,
                source: .query,
                target: target,
                dialect: dialect,
                context: context
            )
        case .inferred:
            let candidates = registry.codecs.values
                .filter {
                    $0.runtimeTarget == target
                        && $0.identity.storageIdentifier == storage
                }
                .sorted { lhs, rhs in
                    _xlCodecKeyIsOrdered(lhs.identity.key, before: rhs.identity.key)
                }
            if let defaultKey = defaults[target],
               let defaultCodec = registry.codecs[defaultKey],
               defaultCodec.identity.storageIdentifier == storage {
                selected = defaultCodec
            }
            else {
                switch candidates.count {
                case 1:
                    selected = candidates[0]
                case 0:
                    throw XLQueryCodecSelectionError.missingCodecForStorage(
                        valueType: String(reflecting: Value.self),
                        dialect: dialect.descriptor.identity,
                        storage: storage,
                        context: context
                    )
                default:
                    throw XLQueryCodecSelectionError.ambiguousCodecForStorage(
                        valueType: String(reflecting: Value.self),
                        dialect: dialect.descriptor.identity,
                        storage: storage,
                        candidates: candidates.map { $0.identity.key },
                        context: context
                    )
                }
            }
        }

        guard selected.identity.storageIdentifier == storage else {
            throw XLValueCodecError.storageMismatch(
                codec: selected.identity.key,
                expected: selected.identity.storageIdentifier,
                actual: storage,
                context: context
            )
        }
        return selected
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


struct _XLValueCodecTarget: Hashable, Sendable {

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


struct _XLAnyValueCodec: Sendable {

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


/// The canonical order for codec keys: by name, then by version.
///
/// Every list of them a caller can see is sorted this way, so a diagnostic
/// naming several candidates reads the same on every run. Shared (issue #558)
/// with SwiftQL's query-capture diagnostics, which sorted candidates with a
/// byte-identical comparator of its own.
package func _xlCodecKeyIsOrdered(
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
