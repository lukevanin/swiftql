//
//  SQLInsertBuilderTests.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//

import XCTest
import GRDB
import SwiftQL



final class InsertBuilderTests: XCTestCase {
    
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
    
    func testInsert() throws {
        let schema = XLSchema()
        let table = schema.table(TestTable.self)
        let values = TestTable(id: "foo", value: 42)
        let subject = InsertBuilder(insert: table).values(values)
        let result = try subject.build()
        XCTAssertEqual(encoder.makeSQL(result).sql, "INSERT INTO `Test` AS `t0` (`id`,`value`) VALUES ('foo',42)")
    }
    
    func testInsertWithoutValuesShouldFail() throws {
        let schema = XLSchema()
        let table = schema.table(TestTable.self)
        let subject = InsertBuilder(insert: table)
        XCTAssertThrowsError(try subject.build())
    }
}

