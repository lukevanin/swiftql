//
//  XLValueCodingDatabase.swift
//  SwiftQL
//
//  A database whose immutable value-coding snapshot resolves contextual
//  bindings and query captures, and the one implementation of both that
//  `GRDBDatabase` and `XLDriverDatabase` share (issue #113). Each database
//  used to carry its own copy.
//


///
/// A database whose immutable value-coding snapshot resolves contextual
/// bindings and query captures (issue #113).
///
/// ``GRDBDatabase`` and ``XLDriverDatabase`` conform, and share one
/// implementation of `contextualBinding` and `queryCapture`. Code that holds
/// any conforming database can declare its contextual bindings and captures
/// without naming the database's driver:
///
/// ```swift
/// func titleCapture(
///     on database: some XLValueCodingDatabase<XLSQLiteDialect>
/// ) throws -> XLQueryCapture<String, String, XLSQLiteDialect> {
///     try database.queryCapture(
///         String.self,
///         expressedAs: String.self,
///         identifiedBy: try XLQuerySlotIdentity(path: ["title"])
///     )
/// }
/// ```
///
public protocol XLValueCodingDatabase<XLDatabaseDialect>: XLDatabase {

    /// The type of ``dialect``.
    ///
    /// Prefixed because every conformer gains it as a member type: a plain
    /// `Dialect` would hide a client's own type of that name inside an
    /// extension of `GRDBDatabase` or `XLDriverDatabase`.
    associatedtype XLDatabaseDialect: XLLiteralValueDialect

    /// The dialect statements are rendered for and values are checked
    /// against.
    var dialect: XLDatabaseDialect { get }

    /// The immutable contextual value-coding policy this database and every
    /// request it makes capture.
    var codingConfiguration: XLValueCodingConfiguration { get }
}


extension XLValueCodingDatabase {

    /// Resolves a named contextual parameter against this database's immutable
    /// coding snapshot.
    public func contextualBinding<Value, Literal>(
        _ valueType: Value.Type,
        expressedAs literalType: Literal.Type,
        named name: XLName,
        nullability: XLParameterNullability = .required,
        context: XLValueCodingContext? = nil,
        selection: XLValueCodecSelection = XLValueCodecSelection()
    ) throws -> XLContextualBindingReference<Value, Literal, XLDatabaseDialect>
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
    ) throws -> XLContextualBindingReference<Value, Literal, XLDatabaseDialect>
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
    ) throws -> XLContextualBindingReference<Value, Literal, XLDatabaseDialect>
    where Literal: XLLiteral {
        try codingConfiguration.contextualBinding(
            valueType,
            expressedAs: literalType,
            key: key,
            nullability: nullability,
            using: dialect,
            context: context,
            selection: selection
        )
    }
}


extension XLValueCodingDatabase {

    /// Declares a contextual capture using this database's immutable coding
    /// configuration. Selection is constrained by `Literal`'s storage
    /// representation in the database's dialect before a default or unique
    /// candidate can be inferred.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        expressedAs literalType: Literal.Type,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLDatabaseDialect>
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
    /// source of literal type, nullability, and storage metadata.
    public func queryCapture<Input, Literal>(
        _ inputType: Input.Type,
        matching expression: any XLExpression<Literal>,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil,
        selection: XLQueryCodecSelection = .inferred
    ) throws -> XLQueryCapture<Input, Literal, XLDatabaseDialect>
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
