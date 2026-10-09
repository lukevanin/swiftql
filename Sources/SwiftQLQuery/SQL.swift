//
//  SQL.swift
//
//  The model macros that name their dialect, and `@SQLCodec`: the macros a
//  dialect author's models use. Their expansions name only this module and
//  SwiftQLCore. The dialect-less overloads, and the declared-query and
//  function macros, are SwiftQLSQLite's (issue #790).
//

///
/// Defines the `@SQLTable(dialect:)` macro.
///
/// Issue #789: the same as `@SQLTable`, with the dialect the model belongs to
/// named as `MyDialect.self`. Without the argument the dialect is
/// `XLSQLiteDialect`.
///
/// Every column of the model carries the dialect, so every expression built
/// from the model does too, and an operation the dialect does not have is a
/// compile error on it. A schema takes the model only when the schema is of
/// the same dialect. A model that two dialects need is declared once for each:
/// a model maps to one database's types, and translating between databases
/// belongs above SwiftQL.
///
/// The model's value slots, such as an assignment in `Setting { row in ... }`
/// and the arguments of `columns(...)`, take the dialect's expressions, which
/// the generated code names as `Dialect.XLAnyExpression<T>` (issue #825). The
/// dialect's generated surface declares that typealias on the dialect type. A
/// dialect without a generated surface declares it itself, as
/// `public typealias XLAnyExpression<T> = any XLExpression<T>`, which leaves
/// its models' slots unchecked; without it the generated code reports that
/// `XLAnyExpression` is not a member type of the dialect. A hand-written
/// expression protocol includes `XLTypeAffinityExpression` for every value
/// type, with no `where` clause, as a generated one does, because a read of a
/// slot returns a value of no dialect inside it; without it the model reports
/// that `XLTypeAffinityExpression` is not convertible to, or does not
/// conform to, the dialect's protocol. The dialect is a dialect
/// type: a generic parameter of the model has no `XLAnyExpression`, and the
/// macro reports it.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, XLTable, Sendable, names: arbitrary)
public macro SQLTable<Dialect: XLSQLDialect>(name: String? = nil, dialect: Dialect.Type) = #externalMacro(module: "SQLMacros", type: "SQLTableMacro")

///
/// Defines the `@SQLResult(dialect:)` macro.
///
/// Issue #789: the same as `@SQLResult`, with the dialect the result belongs
/// to named as `MyDialect.self`. Without the argument the dialect is
/// `XLSQLiteDialect`. See ``SQLTable(name:dialect:)``.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, Sendable, names: arbitrary)
public macro SQLResult<Dialect: XLSQLDialect>(dialect: Dialect.Type) = #externalMacro(module: "SQLMacros", type: "SQLResultMacro")

///
/// Defines the `@SQLCodec` macro.
///
/// Issue #66: attach to one stored property of an `@SQLTable`/`@SQLResult` type to select a
/// named contextual value codec for that property alone, without wrapping or changing the
/// property's Swift value type, its mutability, or the type's memberwise initializer. `key` is
/// any expression whose static type is `XLValueCodecKey` -- typically a codec preset's own key
/// (e.g. `XLDateTextCodec.standardKey`) or `XLValueCodecKey(id:version:)` directly. The
/// macro carries this key as metadata only: it never performs conversion itself, and the
/// selected codec must still be registered with the database's `XLValueCodingConfiguration` for
/// resolution to succeed. Two properties of the same Swift type may each select a different
/// codec this way, letting them use different storage conventions while the database/query
/// coding configuration remains the default policy for every other property. See
/// "Custom Types" in SwiftQL's documentation for the selection precedence and a worked round-trip example.
///
@attached(peer, names: arbitrary)
public macro SQLCodec(_ key: XLValueCodecKey) = #externalMacro(module: "SQLMacros", type: "SQLCodecMacro")
