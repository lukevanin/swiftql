//
//  SQLQueryPeerMacroTests.swift
//  SwiftQL
//
//  Runtime tests for the `@SQLQuery` peer macro (issues #18/#26): the
//  generated statement builders render placeholder SQL with a typed parameter
//  layout, and the generated executors bind invocation values and fetch rows
//  from a GRDB database. Ported from the milestone #28 spike on
//  `experiment/sqlquery-peer-macro`, extended with `.exactlyOne` cardinality
//  coverage added for v1.5.1.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


extension GRDBDatabase {

    @SQLQuery
    func rowsMatchingID(id: String) -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    // Direct-result specs — no `XLQueryStatement` boilerplate. `[TestTable]`
    // dispatches to fetchAll; `TestTable?` dispatches to fetchOne; a bare
    // `TestTable` dispatches to the v1.5.1 `.exactlyOne` cardinality.

    @SQLQuery
    func directRowsMatchingID(id: String) -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func directRowMatchingID(id: String) -> TestTable? {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func theOnlyRowMatchingID(id: String) -> TestTable {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }

    @SQLQuery
    func rowsMatchingIDAndMinimumValue(id: String, minimumValue: Int) -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id && table.value >= minimumValue)
        }
    }

    @SQLQuery
    func doubleRowsMatchingValue(value: Double) -> any XLQueryStatement<DoubleTest> {
        sql { schema in
            let table = schema.table(DoubleTest.self)
            Select(table)
            From(table)
            Where(table.value == value)
        }
    }

    @SQLQuery
    func nullableRowsMatchingValue(value: Int?) -> any XLQueryStatement<TestNullablesTable> {
        sql { schema in
            let table = schema.table(TestNullablesTable.self)
            Select(table)
            From(table)
            Where(table.value == value)
        }
    }
}


final class XLQueryPeerMacroTests: XCTestCase {

    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory
            .appendingPathComponent(filename, isDirectory: false)
            .appendingPathExtension("sqlite")
        encoder = XLiteEncoder(formatter: formatter)
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        encoder = nil
        databasePool = nil
        database = nil
    }


    // MARK: - Placeholder rendering

    func testOneParameterStatementRendersNamedPlaceholderSQL() throws {
        let encoding = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(
            encoding.sql,
            "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (`t0`.`id` == :id)"
        )
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.key), [.named("id")])
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.nullability), [.required])
    }

    func testTwoParameterStatementRendersNamedPlaceholderSQL() throws {
        let encoding = encoder.makeSQL(database.rowsMatchingIDAndMinimumValueStatement())

        XCTAssertTrue(encoding.sql.contains(":id"), "expected ':id' placeholder in \(encoding.sql)")
        XCTAssertTrue(encoding.sql.contains(":minimumValue"), "expected ':minimumValue' placeholder in \(encoding.sql)")
        XCTAssertFalse(encoding.sql.contains("'"), "expected no inline value literal in \(encoding.sql)")
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.key),
            [.named("id"), .named("minimumValue")]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.nullability),
            [.required, .required]
        )
    }

    func testOptionalParameterStatementRendersNullableSlot() throws {
        let encoding = encoder.makeSQL(database.nullableRowsMatchingValueStatement())

        XCTAssertTrue(encoding.sql.contains(":value"), "expected ':value' placeholder in \(encoding.sql)")
        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.key), [.named("value")])
        XCTAssertEqual(encoding.parameterLayout.slots.map(\.nullability), [.nullable])
    }

    func testStatementBuilderRendersIdenticalSQLOnRepeatedCalls() throws {
        let first = encoder.makeSQL(database.rowsMatchingIDStatement())
        let second = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(first.sql, second.sql)
        XCTAssertEqual(first.parameterLayout, second.parameterLayout)
    }


    // MARK: - Execution

    func testOneParameterExecutorFetchesMatchingRowsForEachInvocation() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "alpha"),
            [TestTable(id: "alpha", value: 1)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 2)]
        )
        XCTAssertEqual(try database.fetchRowsMatchingID(id: "gamma"), [])
    }

    func testTwoParameterExecutorFetchesMatchingRows() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "alpha", minimumValue: 2),
            [TestTable(id: "alpha", value: 5)]
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "alpha", minimumValue: 0).count,
            2
        )
        XCTAssertEqual(
            try database.fetchRowsMatchingIDAndMinimumValue(id: "beta", minimumValue: 10),
            []
        )
    }

    func testOptionalParameterExecutorBindsValueAndSQLNull() throws {
        try createNullablesTable()
        try insert(TestNullablesTable(id: "with-value", value: 42))
        try insert(TestNullablesTable(id: "without-value", value: nil))

        XCTAssertEqual(
            try database.fetchNullableRowsMatchingValue(value: 42),
            [TestNullablesTable(id: "with-value", value: 42)]
        )
        // Optional equality renders as SQL `IS`, which is null-safe: a nil
        // binding matches the row whose column is NULL.
        XCTAssertEqual(
            try database.fetchNullableRowsMatchingValue(value: nil),
            [TestNullablesTable(id: "without-value", value: nil)]
        )
    }


    // MARK: - Direct-result execution

    func testDirectResultArrayExecutorFetchesAllMatchingRows() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        // `-> [TestTable]` dispatched to fetchAll and returned every match.
        XCTAssertEqual(
            try database.fetchDirectRowsMatchingID(id: "alpha").count,
            2
        )
        XCTAssertEqual(
            try database.fetchDirectRowsMatchingID(id: "beta"),
            [TestTable(id: "beta", value: 9)]
        )
        XCTAssertEqual(try database.fetchDirectRowsMatchingID(id: "gamma"), [])
    }

    func testDirectResultOptionalExecutorFetchesSingleRow() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        // `-> TestTable?` dispatched to fetchOne and returned an optional row.
        XCTAssertEqual(
            try database.fetchDirectRowMatchingID(id: "beta"),
            TestTable(id: "beta", value: 9)
        )
        XCTAssertNil(try database.fetchDirectRowMatchingID(id: "gamma"))
    }

    func testDirectResultStatementRendersSamePlaceholderSQLAsLegacyForm() throws {
        // The direct-result spec produces the same value-free statement as the
        // legacy XLQueryStatement spelling: a named placeholder, no inline
        // literal. The `sqlResult` -> `sql` callee swap is transparent.
        let direct = encoder.makeSQL(database.directRowsMatchingIDStatement())
        let legacy = encoder.makeSQL(database.rowsMatchingIDStatement())

        XCTAssertEqual(direct.sql, legacy.sql)
        XCTAssertTrue(direct.sql.contains(":id"))
        XCTAssertFalse(direct.sql.contains("'"))
        XCTAssertEqual(direct.parameterLayout.slots.map(\.key), [.named("id")])
    }


    // MARK: - Exactly-one cardinality (v1.5.1)

    func testBareRowExecutorReturnsTheSingleMatchingRow() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 9))

        XCTAssertEqual(
            try database.fetchTheOnlyRowMatchingID(id: "alpha"),
            TestTable(id: "alpha", value: 1)
        )
    }

    func testBareRowExecutorThrowsWhenNoRowMatches() throws {
        try createTestTable()

        XCTAssertThrowsError(try database.fetchTheOnlyRowMatchingID(id: "missing")) { error in
            XCTAssertEqual(
                error as? XLQueryCardinalityError,
                .noRowsMatched
            )
        }
    }

    func testBareRowExecutorThrowsWhenMultipleRowsMatch() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 2))

        XCTAssertThrowsError(try database.fetchTheOnlyRowMatchingID(id: "alpha")) { error in
            XCTAssertEqual(
                error as? XLQueryCardinalityError,
                .moreThanOneRowMatched
            )
        }
    }


    // MARK: - Non-finite REAL parameters

    /// SwiftQL rejects a bound NaN rather than letting SQLite's binding API
    /// silently store SQL `NULL` in its place (see the Real Values article).
    /// `_xlQueryParameterBinding` -- the capture the generated executors call
    /// for every macro parameter -- used to skip that check, unlike the codec
    /// and static-layout captures beside it, and returned `.real(nan)`. The
    /// driver boundary caught it before it ever reached SQLite, so nothing was
    /// ever stored as `NULL`; the value now fails at the point of capture, with
    /// the same error the driver produced.
    func testNaNDoubleParameterIsRejectedAtCapture() throws {
        let layout = encoder
            .makeSQL(database.doubleRowsMatchingValueStatement())
            .parameterLayout

        XCTAssertThrowsError(
            try _xlQueryParameterBinding(Double.nan, named: "value", in: layout)
        ) { error in
            XCTAssertEqual(
                error as? XLSQLValueEncodingError,
                .realBindingWouldBecomeNull(
                    value: .notANumber,
                    valueType: String(reflecting: Double.self),
                    context: XLValueCodingContext(
                        site: .parameter,
                        path: XLValueCodingPath("value")
                    )
                )
            )
        }
    }

    /// The same rejection seen through the generated executor, which is how a
    /// caller meets it.
    func testNaNDoubleParameterIsRejectedThroughTheGeneratedExecutor() throws {
        try createDoubleTable()

        XCTAssertThrowsError(
            try database.fetchDoubleRowsMatchingValue(value: .nan)
        ) { error in
            XCTAssertEqual(
                error as? XLSQLValueEncodingError,
                .realBindingWouldBecomeNull(
                    value: .notANumber,
                    valueType: String(reflecting: Double.self),
                    context: XLValueCodingContext(
                        site: .parameter,
                        path: XLValueCodingPath("value")
                    )
                )
            )
        }
    }

    /// Infinities survive SQLite's binding round trip, so the guard must let
    /// them through -- it rejects NaN specifically, not every non-finite value.
    /// Only the bound parameter carries an infinity here: an inline `REAL`
    /// literal is a separate policy and is rejected before SQLite parses the
    /// statement, so the fixture rows hold finite values.
    func testInfiniteDoubleParametersRemainBindable() throws {
        try createDoubleTable()
        try insert(DoubleTest(id: "finite", value: 1.5))

        XCTAssertEqual(try database.fetchDoubleRowsMatchingValue(value: .infinity), [])
        XCTAssertEqual(try database.fetchDoubleRowsMatchingValue(value: -.infinity), [])
        XCTAssertEqual(
            try database.fetchDoubleRowsMatchingValue(value: 1.5),
            [DoubleTest(id: "finite", value: 1.5)]
        )
    }


    // MARK: - Helpers

    private func createDoubleTable() throws {
        try database.makeRequest(with: sqlCreate(DoubleTest.self)).execute()
    }

    private func insert(_ row: DoubleTest) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func createNullablesTable() throws {
        try database.makeRequest(with: sqlCreate(TestNullablesTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }

    private func insert(_ row: TestNullablesTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
