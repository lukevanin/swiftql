//
//  XLIntegerFunctions.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


extension XLExpression {
    
    
    public func abs() -> some XLExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "ABS", parameters: [self])
    }
}


extension XLExpression {
    
    public func rounded() -> some XLExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
    

    public func rounded() -> some XLExpression<T> where T == Optional<Double>, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
}


extension XLExpression {

    
    public func rounded(to places: Int) -> some XLExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self, places])
    }
}


extension XLExpression {
    
    
    public func floor() -> some XLExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "FLOOR", parameters: [self])
    }
}
