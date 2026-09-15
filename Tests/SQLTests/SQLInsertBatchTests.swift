//
//  SQLInsertBatchTests.swift
//  SwiftQL
//
//  `GRDBDatabase.insert(contentsOf:)` (issue #668): a batch of rows of one
//  table renders one insert statement and prepares it once, instead of one
//  statement per row. Renders are counted through the database's encoder, and
//  preparations through the driver's DEBUG preparation hook. Committed state is
//  read back through a fresh `DatabasePool` and raw GRDB rows, not through the
//  code under test.
//

import Foundation
import XCTest
import GRDB
@testable import SwiftQL


@SQLTable(name: "InsertBatchMixed")
struct InsertBatchMixedRow: Equatable {
    let id: Int
    let label: String?
    let amount: Double
    let payload: Data?
    let flag: Bool
}


/// Counts every statement the database renders.
private final class CountingEncoder: XLEncoder {

    private let base: XLEncoder

    private(set) var renderCount = 0

    init(base: XLEncoder) {
        self.base = base
    }

    func makeSQL(_ expression: any XLEncodable) -> XLEncoding {
        renderCount += 1
        return base.makeSQL(expression)
    }

    func reset() {
        renderCount = 0
    }
}


final class SQLInsertBatchTests: XCTestCase {

    private struct UserError: Error, Equatable {}

    /// The statement `sqlInsert(_:)` renders for `TestTable`, with a parameter
    /// in place of each literal. The default dialect quotes identifiers.
    private static let batchInsertSQL =
        #"INSERT INTO "Test" AS "t0" ("id","value") VALUES (:swiftql_insert_0,:swiftql_insert_1)"#

    private var fileURLs: [URL] = []
    private var pools: [DatabasePool] = []
    private var fileURL: URL!
    private var encoder: CountingEncoder!
    private var database: GRDBDatabase!

    override func setUpWithError() throws {
        (fileURL, encoder, database) = try makeDatabase()
    }

    override func tearDown() {
        for pool in pools {
            try? pool.close()
        }
        for url in fileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        pools = []
        fileURLs = []
        fileURL = nil
        encoder = nil
        database = nil
    }

    private func makeDatabase() throws -> (URL, CountingEncoder, GRDBDatabase) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        let pool = try DatabasePool(path: url.path)
        fileURLs.append(url)
        pools.append(pool)
        let encoder = CountingEncoder(base: XLiteEncoder(dialect: XLSQLiteDialect()))
        let database = GRDBDatabase(
            databasePool: pool,
            configuration: GRDBDatabaseConfiguration(
                codingConfiguration: try XLValueCodingConfiguration(),
                encoder: encoder
            )
        )
        return (url, encoder, database)
    }

    // MARK: - Helpers

    private func createTestTableWithPrimaryKey(in database: GRDBDatabase) throws {
        try database.databasePool.write { db in
            try db.execute(sql: "CREATE TABLE Test (id TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL)")
        }
    }

    private func createMixedTable(in database: GRDBDatabase) throws {
        try database.databasePool.write { db in
            try db.execute(sql: """
                CREATE TABLE InsertBatchMixed (
                    id INTEGER PRIMARY KEY NOT NULL,
                    label TEXT,
                    amount REAL NOT NULL,
                    payload BLOB,
                    flag INTEGER NOT NULL
                )
                """)
        }
    }

    private func makeTestRows(count: Int) -> [TestTable] {
        (0 ..< count).map { index in
            TestTable(id: String(format: "row-%03d", index), value: index * 7 - 50)
        }
    }

    /// Reads `Test` through a brand-new pool on the same file, so only
    /// committed state is visible.
    private func committedTestRows(at url: URL) throws -> [TestTable] {
        let pool = try DatabasePool(path: url.path)
        defer { try? pool.close() }
        return try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, value FROM Test ORDER BY id").map { row in
                TestTable(id: row["id"], value: row["value"])
            }
        }
    }

    /// Reads every `InsertBatchMixed` value with its SQLite storage class
    /// through a brand-new pool, so a silent coercion shows up as a mismatch.
    private func committedMixedRows(at url: URL) throws -> [[String]] {
        let pool = try DatabasePool(path: url.path)
        defer { try? pool.close() }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT typeof(id), quote(id), typeof(label), quote(label),
                       typeof(amount), quote(amount), typeof(payload), quote(payload),
                       typeof(flag), quote(flag)
                FROM InsertBatchMixed ORDER BY id
                """).map { row in
                (0 ..< row.count).map { index in row[index] as String }
            }
        }
    }

    private func observingPreparations(_ body: () throws -> Void) throws -> [String] {
        var prepared: [String] = []
        try GRDBStatementPreparationTestHooks.shared.observe({ prepared.append($0) }) {
            try body()
        }
        return prepared
    }

    // MARK: - Render and prepare once

    func testHundredRowBatchInsideTransactionRendersAndPreparesOnce() throws {
        try createTestTableWithPrimaryKey(in: database)
        let rows = makeTestRows(count: 100)
        encoder.reset()

        let prepared = try observingPreparations {
            try database.withTransaction { scope in
                try scope.insert(contentsOf: rows)
            }
        }

        XCTAssertEqual(encoder.renderCount, 1, "The batch must render one statement for 100 rows.")
        XCTAssertEqual(prepared, [Self.batchInsertSQL], "The batch must prepare one statement for 100 rows.")
        XCTAssertEqual(try committedTestRows(at: fileURL), rows)
    }

    /// The per-row spelling the batch replaces. Pinned so the gap the batch
    /// closes stays visible: each row renders its values as literals, so each
    /// row is a different SQL string that SQLite prepares again.
    func testPerRowSQLInsertRendersAndPreparesEveryRow() throws {
        try createTestTableWithPrimaryKey(in: database)
        let rows = makeTestRows(count: 100)
        encoder.reset()

        let prepared = try observingPreparations {
            try database.withTransaction { scope in
                for row in rows {
                    try scope.makeRequest(with: sqlInsert(row)).execute()
                }
            }
        }

        XCTAssertEqual(encoder.renderCount, 100)
        XCTAssertEqual(Set(prepared).count, 100)
        XCTAssertEqual(try committedTestRows(at: fileURL), rows)
    }

    func testSingleRowInsertSQLIsUnchanged() {
        let encoding = XLiteEncoder(dialect: XLSQLiteDialect())
            .makeSQL(sqlInsert(TestTable(id: "foo", value: 42)))
        XCTAssertEqual(encoding.sql, #"INSERT INTO "Test" AS "t0" ("id","value") VALUES ('foo',42)"#)
        XCTAssertTrue(encoding.parameterLayout.isEmpty)
    }

    func testBatchOnDatabaseCommitsEveryRowInOneTransaction() throws {
        try createTestTableWithPrimaryKey(in: database)
        let rows = makeTestRows(count: 100)
        encoder.reset()

        let prepared = try observingPreparations {
            try database.insert(contentsOf: rows)
        }

        XCTAssertEqual(encoder.renderCount, 1)
        XCTAssertEqual(prepared, [Self.batchInsertSQL])
        XCTAssertEqual(try committedTestRows(at: fileURL), rows)
    }

    // MARK: - Values

    func testBatchStoresTheSameValuesAsPerRowInserts() throws {
        let rows = [
            InsertBatchMixedRow(id: 1, label: "plain", amount: 1234.5678, payload: Data([0x00, 0xff, 0x10]), flag: true),
            InsertBatchMixedRow(id: 2, label: nil, amount: -0.25, payload: nil, flag: false),
            InsertBatchMixedRow(id: 3, label: "it's \"quoted\"", amount: 3.0, payload: Data(), flag: true),
            InsertBatchMixedRow(id: Int.max, label: "", amount: 1e300, payload: Data([0x27]), flag: false),
            InsertBatchMixedRow(id: Int.min, label: "\u{1F600} unicode", amount: 0.1, payload: nil, flag: true),
        ]

        try createMixedTable(in: database)
        encoder.reset()
        let prepared = try observingPreparations {
            try database.withTransaction { scope in
                try scope.insert(contentsOf: rows)
            }
        }
        XCTAssertEqual(encoder.renderCount, 1, "A NULL and a non-NULL value must share one statement.")
        XCTAssertEqual(prepared.count, 1)

        let (perRowURL, _, perRowDatabase) = try makeDatabase()
        try createMixedTable(in: perRowDatabase)
        try perRowDatabase.withTransaction { scope in
            for row in rows {
                try scope.makeRequest(with: sqlInsert(row)).execute()
            }
        }

        let batchState = try committedMixedRows(at: fileURL)
        XCTAssertEqual(batchState.count, rows.count)
        XCTAssertEqual(batchState, try committedMixedRows(at: perRowURL))
    }

    func testNonFiniteRealFailsAsTheSingleRowInsertDoesAndRollsBack() throws {
        try createMixedTable(in: database)
        let finite = InsertBatchMixedRow(id: 1, label: "a", amount: 1, payload: nil, flag: true)
        let infinite = InsertBatchMixedRow(id: 2, label: "b", amount: .infinity, payload: nil, flag: true)

        var singleRowError: Error?
        XCTAssertThrowsError(try database.makeRequest(with: sqlInsert(infinite)).execute()) { error in
            singleRowError = error
        }
        encoder.reset()

        var batchError: Error?
        XCTAssertThrowsError(try database.insert(contentsOf: [finite, infinite])) { error in
            batchError = error
        }

        XCTAssertNotNil(singleRowError as? XLSQLValueEncodingError)
        XCTAssertEqual(
            batchError.map { String(describing: $0) },
            singleRowError.map { String(describing: $0) }
        )
        XCTAssertEqual(encoder.renderCount, 2, "The failing row renders on its own, as sqlInsert(_:) does.")
        XCTAssertEqual(try committedMixedRows(at: fileURL), [], "The finite row must roll back.")
    }

    // MARK: - Transaction and lifetime

    func testConstraintFailureOnDatabaseRollsBackEveryRow() throws {
        try createTestTableWithPrimaryKey(in: database)
        var rows = makeTestRows(count: 100)
        rows[50] = TestTable(id: rows[10].id, value: 1)

        XCTAssertThrowsError(try database.insert(contentsOf: rows))
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testBatchRollsBackWithTheEnclosingScope() throws {
        try createTestTableWithPrimaryKey(in: database)
        let rows = makeTestRows(count: 10)

        XCTAssertThrowsError(
            try database.withTransaction { scope in
                try scope.insert(contentsOf: rows)
                throw UserError()
            }
        ) { error in
            XCTAssertEqual(error as? UserError, UserError())
        }
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testBatchReadsItsOwnWritesInsideTheScope() throws {
        try createTestTableWithPrimaryKey(in: database)
        let rows = makeTestRows(count: 3)

        let visible = try database.withTransaction { scope -> [TestTable] in
            try scope.insert(contentsOf: rows)
            return try scope.makeRequest(with: sql { schema in
                let test = schema.table(TestTable.self)
                Select(test)
                From(test)
                OrderBy(test.id.ascending())
            }).fetchAll()
        }
        XCTAssertEqual(visible, rows)
    }

    func testEscapedScopeThrowsScopeEscaped() throws {
        try createTestTableWithPrimaryKey(in: database)
        var escaped: GRDBDatabase?
        try database.withTransaction { scope in
            escaped = scope
        }

        XCTAssertThrowsError(try XCTUnwrap(escaped).insert(contentsOf: makeTestRows(count: 2))) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testRootDatabaseInsideTransactionIsRejected() throws {
        try createTestTableWithPrimaryKey(in: database)
        let root = database!

        XCTAssertThrowsError(
            try root.withTransaction { _ in
                try root.insert(contentsOf: self.makeTestRows(count: 2))
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testEmptySequenceRendersNothingAndTouchesNoConnection() throws {
        var escaped: GRDBDatabase?
        try database.withTransaction { scope in
            escaped = scope
        }
        encoder.reset()

        XCTAssertNoThrow(try XCTUnwrap(escaped).insert(contentsOf: [TestTable]()))
        XCTAssertEqual(encoder.renderCount, 0)
    }
}
