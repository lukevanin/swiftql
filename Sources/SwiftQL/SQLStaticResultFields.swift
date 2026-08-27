//
//  SQLStaticResultFields.swift
//  SwiftQL
//
//  Building a described field from a coding configuration: resolving which
//  codec applies to a value, and the SQLite storage a Swift type maps to.
//
//  Split out of SQLStaticRowLayout.swift (issue #559).
//

import Foundation


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
                try _xlCaptureSQLiteValue(
                    value,
                    valueType: metadata.typeName,
                    codingContext: codingContext
                )
            }
        )
    }
}


final class _XLStaticDialectValuesRowReader<Dialect>: XLRowReader
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


func _xlStaticSQLiteStorage(
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


func _xlStaticStorageExpression<Storage>(
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
