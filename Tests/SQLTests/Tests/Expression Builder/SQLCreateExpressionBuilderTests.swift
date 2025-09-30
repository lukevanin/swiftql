//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation

import XCTest

@testable import SwiftQL


final class XLCreateExpressionBuilderTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .noEscape
        )
        encoder = XLiteEncoder(formatter: formatter)
    }
    
    override func tearDown() {
        encoder = nil
    }
    
    // MARK: - Create
    
    func testCreateTable() {
        let expression = sql { schema in
            let t = schema.create(TestTable.self)
            Create(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Test (id NOT NULL, value NOT NULL)")
    }
    
    func testCreateNullablesTable() {
        let expression = sql { schema in
            let t = schema.create(TestNullablesTable.self)
            Create(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS TestNullables (id NOT NULL, value)")
    }
    
    func testCreateGenericValueTable() {
        let expression = sql { schema in
            let t = schema.create(GenericTable<String>.self)
            Create(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Generic (id NOT NULL, value NOT NULL)")
    }
    
    
    // MARK: Create ... Select
    
    func testCreateTableUsingSelect() {
        let expression = sql { schema in
            let t = schema.create(Temp.self)
            Create(t)
            As { schema in
                let t = schema.table(EmployeeTable.self)
                let r = result {
                    Temp.SQLReader(
                        id: t.id,
                        value: t.name
                    )
                }
                Select(r)
                From(t)
            }
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Temp AS SELECT t0.id AS id, t0.name AS value FROM Employee AS t0")
    }
    
    func testCreateTableUsingSelectWithCommonTable() {
        let expression = sql { schema in
            let t = schema.create(Temp.self)
            Create(t)
            As { schema in
                
                let cte = schema.commonTableExpression { schema in
                    let t = schema.table(EmployeeTable.self)
                    Select(t)
                    From(t)
                }
                
                let t = schema.table(cte)
                let r = result {
                    Temp.SQLReader(
                        id: t.id,
                        value: t.name
                    )
                }
                With(cte)
                Select(r)
                From(t)
            }
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Temp AS WITH cte0 AS (SELECT t0.id AS id, t0.name AS name, t0.companyId AS companyId, t0.managerEmployeeId AS managerEmployeeId FROM Employee AS t0) SELECT t0.id AS id, t0.name AS value FROM cte0 AS t0")
    }
    
}
