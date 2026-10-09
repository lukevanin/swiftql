//
//  AggregateFunctions+SQLite.swift
//
//  SQLite's own aggregates: TOTAL, GROUP_CONCAT, and the JSON aggregates.
//  Split from AggregateFunctions.swift, whose all-columns expression is
//  every dialect's (issue #790).
//

import Foundation


// MARK: - SQLite aggregates

// SQLite's own: `TOTAL` and `GROUP_CONCAT`. Declared only on a SQLite expression, not generated
// for every dialect (issue #789).

extension XLSQLiteExpression {

    /// Returns the floating-point total of the non-NULL numeric values.
    ///
    /// Unlike `SUM`, SQLite `TOTAL` returns `0.0` for an empty input or an all-NULL group.
    public func total(distinct: Bool = false) -> some XLSQLiteExpression<Double> where T: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Returns the floating-point total of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// SQLite returns `0.0` when no non-NULL input remains.
    public func total<Wrapped>(distinct: Bool = false) -> some XLSQLiteExpression<Double> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values, or returns NULL when the input is empty or contains no non-NULL values.
    public func groupConcatOrNull(distinct: Bool = false) -> some XLSQLiteExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(distinct:) instead. groupConcat() will return an optional expression in SwiftQL 2.")
    public func groupConcat(distinct: Bool = false) -> some XLSQLiteExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values using a separator, or returns NULL when no non-NULL values exist.
    public func groupConcatOrNull(separator: String) -> some XLSQLiteExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", parameters: [self, separator])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(separator:) instead. groupConcat(separator:) will return an optional expression in SwiftQL 2.")
    public func groupConcat(separator: String) -> some XLSQLiteExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", parameters: [self, separator])
    }
}


// MARK: - JSON aggregates


/// SQLite's two JSON aggregates.
///
/// See: https://www.sqlite.org/json1.html#jgrouparray
///
extension XLSQLiteExpression {

    ///
    /// Collects every input row into a JSON array, rendering SQLite's
    /// `json_group_array(X)`.
    ///
    /// An empty group gives `[]`, not SQL `NULL`, so the result is not
    /// optional. A row whose value is SQL `NULL` contributes JSON `null`, so
    /// the array always has one entry per row.
    ///
    /// A value that is already JSON text is collected as a quoted string, not
    /// as a nested structure. Pass it through ``XLSQLiteExpression/minifiedJSON()``
    /// first to nest it.
    ///
    /// A `Bool` value is collected as JSON `true` or `false`, not `1` or `0`.
    /// A `Data` value is rejected before SQLite prepares the statement unless
    /// it is the result of a `jsonb` function.
    ///
    public func jsonGroupArray(
        distinct: Bool = false
    ) -> some XLSQLiteExpression<String> where T: XLLiteral {
        XLFunction<String>(
            name: "json_group_array",
            distinct: distinct,
            parameters: [XLJSONValueArgument(self, function: "json_group_array")]
        )
    }
}


///
/// Collects `name`/`value` pairs into a JSON object, rendering SQLite's
/// `json_group_object(N, V)`.
///
/// An empty group gives `{}`, not SQL `NULL`, so the result is not optional.
///
/// SQLite does not deduplicate names: two rows with the same name give an
/// object with that name twice.
///
/// A row whose name is SQL `NULL` contributes nothing at all, so the object
/// can have fewer members than the group has rows. `name` is a non-optional
/// text expression, so a nullable column cannot be passed here; that case
/// arises only when a column SQLite does not constrain holds `NULL` at run
/// time, which is why the behaviour is documented rather than pinned by a
/// test this signature cannot express.
///
/// There is no `distinct` parameter. SQLite reports
/// `DISTINCT aggregates must have exactly one argument`, and this aggregate
/// takes two.
///
public func jsonGroupObject(
    name: any XLSQLiteExpression<String>,
    value: any XLSQLiteExpression
) -> some XLSQLiteExpression<String> {
    XLFunction<String>(
        name: "json_group_object",
        parameters: [
            name,
            XLJSONValueArgument(value, function: "json_group_object"),
        ]
    )
}
