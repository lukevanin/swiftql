//
//  AggregateFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


/// See: https://www.sqlite.org/lang_aggfunc.html
///
extension XLExpression {
    
    public func count(distinct: Bool = false) -> some XLExpression<Int> where T: XLLiteral {
        XLFunction(name: "COUNT", distinct: distinct, parameters: [self])
    }
    
    
    public func min(distinct: Bool = false) -> some XLExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MIN", distinct: distinct, parameters: [self])
    }
    
    
    public func max(distinct: Bool = false) -> some XLExpression<T> where T: XLComparable & XLLiteral {
        XLFunction(name: "MAX", distinct: distinct, parameters: [self])
    }
    
    
    public func average(distinct: Bool = false) -> some XLExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "AVG", distinct: distinct, parameters: [self])
    }

    
    public func sum(distinct: Bool = false) -> some XLExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "SUM", distinct: distinct, parameters: [self])
    }

    
    public func groupConcat(distinct: Bool = false) -> some XLExpression<T> where T == String, T: XLLiteral {
        XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [self])
    }

    
    public func groupConcat(distinct: Bool = false, separator: String) -> some XLExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [self, separator])
    }
}

//public func count<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: XLLiteral {
//    XLFunction(name: "COUNT", distinct: distinct, parameters: [expression])
//}
//
//
//public func min<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: XLLiteral {
//    XLFunction(name: "MIN", distinct: distinct, parameters: [expression])
//}
//
//
//public func max<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: XLLiteral {
//    XLFunction(name: "MAX", distinct: distinct, parameters: [expression])
//}
//
//
//public func average<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: XLLiteral {
//    XLFunction(name: "AVG", distinct: distinct, parameters: [expression])
//}
//
//
//public func sum<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: Numeric & XLLiteral {
//    XLFunction(name: "SUM", distinct: distinct, parameters: [expression])
//}
//
//
//public func groupConcat<T>(distinct: Bool = false, _ expression: any XLExpression<T>) -> some XLExpression<T> where T: Numeric & XLLiteral {
//    XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [expression])
//}
//
//
//public func groupConcat<T>(distinct: Bool = false, _ expression: any XLExpression, separator: String) -> some XLExpression<T> where T: Numeric & XLLiteral {
//    XLFunction(name: "GROUP_CONCAT", distinct: distinct, parameters: [expression, separator])
//}
