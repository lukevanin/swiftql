//
//  JSONBFunctions.swift
//
//
//  Milestone v1.6: SQLite's binary JSON representation, JSONB, added in
//  SQLite 3.45.0.
//

import Foundation


///
/// SQLite's JSONB functions.
///
/// JSONB is JSON stored as a BLOB in SQLite's own parsed form. Reading a JSONB
/// value costs no reparsing, which is the reason to store JSON in a database
/// rather than beside it. Every function here needs **SQLite 3.45.0 or
/// later**.
///
/// Each function is the twin of a JSON function that returns JSON text, and
/// returns the binary form instead. The functions that return a SQL value
/// rather than JSON have no twin, because their result is not JSON:
/// `json_type`, `json_valid`, `json_array_length`, `json_quote`,
/// `json_error_position`, and `json_pretty` read a JSONB input directly and
/// keep their own result types. That was confirmed against
/// `pragma function_list` on SQLite 3.51.0, which lists eleven `jsonb_`
/// functions and no `jsonb_type`, `jsonb_valid`, `jsonb_array_length`,
/// `jsonb_quote`, `jsonb_error_position`, or `jsonb_pretty`.
///
/// See: https://www.sqlite.org/json1.html#jsonb
///
extension XLExpression {

    ///
    /// Converts the input to JSONB, rendering SQLite's `jsonb(X)`.
    ///
    /// A `NULL` input gives `NULL`, which is why the result is optional.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func minifiedJSONB() -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(name: "jsonb", parameters: [self])
    }

    ///
    /// Reads the element at `path`, rendering SQLite's
    /// `jsonb_extract(X, P)`.
    ///
    /// The result type follows the selected element, exactly as it does for
    /// ``jsonExtract(at:as:)``. The difference is what happens to an object or
    /// an array: `json_extract` returns its JSON text, and `jsonb_extract`
    /// returns it as JSONB, so ask for `Data` in that case.
    ///
    /// The result is optional: a path that matches nothing and a JSON `null`
    /// both give SQL `NULL`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbExtract<Value>(
        at path: XLJSONPath,
        as _: Value.Type
    ) -> some XLExpression<Value?> where T: XLLiteral, Value: XLLiteral {
        XLFunction<Value?>(name: "jsonb_extract", parameters: [self, path])
    }

    ///
    /// Reads the elements at two or more paths, rendering SQLite's
    /// `jsonb_extract(X, P, ...)`.
    ///
    /// With more than one path SQLite collects the selected elements into an
    /// array, and returns it as JSONB. Two paths are required by the
    /// signature, for the same reason as ``jsonExtract(at:_:_:)``.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbExtract(
        at first: XLJSONPath,
        _ second: XLJSONPath,
        _ rest: XLJSONPath...
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(
            name: "jsonb_extract",
            parameters: [self, first, second] + rest
        )
    }

    ///
    /// Adds a value at each path that does not already hold one, rendering
    /// SQLite's `jsonb_insert(X, P, V, ...)`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbInserting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(
            name: "jsonb_insert",
            parameters: [self] + Self.flattenedJSONBAssignments([first] + rest)
        )
    }

    ///
    /// Overwrites the value at each path that already holds one, rendering
    /// SQLite's `jsonb_replace(X, P, V, ...)`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbReplacing(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(
            name: "jsonb_replace",
            parameters: [self] + Self.flattenedJSONBAssignments([first] + rest)
        )
    }

    ///
    /// Writes a value at each path, whether or not one is already there,
    /// rendering SQLite's `jsonb_set(X, P, V, ...)`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbSetting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(
            name: "jsonb_set",
            parameters: [self] + Self.flattenedJSONBAssignments([first] + rest)
        )
    }

    ///
    /// Deletes the value at each path, rendering SQLite's
    /// `jsonb_remove(X, P, ...)`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbRemoving(
        at first: XLJSONPath,
        _ rest: XLJSONPath...
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(
            name: "jsonb_remove",
            parameters: [self, first] + rest
        )
    }

    ///
    /// Applies an RFC 7396 merge patch, rendering SQLite's
    /// `jsonb_patch(X, Y)`.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbPatched(
        with patch: any XLExpression
    ) -> some XLExpression<Data?> where T: XLLiteral {
        XLFunction<Data?>(name: "jsonb_patch", parameters: [self, patch])
    }

    ///
    /// Collects every input row into a JSONB array, rendering SQLite's
    /// `jsonb_group_array(X)`.
    ///
    /// The result is never SQL `NULL`: an empty group gives an empty array.
    ///
    /// It is not always a BLOB, though. SQLite 3.51.0 returns the two text
    /// characters `[]` for an empty group rather than the JSONB encoding of
    /// an empty array, and which form arrives is an engine detail rather than
    /// a promise. Every JSON function accepts both, so this matters only to
    /// code that inspects the bytes.
    ///
    /// Needs SQLite 3.45.0 or later.
    ///
    public func jsonbGroupArray(
        distinct: Bool = false
    ) -> some XLExpression<Data> where T: XLLiteral {
        XLFunction<Data>(
            name: "jsonb_group_array",
            distinct: distinct,
            parameters: [self]
        )
    }

    ///
    /// Flattens path/value pairs into the flat argument list SQLite takes.
    ///
    private static func flattenedJSONBAssignments(
        _ assignments: [(XLJSONPath, any XLExpression)]
    ) -> [any XLExpression] {
        var parameters: [any XLExpression] = []
        parameters.reserveCapacity(assignments.count * 2)
        for assignment in assignments {
            parameters.append(assignment.0)
            parameters.append(assignment.1)
        }
        return parameters
    }
}


///
/// Builds a JSONB array from `elements`, rendering SQLite's
/// `jsonb_array(...)`.
///
/// Needs SQLite 3.45.0 or later.
///
public func jsonbArray(_ elements: any XLExpression...) -> some XLExpression<Data> {
    XLFunction<Data>(name: "jsonb_array", parameters: elements)
}


///
/// Builds a JSONB array from `elements`, rendering SQLite's
/// `jsonb_array(...)`.
///
/// Needs SQLite 3.45.0 or later.
///
public func jsonbArray(_ elements: [any XLExpression]) -> some XLExpression<Data> {
    XLFunction<Data>(name: "jsonb_array", parameters: elements)
}


///
/// Builds a JSONB object from `members`, rendering SQLite's
/// `jsonb_object(...)`.
///
/// Each member is a pair, for the same reason as `jsonObject`: an incomplete
/// member cannot be written, so SQLite's even-argument error cannot be
/// reached from Swift.
///
/// Needs SQLite 3.45.0 or later.
///
public func jsonbObject(
    _ members: (any XLExpression<String>, any XLExpression)...
) -> some XLExpression<Data> {
    jsonbObject(members)
}


///
/// Builds a JSONB object from `members`, rendering SQLite's
/// `jsonb_object(...)`.
///
/// Needs SQLite 3.45.0 or later.
///
public func jsonbObject(
    _ members: [(any XLExpression<String>, any XLExpression)]
) -> some XLExpression<Data> {
    var parameters: [any XLExpression] = []
    parameters.reserveCapacity(members.count * 2)
    for member in members {
        parameters.append(member.0)
        parameters.append(member.1)
    }
    return XLFunction<Data>(name: "jsonb_object", parameters: parameters)
}


///
/// Collects `name`/`value` pairs into a JSONB object, rendering SQLite's
/// `jsonb_group_object(N, V)`.
///
/// There is no `distinct` parameter, for the same reason as
/// ``jsonGroupObject(name:value:)``: SQLite allows `DISTINCT` only on an
/// aggregate with exactly one argument.
///
/// Needs SQLite 3.45.0 or later.
///
public func jsonbGroupObject(
    name: any XLExpression<String>,
    value: any XLExpression
) -> some XLExpression<Data> {
    XLFunction<Data>(name: "jsonb_group_object", parameters: [name, value])
}
