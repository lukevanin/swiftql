//
//  SQLDataChangingStatementsTests.swift
//
//  Rendering coverage for the v1.4.4 data-changing statement surface.
//

import Foundation
import XCTest

@testable import SwiftQL


final class XLDataChangingStatementsTests: XCTestCase {

    var encoder: XLiteEncoder!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .noEscape)
        encoder = XLiteEncoder(formatter: formatter)
    }

    override func tearDown() {
        encoder = nil
    }

    private func instanceValues() -> TestTable.MetaInsert {
        TestTable.MetaInsert(TestTable(id: "foo", value: 42))
    }


    // MARK: - INSERT OR

    func testInsertOrIgnore() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t, or: .ignore)
            Values(instanceValues())
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT OR IGNORE INTO Test AS t0 (id,value) VALUES ('foo',42)"
        )
    }

    func testInsertOrReplace() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Insert(t, or: .replace)
            Values(instanceValues())
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT OR REPLACE INTO Test AS t0 (id,value) VALUES ('foo',42)"
        )
    }

    func testInsertOrAllActionsRender() {
        let expected: [(XLInsertOrAction, String)] = [
            (.rollback, "ROLLBACK"),
            (.abort, "ABORT"),
            (.fail, "FAIL"),
            (.ignore, "IGNORE"),
            (.replace, "REPLACE"),
        ]
        for (action, keyword) in expected {
            let expression = sql { schema in
                let t = schema.table(TestTable.self)
                Insert(t, or: action)
                Values(instanceValues())
            }
            XCTAssertEqual(
                encoder.makeSQL(expression).sql,
                "INSERT OR \(keyword) INTO Test AS t0 (id,value) VALUES ('foo',42)"
            )
        }
    }

    func testInsertOrFunctional() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t, or: .ignore).values(instanceValues())
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT OR IGNORE INTO Test AS t0 (id,value) VALUES ('foo',42)"
        )
    }
}
