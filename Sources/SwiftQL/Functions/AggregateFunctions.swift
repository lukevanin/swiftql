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


@available(*, deprecated, message: "Use all().count() instead. count(_:) will be removed in SwiftQL 2.")
public func count(
    _ expression: any XLExpression<XLAllColumns>
) -> some XLExpression<Int> {
    XLFunction<Int>(name: "COUNT", parameters: [expression])
}


extension XLExpression where T == XLAllColumns {

    /// Counts every input row by rendering `COUNT(*)`.
    public func count() -> some XLExpression<Int> {
        XLFunction<Int>(name: "COUNT", parameters: [self])
    }
}


/// See: https://www.sqlite.org/lang_aggfunc.html
///
extension XLExpression {
    
    public func count(distinct: Bool = false) -> some XLExpression<Int> where T: XLLiteral {
        XLFunction(name: "COUNT", distinct: distinct, parameters: [self])
    }


    /// Returns the minimum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    public func minOrNull(distinct: Bool = false) -> some XLExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MIN", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MIN can return NULL. Use minOrNull(distinct:) instead. min() will return an optional expression in SwiftQL 2.")
    public func min(distinct: Bool = false) -> some XLExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MIN", distinct: distinct, parameters: [self])
    }


    /// Returns the maximum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    public func maxOrNull(distinct: Bool = false) -> some XLExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MAX", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MAX can return NULL. Use maxOrNull(distinct:) instead. max() will return an optional expression in SwiftQL 2.")
    public func max(distinct: Bool = false) -> some XLExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MAX", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, or NULL when the input is empty or contains no non-NULL values.
    ///
    /// SQLite computes `AVG` as a floating-point value for both integer and real inputs.
    public func averageOrNull(distinct: Bool = false) -> some XLExpression<Double?> where T: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// The result remains optional because SQLite returns NULL for an empty input or an all-NULL group.
    public func averageOrNull<Wrapped>(distinct: Bool = false) -> some XLExpression<Double?> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite AVG can return NULL. Use averageOrNull(distinct:) instead. average() will return an optional expression in SwiftQL 2.")
    public func average(distinct: Bool = false) -> some XLExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the sum of the non-NULL values, or NULL when the input is empty or contains no non-NULL values.
    public func sumOrNull(distinct: Bool = false) -> some XLExpression<T?> where T: Numeric & XLLiteral {
        XLFunction<T?>(name: "SUM", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite SUM can return NULL. Use sumOrNull(distinct:) instead. sum() will return an optional expression in SwiftQL 2.")
    public func sum(distinct: Bool = false) -> some XLExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "SUM", distinct: distinct, parameters: [self])
    }


    /// Returns the floating-point total of the non-NULL numeric values.
    ///
    /// Unlike `SUM`, SQLite `TOTAL` returns `0.0` for an empty input or an all-NULL group.
    public func total(distinct: Bool = false) -> some XLExpression<Double> where T: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Returns the floating-point total of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// SQLite returns `0.0` when no non-NULL input remains.
    public func total<Wrapped>(distinct: Bool = false) -> some XLExpression<Double> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values, or returns NULL when the input is empty or contains no non-NULL values.
    public func groupConcatOrNull(distinct: Bool = false) -> some XLExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(distinct:) instead. groupConcat() will return an optional expression in SwiftQL 2.")
    public func groupConcat(distinct: Bool = false) -> some XLExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values using a separator, or returns NULL when no non-NULL values exist.
    public func groupConcatOrNull(separator: String) -> some XLExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", parameters: [self, separator])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(separator:) instead. groupConcat(separator:) will return an optional expression in SwiftQL 2.")
    public func groupConcat(separator: String) -> some XLExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", parameters: [self, separator])
    }
}


// MARK: - JSON aggregates


/// SQLite's two JSON aggregates.
///
/// See: https://www.sqlite.org/json1.html#jgrouparray
///
extension XLExpression {

    ///
    /// Collects every input row into a JSON array, rendering SQLite's
    /// `json_group_array(X)`.
    ///
    /// An empty group gives `[]`, not SQL `NULL`, so the result is not
    /// optional. A row whose value is SQL `NULL` contributes JSON `null`, so
    /// the array always has one entry per row.
    ///
    /// A value that is already JSON text is collected as a quoted string, not
    /// as a nested structure. Pass it through ``XLExpression/minifiedJSON()``
    /// first to nest it.
    ///
    public func jsonGroupArray(
        distinct: Bool = false
    ) -> some XLExpression<String> where T: XLLiteral {
        XLFunction<String>(
            name: "json_group_array",
            distinct: distinct,
            parameters: [self]
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
    name: any XLExpression<String>,
    value: any XLExpression
) -> some XLExpression<String> {
    XLFunction<String>(name: "json_group_object", parameters: [name, value])
}
