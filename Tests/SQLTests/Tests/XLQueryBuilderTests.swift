//
//  File.swift
//
//
//  Created by Luke Van In on 2023/08/22.
//

import XCTest
import GRDB
import SwiftQL

    
final class XLQueryBuilderTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        encoder = XLiteEncoder(formatter: formatter)
    }
    
    override func tearDown() {
        encoder = nil
    }
    
    
    func test_select() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0`")
    }
    
    
    func test_select_from_and() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        query = query.and(company.name == "Apple")
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` WHERE (`t0`.`name` == 'Apple')")
    }
    
    
    func test_select_from_orderBy() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        query = query.orderBy(company.name.ascending())
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` ORDER BY `t0`.`name` ASC")
    }
    
    
    func test_select_from_leftJoin() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        query = query.leftJoin(employee, on: employee.companyId == company.id)
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`)")
    }
    
    
    func test_select_from_leftJoin_and() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        query = query.leftJoin(employee, on: employee.companyId == company.id)
        query = query.and(employee.name == "Tim")
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`) WHERE (`t1`.`name` IS 'Tim')")
    }
    
    
    func test_select_from_leftJoin_and_orderBy() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        
        var query = XLQueryBuilder(select: company)
        query = query.from(company)
        query = query.leftJoin(employee, on: employee.companyId == company.id)
        query = query.and(employee.name == "Tim")
        query = query.orderBy(employee.name.ascending())
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`) WHERE (`t1`.`name` IS 'Tim') ORDER BY `t1`.`name` ASC")
    }
    
}
