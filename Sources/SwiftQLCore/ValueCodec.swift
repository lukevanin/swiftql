//
//  ValueCodec.swift
//  SwiftQLCore
//
//  A codec: the pair of functions that turn one Swift value into a dialect
//  value and back, together with the identity that says which pair this is.
//
//  Reduced to the codec itself by issue #559 -- the identifiers, errors, and
//  registry it was sharing a file with are in ValueCodecIdentity.swift,
//  ValueCodecError.swift, and ValueCodecRegistry.swift.
//

import Foundation


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

    /// Internal rather than `fileprivate`: `XLValueCodecRegistry` is the only
    /// caller and it now lives in another file (issue #559).
    init(
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
