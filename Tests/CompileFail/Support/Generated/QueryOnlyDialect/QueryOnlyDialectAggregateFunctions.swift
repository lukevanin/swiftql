//
//  QueryOnlyDialectAggregateFunctions.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/AggregateFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


@available(*, deprecated, message: "Use all().count() instead. count(_:) will be removed in SwiftQL 2.")
func count(
    _ expression: any QueryOnlyDialectExpression<XLAllColumns>
) -> some QueryOnlyDialectExpression<Int> {
    XLFunction<Int>(name: "COUNT", parameters: [expression])
}


extension QueryOnlyDialectExpression where T == XLAllColumns {

    /// Counts every input row by rendering `COUNT(*)`.
    func count() -> some QueryOnlyDialectExpression<Int> {
        XLFunction<Int>(name: "COUNT", parameters: [self])
    }
}


/// SQLite's aggregates: https://www.sqlite.org/lang_aggfunc.html
///
extension QueryOnlyDialectExpression {
    
    func count(distinct: Bool = false) -> some QueryOnlyDialectExpression<Int> where T: XLLiteral {
        XLFunction(name: "COUNT", distinct: distinct, parameters: [self])
    }


    /// Returns the minimum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    func minOrNull(distinct: Bool = false) -> some QueryOnlyDialectExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MIN", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "MIN can return NULL. Use minOrNull(distinct:) instead. min() will return an optional expression in SwiftQL 2.")
    func min(distinct: Bool = false) -> some QueryOnlyDialectExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MIN", distinct: distinct, parameters: [self])
    }


    /// Returns the maximum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    func maxOrNull(distinct: Bool = false) -> some QueryOnlyDialectExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MAX", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "MAX can return NULL. Use maxOrNull(distinct:) instead. max() will return an optional expression in SwiftQL 2.")
    func max(distinct: Bool = false) -> some QueryOnlyDialectExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MAX", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, or NULL when the input is empty or contains no non-NULL values.
    ///
    /// The result is floating-point for integer and real inputs, as SQLite computes `AVG`.
    func averageOrNull(distinct: Bool = false) -> some QueryOnlyDialectExpression<Double?> where T: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// The result remains optional because `AVG` returns NULL for an empty input or an all-NULL group.
    func averageOrNull<Wrapped>(distinct: Bool = false) -> some QueryOnlyDialectExpression<Double?> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "AVG can return NULL. Use averageOrNull(distinct:) instead. average() will return an optional expression in SwiftQL 2.")
    func average(distinct: Bool = false) -> some QueryOnlyDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the sum of the non-NULL values, or NULL when the input is empty or contains no non-NULL values.
    func sumOrNull(distinct: Bool = false) -> some QueryOnlyDialectExpression<T?> where T: Numeric & XLLiteral {
        XLFunction<T?>(name: "SUM", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SUM can return NULL. Use sumOrNull(distinct:) instead. sum() will return an optional expression in SwiftQL 2.")
    func sum(distinct: Bool = false) -> some QueryOnlyDialectExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "SUM", distinct: distinct, parameters: [self])
    }
}
