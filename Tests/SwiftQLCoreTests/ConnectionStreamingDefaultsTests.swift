import Foundation
import XCTest

import SwiftQLCore


/// Issue #682: `forEachRow(_:_:)`, `withValuesStepper(_:_:)`, and
/// `validateBindings(in:)` are public connection requirements with defaults,
/// so a connection that implements only `fetchAll(_:)` still serves
/// row-at-a-time consumers.
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
