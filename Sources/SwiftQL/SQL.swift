///
/// Defines the `@SQLTable` macro.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, XLTable, names: arbitrary)
public macro SQLTable(name: String? = nil) = #externalMacro(module: "SQLMacros", type: "SQLTableMacro")

///
/// Defines the `@SQLResult` macro.
///
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, names: arbitrary)
public macro SQLResult() = #externalMacro(module: "SQLMacros", type: "SQLResultMacro")

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
