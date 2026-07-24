//
//  SQLQueryPeerMacroSupport.swift
//  SwiftQL
//
//  Spike (#359): runtime support for `@SQLQuery` macro-generated executors.
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
/// Spike (#359) support for `@SQLQuery` macro-generated executors. The macro
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
/// The trapping direct-result entry point for `@SQLQuery` specifications.
///
/// Spike (#369): a `@SQLQuery` spec written with a direct result type
/// (`[Row]` / `Row?`) calls this instead of `sql {}` so the function
/// type-checks without the `XLQueryStatement` return-type boilerplate. `Result`
/// appears only in return position, so it is inferred from the enclosing
/// function's declared return type — one entry point satisfies both
/// cardinalities with no overload ambiguity.
///
/// This function is only a type-check anchor and a syntax source for the macro;
/// invoking it directly traps loudly, because the real work happens in the
/// macro-generated executor peer. The macro rewrites this callee back to
/// `sql {}` when it emits the value-free statement builder.
///
/// The name is provisional (per #26, generated and entry-point names are not
/// frozen) — `sqlQuery` is already the labeled-closure statement builder in
/// `SQLFunctionalSyntax.swift`, so the direct-result anchor needs its own name.
///
public func sqlResult<Row, Result>(
    @XLQueryExpressionBuilder _ builder: (XLSchema) -> any XLQueryStatement<Row>
) -> Result {
    fatalError(
        "'sqlResult' marks a @SQLQuery specification, not an executor. "
        + "Call the generated executor peer (e.g. fetchPersonByName) instead."
    )
}
