//
//  StringFunctions.swift
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


private struct XLCollationExpression<T>: XLExpression {

    let operand: any XLExpression

    let collation: XLCollation

    func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.unarySuffix(
                collation.sqlSuffix,
                expression: operand.makeSQL
            )
        }
    }
}


private extension XLCollation {

    var sqlSuffix: String {
        switch self {
        case .binary:
            "COLLATE BINARY"
        case .nocase:
            "COLLATE NOCASE"
        case .rtrim:
            "COLLATE RTRIM"
        }
    }
}


extension XLExpression {
    
    public func collate(_ collation: XLCollation) -> some XLExpression<String> where T == String {
        XLCollationExpression<String>(operand: self, collation: collation)
    }
    
    public func collate(_ collation: XLCollation) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLCollationExpression<Optional<String>>(
            operand: self,
            collation: collation
        )
    }
}


public func printf(format: String, _ parameters: any XLExpression ...) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}


public func printf(format: String, _ parameters: [any XLExpression]) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}
