//
//  SQLLiteralValueDialect.swift
//  SwiftQL
//
//  The dialect seam the static-field, capture, binding, and declared-query
//  factories are generic over, so the code the macros generate carries the
//  dialect as a parameter instead of naming SQLite (issue #687).
//

import Foundation


///
/// A dialect that can carry SwiftQL's intrinsic literal values.
///
/// Generated code reaches this protocol in two places: the
/// `staticResultField(<property>:...)` member `@SQLCodec` generates calls the
/// configuration's `staticResultField`, and the `@SQLQuery`, `@SQLQueries`,
/// and `@SQLBindings` packets call the declared-query parameter binding. The
/// factories a caller uses to build the fields it passes to a generated
/// `staticRowLayout(using:...)` are generic over it too:
/// `XLStaticSelectField.intrinsic`, and the configuration's
/// `staticResultField`. So are `XLQueryCapture.intrinsic` and the
/// configuration's `queryCapture` and `contextualBinding`. A model is
/// therefore declared once and builds its static layout against any
/// conforming dialect.
///
/// The requirements are static because they describe the dialect's value
/// model, which is a property of the dialect type and not of a configured
/// instance. That lets generated code name the dialect by its type alone.
///
/// `XLSQLiteDialect` conforms with SQLite's five storage classes.
///
/// The literal protocols themselves are still SQLite's binding vocabulary:
/// ``XLBindable`` binds through ``XLBindingContext``'s five storage classes
/// and ``XLLiteral`` reads through ``XLColumnReader``. A conforming dialect
/// maps those onto its own value type. Issue #686 replaces that vocabulary
/// with a dialect-parametric storage witness.
///
public protocol XLLiteralValueDialect: XLValueCodingDialect {

    ///
    /// The storage identifier this dialect uses for values of `type`, or
    /// `nil` when the storage is not statically known.
    ///
    /// An optional type reports its wrapped type's storage. The identifier
    /// must agree with `XLValueCodingDialect.stableStorageIdentifier(for:)`
    /// for a value of that type.
    ///
    static func literalStorageIdentifier(for type: Any.Type) -> XLValueStorageIdentifier?

    ///
    /// Decodes one literal from one dialect value.
    ///
    static func decodeLiteral<Literal>(
        _ type: Literal.Type,
        from value: Value
    ) throws -> Literal where Literal: XLLiteral

    ///
    /// Encodes one literal into one dialect value.
    ///
    /// The dialect owns the check for a value it cannot store faithfully, and
    /// throws for it here: no caller checks the value first. SQLite throws
    /// ``XLSQLValueEncodingError`` for a NaN `REAL`, which SQLite would store
    /// as `NULL`. A dialect that stores NaN as itself accepts it.
    ///
    /// - Parameters:
    ///   - value: The literal to encode.
    ///   - valueType: Names the value's type in a thrown error.
    ///   - codingContext: Names the parameter or property in a thrown error.
    ///
    static func encodeLiteral<Literal>(
        _ value: Literal,
        valueType: String,
        codingContext: XLValueCodingContext
    ) throws -> Value where Literal: XLBindable

    ///
    /// Returns whether a dialect value is SQL `NULL`.
    ///
    /// Static for the reason the other requirements are, so a declared-query
    /// parameter binding can reject `NULL` for a required slot with no dialect
    /// instance. It must agree with `XLValueCodingDialect.isNull(_:)`.
    ///
    static func isNullLiteral(_ value: Value) -> Bool
}


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
