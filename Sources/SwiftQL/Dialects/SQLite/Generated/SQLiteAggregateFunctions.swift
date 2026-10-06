//
//  SQLiteAggregateFunctions.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/AggregateFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


@available(*, deprecated, message: "Use all().count() instead. count(_:) will be removed in SwiftQL 2.")
public func count(
    _ expression: any XLSQLiteExpression<XLAllColumns>
) -> some XLSQLiteExpression<Int> {
    XLFunction<Int>(name: "COUNT", parameters: [expression])
}


extension XLSQLiteExpression where T == XLAllColumns {

    /// Counts every input row by rendering `COUNT(*)`.
    public func count() -> some XLSQLiteExpression<Int> {
        XLFunction<Int>(name: "COUNT", parameters: [self])
    }
}


/// See: https://www.sqlite.org/lang_aggfunc.html
///
extension XLSQLiteExpression {
    
    public func count(distinct: Bool = false) -> some XLSQLiteExpression<Int> where T: XLLiteral {
        XLFunction(name: "COUNT", distinct: distinct, parameters: [self])
    }


    /// Returns the minimum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    public func minOrNull(distinct: Bool = false) -> some XLSQLiteExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MIN", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MIN can return NULL. Use minOrNull(distinct:) instead. min() will return an optional expression in SwiftQL 2.")
    public func min(distinct: Bool = false) -> some XLSQLiteExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MIN", distinct: distinct, parameters: [self])
    }


    /// Returns the maximum non-NULL value, or NULL when the input is empty or contains no non-NULL values.
    public func maxOrNull(distinct: Bool = false) -> some XLSQLiteExpression<T?> where T: XLComparable & XLLiteral {
        XLFunction<T?>(name: "MAX", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite MAX can return NULL. Use maxOrNull(distinct:) instead. max() will return an optional expression in SwiftQL 2.")
    public func max(distinct: Bool = false) -> some XLSQLiteExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MAX", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, or NULL when the input is empty or contains no non-NULL values.
    ///
    /// SQLite computes `AVG` as a floating-point value for both integer and real inputs.
    public func averageOrNull(distinct: Bool = false) -> some XLSQLiteExpression<Double?> where T: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the average of the non-NULL numeric values, ignoring NULL inputs.
    ///
    /// The result remains optional because SQLite returns NULL for an empty input or an all-NULL group.
    public func averageOrNull<Wrapped>(distinct: Bool = false) -> some XLSQLiteExpression<Double?> where T == Optional<Wrapped>, Wrapped: Numeric & XLLiteral {
        XLFunction<Double?>(name: "AVG", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite AVG can return NULL. Use averageOrNull(distinct:) instead. average() will return an optional expression in SwiftQL 2.")
    public func average(distinct: Bool = false) -> some XLSQLiteExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "AVG", distinct: distinct, parameters: [self])
    }


    /// Returns the sum of the non-NULL values, or NULL when the input is empty or contains no non-NULL values.
    public func sumOrNull(distinct: Bool = false) -> some XLSQLiteExpression<T?> where T: Numeric & XLLiteral {
        XLFunction<T?>(name: "SUM", distinct: distinct, parameters: [self])
    }


    @available(*, deprecated, message: "SQLite SUM can return NULL. Use sumOrNull(distinct:) instead. sum() will return an optional expression in SwiftQL 2.")
    public func sum(distinct: Bool = false) -> some XLSQLiteExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "SUM", distinct: distinct, parameters: [self])
    }
}
