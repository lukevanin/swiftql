//
//  SQLScalarResult.swift
//
//
//  Created by Luke Van In on 2024/10/31.
//

import Foundation


///
/// Scalar result
///
/// Convenience type used where a scalar result (single column) needs to be returned from an expression
/// that returns a table, such as when a scalar result is returned by a common table expression.
///
@SQLTable
public struct SQLScalarResult<T> where T: XLLiteral & XLExpression {
    
    public var scalarValue: T
}



extension SQLScalarResult: Equatable where T: Equatable {
    
}

extension SQLScalarResult: Hashable where T: Hashable {
    
}
