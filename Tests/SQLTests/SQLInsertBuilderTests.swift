/**
 * © 2019 - 2023 SEG Solutions
 *
 * NOTICE: All information contained herein is, and remains
 * the property of SEG Solutions and its suppliers,
 * if any.  The intellectual and technical concepts contained
 * herein are proprietary to SEG Solutions and its suppliers.
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from SEG Solutions.
 */

import XCTest
import GRDB
import SwiftQL



final class XLInsertBuilderTests: XCTestCase {
    
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
        let subject = XLInsertBuilder(insert: table).values(values)
        let result = try subject.build()
        XCTAssertEqual(encoder.makeSQL(result).sql, "INSERT INTO `Test` AS `t0` (`id`,`value`) VALUES ('foo',42)")
    }
    
    func testInsertWithoutValuesShouldFail() throws {
        let schema = XLSchema()
        let table = schema.table(TestTable.self)
        let subject = XLInsertBuilder(insert: table)
        XCTAssertThrowsError(try subject.build())
    }
}

