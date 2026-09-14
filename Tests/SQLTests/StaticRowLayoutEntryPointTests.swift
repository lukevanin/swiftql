//
//  StaticRowLayoutEntryPointTests.swift
//
//  Issue #650: a statement built from `staticRowLayout(using:)` succeeds at
//  every entry point. Before the fix, the generic entry points saw a layout
//  only as `XLRowReadable`, replayed its `readRow` against the definition
//  reader, and trapped, because a layout reads dialect values that the
//  definition reader cannot supply.
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
        let sql = encoder.makeSQL(
            insert(t).values(TestTable(id: "a", value: 1)).returning(layout)
        ).sql
        XCTAssertTrue(sql.hasSuffix(" RETURNING id, value"), sql)
    }

    func testUpdateReturning() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        let sql = encoder.makeSQL(
            update(w).set { $0.value = 99 }.where(w.id == "a").returning(layout)
        ).sql
        XCTAssertTrue(sql.hasSuffix(" RETURNING id, value"), sql)
    }

    func testDeleteReturning() throws {
        let schema = XLSchema()
        let w = schema.into(TestTable.self)
        let projection = schema.table(TestTable.self)
        let layout = try testTableLayout(id: projection.id, value: projection.value)
        let sql = encoder.makeSQL(
            delete(w).where(w.id == "a").returning(layout)
        ).sql
        XCTAssertTrue(sql.hasSuffix(" RETURNING id, value"), sql)
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
    }

    override func tearDown() {
        database = nil
        databasePool = nil
    }

    func testEveryEntryPointExecutesAndDecodesThroughTheLayout() throws {
        // insert(...).returning(layout)
        let insertSchema = XLSchema()
        let insertTable = insertSchema.table(TestTable.self)
        let insertLayout = try testTableLayout(id: insertTable.id, value: insertTable.value)
        let inserted: [TestTable] = try database.makeRequest(
            with: insert(insertTable).values(TestTable(id: "a", value: 1)).returning(insertLayout)
        ).fetchAll()
        XCTAssertEqual(inserted, [TestTable(id: "a", value: 1)])

        // insert(...).select(layout)
        let copySchema = XLSchema()
        let copyTarget = copySchema.table(TestTable.self)
        let copySource = copySchema.table(TestTable.self)
        let copyLayout = try testTableLayout(
            id: copySource.id + "-copy",
            value: copySource.value + 1
        )
        try database.makeRequest(
            with: insert(copyTarget).select(copyLayout).from(copySource).where(copySource.id == "a")
        ).execute()

        // select(layout)
        let selectSchema = XLSchema()
        let selectTable = selectSchema.table(TestTable.self)
        let selectLayout = try testTableLayout(id: selectTable.id, value: selectTable.value)
        let selected: [TestTable] = try database.makeRequest(
            with: select(selectLayout).from(selectTable).orderBy(selectTable.id.ascending())
        ).fetchAll()
        XCTAssertEqual(selected, [TestTable(id: "a", value: 1), TestTable(id: "a-copy", value: 2)])

        // with(...).select(layout)
        let withSchema = XLSchema()
        let cte = withSchema.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id == "a-copy")
        }
        let withTable = withSchema.table(cte)
        let withLayout = try testTableLayout(id: withTable.id, value: withTable.value)
        let factored: [TestTable] = try database.makeRequest(
            with: with(cte).select(withLayout).from(withTable)
        ).fetchAll()
        XCTAssertEqual(factored, [TestTable(id: "a-copy", value: 2)])

        // QueryBuilder(select: layout)
        let builderSchema = XLSchema()
        let builderTable = builderSchema.table(TestTable.self)
        let builderLayout = try testTableLayout(id: builderTable.id, value: builderTable.value)
        let built: [TestTable] = try database.makeRequest(
            with: QueryBuilder(select: builderLayout)
                .from(builderTable)
                .and(builderTable.id == "a")
                .build()
        ).fetchAll()
        XCTAssertEqual(built, [TestTable(id: "a", value: 1)])

        // update(...).returning(layout)
        let updateSchema = XLSchema()
        let updateTarget = updateSchema.into(TestTable.self)
        let updateProjection = updateSchema.table(TestTable.self)
        let updateLayout = try testTableLayout(id: updateProjection.id, value: updateProjection.value)
        let updated: [TestTable] = try database.makeRequest(
            with: update(updateTarget).set { $0.value = 99 }.where(updateTarget.id == "a").returning(updateLayout)
        ).fetchAll()
        XCTAssertEqual(updated, [TestTable(id: "a", value: 99)])

        // delete(...).returning(layout)
        let deleteSchema = XLSchema()
        let deleteTarget = deleteSchema.into(TestTable.self)
        let deleteProjection = deleteSchema.table(TestTable.self)
        let deleteLayout = try testTableLayout(id: deleteProjection.id, value: deleteProjection.value)
        let deleted: [TestTable] = try database.makeRequest(
            with: delete(deleteTarget).where(deleteTarget.id == "a-copy").returning(deleteLayout)
        ).fetchAll()
        XCTAssertEqual(deleted, [TestTable(id: "a-copy", value: 2)])
    }
}
