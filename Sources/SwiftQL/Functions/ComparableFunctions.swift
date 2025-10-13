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
public func min<T>(_ values: any XLExpression<T>...) -> some XLExpression<T> where T: XLComparable & XLLiteral {
    XLFunction(name: "MIN", parameters: values)
}


///
/// Returns the maximum value from a list of expressions.
///
public func max<T>(_ values: any XLExpression<T>...) -> some XLExpression<T> where T: XLComparable & XLLiteral {
    XLFunction(name: "MAX", parameters: values)
}
