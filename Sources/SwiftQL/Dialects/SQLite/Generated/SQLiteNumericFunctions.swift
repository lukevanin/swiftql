//
//  SQLiteNumericFunctions.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/NumericFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


extension XLSQLiteExpression {
    
    
    public func abs() -> some XLSQLiteExpression<T> where T: Numeric & XLLiteral {
        XLFunction(name: "ABS", parameters: [self])
    }
}


extension XLSQLiteExpression {
    
    public func rounded() -> some XLSQLiteExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
    

    public func rounded() -> some XLSQLiteExpression<T> where T == Optional<Double>, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self])
    }
}


extension XLSQLiteExpression {

    
    public func rounded(to places: Int) -> some XLSQLiteExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "ROUND", parameters: [self, places])
    }
}


extension XLSQLiteExpression {
    
    
    public func floor() -> some XLSQLiteExpression<T> where T == Double, T: XLLiteral {
        XLFunction(name: "FLOOR", parameters: [self])
    }
}
