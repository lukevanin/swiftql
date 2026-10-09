//
//  SQLLiteralValueDialect+SQLite.swift
//
//  SQLite's conformance to XLLiteralValueDialect, with its five storage
//  classes. Split from SQLLiteralValueDialect.swift, whose protocol is every
//  dialect's (issue #790).
//

import Foundation


extension XLSQLiteDialect: XLLiteralValueDialect {

    public static func literalStorageIdentifier(
        for type: Any.Type
    ) -> XLValueStorageIdentifier? {
        sqliteStorageClass(for: type).map { storage in
            XLValueStorageIdentifier(rawValue: storage.rawValue)
        }
    }

    public static func decodeLiteral<Literal>(
        _ type: Literal.Type,
        from value: XLSQLiteValue
    ) throws -> Literal where Literal: XLLiteral {
        try Literal(
            reader: XLSQLiteValueReader(values: [value]),
            at: 0
        )
    }

    public static func encodeLiteral<Literal>(
        _ value: Literal,
        valueType: String,
        codingContext: XLValueCodingContext
    ) throws -> XLSQLiteValue where Literal: XLBindable {
        try _xlCaptureSQLiteValue(
            value,
            valueType: valueType,
            codingContext: codingContext
        )
    }

    public static func isNullLiteral(_ value: XLSQLiteValue) -> Bool {
        value == .null
    }
}


///
/// The SQLite storage class of an intrinsic v1 literal type, or `nil` for any
/// other type. Moved from LegacyValueMetadata.swift with the SQLite
/// conformance that reads it (issue #790).
///
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
