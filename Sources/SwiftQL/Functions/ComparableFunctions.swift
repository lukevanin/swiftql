//
//  ComparableFunctions.swift
//  
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


///
/// Returns the miniumum value from a list of expressions.
///
@available(*, deprecated, message: "Use a.min(b, ...) instead. min(_:) will be removed in SwiftQL 2.")
public func min<T>(_ values: any XLExpression<T>...) -> some XLExpression<T> where T: XLComparable & XLLiteral {
    XLFunction(name: "MIN", parameters: values)
}


///
/// Returns the maximum value from a list of expressions.
///
@available(*, deprecated, message: "Use a.max(b, ...) instead. max(_:) will be removed in SwiftQL 2.")
public func max<T>(_ values: any XLExpression<T>...) -> some XLExpression<T> where T: XLComparable & XLLiteral {
    XLFunction(name: "MAX", parameters: values)
}


extension XLExpression where T: XLComparable & XLLiteral {

    /// Returns the minimum value among `self` and `others`.
    ///
    /// Takes at least one further expression, both to match SQLite's scalar
    /// `MIN` (meaningless with a single argument) and to stay unambiguous
    /// against the deprecated zero-argument aggregate `min(distinct:)`.
    public func min(_ first: any XLExpression<T>, _ rest: any XLExpression<T>...) -> some XLExpression<T> {
        XLFunction(name: "MIN", parameters: [self, first] + rest)
    }

    /// Returns the maximum value among `self` and `others`.
    ///
    /// Takes at least one further expression, both to match SQLite's scalar
    /// `MAX` (meaningless with a single argument) and to stay unambiguous
    /// against the deprecated zero-argument aggregate `max(distinct:)`.
    public func max(_ first: any XLExpression<T>, _ rest: any XLExpression<T>...) -> some XLExpression<T> {
        XLFunction(name: "MAX", parameters: [self, first] + rest)
    }
}
