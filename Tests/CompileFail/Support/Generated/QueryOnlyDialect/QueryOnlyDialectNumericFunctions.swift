//
//  QueryOnlyDialectNumericFunctions.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension QueryOnlyDialectExpression {
    
    
    func abs() -> some QueryOnlyDialectExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "ABS", parameters: [self])
    }
}


extension QueryOnlyDialectExpression {
    
    func rounded() -> some QueryOnlyDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
    

    func rounded() -> some QueryOnlyDialectExpression<T> where T == Optional<Double>, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
}


extension QueryOnlyDialectExpression {

    
    func rounded(to places: Int) -> some QueryOnlyDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self, places])
    }
}


extension QueryOnlyDialectExpression {
    
    
    func floor() -> some QueryOnlyDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "FLOOR", parameters: [self])
    }
}
