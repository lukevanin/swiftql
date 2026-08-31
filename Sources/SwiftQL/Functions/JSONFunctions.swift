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


// MARK: - Constructors


///
/// Builds a JSON array from `elements`, rendering SQLite's `json_array(...)`.
///
/// An element that is SQL `NULL` becomes JSON `null`, so the result is never
/// `NULL`. An element that is already JSON text becomes a quoted string, not
/// a nested structure; wrap it in ``XLExpression/minifiedJSON()`` to nest it.
///
/// See: https://www.sqlite.org/json1.html#jarray
///
public func jsonArray(_ elements: any XLExpression...) -> some XLExpression<String> {
    XLFunction<String>(name: "json_array", parameters: elements)
}


///
/// Builds a JSON array from `elements`, rendering SQLite's `json_array(...)`.
///
public func jsonArray(_ elements: [any XLExpression]) -> some XLExpression<String> {
    XLFunction<String>(name: "json_array", parameters: elements)
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
/// `NULL`.
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
        parameters.append(member.1)
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
    public func validJSONOrNull() -> some XLExpression<Bool?> where T: XLLiteral {
        XLFunction(name: "json_valid", parameters: [self])
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
    /// or `NULL` when the input is not an array.
    ///
    public func jsonArrayLength() -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self])
    }

    ///
    /// Returns the number of elements in the array at `path`, or `NULL` when
    /// the path selects nothing or selects a value that is not an array.
    ///
    public func jsonArrayLength(path: String) -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self, path])
    }

    ///
    /// Returns the number of elements in the array at `path`, or `NULL` when
    /// the path selects nothing or selects a value that is not an array.
    ///
    public func jsonArrayLength(path: XLJSONPath) -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self, path])
    }

    @available(*, deprecated, message: "SQLite json_valid returns NULL for a NULL input. Use validJSONOrNull() instead. validJSON() will return an optional expression in SwiftQL 2.")
    public func validJSON() -> some XLExpression<Bool> where T: XLLiteral {
        XLFunction(name: "json_valid", parameters: [self])
    }

}
