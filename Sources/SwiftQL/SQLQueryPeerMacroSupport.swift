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
    let sqliteValue = (context as! XLSQLiteValueCaptureContext).value
    if sqliteValue == .null, slot.nullability == .required {
        throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
    }
    return try XLInvocationBinding(slot: slot, value: sqliteValue)
}
