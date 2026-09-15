//
//  JSONFunctions.swift
//
//

import Foundation


// MARK: - Validation flags


///
/// The flag set SQLite's `json_valid(X, F)` accepts as its second argument.
///
/// Each member names one bit of SQLite's mask. An empty set is not a valid
/// argument, so ``XLExpression/validJSONOrNull(flags:)`` treats it as
/// ``json``, which is what SQLite uses when the argument is left out.
///
/// The two-argument form of `json_valid` needs SQLite 3.45.0 or later.
///
/// See: https://www.sqlite.org/json1.html#jvalid
///
public struct XLJSONValidationFlags: OptionSet, Hashable, Sendable {

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The input is JSON text that conforms to RFC 8259. SQLite's default.
    public static let json = XLJSONValidationFlags(rawValue: 0x01)

    /// The input is JSON5 text.
    public static let json5 = XLJSONValidationFlags(rawValue: 0x02)

    /// The input is a JSONB blob, checked only superficially. A blob that
    /// passes this check can still be malformed deeper inside.
    public static let jsonbShallow = XLJSONValidationFlags(rawValue: 0x04)

    /// The input is a JSONB blob, checked completely.
    public static let jsonbStrict = XLJSONValidationFlags(rawValue: 0x08)
}


// MARK: - JSON values


///
/// A value that a JSON function writes into a document.
///
/// SQLite has no boolean, so a Swift `Bool` reaches it as the integer `0` or
/// `1`, and `json_set(X, P, true)` stores the number `1`. A `Codable` reader
/// of a `Bool` field then throws. This wrapper renders a `Bool` literal as
/// `json('true')` or `json('false')`, and any other `Bool` expression as
/// `json(CASE (X) <> 0 WHEN 1 THEN 'true' WHEN 0 THEN 'false' END)`, which
/// reads `X` once and keeps SQL `NULL` as JSON `null`.
///
/// SQLite also has no JSON form for a blob: it reports
/// `JSON cannot hold BLOB values`, or reads the bytes as a document when they
/// happen to be valid JSONB. A `Data` value is therefore reported as
/// ``XLSQLValueEncodingError/blobInJSONValue(valueType:function:)`` before
/// SQLite prepares the statement, unless it is the result of a `jsonb`
/// function, which is how a JSONB document is nested on purpose.
///
/// Every other value renders exactly as it did before.
///
struct XLJSONValueArgument: XLExpression {

    typealias T = String?

    private let value: any XLExpression

    private let function: String

    init(_ value: any XLExpression, function: String) {
        self.value = value
        self.function = function
    }

    static func wrapping(
        _ values: [any XLExpression],
        function: String
    ) -> [any XLExpression] {
        values.map { XLJSONValueArgument($0, function: function) }
    }

    func makeSQL(context: inout XLBuilder) {
        if let literal = value as? Bool {
            XLFunction<String?>(
                name: "json",
                parameters: [literal ? "true" : "false"]
            )
            .makeSQL(context: &context)
            return
        }
        let valueType = Self.valueType(of: value)
        if valueType == Bool.self || valueType == Bool?.self {
            makeBooleanSQL(context: &context)
            return
        }
        if valueType == Data.self || valueType == Data?.self {
            let isJSONB = (value as? any XLNamedFunction)?
                .functionName
                .hasPrefix("jsonb") ?? false
            if !isJSONB {
                context.valueEncodingFailed(
                    .blobInJSONValue(
                        valueType: String(describing: valueType),
                        function: function
                    )
                )
            }
        }
        value.makeSQL(context: &context)
    }

    private func makeBooleanSQL(context: inout XLBuilder) {
        let value = value
        context.simpleFunction(name: "json") { list in
            list.listItem { context in
                context.block(
                    beginsWith: "CASE",
                    endsWith: "END",
                    separator: .tuple
                ) { context in
                    context.binaryOperator(
                        "<>",
                        left: value.makeSQL,
                        right: { $0.integer(0) }
                    )
                    context.unaryPrefix("WHEN") { $0.integer(1) }
                    context.unaryPrefix("THEN") { $0.text("true") }
                    context.unaryPrefix("WHEN") { $0.integer(0) }
                    context.unaryPrefix("THEN") { $0.text("false") }
                }
            }
        }
    }

    private static func valueType<Value>(
        of value: Value
    ) -> Any.Type where Value: XLExpression {
        Value.T.self
    }
}


// MARK: - Constructors


///
/// Builds a JSON array from `elements`, rendering SQLite's `json_array(...)`.
///
/// An element that is SQL `NULL` becomes JSON `null`, so the result is never
/// `NULL`. An element that is already JSON text becomes a quoted string, not
/// a nested structure; wrap it in ``XLExpression/minifiedJSON()`` to nest it.
///
/// A `Bool` element becomes JSON `true` or `false`, not `1` or `0`. A `Data`
/// element is rejected before SQLite prepares the statement unless it is the
/// result of a `jsonb` function.
///
/// See: https://www.sqlite.org/json1.html#jarray
///
public func jsonArray(_ elements: any XLExpression...) -> some XLExpression<String> {
    jsonArray(elements)
}


///
/// Builds a JSON array from `elements`, rendering SQLite's `json_array(...)`.
///
public func jsonArray(_ elements: [any XLExpression]) -> some XLExpression<String> {
    XLFunction<String>(
        name: "json_array",
        parameters: XLJSONValueArgument.wrapping(elements, function: "json_array")
    )
}


///
/// Builds a JSON object from `members`, rendering SQLite's
/// `json_object(...)`.
///
/// SQLite takes the members as a flat list and reports
/// `json_object() requires an even number of arguments` when one is left
/// incomplete. Taking each member as a pair means an incomplete member cannot
/// be written at all, so that error cannot reach SQLite from here.
///
/// A value that is SQL `NULL` becomes JSON `null`, so the result is never
/// `NULL`. A `Bool` value becomes JSON `true` or `false`, not `1` or `0`. A
/// `Data` value is rejected before SQLite prepares the statement unless it
/// is the result of a `jsonb` function.
///
/// ```swift
/// jsonObject(("name", person.name), ("age", person.age))
/// ```
///
/// See: https://www.sqlite.org/json1.html#jobj
///
public func jsonObject(
    _ members: (any XLExpression<String>, any XLExpression)...
) -> some XLExpression<String> {
    jsonObject(members)
}


///
/// Builds a JSON object from `members`, rendering SQLite's
/// `json_object(...)`.
///
public func jsonObject(
    _ members: [(any XLExpression<String>, any XLExpression)]
) -> some XLExpression<String> {
    var parameters: [any XLExpression] = []
    parameters.reserveCapacity(members.count * 2)
    for member in members {
        parameters.append(member.0)
        parameters.append(XLJSONValueArgument(member.1, function: "json_object"))
    }
    return XLFunction<String>(name: "json_object", parameters: parameters)
}


// MARK: - Scalar functions


/// See: https://www.sqlite.org/json1.html
///
extension XLExpression {

    ///
    /// Validates the input and returns it minified, rendering SQLite's
    /// `json(X)`.
    ///
    /// Whitespace between tokens is removed. A `NULL` input gives `NULL`,
    /// which is why the result is optional.
    ///
    /// Use this to nest a value that is already JSON inside `jsonArray` or
    /// `jsonObject`, which otherwise treat JSON text as a plain string.
    ///
    /// Those two names are written in code font rather than as symbol links:
    /// each has a variadic and an array overload, and DocC rejects a link
    /// that matches both.
    ///
    public func minifiedJSON() -> some XLExpression<String?> where T: XLLiteral {
        XLFunction(name: "json", parameters: [self])
    }

    ///
    /// Renders the input with indentation, rendering SQLite's
    /// `json_pretty(X)`.
    ///
    /// Needs SQLite 3.46.0 or later. A `NULL` input gives `NULL`.
    ///
    public func prettyJSON() -> some XLExpression<String?> where T: XLLiteral {
        XLFunction(name: "json_pretty", parameters: [self])
    }

    ///
    /// Converts a SQL value to its JSON form, rendering SQLite's
    /// `json_quote(X)`.
    ///
    /// A string is quoted and escaped, a number is left as it is, and SQL
    /// `NULL` becomes JSON `null`. The result is therefore never `NULL`.
    ///
    public func jsonQuoted() -> some XLExpression<String> where T: XLLiteral {
        XLFunction(name: "json_quote", parameters: [self])
    }

    ///
    /// Reports the JSON type at the root of the input, rendering SQLite's
    /// `json_type(X)`.
    ///
    /// The result is one of `object`, `array`, `integer`, `real`, `true`,
    /// `false`, `text`, or `null`. A `NULL` input gives `NULL`.
    ///
    public func jsonType() -> some XLExpression<String?> where T: XLLiteral {
        XLFunction(name: "json_type", parameters: [self])
    }

    ///
    /// Reports the JSON type at `path`, rendering SQLite's
    /// `json_type(X, P)`.
    ///
    /// A path that matches nothing gives `NULL`, which is why the result is
    /// optional. Note that a path selecting a JSON `null` gives the string
    /// `null`, not SQL `NULL`.
    ///
    public func jsonType(at path: XLJSONPath) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction(name: "json_type", parameters: [self, path])
    }

    ///
    /// Reports where the input first fails to parse as JSON, rendering
    /// SQLite's `json_error_position(X)`.
    ///
    /// The result is zero when the input parses, and the one-based character
    /// position of the first fault when it does not. A `NULL` input gives
    /// `NULL`.
    ///
    /// Needs SQLite 3.42.0 or later.
    ///
    public func jsonErrorPosition() -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_error_position", parameters: [self])
    }

    ///
    /// Reports whether the input is well-formed JSON, rendering SQLite's
    /// `json_valid(X)`.
    ///
    /// A `NULL` input gives `NULL`, not false, which is why the result is
    /// optional.
    ///
    /// This form checks JSON text only. A JSONB blob reports false, even a
    /// well-formed one. Use ``validJSONOrJSONBOrNull()`` for a value that can
    /// be JSONB.
    ///
    public func validJSONOrNull() -> some XLExpression<Bool?> where T: XLLiteral {
        XLFunction(name: "json_valid", parameters: [self])
    }

    ///
    /// Reports whether the input is well-formed JSON text or a well-formed
    /// JSONB blob, rendering SQLite's `json_valid(X, 9)`.
    ///
    /// The flag is ``XLJSONValidationFlags/json`` combined with
    /// ``XLJSONValidationFlags/jsonbStrict``. SQLite checks text as RFC 8259
    /// JSON and a blob completely as JSONB, so this is the check to use in a
    /// `CHECK` constraint on a column that can hold JSONB. A `NULL` input
    /// gives `NULL`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func validJSONOrJSONBOrNull() -> some XLExpression<Bool?> where T: XLLiteral {
        validJSONOrNull(flags: [.json, .jsonbStrict])
    }

    ///
    /// Reports whether the input is well-formed under `flags`, rendering
    /// SQLite's `json_valid(X, F)`.
    ///
    /// An empty flag set is not a valid argument to SQLite, so it renders as
    /// ``XLJSONValidationFlags/json``, which is what SQLite uses when the
    /// argument is left out.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func validJSONOrNull(
        flags: XLJSONValidationFlags
    ) -> some XLExpression<Bool?> where T: XLLiteral {
        let resolved = flags.isEmpty ? XLJSONValidationFlags.json : flags
        return XLFunction<Bool?>(
            name: "json_valid",
            parameters: [self, resolved.rawValue]
        )
    }

    ///
    /// Returns the number of elements in the array at the root of the input,
    /// rendering SQLite's `json_array_length(X)`.
    ///
    /// A root that is not an array gives `0`, not `NULL`. A `NULL` input
    /// gives `NULL`.
    ///
    public func jsonArrayLength() -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self])
    }

    ///
    /// Returns the number of elements in the array at `path`, rendering
    /// SQLite's `json_array_length(X, P)`.
    ///
    /// A path that selects a value that is not an array gives `0`. Only a
    /// path that selects nothing, or a `NULL` input, gives `NULL`.
    ///
    public func jsonArrayLength(path: String) -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self, path])
    }

    ///
    /// Returns the number of elements in the array at `path`, rendering
    /// SQLite's `json_array_length(X, P)`.
    ///
    /// A path that selects a value that is not an array gives `0`. Only a
    /// path that selects nothing, or a `NULL` input, gives `NULL`.
    ///
    public func jsonArrayLength(path: XLJSONPath) -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self, path])
    }

    @available(*, deprecated, message: "SQLite json_valid returns NULL for a NULL input. Use validJSONOrNull() instead. validJSON() will return an optional expression in SwiftQL 2.")
    public func validJSON() -> some XLExpression<Bool> where T: XLLiteral {
        XLFunction(name: "json_valid", parameters: [self])
    }

}
