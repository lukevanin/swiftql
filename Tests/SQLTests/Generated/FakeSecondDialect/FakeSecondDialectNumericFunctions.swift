//
//  FakeSecondDialectNumericFunctions.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension FakeSecondDialectExpression {
    
    
    @_disfavoredOverload
    func abs() -> some FakeSecondDialectExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "ABS", parameters: [self])
    }
}


extension FakeSecondDialectExpression {
    
    @_disfavoredOverload
    func rounded() -> some FakeSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
    

    @_disfavoredOverload
    func rounded() -> some FakeSecondDialectExpression<T> where T == Optional<Double>, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
}


extension FakeSecondDialectExpression {

    
    @_disfavoredOverload
    func rounded(to places: Int) -> some FakeSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self, places])
    }
}


extension FakeSecondDialectExpression {
    
    
    @_disfavoredOverload
    func floor() -> some FakeSecondDialectExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "FLOOR", parameters: [self])
    }
}
