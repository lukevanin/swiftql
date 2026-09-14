//
//  StaticRowLayoutEntryPointTests.swift
//
//  Issue #650: a statement built from `staticRowLayout(using:)` succeeds at
//  every entry point. Before the fix, the generic entry points saw a layout
//  only as `XLRowReadable`, replayed its `readRow` against the definition
//  reader, and trapped, because a layout reads dialect values that the
//  definition reader cannot supply.
//
//  The layouts here select plain columns only. The Swift 5.9 and 6.0
//  compilers crash in SILGen when an opaque operator result such as
//  `column + "suffix"` converts to the `any XLExpression<String>` parameter
//  of the helper below, so the tests avoid that shape.
//

import Foundation
import GRDB
import SwiftQL
import XCTest


/// Builds a static row layout for `TestTable` from two column expressions.
private func testTableLayout(
    id: any XLExpression<String>,
    value: any XLExpression<Int>
) throws -> XLStaticRowLayout<TestTable, XLSQLiteDialect> {
    try TestTable.staticRowLayout(
        using: XLSQLiteDialect.self,
        id: XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: id,
            identifiedBy: XLQuerySlotIdentity(path: ["entry-point", "id"])
        ),
        value: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
            selecting: value,
            identifiedBy: XLQuerySlotIdentity(path: ["entry-point", "value"])
        )
    )
}


/// Calls `select(_:)` from a generic context that sees the projection only as
/// `XLRowReadable`, so overload resolution picks the dynamic entry point.
private func genericSelect<R: XLRowReadable>(_ projection: R) -> XLQuerySelectStatement<R.Row> {
    select(projection)
}


/// Creates a `Returning` clause from a generic context that sees the
/// projection only as `XLRowReadable`.
private func genericReturning<R: XLRowReadable>(_ projection: R) -> Returning<R.Row> {
    Returning(projection)
}


final class StaticRowLayoutEntryPointRenderTests: XLSyntaxTestCase {

    func testFunctionalSelect() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        assertRenders(
            select(layout).from(t),
            as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0"
        )
    }

    func testWithSelect() throws {
        let schema = XLSchema()
        let cte = schema.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = schema.table(cte)
        let layout = try testTableLayout(id: t.id, value: t.value)
        assertRenders(
            with(cte).select(layout).from(t),
            as: "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0"
        )
    }

    func testInsertSelect() throws {
        let schema = XLSchema()
        let target = schema.table(TestTable.self)
        let source = schema.table(TestTable.self)
        let layout = try testTableLayout(id: source.id, value: source.value)
        assertRenders(
            insert(target).select(layout).from(source),
            as: "INSERT INTO Test AS t0 SELECT t1.id AS id, t1.value AS value FROM Test AS t1"
        )
    }

    func testQueryBuilderInitSelect() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        let statement = try QueryBuilder(select: layout).from(t).build()
        assertRenders(
            statement,
            as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0"
        )
    }

    func testInsertReturning() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        assertRenders(
            insert(t).values(TestTable(id: "a", value: 1)).returning(layout),
            as: "INSERT INTO Test AS t0 (id,value) VALUES ('a',1) RETURNING id, value"
        )
    }

    func testUpdateReturning() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        assertRenders(
            update(w).set { $0.value = 99 }.where(w.id == "a").returning(layout),
            as: "UPDATE Test AS t0 SET value = 99 WHERE (t0.id == 'a') RETURNING id, value"
        )
    }

    func testDeleteReturning() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        assertRenders(
            delete(w).where(w.id == "a").returning(layout),
            as: "DELETE FROM Test AS t0 WHERE (t0.id == 'a') RETURNING id, value"
        )
    }

    /// A generic caller that sees the layout only as `XLRowReadable` reaches
    /// the dynamic initializers. They detect the layout at run time and use
    /// its metadata instead of the replay.
    func testGenericCallerThatErasesTheLayoutDoesNotReplay() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        assertRenders(
            genericSelect(layout).from(t),
            as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0"
        )
        assertRenders(genericReturning(layout), as: "RETURNING id, value")
    }
}


/// Runs each entry point on SQLite and decodes the rows through the layout.
/// Each test starts from one row, `("a", 1)`, in a new database.
final class StaticRowLayoutEntryPointExecutionTests: XCTestCase {

    private var databasePool: DatabasePool!

    private var database: GRDBDatabase!

    override func setUpWithError() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        let formatter = XLiteFormatter(identifierFormattingOptions: .sqlite)
        databasePool = try DatabasePool(path: fileURL.path)
        database = try GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
    }

    override func tearDown() {
        database = nil
        databasePool = nil
    }

    func testFunctionalSelectExecutes() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        let statement = select(layout).from(t)
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1)])
    }

    func testWithSelectExecutes() throws {
        let schema = XLSchema()
        let cte = schema.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = schema.table(cte)
        let layout = try testTableLayout(id: t.id, value: t.value)
        let statement = with(cte).select(layout).from(t)
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1)])
    }

    func testInsertSelectExecutes() throws {
        let schema = XLSchema()
        let target = schema.table(TestTable.self)
        let source = schema.table(TestTable.self)
        let layout = try testTableLayout(id: source.id, value: source.value)
        let statement = insert(target).select(layout).from(source)
        try database.makeRequest(with: statement).execute()

        let readSchema = XLSchema()
        let read = readSchema.table(TestTable.self)
        let rows: [TestTable] = try database.makeRequest(with: select(read).from(read)).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1), TestTable(id: "a", value: 1)])
    }

    func testQueryBuilderInitSelectExecutes() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        let statement = try QueryBuilder(select: layout).from(t).build()
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1)])
    }

    func testInsertReturningExecutes() throws {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let layout = try testTableLayout(id: t.id, value: t.value)
        let statement = insert(t).values(TestTable(id: "b", value: 2)).returning(layout)
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "b", value: 2)])
    }

    func testUpdateReturningExecutes() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        let statement = update(w).set { $0.value = 99 }.where(w.id == "a").returning(layout)
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 99)])
    }

    func testDeleteReturningExecutes() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        let statement = delete(w).where(w.id == "a").returning(layout)
        let rows: [TestTable] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [TestTable(id: "a", value: 1)])
    }
}
