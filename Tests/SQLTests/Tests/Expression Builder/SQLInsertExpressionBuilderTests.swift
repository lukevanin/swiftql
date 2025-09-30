//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation

import XCTest

@testable import SwiftQL


final class XLInsertExpressionBuilderTests: XCTestCase {
    
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
    
    // MARK: INSERT ... VALUES
    
    func testInsertDiscreteParameters() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let valueParameter = XLNamedBindingReference<Int>(name: "value")
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t)
            Values(
                TestTable.MetaInsert(
                    id: idParameter,
                    value: valueParameter
                )
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "INSERT INTO Test AS t0 (id,value) VALUES (:id,:value)")
    }
    
    func testInsertInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t)
            Values(TestTable.MetaInsert(instance))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
    }
    
    func testInsertImplicitInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t)
            Values(instance)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
    }
    
    func testInsertSelect() {
        let expression = sql { schema in
            let t = schema.table(Temp.self)
            let e = schema.table(EmployeeTable.self)
            let r = Temp.columns(
                id: e.id,
                value: e.name
            )
            Insert(t)
            Select(r)
            From(e)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM Employee AS t1")
    }
    
    func testInsertSelectWithCommonTableExpression() {
        let expression = sql { schema in
            let cte = schema.commonTableExpression { schema in
                let t = schema.table(CompanyTable.self)
                Select(t)
                From(t)
            }
            let t = schema.table(Temp.self)
            let e = schema.table(cte)
            let r = Temp.columns(
                id: e.id,
                value: e.name
            )
            With(cte)
            Insert(t)
            Select(r)
            From(e)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM cte0 AS t1")
    }
}
