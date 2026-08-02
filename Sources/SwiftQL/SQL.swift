///
/// Defines the `@SQLTable` macro.
///
/// ## Concurrency
///
/// The macro declares the `Sendable` conformance of a `public` (or `package`) model (issue #531).
/// A table model is a struct whose stored properties are column values, so it is a value type
/// built from value types, and it is the kind of value that gets read on one task and used on
/// another. Swift infers `Sendable` for such a struct on its own, but withholds the inference from
/// a type other modules can see, so a public model used to need the conformance written by hand at
/// every declaration. A model that is `internal` or narrower keeps the compiler's own inferred
/// conformance and gets nothing generated, since the inference is already exact.
///
/// The conformance is checked, not asserted. If a stored property's type is not `Sendable`, the
/// compiler diagnoses that on the generated extension instead of the model quietly claiming
/// something untrue. To take responsibility for such a property yourself, state the conformance
/// on the declaration -- `@unchecked Sendable` included. The macro generates nothing when the
/// declaration already conforms to `Sendable`.
///
/// A *generic* model is left alone. It would need a conditional conformance -- one `Sendable`
/// requirement per generic parameter -- and an extension macro cannot write one: resolving the
/// `where` clause needs the type's generic signature, which needs the type's extensions, which is
/// what the macro is producing, and the compiler stops with `circular reference expanding
/// extension macros`. Declare it yourself if you want it, `extension MyRow: Sendable where
/// T: Sendable {}`, and the macro defers to that like any other stated conformance.
///
/// Requires Swift 6.0 or later. Swift 5.9 treats a macro-expanded extension as a separate source
/// file for the rule that a `Sendable` conformance must be declared alongside its type, and warns
/// on every model, so nothing is generated on that support point. See COMPATIBILITY.md.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, XLTable, Sendable, names: arbitrary)
public macro SQLTable(name: String? = nil) = #externalMacro(module: "SQLMacros", type: "SQLTableMacro")

///
/// Defines the `@SQLResult` macro.
///
/// ## Concurrency
///
/// As with `@SQLTable`, the macro declares the result type's `Sendable` conformance (issue #531)
/// unless the declaration already states it. See ``SQLTable(name:)`` for the reasoning and the
/// opt-out.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, Sendable, names: arbitrary)
public macro SQLResult() = #externalMacro(module: "SQLMacros", type: "SQLResultMacro")

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
/// <doc:CustomTypes> for the selection precedence and a worked round-trip example.
///
@attached(peer, names: arbitrary)
public macro SQLCodec(_ key: XLValueCodecKey) = #externalMacro(module: "SQLMacros", type: "SQLCodecMacro")

///
/// Defines the `@SQLQuery` macro.
///
/// Issues #18/#26 (ported from the milestone #28 spike): attaches to a
/// query-specification function in a database extension and generates two
/// peers — a value-free statement builder whose parameter references are
/// rewritten to typed `XLNamedBindingReference` placeholders, and an executor
/// that binds the parameter values through an immutable invocation packet.
/// The fetch is dispatched from the function's return annotation: `[Row]`
/// fetches all rows, `Row?` fetches one, a bare `Row` fetches exactly one
/// (throwing if the query matches zero or more than one row), and the legacy
/// `any/some XLQueryStatement<Row>` spelling fetches all rows. A direct-result
/// specification (`[Row]` / `Row?` / `Row`) writes its body with the trapping
/// `sqlResult {}` entry point instead of `sql {}`. See
/// <doc:DeclaredQueries> for the frozen-literal guard and render-once caching
/// this macro relies on.
///
@attached(peer, names: arbitrary)
public macro SQLQuery() = #externalMacro(module: "SQLMacros", type: "SQLQueryMacro")

///
/// Defines the `@SQLQueries` macro.
///
/// Issues #18/#26 (ported from the milestone #28 spike, container encoding):
/// attaches to a database extension holding a nested `Query` container of
/// specification functions, and generates the executors as members of the
/// database — a connection-scoped `Context` with one executor per
/// specification, an `execute(_:)` entry point, and one database-level
/// convenience executor per specification (sugar over `execute`). Executors
/// carry the specification's own name; the `Query` container is never
/// referenced by generated code, so it may be declared `private` to hide the
/// trapping specs from the visible API. See <doc:DeclaredQueries>.
///
@attached(member, names: arbitrary)
public macro SQLQueries() = #externalMacro(module: "SQLMacros", type: "SQLQueriesMacro")

///
/// Defines the `@SQLFunction` macro.
///
/// Attach to a struct which conforms to `XLCustomFunction` and declares one stored property per
/// SQL argument, each typed as `any XLExpression<...>` (or `some XLExpression<...>`). The macro
/// generates the ``XLCustomFunctionDefinition`` and `makeSQL(context:)` boilerplate from those
/// properties, in declaration order. Conformance to `XLCustomFunction` and `execute(reader:)` are
/// still written by hand.
///
/// - Parameter name: The SQL function name used to register with SQLite and emit in generated
///   SQL. Defaults to the name of the struct.
///
@attached(member, names: arbitrary)
public macro SQLFunction(name: String? = nil) = #externalMacro(module: "SQLMacros", type: "SQLFunctionMacro")
