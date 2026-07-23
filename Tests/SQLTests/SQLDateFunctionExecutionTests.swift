//
//  SQLDateFunctionExecutionTests.swift
//
//
//  Milestone v1.4.3: date-and-time constructors, ordered modifiers, date
//  components, and date operators, validated against real SQLite. The pinned
//  values are what SQLite computes for a fixed input moment, so a regression in
//  rendering or argument order cannot be sorted or coerced away.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLDateFunctionExecutionTests: XCTestCase {

    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!

    /// A fixed moment. 2026-07-19 is a Sunday (SQLite `%w` = 0) and is the
    /// 200th day of a non-leap year (`%j` = 200).
    private static let moment = "2026-07-19 12:30:45"

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(
            databasePool: databasePool,
            formatter: formatter,
            logger: nil
        )
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    private func moment() -> XLNamedBindingReference<String> {
        XLNamedBindingReference<String>(name: "moment")
    }

    private func evaluate<Value>(
        _ expression: any XLExpression<Value>
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        var request = database.makeRequest(with: statement)
        request.set(moment(), Self.moment)
        return try request.fetchOne()
    }

    // MARK: - Constructors

    func testConstructorsMatchPinnedSQLiteResults() throws {
        let d = moment()
        XCTAssertEqual(try evaluate(d.date()), "2026-07-19")
        XCTAssertEqual(try evaluate(d.time()), "12:30:45")
        XCTAssertEqual(try evaluate(d.datetime()), "2026-07-19 12:30:45")
        XCTAssertEqual(try evaluate(d.strftime("%Y/%m/%d")), "2026/07/19")
    }

    // MARK: - Relative offsets and anchoring (issue #60)

    func testModifiersComputeRelativeMoments() throws {
        let d = moment()
        XCTAssertEqual(try evaluate(d.datetime(.months(1))), "2026-08-19 12:30:45")
        XCTAssertEqual(try evaluate(d.datetime(.days(5))), "2026-07-24 12:30:45")
        XCTAssertEqual(try evaluate(d.datetime(.hours(-12))), "2026-07-19 00:30:45")
        XCTAssertEqual(try evaluate(d.datetime(.minutes(-30))), "2026-07-19 12:00:45")
        XCTAssertEqual(try evaluate(d.datetime(.years(-1))), "2025-07-19 12:30:45")
        XCTAssertEqual(try evaluate(d.date(.startOfMonth)), "2026-07-01")
        XCTAssertEqual(try evaluate(d.date(.startOfYear)), "2026-01-01")
        // Modifiers apply left to right: add a month, then snap to its start.
        XCTAssertEqual(
            try evaluate(d.datetime(.months(1), .startOfMonth)),
            "2026-08-01 00:00:00"
        )
    }

    // MARK: - Components (issue #64)

    func testComponentsMatchPinnedSQLiteResults() throws {
        let d = moment()
        XCTAssertEqual(try evaluate(d.year()), 2026)
        XCTAssertEqual(try evaluate(d.month()), 7)
        XCTAssertEqual(try evaluate(d.day()), 19)
        XCTAssertEqual(try evaluate(d.hour()), 12)
        XCTAssertEqual(try evaluate(d.minute()), 30)
        XCTAssertEqual(try evaluate(d.second()), 45)
        XCTAssertEqual(try evaluate(d.dayOfYear()), 200)
        XCTAssertEqual(try evaluate(d.dayOfWeek()), 0)
    }

    // MARK: - Operators (issue #63)

    func testDateOperatorsAndJulianDayDifference() throws {
        let d = moment()

        // One julian day between a moment and the same moment plus a day.
        let difference = try XCTUnwrap(
            try evaluate(d.julianDay(.days(1)) - d.julianDay())
        )
        XCTAssertEqual(difference, 1.0, accuracy: 1e-9)

        // Text-ordered comparison of the truncated date.
        XCTAssertEqual(try evaluate(d.date() < "2026-07-20"), true)
        XCTAssertEqual(try evaluate(d.date() >= "2026-07-20"), false)

        // Integer component comparison.
        XCTAssertEqual(try evaluate(d.year() != 2026), false)
        XCTAssertEqual(try evaluate(d.year() >= 2026), true)
    }
}
