//
//  FakeSecondDialectAggregateFunctions.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/AggregateFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


@available(*, deprecated, message: "Use all().count() instead. count(_:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func count(
    _ expression: any FakeSecondDialectExpression<XLAllColumns>
) -> some FakeSecondDialectExpression<Int> {
    XLFunction<Int>(name: "COUNT", parameters: [expression])
}


extension FakeSecondDialectExpression where T == XLAllColumns {

    /// Counts every input row by rendering `COUNT(*)`.
    @_disfavoredOverload
    func count() -> some FakeSecondDialectExpression<Int> {
        XLFunction<Int>(name: "COUNT", parameters: [self])
    }
}


/// See: https://www.sqlite.org/lang_aggfunc.html
///
extension FakeSecondDialectExpression {
    
    @_disfavoredOverload
    func count(distinct: Bool = false) -> some FakeSecondDialectExpression<Int> where T: XLLiteral {
        XLFunction(name: "COUNT", distinct: distinct, parameters: [self])
    }


    /// Returns the minimum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    @_disfavoredOverload
    func minOrNull(distinct: Bool = false) -> some FakeSecondDialectExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MIN", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MIN can return NULL. Use minOrNull(distinct:) instead. min() will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func min(distinct: Bool = false) -> some FakeSecondDialectExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MIN", distinct: distinct, parameters: [self])
    }


    /// Returns the maximum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    @_disfavoredOverload
    func maxOrNull(distinct: Bool = false) -> some FakeSecondDialectExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MAX", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MAX can return NULL. Use maxOrNull(distinct:) instead. max() will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func max(distinct: Bool = false) -> some FakeSecondDialectExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MAX", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, or NULL when the input is empty or contains no non-NULL values.
    ///
    /// SQLite computes `AVG` as a floating-point value for both integer and real inputs.
    @_disfavoredOverload
    func averageOrNull(distinct: Bool = false) -> some FakeSecondDialectExpression<Double?> where T: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// The result remains optional because SQLite returns NULL for an empty input or an all-NULL group.
    @_disfavoredOverload
    func averageOrNull<Wrapped>(distinct: Bool = false) -> some FakeSecondDialectExpression<Double?> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite AVG can return NULL. Use averageOrNull(distinct:) instead. average() will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func average(distinct: Bool = false) -> some FakeSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the sum of the non-NULL values, or NULL when the input is empty or contains no non-NULL values.
    @_disfavoredOverload
    func sumOrNull(distinct: Bool = false) -> some FakeSecondDialectExpression<T?> where T: Numeric & XLLiteral {
        XLFunction<T?>(name: "SUM", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite SUM can return NULL. Use sumOrNull(distinct:) instead. sum() will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func sum(distinct: Bool = false) -> some FakeSecondDialectExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "SUM", distinct: distinct, parameters: [self])
    }


    /// Returns the floating-point total of the non-NULL numeric values.
    ///
    /// Unlike `SUM`, SQLite `TOTAL` returns `0.0` for an empty input or an all-NULL group.
    @_disfavoredOverload
    func total(distinct: Bool = false) -> some FakeSecondDialectExpression<Double> where T: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Returns the floating-point total of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// SQLite returns `0.0` when no non-NULL input remains.
    @_disfavoredOverload
    func total<Wrapped>(distinct: Bool = false) -> some FakeSecondDialectExpression<Double> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double>(name: "TOTAL", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values, or returns NULL when the input is empty or contains no non-NULL values.
    @_disfavoredOverload
    func groupConcatOrNull(distinct: Bool = false) -> some FakeSecondDialectExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(distinct:) instead. groupConcat() will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func groupConcat(distinct: Bool = false) -> some FakeSecondDialectExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }


    /// Concatenates the non-NULL values using a separator, or returns NULL when no non-NULL values exist.
    @_disfavoredOverload
    func groupConcatOrNull(separator: String) -> some FakeSecondDialectExpression<String?> where T == String, T: XLLiteral {
        XLFunction<String?>(name: "GROUP_CONCAT", parameters: [self, separator])
    }


    @available(*, deprecated, message: "SQLite GROUP_CONCAT can return NULL. Use groupConcatOrNull(separator:) instead. groupConcat(separator:) will return an optional expression in SwiftQL 2.")
    @_disfavoredOverload
    func groupConcat(separator: String) -> some FakeSecondDialectExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", parameters: [self, separator])
    }
}
