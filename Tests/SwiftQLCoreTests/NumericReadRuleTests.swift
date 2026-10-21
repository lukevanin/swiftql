import Foundation
import XCTest

import SwiftQLCore


/// Issue #690: one numeric rule for every SQLite read. An integer read
/// accepts a REAL only when it is exactly an integer in `Int` range, a real
/// read accepts an INTEGER, and a static layout's intrinsic fields apply the
/// same rule through the dialect.
final class NumericReadRuleTests: XCTestCase {

    private let integerStorage = XLValueStorageIdentifier(rawValue: "integer")

    private let realStorage = XLValueStorageIdentifier(rawValue: "real")

    private let textStorage = XLValueStorageIdentifier(rawValue: "text")

    func testIntegerReadAcceptsARealThatIsExactlyAnInteger() throws {
        let row = XLValuesRowHandle<XLSQLiteValue>([
            .real(42.0), .real(-7.0), .real(-0.0), .real(9_007_199_254_740_992.0), .integer(5),
        ])

        XCTAssertEqual(try row.readInteger(at: 0), 42)
        XCTAssertEqual(try row.readInteger(at: 1), -7)
        XCTAssertEqual(try row.readInteger(at: 2), 0)
        XCTAssertEqual(try row.readInteger(at: 3), 9_007_199_254_740_992)
        XCTAssertEqual(try row.readInteger(at: 4), 5)
    }

    func testIntegerReadRejectsARealThatIsNotExactlyAnInteger() {
        let values: [XLSQLiteValue] = [
            .real(42.75),
            .real(-0.5),
            .real(1e30),
            .real(-1e30),
            .real(.infinity),
            .real(-.infinity),
            // The first double above `Int64.max`.
            .real(9_223_372_036_854_775_808.0),
        ]
        let row = XLValuesRowHandle<XLSQLiteValue>(values)

        for index in values.indices {
            XCTAssertThrowsError(try row.readInteger(at: index), "value \(values[index])") { error in
                XCTAssertEqual(
                    error as? XLColumnReadError,
                    XLColumnReadError(
                        index: index,
                        expectedType: "Int",
                        failure: .typeMismatch(actualType: "REAL")
                    )
                )
            }
        }
    }

    func testRealReadAcceptsAnIntegerAndAReal() throws {
        let row = XLValuesRowHandle<XLSQLiteValue>([.integer(3), .real(2.5)])

        XCTAssertEqual(try row.readReal(at: 0), 3.0)
        XCTAssertEqual(try row.readReal(at: 1), 2.5)
    }

    func testSQLiteDialectReadsAnIntrinsicFieldByTheSameRule() {
        let dialect = XLSQLiteDialect()

        XCTAssertEqual(dialect.intrinsicReadValue(.integer(3), as: realStorage), .real(3.0))
        XCTAssertEqual(dialect.intrinsicReadValue(.real(4.0), as: integerStorage), .integer(4))
        XCTAssertEqual(dialect.intrinsicReadValue(.real(2.5), as: realStorage), .real(2.5))
        XCTAssertEqual(dialect.intrinsicReadValue(.integer(9), as: integerStorage), .integer(9))
        XCTAssertEqual(dialect.intrinsicReadValue(.text("a"), as: textStorage), .text("a"))

        // A REAL that is not exactly an integer is not an INTEGER.
        XCTAssertNil(dialect.intrinsicReadValue(.real(42.75), as: integerStorage))
        XCTAssertNil(dialect.intrinsicReadValue(.real(1e30), as: integerStorage))
        // Nothing but a number converts to a number.
        XCTAssertNil(dialect.intrinsicReadValue(.text("4"), as: integerStorage))
        XCTAssertNil(dialect.intrinsicReadValue(.blob(Data([4])), as: realStorage))
        XCTAssertNil(dialect.intrinsicReadValue(.integer(4), as: textStorage))
        XCTAssertNil(dialect.intrinsicReadValue(.integer(4), as: XLValueStorageIdentifier(rawValue: "unknown")))
    }
}
