//
//  SampleTables.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation
import SwiftQL


@SQLTable(name: "Company")
struct CompanyTable: Equatable, Identifiable {
    
    let id: String
    
    let name: String
}


@SQLTable(name: "Employee")
struct EmployeeTable: Equatable, Identifiable {
    
    let id: String
    
    let name: String
    
    let companyId: String?
    
    let managerEmployeeId: String?
}


@SQLTable(name: "Order")
struct OrderTable: Identifiable {
    
    let id: String
    
//    @XLDate var date: Date
}


@SQLTable
struct Todo: Identifiable {
    
    let id: String
    
    let description: String
    
    let isComplete: Bool
}


@SQLTable
struct Org {
    var name: String?
    var boss: String?
}


@SQLTable
struct Family {
var name: String?
var mom: String?
var dad: String?
var born: Date?
var died: Date?
}


///
/// A table with a column that holds a JSON document, used by the JSON
/// documentation page.
///
@SQLTable
struct Note: Identifiable {

    let id: String

    let title: String

    /// A JSON object, for example:
    /// `{"tags":["home","urgent"],"priority":2,"due":null}`
    let metadata: String
}
