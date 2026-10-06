//
//  AggregateFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


/// The unqualified all-columns expression rendered as `*`.
///
/// Use all() with count(_:) to count every input row.
public struct XLAllColumns: XLExpression {

    public typealias T = XLAllColumns

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
        context.block(
            beginsWith: "*",
            endsWith: "",
            separator: .elided
        ) { _ in
        }
    }
}


/// Returns the unqualified all-columns expression rendered as `*`.
public func all() -> XLAllColumns {
    XLAllColumns()
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
