//
//  SQLQueryPeerMacroSupport.swift
//  SwiftQL
//
//  Runtime support for `@SQLQuery` / `@SQLQueries` macro-generated executors
//  (issues #18/#26, ported from the milestone #28 spike on
//  `experiment/sqlquery-peer-macro`).
//

import Foundation


///
/// Encodes one intrinsic literal parameter value for a named placeholder in a
/// prepared parameter layout.
///
/// Support for `@SQLQuery`/`@SQLQueries` macro-generated executors. The macro
/// rewrites function-parameter references into typed `XLNamedBindingReference`
/// placeholders, and the generated executor calls this function to encode each
/// runtime value into the immutable invocation packet. The static metadata
/// derived from `T` must match the rendered slot exactly, mirroring the
/// validation performed by the request `set` compatibility shim.
///
public func _xlQueryParameterBinding<T>(
    _ value: T,
    named name: XLName,
    in layout: XLParameterLayout
) throws -> XLInvocationBinding<XLSQLiteValue> where T: XLBindable & XLLiteral {
    let declaration = _xlLegacyParameterDeclaration(
        for: T.self,
        key: .named(name.rawValue)
    )
    guard let slot = layout.slot(for: declaration.key) else {
        throw XLInvocationBindingError.parameterDeclarationNotInLayout(
            declaration: declaration
        )
    }
    guard slot.declaration == declaration else {
        throw XLInvocationBindingError.parameterMetadataMismatch(
            expected: slot,
            actual: declaration.slot(at: slot.index)
        )
    }
    let sqliteValue = try _xlCaptureSQLiteValue(
        value,
        valueType: slot.valueTypeName,
        codingContext: slot.codingContext
    )
    if sqliteValue == .null, slot.nullability == .required {
        throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
    }
    return try XLInvocationBinding(slot: slot, value: sqliteValue)
}


///
/// The trapping direct-result entry point for `@SQLQuery`/`@SQLQueries`
/// specifications.
///
/// A specification written with a direct result type (`[Row]` / `Row?` /
/// `Row`) calls this instead of `sql {}` so the function type-checks without
/// the `XLQueryStatement` return-type boilerplate. `Result` appears only in
/// return position, so it is inferred from the enclosing function's declared
/// return type — one entry point satisfies every cardinality with no overload
/// ambiguity.
///
/// This function is only a type-check anchor and a syntax source for the
/// macro; invoking it directly traps loudly, because the real work happens in
/// the macro-generated executor peer. The macro rewrites this callee back to
/// `sql {}` when it emits the value-free statement builder.
///
/// The name is provisional — `sqlQuery` and `sql` are already statement
/// builders in `SQLFunctionalSyntax.swift` / the query expression builder, so
/// the direct-result anchor needs its own name.
///
public func sqlResult<Row, Result>(
    @XLQueryExpressionBuilder _ builder: (XLSchema) -> any XLQueryStatement<Row>
) -> Result {
    fatalError(
        "'sqlResult' marks a @SQLQuery/@SQLQueries specification, not an "
        + "executor. Call the macro-generated executor instead -- a peer "
        + "function for @SQLQuery, or a member of the database/Context for "
        + "@SQLQueries."
    )
}


///
/// Thrown by a macro-generated executor when the declaration's return
/// annotation requires exactly one row (a bare, non-optional, non-array
/// `Row` result) but the rendered query matched zero rows or more than one.
///
/// No `XLRequest` fetch operation enforces "zero or many is an error" on its
/// own, so the generated executor calls `fetchAtMost(2, bindings:)` and
/// validates the count itself before returning the single element. Fetching
/// at most two rows -- rather than every matching row -- means a query that
/// accidentally matches many rows is rejected cheaply, but also means the
/// "more than one" case never has an exact matched-row count to report:
/// there are separate cases below instead of one case carrying a
/// possibly-misleading `Int`.
///
public enum XLQueryCardinalityError: Error, Equatable, Sendable, LocalizedError {

    /// The query matched zero rows.
    case noRowsMatched

    /// The query matched more than one row. The exact count is unknown --
    /// the executor stops fetching as soon as a second row is seen.
    case moreThanOneRowMatched

    public var errorDescription: String? {
        switch self {
        case .noRowsMatched:
            return "'@SQLQuery'/'@SQLQueries' declared a result of exactly one row, "
                + "but the query matched 0 rows."
        case .moreThanOneRowMatched:
            return "'@SQLQuery'/'@SQLQueries' declared a result of exactly one row, "
                + "but the query matched more than one row."
        }
    }
}
