//
//  JSONFunctions.swift
//
//

import Foundation


/// See: https://www.sqlite.org/json1.html
///
extension XLExpression {
    
    public func jsonArrayLength() -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self])
    }
    
    public func jsonArrayLength(path: String) -> some XLExpression<Int?> where T: XLLiteral {
        XLFunction(name: "json_array_length", parameters: [self, path])
    }
    
    public func validJSON() -> some XLExpression<Bool> where T: XLLiteral {
        XLFunction(name: "json_valid", parameters: [self])
    }
    
}
