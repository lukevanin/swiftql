//
//  CompileFailSecondDialectNumericFunctions.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension CompileFailSecondDialectExpression {
    
    
    @_disfavoredOverload
    func abs() -> some CompileFailSecondDialectExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "ABS", parameters: [self])
    }
}


extension CompileFailSecondDialectExpression {
    
    @_disfavoredOverload
    func rounded() -> some CompileFailSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
    

    @_disfavoredOverload
    func rounded() -> some CompileFailSecondDialectExpression<T> where T == Optional<Double>, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
}


extension CompileFailSecondDialectExpression {

    
    @_disfavoredOverload
    func rounded(to places: Int) -> some CompileFailSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self, places])
    }
}


extension CompileFailSecondDialectExpression {
    
    
    @_disfavoredOverload
    func floor() -> some CompileFailSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "FLOOR", parameters: [self])
    }
}
