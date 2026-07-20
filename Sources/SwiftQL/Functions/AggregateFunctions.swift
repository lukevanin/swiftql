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


/// Counts every input row by rendering `COUNT(*)`.
public func count(
    _ expression: any XLExpression<XLAllColumns>
) -> some XLExpression<Int> {
    XLFunction<Int>(name: "COUNT", parameters: [expression])
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


    /// Returns the average of the non-NULL values, or NULL when the input is empty or contains no non-NULL values.
    public func averageOrNull(distinct: Bool = false) -> some XLExpression<Double?> where T == Double, T: XLLiteral {
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
