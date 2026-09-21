//
//  TestTable.swift
//  
//
//  Created by Luke Van In on 2023/07/27.
//

import Foundation
import SwiftQL


@SQLTable(name: "Test")
struct TestTable: Equatable, Identifiable {
    
    let id: String
    
    let value: Int
}


@SQLTable(name: "TestNullables")
struct TestNullablesTable: Equatable, Identifiable {
    
    let id: String
    
    let value: Int?
}


@SQLTable(name: "Temp") 
struct Temp: Identifiable, Equatable {
    var id: String
    var value: String
}


@SQLTable(name: "Generic")
struct GenericTable<Value: XLLiteral & XLExpression> {
    var id: String
    var type: String
    var value: Value
}

// A generic model cannot get a `Sendable` conformance from `@SQLTable`, so it
// states the conditional one itself. See `SQLMacro.swift` and issue #685.
extension GenericTable: Sendable where Value: Sendable {

}


@SQLTable(name: "DateTest")
struct DateTest: Identifiable, Equatable {
    
    var id: Int
    
    var date: Date
}


@SQLTable(name: "DateTest")
struct OptionalDateTest: Identifiable, Equatable {
    
    var id: Int
    
    var date: Date?
}


@SQLTable(name: "DoubleTest")
struct DoubleTest: Equatable, Identifiable {
    
    let id: String
    
    let value: Double
}
