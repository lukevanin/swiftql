//
//  File.swift
//
//
//  Created by Luke Van In on 2024/10/29.
//

import Foundation

import XCTest

@testable import SwiftQL


final class XLUpdateExpressionBuilderTests: XCTestCase {
    
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
    
    // MARK: - UPDATE
    
    func testUpdateSettingDescreteValues() {
        let expression = sql { ns in
            let t = ns.into(TestTable.self)
            Update(t)
            Setting<TestTable> { row in
                row.value = 42
            }
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "UPDATE Test AS t0 SET value = 42")
    }
    
    func testUpdateSettingDescreteValuesWithClosure() {
        let expression = sql { ns in
            let t = ns.into(TestTable.self)
            Update(t)
            Setting<TestTable> { row in
                row.value = t.value + 10
            }
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "UPDATE Test AS t0 SET value = (t0.value + 10)")
    }
    
    func testUpdateSettingDescreteValuesWithWhere() {
        let expression = sql { ns in
            let t = ns.into(TestTable.self)
            Update(t)
            Setting<TestTable> { row in
                row.value = 1
            }
            Where(
                t.value != 0
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "UPDATE Test AS t0 SET value = 1 WHERE (t0.value != 0)")
    }

    func testUpdateSettingDiscreteValuesWithMetaInstance() {
        let expression = sql { ns in
            let t = ns.into(TestTable.self)
            Update(t)
            Setting(TestTable.MetaUpdate(
                value: 42
            ))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "UPDATE Test AS t0 SET value = 42")
    }
    
    func testUpdateSettingDiscreteValuesWithMetaInstanceWithExpression() {
        let expression = sql { ns in
            let t = ns.into(TestTable.self)
            Update(t)
            Setting(TestTable.MetaUpdate(
                value: t.value + 10
            ))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "UPDATE Test AS t0 SET value = (t0.value + 10)")
    }

    func testUpdateFrom() {
        let expression = sql { schema in
            let t = schema.into(Temp.self)
            let s = schema.fromExpression { schema in
                let t = schema.table(CompanyTable.self)
                Select(t)
                From(t)
            }
            Update(t)
            Setting<Temp> { row in
                row.value = t.value + " " + s.name
            }
            From(s)
            Where(t.id == s.id)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Temp AS t0 SET value = t0.value || ' ' || t1.name FROM (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) AS t1 WHERE (t0.id == t1.id)")
        XCTAssertTrue(result.entities.contains("Temp"))
    }
}
