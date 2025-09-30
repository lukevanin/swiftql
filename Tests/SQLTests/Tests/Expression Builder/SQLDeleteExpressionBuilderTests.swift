//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/30.
//

import XCTest

import SwiftQL


final class XLDeleteExpressionBuilderTests: XCTestCase {
    
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
    
    // MARK: - Delete
    
    func testDelete() {
        let expression = sql { schema in
            let t = schema.into(TestTable.self)
            Delete(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "DELETE FROM Test AS t0")
    }
    
    func testDeleteWhere() {
        let expression = sql { schema in
            let t = schema.into(TestTable.self)
            Delete(t)
            Where(t.value == 42)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "DELETE FROM Test AS t0 WHERE (t0.value == 42)")
    }
    
    func testDeleteWithCommonTableExpression() {
        let expression = sql { schema in
            let cte = schema.commonTableExpression { schema in
                let t = schema.table(TestTable.self)
                Select(t)
                From(t)
            }
            let t0 = schema.table(cte)
            let t1 = schema.into(TestTable.self)
            With(cte)
            Delete(t1)
            Where(
                t1.id.in { _ in
                    Select(t0.id)
                    From(t0)
                }
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) DELETE FROM Test AS t1 WHERE (t1.id IN (SELECT t0.id FROM cte0 AS t0))")
    }
    
    func testDeleteWithSubquery() {
        let expression = sql { schema in
            let t0 = schema.into(TestTable.self)
            Delete(t0)
            Where(
                t0.id.in { schema in
                    let t0 = schema.table(TestTable.self)
                    Select(t0.id)
                    From(t0)
                }
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "DELETE FROM Test AS t0 WHERE (t0.id IN (SELECT t0.id FROM Test AS t0))")
    }
}
