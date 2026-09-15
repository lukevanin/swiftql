//
//  JSONMutation.swift
//
//
//  Milestone v1.6: reading values out of a JSON document, and writing values
//  back into one.
//

import Foundation


///
/// Reading and writing values inside a JSON document.
///
/// See: https://www.sqlite.org/json1.html
///
extension XLExpression {

    // MARK: - Extraction

    ///
    /// Reads the element at `path` as a SQL value, rendering SQLite's
    /// `json_extract(X, P)`.
    ///
    /// The result type is the one the caller states, and it is optional: a
    /// path that matches nothing and a JSON `null` both give SQL `NULL`. An
    /// object or an array has no SQL value, so SQLite returns its JSON text;
    /// ask for `String` in that case.
    ///
    /// This is the single-path form. With more than one path SQLite returns a
    /// JSON array instead of a value, which is a different result type, so
    /// that form is ``jsonExtract(at:_:_:)``.
    ///
    public func jsonExtract<Value>(
        at path: XLJSONPath,
        as _: Value.Type
    ) -> some XLExpression<Value?> where T: XLLiteral, Value: XLLiteral {
        XLFunction<Value?>(name: "json_extract", parameters: [self, path])
    }

    ///
    /// Reads the elements at two or more paths, rendering SQLite's
    /// `json_extract(X, P, ...)`.
    ///
    /// With more than one path SQLite collects the selected elements into a
    /// JSON array, so the result is always JSON text and never a scalar. A
    /// path that matches nothing contributes JSON `null` to the array rather
    /// than removing an entry, so the array always has one entry per path.
    ///
    /// Two paths are required by the signature. One path selects a value, not
    /// an array, and that form is ``jsonExtract(at:as:)``. Requiring two here
    /// means the two result types cannot be confused at the call site.
    ///
    public func jsonExtract(
        at first: XLJSONPath,
        _ second: XLJSONPath,
        _ rest: XLJSONPath...
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(
            name: "json_extract",
            parameters: [self, first, second] + rest
        )
    }

    // MARK: - Mutation

    ///
    /// Adds a value at each path that does not already hold one, rendering
    /// SQLite's `json_insert(X, P, V, ...)`.
    ///
    /// In this function and its siblings, a `Bool` value is written as JSON
    /// `true` or `false`, not `1` or `0`. A `Data` value is rejected before
    /// SQLite prepares the statement unless it is the result of a `jsonb`
    /// function.
    ///
    /// A path that already holds a value is left alone. Use
    /// `jsonSetting(_:_:)` to add or overwrite, and `jsonReplacing(_:_:)`
    /// to overwrite only.
    ///
    /// The result is the whole document, and it is optional because a `NULL`
    /// document gives `NULL`.
    ///
    public func jsonInserting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(
            name: "json_insert",
            parameters: [self] + Self.flattened([first] + rest, function: "json_insert")
        )
    }

    ///
    /// Overwrites the value at each path that already holds one, rendering
    /// SQLite's `json_replace(X, P, V, ...)`.
    ///
    /// A path that holds nothing is left alone.
    ///
    public func jsonReplacing(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(
            name: "json_replace",
            parameters: [self] + Self.flattened([first] + rest, function: "json_replace")
        )
    }

    ///
    /// Writes a value at each path, whether or not one is already there,
    /// rendering SQLite's `json_set(X, P, V, ...)`.
    ///
    public func jsonSetting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(
            name: "json_set",
            parameters: [self] + Self.flattened([first] + rest, function: "json_set")
        )
    }

    ///
    /// Deletes the value at each path, rendering SQLite's
    /// `json_remove(X, P, ...)`.
    ///
    /// SQLite applies the paths from left to right, so a path that names an
    /// array element by index refers to the array as it stands after the
    /// earlier removals.
    ///
    public func jsonRemoving(
        at first: XLJSONPath,
        _ rest: XLJSONPath...
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(
            name: "json_remove",
            parameters: [self, first] + rest
        )
    }

    ///
    /// Applies an RFC 7396 merge patch, rendering SQLite's
    /// `json_patch(X, Y)`.
    ///
    /// A member of `patch` whose value is JSON `null` removes that member from
    /// the document. Every other member is added or overwritten. Arrays are
    /// replaced whole, not merged.
    ///
    public func jsonPatched(
        with patch: any XLExpression
    ) -> some XLExpression<String?> where T: XLLiteral {
        XLFunction<String?>(name: "json_patch", parameters: [self, patch])
    }

    ///
    /// Flattens path/value pairs into the flat argument list SQLite takes.
    ///
    private static func flattened(
        _ assignments: [(XLJSONPath, any XLExpression)],
        function: String
    ) -> [any XLExpression] {
        var parameters: [any XLExpression] = []
        parameters.reserveCapacity(assignments.count * 2)
        for assignment in assignments {
            parameters.append(assignment.0)
            parameters.append(
                XLJSONValueArgument(assignment.1, function: function)
            )
        }
        return parameters
    }
}


///
/// The mutation functions on a document that is not `NULL`.
///
/// SQLite returns `NULL` from `json_insert`, `json_replace`, `json_set`, and
/// `json_remove` only when the document is `NULL`, with one exception:
/// `json_remove` also returns `NULL` when it removes the root, `$`. A
/// malformed document is an error, not `NULL`, and a `NULL` value is written
/// as JSON `null`. So when the document's type is `String`, the result is
/// `String` too, and it assigns to a `NOT NULL` column without `coalesce`.
///
/// A `String?` document keeps the optional result. `jsonPatched(with:)` has
/// no form here, because a `NULL` patch also gives `NULL`.
///
extension XLExpression where T == String {

    ///
    /// Adds a value at each path that does not already hold one, rendering
    /// SQLite's `json_insert(X, P, V, ...)`.
    ///
    /// The document is not `NULL`, so the result is not either.
    ///
    public func jsonInserting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String> {
        XLFunction<String>(
            name: "json_insert",
            parameters: [self] + Self.flattened([first] + rest, function: "json_insert")
        )
    }

    ///
    /// Overwrites the value at each path that already holds one, rendering
    /// SQLite's `json_replace(X, P, V, ...)`.
    ///
    /// The document is not `NULL`, so the result is not either.
    ///
    public func jsonReplacing(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String> {
        XLFunction<String>(
            name: "json_replace",
            parameters: [self] + Self.flattened([first] + rest, function: "json_replace")
        )
    }

    ///
    /// Writes a value at each path, whether or not one is already there,
    /// rendering SQLite's `json_set(X, P, V, ...)`.
    ///
    /// The document is not `NULL`, so the result is not either.
    ///
    public func jsonSetting(
        _ first: (XLJSONPath, any XLExpression),
        _ rest: (XLJSONPath, any XLExpression)...
    ) -> some XLExpression<String> {
        XLFunction<String>(
            name: "json_set",
            parameters: [self] + Self.flattened([first] + rest, function: "json_set")
        )
    }

    ///
    /// Deletes the value at each path, rendering SQLite's
    /// `json_remove(X, P, ...)`.
    ///
    /// SQLite returns `NULL` when it removes the root, so a root path is
    /// reported as ``XLSQLValueEncodingError/jsonRootRemoval(function:)``
    /// before SQLite prepares the statement. Every other path leaves a
    /// document, so the result is not `NULL`.
    ///
    public func jsonRemoving(
        at first: XLJSONPath,
        _ rest: XLJSONPath...
    ) -> some XLExpression<String> {
        XLFunction<String>(
            name: "json_remove",
            parameters: [self] + XLJSONRemovedPath.wrapping([first] + rest, function: "json_remove")
        )
    }
}


///
/// A path passed to the non-optional `json_remove` or `jsonb_remove`.
///
/// Removing the root gives SQL `NULL`, which the non-optional result type
/// cannot hold, so the root path is reported as an encoding error. Every
/// other path renders exactly as ``XLJSONPath`` does.
///
struct XLJSONRemovedPath: XLExpression {

    typealias T = String

    private let path: XLJSONPath

    private let function: String

    static func wrapping(
        _ paths: [XLJSONPath],
        function: String
    ) -> [any XLExpression] {
        paths.map { XLJSONRemovedPath(path: $0, function: function) }
    }

    func makeSQL(context: inout XLBuilder) {
        if path == .root {
            context.valueEncodingFailed(.jsonRootRemoval(function: function))
        }
        path.makeSQL(context: &context)
    }
}
