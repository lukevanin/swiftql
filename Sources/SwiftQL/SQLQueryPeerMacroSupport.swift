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
/// Captures one normalized SQLite value from an `XLBindable` conformer.
///
private struct XLSQLiteValueCaptureContext: XLBindingContext {

    var value: XLSQLiteValue = .null

    mutating func bindNull() {
        self.value = .null
    }

    mutating func bindInteger(value: Int) {
        self.value = .integer(Int64(value))
    }

    mutating func bindReal(value: Double) {
        self.value = .real(value)
    }

    mutating func bindText(value: String) {
        self.value = .text(value)
    }

    mutating func bindBlob(value: Data) {
        self.value = .blob(value)
    }
}


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
    var context: any XLBindingContext = XLSQLiteValueCaptureContext()
    value.bind(context: &context)
    guard let capture = context as? XLSQLiteValueCaptureContext else {
        // `bind(context:)` receives the context `inout`, so a conformer could
        // replace it with a different type. Intrinsic literal conformers never
        // do; fail with a diagnostic that names the offender if one does.
        preconditionFailure(
            "\(T.self).bind(context:) replaced the binding context with "
            + "\(type(of: context)); expected it to write the value into the "
            + "provided XLSQLiteValueCaptureContext."
        )
    }
    let sqliteValue = capture.value
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
        + "executor. Call the macro-generated executor peer instead."
    )
}


///
/// Thrown by a macro-generated executor when the declaration's return
/// annotation requires exactly one row (a bare, non-optional, non-array
/// `Row` result) but the rendered query matched zero rows or more than one.
///
/// No `XLRequest` fetch operation enforces "zero or many is an error" on its
/// own, so the generated executor fetches every matching row and validates
/// the count itself before returning the single element.
///
public enum XLQueryCardinalityError: Error, Equatable, Sendable, LocalizedError {

    case exactlyOneRowExpected(actual: Int)

    public var errorDescription: String? {
        switch self {
        case .exactlyOneRowExpected(0):
            return "'@SQLQuery'/'@SQLQueries' declared a result of exactly one row, "
                + "but the query matched 0 rows."
        case .exactlyOneRowExpected:
            // The executor fetches at most two rows to reject a many-row match cheaply, so any
            // count above 1 here means "more than one" rather than an exact total.
            return "'@SQLQuery'/'@SQLQueries' declared a result of exactly one row, "
                + "but the query matched more than one row."
        }
    }
}
