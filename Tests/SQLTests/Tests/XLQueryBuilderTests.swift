//
//  File.swift
//
//
//  Created by Luke Van In on 2023/08/22.
//

import XCTest
import GRDB
import SwiftQL

    
final class QueryBuilderTests: XCTestCase {
    
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
        
        var query = QueryBuilder(select: company)
        query = query.from(company)
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0`")
    }
    
    
    func test_select_from_and() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        
        var query = QueryBuilder(select: company)
        query = query.from(company)
        query = query.and(company.name == "Apple")
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` WHERE (`t0`.`name` == 'Apple')")
    }
    
    
    func test_select_from_orderBy() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        
        var query = QueryBuilder(select: company)
        query = query.from(company)
        query = query.orderBy(company.name.ascending())
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` ORDER BY `t0`.`name` ASC")
    }


    func test_select_from_limit() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let query = QueryBuilder(select: company)
            .from(company)
            .limit(10)

        let finalResult = try encoder.makeSQL(query.build()).sql

        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LIMIT 10")
    }


    func test_select_from_limit_offset() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let query = QueryBuilder(select: company)
            .from(company)
            .limit(10)
            .offset(5)

        let finalResult = try encoder.makeSQL(query.build()).sql

        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LIMIT 10 OFFSET 5")
    }


    func test_select_from_unbounded_limit_offset() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let query = QueryBuilder(select: company)
            .from(company)
            .limit(-1)
            .offset(5)

        let finalResult = try encoder.makeSQL(query.build()).sql

        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LIMIT -1 OFFSET 5")
    }


    func test_select_from_bound_limit_offset() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let limit = XLNamedBindingReference<Int>(name: "limit")
        let offset = XLNamedBindingReference<Int>(name: "offset")
        let query = QueryBuilder(select: company)
            .from(company)
            .limit(limit)
            .offset(offset)

        let finalResult = try encoder.makeSQL(query.build()).sql

        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LIMIT :limit OFFSET :offset")
    }


    func test_select_from_type_erased_numeric_limit_offset() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let limit: any XLExpression = 10.0
        let offset: any XLExpression = 5.0
        let query = QueryBuilder(select: company)
            .from(company)
            .limit(limit)
            .offset(offset)

        let finalResult = try encoder.makeSQL(query.build()).sql

        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LIMIT 10.0 OFFSET 5.0")
    }


    func test_select_from_offset_without_limit_throws() {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let query = QueryBuilder(select: company)
            .from(company)
            .offset(5)

        XCTAssertThrowsError(try query.build())
    }
    
    
    func test_select_from_leftJoin() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        
        var query = QueryBuilder(select: company)
        query = query.from(company)
        query = query.leftJoin(employee, on: employee.companyId == company.id)
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`)")
    }
    
    
    func test_select_from_leftJoin_and() throws {
        
        let schema = XLSchema()
        
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        
        var query = QueryBuilder(select: company)
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
        
        var query = QueryBuilder(select: company)
        query = query.from(company)
        query = query.leftJoin(employee, on: employee.companyId == company.id)
        query = query.and(employee.name == "Tim")
        query = query.orderBy(employee.name.ascending())
        
        let finalResult = try encoder.makeSQL(query.build()).sql
        
        XCTAssertEqual(finalResult, "SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`) WHERE (`t1`.`name` IS 'Tim') ORDER BY `t1`.`name` ASC")
    }

    func testCopyPreservesAllStoredStateAndMutatesOnlyTheCopy() throws {
        let schema = XLSchema()
        let commonTable = schema.commonTable { schema in
            let table = schema.table(TestTable.self)
            return select(table).from(table)
        }
        let company = schema.table(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        let original = QueryBuilder(select: company)
            .with(commonTable)
            .from(company)
            .leftJoin(employee, on: employee.companyId == company.id)
            .and(company.name == "Apple")
            .or(employee.name == "Tim")
            .groupBy(company.id)
            .orderBy(company.name.ascending())
            .limit(10)
            .offset(5)
        let copy = original.orderBy(company.id.descending())

        let originalSQL = try encoder.makeSQL(original.build()).sql
        let copySQL = try encoder.makeSQL(copy.build()).sql

        XCTAssertEqual(
            originalSQL,
            "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`) WHERE ((`t0`.`name` == 'Apple') OR (`t1`.`name` IS 'Tim')) GROUP BY `t0`.`id` ORDER BY `t0`.`name` ASC LIMIT 10 OFFSET 5"
        )
        XCTAssertEqual(
            copySQL,
            "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0` LEFT JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`) WHERE ((`t0`.`name` == 'Apple') OR (`t1`.`name` IS 'Tim')) GROUP BY `t0`.`id` ORDER BY `t0`.`name` ASC, `t0`.`id` DESC LIMIT 10 OFFSET 5"
        )
    }
    
}
