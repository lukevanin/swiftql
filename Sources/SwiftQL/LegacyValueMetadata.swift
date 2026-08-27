//
//  LegacyValueMetadata.swift
//  SwiftQL
//
//  ⚠️ Legacy v1 surface, removed in v2.
//
//  The reflective type-to-storage mapping the pre-codec binding path depends
//  on: it answers "what SQLite storage class does this Swift type use" by
//  comparing metatypes. Everything reached through a value codec answers that
//  from the codec's declared storage identifier instead, which is why this is a
//  compatibility shim rather than the mechanism.
//
//  Split out of `SQLInvocationBindings.swift` (issue #555) so what goes away in
//  v2 is visible as a file rather than as a tail of one.
//

import Foundation


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


protocol _XLOptionalLiteralType {
    static var wrappedType: Any.Type { get }
}


extension Optional: _XLOptionalLiteralType {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}


func sqliteStorageClass(
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


func legacyValueMetadata(
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


extension XLBindingKey {

    /// The binding key as it appears in a value-coding path -- the name for a
    /// named parameter, the index for a positional one.
    var contextPathComponent: String {
        switch self {
        case .named(let name):
            return name
        case .indexed(let index):
            return String(index)
        }
    }
}
