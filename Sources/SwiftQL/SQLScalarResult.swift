//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/31.
//

import Foundation


@SQLTable
public struct SQLScalarResult<T> where T: XLLiteral & XLExpression {
    
    public var scalarValue: T
}



extension SQLScalarResult: Equatable where T: Equatable {
    
}

extension SQLScalarResult: Hashable where T: Hashable {
    
}
