//
//  SQLStaticResultFields.swift
//  SwiftQL
//
//  Building a described field from a coding configuration: resolving which
//  codec applies to a value, and the storage a Swift type maps to in the
//  field's dialect.
//
//  Split out of SQLStaticRowLayout.swift (issue #559).
//

import Foundation


extension XLValueCodingConfiguration {

    /// Creates a required contextual result field for `dialect`. `Storage` is
    /// a type witness for the selected SQL expression's intrinsic storage
    /// carrier; no value or `sqlDefault()` call is required.
    ///
    /// `expression` must be an expression of `dialect`, such as a column of a
    /// model declared for it. Any other expression throws
    /// ``XLStaticRowLayoutError/expressionDialectMismatch(identity:expectedDialect:foundDialect:expressionType:)``.
    public func staticResultField<Value, Storage, Dialect>(
        _ valueType: Value.Type,
        selecting expression: any XLEncodable,
        storedAs storageType: Storage.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: Dialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLStaticSelectField<Value, Storage, Dialect>
    where Storage: XLLiteral, Dialect: XLLiteralValueDialect {
        let storage = try _xlStaticLiteralStorage(
            storageType,
            in: Dialect.self,
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
            in: Dialect.self,
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

    /// Creates a nullable contextual result field for `dialect`. Optionality
    /// belongs to the field contract; the same nonoptional codec is reused for
    /// present values while SQL `NULL` maps to and from `nil`.
    public func staticResultField<Value, Storage, Dialect>(
        _ valueType: Value?.Type,
        selecting expression: any XLEncodable,
        storedAs storageType: Storage?.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: Dialect,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLStaticSelectField<Value?, Storage?, Dialect>
    where Storage: XLLiteral, Dialect: XLLiteralValueDialect {
        let storage = try _xlStaticLiteralStorage(
            Storage.self,
            in: Dialect.self,
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
            in: Dialect.self,
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
where Dialect: XLLiteralValueDialect, Value: XLLiteral, Storage == Value {

    /// Creates a codec-free field for an intrinsic v1 literal whose storage in
    /// `dialect` is statically known. This never calls `sqlDefault()`.
    ///
    /// `expression` must be an expression of `dialect`, such as a column of a
    /// model declared for it. A column of another dialect's model throws
    /// ``XLStaticRowLayoutError/expressionDialectMismatch(identity:expectedDialect:foundDialect:expressionType:)``
    /// (issue #789).
    public static func intrinsic(
        selecting expression: any XLExpression<Value>,
        identifiedBy identity: XLQuerySlotIdentity,
        using dialect: Dialect,
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        let storage = try _xlStaticLiteralStorage(
            Value.self,
            in: Dialect.self,
            identity: identity
        )
        let expression = try _xlDialectExpression(
            expression,
            in: Dialect.self,
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
                try Dialect.decodeLiteral(Value.self, from: value)
            },
            encode: { value in
                try Dialect.encodeLiteral(
                    value,
                    valueType: metadata.typeName,
                    codingContext: codingContext
                )
            }
        )
    }
}


extension XLStaticSelectField
where Dialect == XLSQLiteDialect, Value: XLLiteral, Storage == Value {

    /// Creates a codec-free SQLite field for an intrinsic v1 literal whose
    /// SQLite storage class is statically known. This never calls
    /// `sqlDefault()`.
    ///
    /// The same as ``intrinsic(selecting:identifiedBy:using:context:)`` with
    /// a default `XLSQLiteDialect`.
    public static func intrinsic(
        selecting expression: any XLExpression<Value>,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        try intrinsic(
            selecting: expression,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context
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


func _xlStaticLiteralStorage<Dialect>(
    _ type: Any.Type,
    in _: Dialect.Type,
    identity: XLQuerySlotIdentity
) throws -> XLValueStorageIdentifier where Dialect: XLLiteralValueDialect {
    guard let storage = Dialect.literalStorageIdentifier(for: type) else {
        // The case keeps its v1 name although any dialect can reach it now:
        // renaming it would break callers that match on it.
        throw XLStaticRowLayoutError.unsupportedSQLiteStorage(
            identity: identity,
            storageType: String(reflecting: type)
        )
    }
    return storage
}


///
/// Retypes a selected expression to its storage carrier, in the field's
/// dialect.
///
/// The configuration's field factories take the expression erased, so the
/// dialect is checked here, at run time, rather than by the compiler: see
/// ``_xlDialectExpression(_:in:identity:)``.
///
func _xlStaticStorageExpression<Storage, Dialect>(
    _ expression: any XLEncodable,
    as storageType: Storage.Type,
    in dialect: Dialect.Type,
    identity: XLQuerySlotIdentity
) throws -> XLDialectExpression<Storage, Dialect> {
    let typed: any XLExpression<Storage>
    if let retypable = expression as? any XLStaticStorageRetypableExpression {
        typed = retypable.staticStorageExpression(as: storageType)
    }
    else if let expression = expression as? any XLExpression<Storage> {
        typed = expression
    }
    else {
        throw XLStaticRowLayoutError.expressionStorageTypeMismatch(
            identity: identity,
            expectedStorageType: String(reflecting: Storage.self),
            expressionType: String(reflecting: type(of: expression))
        )
    }
    return try _xlDialectExpression(typed, in: dialect, identity: identity)
}


///
/// The selected expression as an expression of the field's dialect.
///
/// Every part of the expression that records its dialect, such as a column of
/// a model or a capture, must record `Dialect`: an expression that holds a
/// column of a model declared for another dialect, at any depth, throws
/// ``XLStaticRowLayoutError/expressionDialectMismatch(identity:expectedDialect:foundDialect:expressionType:)``
/// (issue #789). Any other part, such as a value, belongs to every dialect.
///
/// The walk reads stored properties through `Mirror`, so it does not see into
/// a closure; a `CASE` expression, which keeps its arms in closures, records
/// its dialect itself. A part that records the expected dialect is trusted,
/// and the walk does not descend into it, except a value read back from a
/// generated `MetaUpdate` slot, which records its model's dialect without
/// having checked it (issue #825). A field is built once per layout, so the
/// walk is not on a per-row path.
///
func _xlDialectExpression<Storage, Dialect>(
    _ expression: any XLExpression<Storage>,
    in _: Dialect.Type,
    identity: XLQuerySlotIdentity
) throws -> XLDialectExpression<Storage, Dialect> {
    var visited = Set<ObjectIdentifier>()
    if let found = _xlForeignDialect(in: expression, expected: Dialect.self, visited: &visited) {
        throw XLStaticRowLayoutError.expressionDialectMismatch(
            identity: identity,
            expectedDialect: String(reflecting: Dialect.self),
            foundDialect: String(reflecting: found),
            expressionType: String(reflecting: type(of: expression))
        )
    }
    return XLDialectExpression<Storage, Dialect>.wrapping(expression, verified: true)
}


///
/// The dialect of the first part of `value` that records a dialect other than
/// `expected`, or `nil` when every part that records one records `expected`.
///
func _xlForeignDialect(
    in value: Any,
    expected: Any.Type,
    visited: inout Set<ObjectIdentifier>
) -> Any.Type? {
    // A slot's read records its model's dialect without having checked what
    // it holds, so the walk looks inside it (issue #825).
    if let unverified = value as? any XLUnverifiedDialectExpression,
       let wrapped = unverified.unverifiedExpression {
        return _xlForeignDialect(in: wrapped, expected: expected, visited: &visited)
    }
    if let tagged = value as? any XLDialectTaggedExpression {
        return tagged.expressionDialect == expected ? nil : tagged.expressionDialect
    }
    // A literal value, such as a string, a number, or `Data`, belongs to
    // every dialect, and walking it would only visit its contents.
    if value is any XLLiteral {
        return nil
    }
    // A value tree cannot be cyclic; only a reference can lead back to a part
    // already walked, so each object is walked once.
    if type(of: value) is AnyClass {
        let object = value as AnyObject
        guard visited.insert(ObjectIdentifier(object)).inserted else {
            return nil
        }
    }
    var mirror: Mirror? = Mirror(reflecting: value)
    while let current = mirror {
        for child in current.children {
            if let found = _xlForeignDialect(in: child.value, expected: expected, visited: &visited) {
                return found
            }
        }
        // A class's inherited stored properties are its superclass's.
        mirror = current.superclassMirror
    }
    return nil
}
