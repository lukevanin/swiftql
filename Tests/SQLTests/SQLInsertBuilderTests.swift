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

    func testCopyPreservesCommonTablesAndMutatesOnlyTheCopy() throws {
        let schema = XLSchema()
        let commonTable = schema.commonTable { schema in
            let table = schema.table(TestTable.self)
            return select(table).from(table)
        }
        let table = schema.table(TestTable.self)
        let original = InsertBuilder(insert: table)
            .with(commonTable)
            .values(TestTable(id: "original", value: 42))
        let copy = original.values(TestTable(id: "copy", value: 84))

        let originalSQL = try encoder.makeSQL(original.build()).sql
        let copySQL = try encoder.makeSQL(copy.build()).sql

        XCTAssertEqual(
            originalSQL,
            "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) INSERT INTO `Test` AS `t0` (`id`,`value`) VALUES ('original',42)"
        )
        XCTAssertEqual(
            copySQL,
            "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) INSERT INTO `Test` AS `t0` (`id`,`value`) VALUES ('copy',84)"
        )
    }
}
