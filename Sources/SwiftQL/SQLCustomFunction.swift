//
//  XLCustomFunction.swift
//  
//
//  Created by Luke Van In on 2023/08/08.
//

import Foundation


public struct XLCustomFunctionDefinition: Hashable {
    
    public var name: String
    
    public var numberOfArguments: Int
    
    public init(name: String, numberOfArguments: Int) {
        self.name = name
        self.numberOfArguments = numberOfArguments
    }
}


public protocol XLCustomFunction<T>: XLExpression {
    static var definition: XLCustomFunctionDefinition { get }
    static func execute(reader: XLColumnReader) throws -> T
}
