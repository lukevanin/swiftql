//
//  CursorDriverTests.swift
//  SwiftQLDriverDatabaseTests
//
//  Issue #678: requests decode each row by reading its columns from the row
//  handle a driver's cursor lends, and a driver outside SwiftQL backs a
//  lazily stepped `XLResultSet` through the public row-handle stepper.
//

import Foundation
import SwiftQL
import XCTest


final class CursorDriverTests: XCTestCase {

    private var driver: CursorDriver!

    private var database: XLDriverDatabase<CursorDriver>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        driver = CursorDriver()
        database = try XLDriverDatabase(driver: driver)
        driver.log.rows = [
            [.text("ann"), .integer(31)],
            [.text("ben"), .integer(42)],
            [.text("cy"), .integer(53)],
        ]
    }

    override func tearDown() {
        database = nil
        driver = nil
        super.tearDown()
    }

    /// Each `next()` steps one row and reads its two columns from the handle,
    /// and stopping early leaves the later rows unstepped. Nothing is fetched
    /// eagerly.
    func testResultSetStepsTheDriverCursorOneRowPerNext() throws {
        let request = database.makeRequest(with: selectPeople())

        let first = try request.withResultSet { rows -> DriverPerson? in
            XCTAssertEqual(driver.log.events, [], "No row is stepped before next().")
            let first = try rows.next()
            XCTAssertEqual(driver.log.events, ["step 0", "read 0.0", "read 0.1"])
            return first
        }

        XCTAssertEqual(first, DriverPerson(id: "ann", age: 31))
        XCTAssertEqual(driver.log.events, ["step 0", "read 0.0", "read 0.1"])
    }

    func testResultSetReadsEveryRowThenStaysExhausted() throws {
        let request = database.makeRequest(with: selectPeople())

        let people = try request.withResultSet { rows -> [DriverPerson] in
            var people: [DriverPerson] = []
            while let person = try rows.next() {
                people.append(person)
            }
            XCTAssertNil(try rows.next())
            return people
        }

        XCTAssertEqual(people.map(\.id), ["ann", "ben", "cy"])
        XCTAssertFalse(driver.log.events.contains("fetchAll"))
    }

    /// `fetchAll()` decodes each row from the handle while the cursor is on
    /// it: one step, then that row's reads, with no array of values built by
    /// an eager fetch.
    func testFetchAllDecodesEachRowFromTheHandle() throws {
        let people = try database.makeRequest(with: selectPeople()).fetchAll()

        XCTAssertEqual(people.map(\.age), [31, 42, 53])
        XCTAssertEqual(driver.log.events, [
            "step 0", "read 0.0", "read 0.1",
            "step 1", "read 1.0", "read 1.1",
            "step 2", "read 2.0", "read 2.1",
        ])
    }

    func testFetchAtMostStopsTheCursorAtTheLimit() throws {
        let people = try database.makeRequest(with: selectPeople())
            .fetchAtMost(1, bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty))

        XCTAssertEqual(people, [DriverPerson(id: "ann", age: 31)])
        XCTAssertFalse(driver.log.events.contains("step 1"), "\(driver.log.events)")
    }

    /// A read the row reader cannot satisfy fails the decode with the
    /// storage-class rules every SwiftQL reader shares.
    func testAHandleThatImplementsOnlyValueAtReadsBySQLiteRules() throws {
        driver.log.rows = [[.integer(7), .real(42.9)]]

        XCTAssertThrowsError(try database.makeRequest(with: selectPeople()).fetchAll()) { error in
            XCTAssertEqual(
                error as? XLColumnReadError,
                XLColumnReadError(
                    index: 0,
                    expectedType: "String",
                    failure: .typeMismatch(actualType: "INTEGER")
                )
            )
        }
    }

    /// The value-level members are the contract's eager defaults on this
    /// connection, and still serve a value-level caller.
    func testPreparedInvocationReadsValuesThroughTheEagerDefault() throws {
        let invocation = database.prepareInvocation(with: selectPeople())

        let first = try invocation.fetchOneValues(
            bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        )

        XCTAssertEqual(first, [.text("ann"), .integer(31)])
        XCTAssertEqual(driver.log.events, ["fetchAll"])
    }

    private func selectPeople() -> any XLQueryStatement<DriverPerson> {
        sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
        }
    }
}
