//
//  SQLDataChangingStatementsTests.swift
//
//  Rendering coverage for the v1.4.4 data-changing statement surface:
//  INSERT OR, REPLACE, ON CONFLICT upsert, and RETURNING.
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


    // MARK: - REPLACE

    func testReplace() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Replace(t)
            Values(instanceValues())
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "REPLACE INTO Test AS t0 (id,value) VALUES ('foo',42)"
        )
    }

    func testReplaceFunctional() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = replace(t).values(instanceValues())
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "REPLACE INTO Test AS t0 (id,value) VALUES ('foo',42)"
        )
    }


    // MARK: - ON CONFLICT

    func testOnConflictDoNothingWithTarget() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t)
            .values(instanceValues())
            .onConflictDoNothing("id")
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42) ON CONFLICT (id) DO NOTHING"
        )
    }

    func testOnConflictDoNothingBare() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t)
            .values(instanceValues())
            .onConflictDoNothing()
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42) ON CONFLICT DO NOTHING"
        )
    }

    func testOnConflictDoUpdateWithExcluded() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let excluded = schema.excluded(TestTable.self)
        let expression = insert(t)
            .values(instanceValues())
            .onConflict("id", doUpdate: { row in row.value = excluded.value })
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42) ON CONFLICT (id) DO UPDATE SET value = excluded.value"
        )
    }

    func testOnConflictDoUpdateWithWhere() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let excluded = schema.excluded(TestTable.self)
        let expression = insert(t)
            .values(instanceValues())
            .onConflict(
                OnConflict.doUpdate(
                    on: "id",
                    set: { row in row.value = excluded.value },
                    where: excluded.value > t.value
                )
            )
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42) ON CONFLICT (id) DO UPDATE SET value = excluded.value WHERE (excluded.value > t0.value)"
        )
    }


    // MARK: - RETURNING

    func testInsertReturningRow() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let returned = schema.returning(TestTable.self)
        let expression = insert(t)
            .values(instanceValues())
            .returning(returned)
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42) RETURNING id AS id, value AS value"
        )
    }

    func testUpdateReturningScalar() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let returned = schema.returning(TestTable.self)
        let expression = update(t)
            .set { row in row.value = 42 }
            .returning(returned.value)
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "UPDATE Test AS t0 SET value = 42 RETURNING value"
        )
    }

    func testDeleteReturningScalar() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let returned = schema.returning(TestTable.self)
        let expression = delete(t)
            .where(t.value == 42)
            .returning(returned.id)
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "DELETE FROM Test AS t0 WHERE (t0.value == 42) RETURNING id"
        )
    }


    // MARK: - UPDATE with common table expression

    func testUpdateWithCommonTableExpression() {
        let expression = sql { schema in
            let cte = schema.commonTableExpression { schema in
                let source = schema.table(TestTable.self)
                Select(source)
                From(source)
            }
            let selected = schema.table(cte)
            let t = schema.into(TestTable.self)
            With(cte)
            Update(t)
            Setting<TestTable> { row in
                row.value = t.value + 1
            }
            Where(t.id.in { _ in
                Select(selected.id)
                From(selected)
            })
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) UPDATE Test AS t1 SET value = (t1.value + 1) WHERE (t1.id IN (SELECT t0.id FROM cte0 AS t0))"
        )
    }
}
