//
//  EmployeeTable.swift
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
