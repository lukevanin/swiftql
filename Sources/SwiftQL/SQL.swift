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
