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
/// Spike (#359): attaches to a statement-returning function in a database
/// extension and generates two peers — a value-free statement builder whose
/// parameter references are rewritten to typed `XLNamedBindingReference`
/// placeholders, and a `fetchAll` executor that binds the parameter values
/// through an immutable invocation packet. Generated names are provisional
/// while #26 settles the packaging decision.
///
@attached(peer, names: arbitrary)
public macro SQLQuery() = #externalMacro(module: "SQLMacros", type: "SQLQueryMacro")
