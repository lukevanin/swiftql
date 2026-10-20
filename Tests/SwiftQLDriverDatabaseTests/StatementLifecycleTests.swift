//
//  StatementLifecycleTests.swift
//  SwiftQLDriverDatabaseTests
//
//  Issue #677: SwiftQL finalizes every statement it prepares, on the
//  connection access that prepared it, after the statement's run and also
//  when binding or running it throws. A caching connection relies on this to
//  return each statement to its cache.
//

import Foundation
@testable import SwiftQLSQLite
import XCTest


final class StatementLifecycleTests: XCTestCase {

    private var driver: ScriptedDriver!

    private var database: XLDriverDatabase<ScriptedDriver>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        driver = ScriptedDriver()
        database = try XLDriverDatabase(driver: driver)
        driver.store.rows = [[.text("ana"), .integer(30)], [.text("ben"), .integer(41)]]
    }

    override func tearDown() {
        database = nil
        driver = nil
        super.tearDown()
    }

    func testEveryRequestFinalizesTheStatementItRan() async throws {
        let request = database.makeRequest(with: selectPeople())
        _ = try request.fetchAll()
        _ = try request.fetchOne()
        _ = try await request.async.fetchAll()
        _ = try request.withResultSet { rows in
            try rows.next()
        }
        _ = try database.prepareInvocation(with: selectPeople())
            .fetchAllValues(bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty))
        try database.makeRequest(with: sqlInsert(DriverPerson(id: "cy", age: 52))).execute()

        let lifecycle = driver.store.lifecycle
        XCTAssertEqual(statementNumbers(lifecycle), Array(1 ... 6))
        for number in statementNumbers(lifecycle) {
            XCTAssertEqual(
                events(of: number, in: lifecycle),
                [.prepared(number), .ran(number), .finalized(number)],
                "Statement \(number) must be finalized once, after it ran."
            )
        }
    }

    func testAStatementIsFinalizedWhenItsRunThrows() throws {
        driver.store.failing = .run

        let request = database.makeRequest(with: selectPeople())
        XCTAssertThrowsError(try request.fetchAll())
        XCTAssertThrowsError(
            try database.makeRequest(with: sqlInsert(DriverPerson(id: "dee", age: 19))).execute()
        )
        XCTAssertThrowsError(try request.withResultSet { rows in try rows.next() })
        XCTAssertThrowsError(
            try database.prepareInvocation(with: selectPeople()).forEachValueRow(
                bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty)
            ) { _ in .advance }
        )

        XCTAssertEqual(driver.store.lifecycle, [
            .prepared(1), .ran(1), .finalized(1),
            .prepared(2), .ran(2), .finalized(2),
            .prepared(3), .ran(3), .finalized(3),
            .prepared(4), .ran(4), .finalized(4),
        ])
    }

    func testAStatementIsFinalizedWhenBindingThrows() throws {
        let minimumAge = XLNamedBindingReference<Int>(name: "minimumAge")
        var request = database.makeRequest(with: sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
            Where(person.age >= minimumAge)
        })
        request.set(minimumAge, 21)
        driver.store.failing = .bind

        XCTAssertThrowsError(try request.fetchAll()) { error in
            guard case .driverBindingFailed = error as? XLInvocationBindingError else {
                return XCTFail("Expected a driver binding failure, got \(error).")
            }
        }

        XCTAssertEqual(driver.store.lifecycle, [.prepared(1), .finalized(1)])
    }

    func testAStatementIsFinalizedWhenTheResultSetBodyThrows() throws {
        struct BodyFailure: Error {}
        let request = database.makeRequest(with: selectPeople())

        XCTAssertThrowsError(
            try request.withResultSet { rows -> Void in
                _ = try rows.next()
                throw BodyFailure()
            }
        ) { error in
            XCTAssertTrue(error is BodyFailure, "\(error)")
        }

        XCTAssertEqual(driver.store.lifecycle, [.prepared(1), .ran(1), .finalized(1)])
    }

    // MARK: - Helpers

    private func statementNumbers(_ lifecycle: [ScriptedStore.LifecycleEvent]) -> [Int] {
        lifecycle.compactMap { event in
            if case .prepared(let number) = event {
                return number
            }
            return nil
        }
    }

    private func events(
        of number: Int,
        in lifecycle: [ScriptedStore.LifecycleEvent]
    ) -> [ScriptedStore.LifecycleEvent] {
        lifecycle.filter { event in
            switch event {
            case .prepared(let other), .ran(let other), .finalized(let other):
                return other == number
            }
        }
    }

    private func selectPeople() -> any XLQueryStatement<DriverPerson> {
        sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
        }
    }
}


/// Issue #677 with #678: the row-handle paths finalize their statement once,
/// after the cursor's last step, whether the rows run out, the request stops
/// early, or the body throws. The cursor driver implements the row-handle
/// members itself, so these tests run SwiftQL's row-handle paths rather than
/// the value-level defaults.
final class RowHandleLifecycleTests: XCTestCase {

    private struct BodyFailure: Error {}

    private var driver: CursorDriver!

    private var database: XLDriverDatabase<CursorDriver>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        driver = CursorDriver()
        database = try XLDriverDatabase(driver: driver)
        driver.log.rows = [[.text("ann"), .integer(31)], [.text("ben"), .integer(42)]]
    }

    override func tearDown() {
        database = nil
        driver = nil
        super.tearDown()
    }

    // MARK: - forEachRowHandle

    func testFetchAllFinalizesAfterTheLastRow() throws {
        _ = try database.makeRequest(with: selectPeople()).fetchAll()

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "step 1", "finalize"])
    }

    func testAsyncFetchAllFinalizesAfterTheLastRow() async throws {
        _ = try await database.makeRequest(with: selectPeople()).async.fetchAll()

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "step 1", "finalize"])
    }

    func testFetchAtMostFinalizesWhenItStopsEarly() throws {
        _ = try database.makeRequest(with: selectPeople())
            .fetchAtMost(1, bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty))

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "finalize"])
    }

    func testFetchAllFinalizesWhenARowFailsToDecode() {
        driver.log.rows = [[.null, .integer(31)], [.text("ben"), .integer(42)]]

        XCTAssertThrowsError(try database.makeRequest(with: selectPeople()).fetchAll())

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "finalize"])
    }

    // MARK: - withRowHandleStepper

    func testResultSetFinalizesAfterTheRowsRunOut() throws {
        _ = try database.makeRequest(with: selectPeople()).withResultSet { rows -> Int in
            var count = 0
            while try rows.next() != nil {
                count += 1
            }
            return count
        }

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "step 1", "finalize"])
    }

    func testResultSetFinalizesWhenTheBodyStopsEarly() throws {
        _ = try database.makeRequest(with: selectPeople()).withResultSet { rows in
            try rows.next()
        }

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "finalize"])
    }

    func testResultSetFinalizesWhenTheBodyThrows() {
        XCTAssertThrowsError(
            try database.makeRequest(with: selectPeople()).withResultSet { rows -> Void in
                _ = try rows.next()
                throw BodyFailure()
            }
        ) { error in
            XCTAssertTrue(error is BodyFailure, "\(error)")
        }

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "finalize"])
    }

    func testResultSetFinalizesWhenARowFailsToDecode() {
        driver.log.rows = [[.null, .integer(31)]]

        XCTAssertThrowsError(
            try database.makeRequest(with: selectPeople()).withResultSet { rows in
                try rows.next()
            }
        )

        XCTAssertEqual(driver.log.lifecycle, ["prepare", "step 0", "finalize"])
    }

    private func selectPeople() -> any XLQueryStatement<DriverPerson> {
        sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
        }
    }
}
