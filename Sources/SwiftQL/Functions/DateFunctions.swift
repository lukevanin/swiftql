//
//  DateFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


public enum XLDateFunctionModifiers: String {
    
    #warning("TODO: Include all modifiers")
    
    case subseconds = "subsec"
}


public func unixepoch(date: String, modifiers: Set<XLDateFunctionModifiers>) -> some XLExpression<TimeInterval> {
    var parameters: [any XLExpression] = []
    parameters.append(date)
    let sortedModifiers = modifiers.map { $0.rawValue }.sorted()
    for modifier in sortedModifiers {
        parameters.append(modifier)
    }
    return XLFunction(name: "unixepoch", parameters: parameters)
}


extension XLExpression {
    
    public func toUnixTimestamp() -> some XLExpression<Int> where T == String {
        return XLFunction(name: "unixepoch", parameters: [self])
    }
}


extension XLExpression {
    
    public func toUnixTimestamp() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        return XLFunction(name: "unixepoch", parameters: [self])
    }
}
