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


    // MARK: - ON CONFLICT (upsert)

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

    /// The `excluded` pseudo table renders as the bare `excluded` keyword when
    /// used as a table source — never as the aliased base table — so accidental
    /// use outside an upsert produces `FROM excluded`, which SQLite rejects,
    /// rather than silently querying the underlying table.
    func testExcludedRendersAsBarePseudoTable() {
        let schema = XLSchema()
        let excluded = schema.excluded(TestTable.self)
        let expression = sql { _ in
            Select(excluded)
            From(excluded)
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "SELECT excluded.id AS id, excluded.value AS value FROM excluded"
        )
    }


    // MARK: - UPDATE with common table expression

    func testUpdateWithCommonTable() {
        let schema = XLSchema()
        let source = schema.commonTable { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t)
        }
        let t = schema.into(TestTable.self)
        let s = schema.table(source)
        let expression = with(source)
            .update(t)
            .set { row in row.value = s.value + 100 }
            .from(s)
            .where(t.id == s.id)
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) UPDATE Test AS t0 SET value = (t1.value + 100) FROM cte0 AS t1 WHERE (t0.id == t1.id)"
        )
    }
}
