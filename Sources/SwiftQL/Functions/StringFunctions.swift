//
//  File.swift
//  
//
//  Created by Luke Van In on 2023/09/08.
//

import Foundation


/// https://www.sqlite.org/datatype3.html#collation
///
public enum XLCollation: String {
    
    case binary = "BINARY"
    
    case nocase = "NOCASE"
    
    case rtrim = "RTRIM"
}


extension XLExpression {
    
    public func collate(_ collation: XLCollation) -> some XLExpression<String> where T == String {
        XLBinaryOperatorExpression(op: "COLLATE", lhs: self, rhs: collation.rawValue)
    }
    
    public func collate(_ collation: XLCollation) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "COLLATE", lhs: self, rhs: collation.rawValue)
    }
}


public func printf(format: String, _ parameters: any XLExpression ...) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}


public func printf(format: String, _ parameters: [any XLExpression]) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}
