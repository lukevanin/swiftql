import Foundation
import XCTest

import SwiftQLCore


/// Issue #682: `forEachRow(_:_:)`, `withValuesStepper(_:_:)`, and
/// `validateBindings(in:)` are public connection requirements with defaults,
/// so a connection that implements only `fetchAll(_:)` still serves
/// row-at-a-time consumers. Issue #678 adds `forEachRowHandle(_:_:)` and
/// `withRowHandleStepper(_:_:)`, whose defaults wrap those rows in
/// `XLValuesRowHandle`.
final class ConnectionStreamingDefaultsTests: XCTestCase {

    func testDefaultForEachRowVisitsRowsInOrderAndStopsWhenAsked() throws {
        var connection = EagerConnection(rows: [[.integer(1)], [.integer(2)], [.integer(3)]])
        var visited: [[XLSQLiteValue]] = []

        try connection.forEachRow("SELECT") { row in
            visited.append(row)
            return visited.count == 2 ? .stop : .advance
        }

        XCTAssertEqual(visited, [[.integer(1)], [.integer(2)]])
    }

    func testDefaultForEachRowRethrowsTheCallbackError() {
        struct Stop: Error {}
        var connection = EagerConnection(rows: [[.integer(1)]])

        XCTAssertThrowsError(try connection.forEachRow("SELECT") { _ in throw Stop() }) { error in
            XCTAssertTrue(error is Stop)
        }
    }

    func testDefaultStepperReturnsEachRowThenStaysExhausted() throws {
        var connection = EagerConnection(rows: [[.text("a")], [.text("b")]])

        let stepped = try connection.withValuesStepper("SELECT") { next -> [[XLSQLiteValue]?] in
            [try next(), try next(), try next(), try next()]
        }

        XCTAssertEqual(stepped, [[.text("a")], [.text("b")], nil, nil])
    }

    func testDefaultStepperReportsAFetchFailureBeforeBodyRuns() {
        var connection = EagerConnection(rows: [], failsFetch: true)
        var bodyRan = false

        XCTAssertThrowsError(
            try connection.withValuesStepper("SELECT") { _ in bodyRan = true }
        )
        XCTAssertFalse(bodyRan)
    }

    func testDefaultValidateBindingsAcceptsAnyStatement() {
        let connection = EagerConnection(rows: [])

        XCTAssertNoThrow(try connection.validateBindings(in: "SELECT ?"))
    }

    // MARK: - Row handles (issue #678)

    /// A connection that declares no row handle gets ``XLValuesRowHandle``,
    /// and its row-handle members wrap the value-level ones.
    func testDefaultRowHandleIsTheValuesHandle() {
        XCTAssertTrue(EagerConnection.RowHandle.self == XLValuesRowHandle<XLSQLiteValue>.self)
    }

    func testDefaultForEachRowHandleReadsEachRowAndStopsWhenAsked() throws {
        var connection = EagerConnection(rows: [
            [.integer(1), .text("one")],
            [.integer(2), .text("two")],
            [.integer(3), .text("three")],
        ])
        var visited: [String] = []

        try connection.forEachRowHandle("SELECT") { row in
            visited.append("\(try row.readInteger(at: 0)) \(try row.readText(at: 1))")
            return visited.count == 2 ? .stop : .advance
        }

        XCTAssertEqual(visited, ["1 one", "2 two"])
    }

    func testDefaultRowHandleStepperReturnsEachRowThenStaysExhausted() throws {
        var connection = EagerConnection(rows: [[.text("a")], [.text("b")]])

        let stepped = try connection.withRowHandleStepper("SELECT") { next -> [String?] in
            try (0 ..< 4).map { _ in try next()?.readText(at: 0) }
        }

        XCTAssertEqual(stepped, ["a", "b", nil, nil])
    }

    func testDefaultRowHandleStepperReportsAFetchFailureBeforeBodyRuns() {
        var connection = EagerConnection(rows: [], failsFetch: true)
        var bodyRan = false

        XCTAssertThrowsError(
            try connection.withRowHandleStepper("SELECT") { _ in bodyRan = true }
        )
        XCTAssertFalse(bodyRan)
    }

    func testValuesRowHandleReadsBySQLiteStorageClassRules() throws {
        let row = XLValuesRowHandle<XLSQLiteValue>([
            .integer(42), .real(42.75), .blob(Data("text".utf8)), .text("blob"), .null,
        ])

        XCTAssertEqual(row.columnCount, 5)
        XCTAssertEqual(try row.readReal(at: 0), 42)
        XCTAssertEqual(try row.readInteger(at: 1), 42)
        XCTAssertEqual(try row.readText(at: 2), "text")
        XCTAssertEqual(try row.readBlob(at: 3), Data("blob".utf8))
        XCTAssertTrue(try row.isNull(at: 4))
        XCTAssertFalse(try row.isNull(at: 0))
        XCTAssertEqual(try row.copyValues(), row.values)
        assertReadError(
            try row.readText(at: 0),
            XLColumnReadError(index: 0, expectedType: "String", failure: .typeMismatch(actualType: "INTEGER"))
        )
        assertReadError(
            try row.readInteger(at: 4),
            XLColumnReadError(index: 4, expectedType: "Int", failure: .nullValue)
        )
        assertReadError(
            try row.readInteger(at: 5),
            XLColumnReadError(index: 5, expectedType: "Int", failure: .indexOutOfBounds(valueCount: 5))
        )
        assertReadError(
            try row.value(at: -1),
            XLColumnReadError(index: -1, expectedType: nil, failure: .indexOutOfBounds(valueCount: 5))
        )
    }

    /// A value of another dialect has no SQLite storage class, so a column
    /// read refuses it by name, and ``XLRowHandle/value(at:)`` still reads it.
    func testValuesRowHandleRefusesAColumnReadOfAnotherDialectsValue() throws {
        let row = XLValuesRowHandle<OtherDialectValue>([OtherDialectValue(storageType: "token")])

        XCTAssertEqual(try row.value(at: 0), OtherDialectValue(storageType: "token"))
        assertReadError(
            try row.readText(at: 0),
            XLColumnReadError(index: 0, expectedType: "String", failure: .typeMismatch(actualType: "token"))
        )
    }

    /// A SQLite handle that implements only `value(at:)` gets the five column
    /// reads, and each read asks for its own column alone.
    func testSQLiteHandleReadsOneColumnPerReadThroughValueAt() throws {
        let row = CountingSQLiteHandle(row: [.text("skip"), .integer(7), .blob(Data([1]))])

        XCTAssertEqual(try row.readInteger(at: 1), 7)
        XCTAssertEqual(row.reads.indices, [1])
        XCTAssertEqual(try row.readText(at: 2), "\u{1}")
        XCTAssertEqual(row.reads.indices, [1, 2])
        assertReadError(
            try row.readReal(at: 3),
            XLColumnReadError(index: 3, expectedType: "Double", failure: .indexOutOfBounds(valueCount: 3))
        )
        XCTAssertEqual(row.reads.indices, [1, 2], "An out-of-bounds read is refused before value(at:).")
        XCTAssertEqual(try row.copyValues(), [.text("skip"), .integer(7), .blob(Data([1]))])
    }

    private func assertReadError<T>(
        _ expression: @autoclosure () throws -> T,
        _ expected: XLColumnReadError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLColumnReadError, expected, file: file, line: line)
        }
    }
}


/// A dialect value that is not SQLite's.
private struct OtherDialectValue: XLDialectValue {
    let storageType: String
}


/// Records the column indices `value(at:)` was asked for.
private final class ReadRecord {
    var indices: [Int] = []
}


/// A SQLite row handle that implements only the required members.
private struct CountingSQLiteHandle: XLRowHandle {

    let row: [XLSQLiteValue]

    let reads = ReadRecord()

    var columnCount: Int {
        row.count
    }

    func value(at index: Int) throws -> XLSQLiteValue {
        reads.indices.append(index)
        return row[index]
    }
}


/// A connection that implements only the required members, so every row
/// consumer runs on the contract's defaults.
private struct EagerConnection: XLDatabaseDriverConnection {

    struct FetchFailure: Error {}

    let driverIdentifier = XLDriverIdentifier(rawValue: "eager-double")
    let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    let dialect = XLSQLiteDialect()
    let rows: [[XLSQLiteValue]]
    var failsFetch = false

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        statement.logicalStatement.sql
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        if failsFetch {
            throw FetchFailure()
        }
        return rows
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        try fetchAll(statement).first
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .write)
    }
}
