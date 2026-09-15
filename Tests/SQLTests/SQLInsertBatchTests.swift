//
//  SQLInsertBatchTests.swift
//  SwiftQL
//
//  `GRDBDatabase.insert(contentsOf:)` (issue #668): a batch of rows of one
//  table renders one insert statement and prepares it once, instead of one
//  statement per row. Renders are counted through the database's encoder, and
//  preparations through the driver's DEBUG preparation hook, filtered to the
//  test's own database file. Committed state is read back through a fresh
//  `DatabasePool` and raw GRDB rows, not through the code under test.
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


/// An integer literal that renders a negative value as a unary minus applied
/// to its magnitude, so its values clause has a different shape from a
/// non-negative value's.
struct InsertBatchSignedCode: XLCustomType, Equatable {

    typealias T = Self

    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    init(reader: XLFieldReader) throws {
        rawValue = try reader.readInteger()
    }

    func bind(context: inout XLBindingContext) {
        context.bindInteger(value: rawValue)
    }

    func makeSQL(context: inout XLBuilder) {
        guard rawValue < 0 else {
            context.integer(rawValue)
            return
        }
        let magnitude = -rawValue
        context.unaryOperator("-") { context in
            context.integer(magnitude)
        }
    }

    static func sqlDefault() -> InsertBatchSignedCode {
        InsertBatchSignedCode(0)
    }
}


@SQLTable(name: "InsertBatchCoded")
struct InsertBatchCodedRow: Equatable {
    let id: Int
    let code: InsertBatchSignedCode
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

    private func makeTestRows(count: Int, prefix: String = "row") -> [TestTable] {
        (0 ..< count).map { index in
            TestTable(id: prefix + String(format: "-%03d", index), value: index * 7 - 50)
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

    /// Reads every value of `table` with its SQLite storage class through a
    /// brand-new pool, so a silent coercion shows up as a mismatch.
    private func committedTypedRows(
        at url: URL,
        table: String,
        columns: [String]
    ) throws -> [[String]] {
        let pool = try DatabasePool(path: url.path)
        defer { try? pool.close() }
        let selection = columns
            .map { "typeof(\($0)), quote(\($0))" }
            .joined(separator: ", ")
        return try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT \(selection) FROM \(table) ORDER BY id").map { row in
                (0 ..< row.count).map { index in row[index] as String }
            }
        }
    }

    private func committedMixedRows(at url: URL) throws -> [[String]] {
        try committedTypedRows(
            at: url,
            table: "InsertBatchMixed",
            columns: ["id", "label", "amount", "payload", "flag"]
        )
    }

    /// The SQL of every statement prepared on this test's own database file
    /// while `body` runs. Preparations on any other database are ignored.
    private func observingPreparations(_ body: () throws -> Void) throws -> [String] {
        var prepared: [String] = []
        try GRDBStatementPreparationTestHooks.shared.observe(
            databasePath: fileURL.path,
            { prepared.append($0) }
        ) {
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

    func testPreparationObserverIgnoresOtherDatabases() throws {
        try createTestTableWithPrimaryKey(in: database)
        let (_, _, otherDatabase) = try makeDatabase()
        try createTestTableWithPrimaryKey(in: otherDatabase)
        let rows = makeTestRows(count: 3)

        let prepared = try observingPreparations {
            try otherDatabase.insert(contentsOf: rows)
        }

        XCTAssertEqual(prepared, [])
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

    /// A row whose values clause has a different shape from the first row's
    /// renders on its own, with its literals, and the rows after it bind to
    /// the shared statement again.
    func testRowWithDifferentShapeRendersOnItsOwnAndLaterRowsStillBind() throws {
        try database.databasePool.write { db in
            try db.execute(sql: "CREATE TABLE InsertBatchCoded (id INTEGER PRIMARY KEY NOT NULL, code INTEGER NOT NULL)")
        }
        let rows = [
            InsertBatchCodedRow(id: 1, code: InsertBatchSignedCode(10)),
            InsertBatchCodedRow(id: 2, code: InsertBatchSignedCode(20)),
            InsertBatchCodedRow(id: 3, code: InsertBatchSignedCode(-30)),
            InsertBatchCodedRow(id: 4, code: InsertBatchSignedCode(40)),
        ]
        encoder.reset()

        let prepared = try observingPreparations {
            try database.withTransaction { scope in
                try scope.insert(contentsOf: rows)
            }
        }

        XCTAssertEqual(encoder.renderCount, 2, "Only the row with a different shape renders again.")
        XCTAssertEqual(prepared.count, 2, "The shared statement and the one literal row prepare once each.")
        XCTAssertTrue(prepared.first?.contains(":swiftql_insert_1") ?? false)
        XCTAssertFalse(prepared.last?.contains(":swiftql_insert_") ?? true)
        XCTAssertEqual(
            try committedTypedRows(at: fileURL, table: "InsertBatchCoded", columns: ["id", "code"]),
            [
                ["integer", "1", "integer", "10"],
                ["integer", "2", "integer", "20"],
                ["integer", "3", "integer", "-30"],
                ["integer", "4", "integer", "40"],
            ]
        )
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

    /// A caught mid-batch failure inside a scope removes every row of that
    /// batch, and keeps the writes the body made before and after it.
    func testCaughtFailureInsideScopeRollsBackOnlyTheBatch() throws {
        try createTestTableWithPrimaryKey(in: database)
        let before = TestTable(id: "a-before", value: 1)
        let after = TestTable(id: "z-after", value: 2)
        let second = TestTable(id: "n-second", value: 4)
        var batch = makeTestRows(count: 100, prefix: "m-batch")
        batch[50] = TestTable(id: batch[10].id, value: 3)

        var batchError: Error?
        try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(before)).execute()
            do {
                try scope.insert(contentsOf: batch)
            }
            catch {
                batchError = error
            }
            try scope.makeRequest(with: sqlInsert(after)).execute()
            // A second batch on the same scope still works after the failure.
            try scope.insert(contentsOf: [second])
        }

        XCTAssertNotNil(batchError, "The duplicate key must fail the batch.")
        XCTAssertEqual(try committedTestRows(at: fileURL), [before, second, after])
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
        let rows = makeTestRows(count: 2)

        XCTAssertThrowsError(try XCTUnwrap(escaped).insert(contentsOf: rows)) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testEscapedScopeThrowsScopeEscapedForAnEmptySequence() throws {
        var escaped: GRDBDatabase?
        try database.withTransaction { scope in
            escaped = scope
        }
        encoder.reset()

        XCTAssertThrowsError(try XCTUnwrap(escaped).insert(contentsOf: [TestTable]())) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .scopeEscaped)
        }
        XCTAssertEqual(encoder.renderCount, 0)
    }

    func testRootDatabaseInsideTransactionIsRejected() throws {
        try createTestTableWithPrimaryKey(in: database)
        let root: GRDBDatabase = database
        let rows = makeTestRows(count: 2)

        XCTAssertThrowsError(
            try root.withTransaction { _ in
                try root.insert(contentsOf: rows)
            }
        ) { error in
            XCTAssertEqual(error as? XLTransactionScopeError, .nestedTransactionUnsupported)
        }
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    func testEmptySequenceRendersAndWritesNothing() throws {
        try createTestTableWithPrimaryKey(in: database)
        encoder.reset()

        XCTAssertNoThrow(try database.insert(contentsOf: [TestTable]()))
        XCTAssertNoThrow(
            try database.withTransaction { scope in
                try scope.insert(contentsOf: [TestTable]())
            }
        )
        XCTAssertEqual(encoder.renderCount, 0)
        XCTAssertEqual(try committedTestRows(at: fileURL), [])
    }

    /// Every element of a lazy sequence is produced inside the connection
    /// access, after the scope's liveness was checked.
    func testLazySequenceIsReadInsideTheConnectionAccess() throws {
        try createTestTableWithPrimaryKey(in: database)
        var escaped: GRDBDatabase?
        try database.withTransaction { scope in
            escaped = scope
        }
        var producedCount = 0
        let lazyRows = (0 ..< 3).lazy.map { index -> TestTable in
            producedCount += 1
            return TestTable(id: "lazy-\(index)", value: index)
        }

        XCTAssertThrowsError(try XCTUnwrap(escaped).insert(contentsOf: lazyRows))
        XCTAssertEqual(producedCount, 0, "An escaped scope must fail before the sequence is read.")

        try database.insert(contentsOf: lazyRows)
        XCTAssertEqual(producedCount, 3)
    }
}
