//
//  XLExpressionFunctions.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation


// MARK: - Ordering terms

extension XLExpression {
    
    public func ascending() -> some XLOrderingTerm {
        Ascending(expression: self)
    }

    public func descending() -> some XLOrderingTerm {
        Descending(expression: self)
    }
}
