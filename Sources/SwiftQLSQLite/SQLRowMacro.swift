///
/// Defines the `#row` macro.
///
/// `#row(...)` builds an ad hoc, unnamed row projection from a short list of column
/// expressions, the same way `Type.columns(...)` builds a named one for a declared
/// `@SQLResult`/`@SQLTable` type. Use `#row` for a quick, one-off projection that does not
/// deserve (or does not yet have) a declared result type; use `.columns(...)` on a declared
/// `@SQLResult`/`@SQLTable` type when the columns have meaningful names that should appear in
/// the decoded model.
///
/// `#row` accepts between one and six column expressions:
///
/// ```swift
/// let row = #row(person.id, person.name)
/// Select(row)
/// From(person)
/// ```
///
/// The row types are SQLite results, so `#row` takes SQLite expressions: a SQLite model's
/// columns, the expressions composed from them, and Swift values. Another dialect's column is a
/// compile error at the argument (issue #825).
///
/// A single column expands to ``SQLScalarResult``; two to six columns expand to the matching
/// `SQLRow2`...`SQLRow6` type, whose fields are named positionally (`_0`, `_1`, ...) — not
/// linked here since those shapes are unavailable at the Swift 6.0 doc-build pin below.
///
/// The two-to-six column shapes are available on Swift 6.1 and later only. Decoding a
/// 2+ generic-parameter result type (`SQLRow2`...`SQLRow6`) through `fetchAll()`/`publish()`
/// crashes swift-frontend in IRGen on both the pinned Swift 5.9.2 and Swift 6.0 compatibility
/// cells. The one-column shape (`SQLScalarResult`, a single generic parameter) is unaffected
/// and available on every compatibility cell. See #408 and COMPATIBILITY.md.
///
@freestanding(expression)
public macro row<C0>(
    _ c0: any XLSQLiteExpression<C0>
) -> SQLScalarResult<C0>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression

#if compiler(>=6.1)
@freestanding(expression)
public macro row<C0, C1>(
    _ c0: any XLSQLiteExpression<C0>,
    _ c1: any XLSQLiteExpression<C1>
) -> SQLRow2<C0, C1>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression

@freestanding(expression)
public macro row<C0, C1, C2>(
    _ c0: any XLSQLiteExpression<C0>,
    _ c1: any XLSQLiteExpression<C1>,
    _ c2: any XLSQLiteExpression<C2>
) -> SQLRow3<C0, C1, C2>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression

@freestanding(expression)
public macro row<C0, C1, C2, C3>(
    _ c0: any XLSQLiteExpression<C0>,
    _ c1: any XLSQLiteExpression<C1>,
    _ c2: any XLSQLiteExpression<C2>,
    _ c3: any XLSQLiteExpression<C3>
) -> SQLRow4<C0, C1, C2, C3>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression

@freestanding(expression)
public macro row<C0, C1, C2, C3, C4>(
    _ c0: any XLSQLiteExpression<C0>,
    _ c1: any XLSQLiteExpression<C1>,
    _ c2: any XLSQLiteExpression<C2>,
    _ c3: any XLSQLiteExpression<C3>,
    _ c4: any XLSQLiteExpression<C4>
) -> SQLRow5<C0, C1, C2, C3, C4>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression, C4: XLLiteral & XLExpression

@freestanding(expression)
public macro row<C0, C1, C2, C3, C4, C5>(
    _ c0: any XLSQLiteExpression<C0>,
    _ c1: any XLSQLiteExpression<C1>,
    _ c2: any XLSQLiteExpression<C2>,
    _ c3: any XLSQLiteExpression<C3>,
    _ c4: any XLSQLiteExpression<C4>,
    _ c5: any XLSQLiteExpression<C5>
) -> SQLRow6<C0, C1, C2, C3, C4, C5>.MetaResult = #externalMacro(module: "SQLMacros", type: "SQLRowMacro") where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression, C4: XLLiteral & XLExpression, C5: XLLiteral & XLExpression
#endif
