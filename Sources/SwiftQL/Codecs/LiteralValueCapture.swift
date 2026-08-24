//
//  LiteralValueCapture.swift
//  SwiftQL
//
//  The one place a Swift value written through `XLBindable.bind(context:)` is
//  captured as a normalized `XLSQLiteValue` (issue #554). Four byte-identical
//  private capture contexts used to do this, three of them recovering the
//  written value with a force cast.
//

import Foundation


///
/// Captures the single normalized SQLite value an `XLBindable` conformer writes
/// through its binding context.
///
/// Every capture path in SwiftQL shares this type, so the mapping from a bound
/// Swift value to an ``XLSQLiteValue`` is defined exactly once.
///
struct XLSQLiteValueCapture: XLBindingContext {

    var value: XLSQLiteValue = .null

    mutating func bindNull() {
        value = .null
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
/// Runs `bind` against a fresh ``XLSQLiteValueCapture`` and returns the value it
/// wrote.
///
/// `bind(context:)` receives its context `inout` as an existential, so a
/// conformer is free to replace it with a context of another type. Intrinsic
/// literal conformers never do. If one does, the value it wrote is unreachable
/// and there is no correct value to return, so this traps -- as the force casts
/// it replaces did -- but names the offending type instead of reporting an
/// unexplained cast failure.
///
/// - Parameters:
///   - valueType: Names the conformer in the diagnostic. Evaluated only when
///     the context was replaced.
///   - bind: Writes one value into the provided context.
func _xlCapturedSQLiteValue(
    of valueType: @autoclosure () -> String,
    bind: (inout any XLBindingContext) -> Void
) -> XLSQLiteValue {
    var context: any XLBindingContext = XLSQLiteValueCapture()
    bind(&context)
    guard let capture = context as? XLSQLiteValueCapture else {
        preconditionFailure(
            "\(valueType()).bind(context:) replaced the binding context with "
            + "\(type(of: context)); expected it to write the value into the "
            + "provided XLSQLiteValueCapture."
        )
    }
    return capture.value
}


///
/// Captures `value` as a normalized SQLite value, rejecting one that SQLite
/// would silently store as something other than what was bound.
///
/// SQLite's binding API turns an IEEE 754 NaN into SQL `NULL`. SwiftQL treats
/// that as an error rather than a silent change of meaning, so a NaN `REAL`
/// throws ``XLSQLValueEncodingError/realBindingWouldBecomeNull(value:valueType:context:)``
/// here, at the point of capture, for every path that binds a value. Infinities
/// survive the round trip and are captured unchanged. See
/// <doc:RealValues>.
///
/// - Parameters:
///   - value: The Swift value to capture.
///   - valueType: The value's type name, as it appears in the thrown error.
///   - codingContext: The parameter or property the value is bound for, as it
///     appears in the thrown error.
func _xlCaptureSQLiteValue<T>(
    _ value: T,
    valueType: @autoclosure () -> String,
    codingContext: @autoclosure () -> XLValueCodingContext
) throws -> XLSQLiteValue where T: XLBindable {
    let captured = _xlCapturedSQLiteValue(of: valueType()) { context in
        value.bind(context: &context)
    }
    if case .real(let real) = captured,
       let error = XLSQLValueEncodingError.bindingFailure(
           for: real,
           valueType: valueType(),
           context: codingContext()
       ) {
        throw error
    }
    return captured
}
