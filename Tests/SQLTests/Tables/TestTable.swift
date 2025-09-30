//
//  TestTables.swift
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
struct GenericTable<Value>: Identifiable, Equatable where Value: XLLiteral & XLExpression & Equatable {
    var id: String
    var value: Value
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
