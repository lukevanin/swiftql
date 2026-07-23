import Foundation
import SwiftQL
import XCTest


final class XLScalarFunctionTests: XCTestCase {

    private var encoder: XLiteEncoder!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .noEscape)
        )
    }

    override func tearDown() {
        encoder = nil
    }

    func testNumericAndComparableFunctions() {
        let integer = XLNamedBindingReference<Int>(name: "integer")
        let real = XLNamedBindingReference<Double>(name: "real")
        let optionalReal = XLNamedBindingReference<Double?>(name: "optionalReal")

        assertSQL(integer.abs(), "ABS(:integer)")
        assertSQL(real.abs(), "ABS(:real)")
        assertSQL(real.rounded(), "ROUND(:real)")
        assertSQL(optionalReal.rounded(), "ROUND(:optionalReal)")
        assertSQL(real.rounded(to: 2), "ROUND(:real, 2)")
        assertSQL(real.floor(), "FLOOR(:real)")
        assertSQL(min(integer, 0, 10), "MIN(:integer, 0, 10)")
        assertSQL(max(integer, 0, 10), "MAX(:integer, 0, 10)")

        assertExpressionType(integer.abs(), Int.self)
        assertExpressionType(real.rounded(), Double.self)
        assertExpressionType(optionalReal.rounded(), Double?.self)
        assertExpressionType(real.floor(), Double.self)
    }

    func testConditionalFunctionOverloads() {
        let condition = XLNamedBindingReference<Bool>(name: "condition")
        let optionalThen = XLNamedBindingReference<String?>(name: "optionalThen")
        let optionalElse = XLNamedBindingReference<String?>(name: "optionalElse")

        let required = iif(condition, then: "yes", else: "no")
        let optionalTrue = iif(condition, then: optionalThen, else: "no")
        let optionalFalse = iif(condition, then: "yes", else: optionalElse)
        let optionalBoth = iif(condition, then: optionalThen, else: optionalElse)

        assertSQL(required, "IIF(:condition, 'yes', 'no')")
        assertSQL(optionalTrue, "IIF(:condition, :optionalThen, 'no')")
        assertSQL(optionalFalse, "IIF(:condition, 'yes', :optionalElse)")
        assertSQL(optionalBoth, "IIF(:condition, :optionalThen, :optionalElse)")

        assertExpressionType(required, String.self)
        assertExpressionType(optionalTrue, String?.self)
        assertExpressionType(optionalFalse, String?.self)
        assertExpressionType(optionalBoth, String?.self)
    }

    func testDateAndJSONFunctions() {
        let date = XLNamedBindingReference<String>(name: "date")
        let optionalDate = XLNamedBindingReference<String?>(name: "optionalDate")
        let json = XLNamedBindingReference<String>(name: "json")

        assertSQL(
            unixepoch(date: "1970-01-01T00:00:00Z", modifiers: [.subseconds]),
            "unixepoch('1970-01-01T00:00:00Z', 'subsec')"
        )
        assertSQL(date.toUnixTimestamp(), "unixepoch(:date)")
        assertSQL(optionalDate.toUnixTimestamp(), "unixepoch(:optionalDate)")
        assertSQL(json.jsonArrayLength(), "json_array_length(:json)")
        assertSQL(json.jsonArrayLength(path: "$.items"), "json_array_length(:json, '$.items')")
        assertSQL(json.validJSON(), "json_valid(:json)")

        assertExpressionType(date.toUnixTimestamp(), Int.self)
        assertExpressionType(optionalDate.toUnixTimestamp(), Int?.self)
        assertExpressionType(json.jsonArrayLength(), Int?.self)
        assertExpressionType(json.validJSON(), Bool.self)
    }

    func testDateConstructorsModifiersAndComponents() {
        let date = XLNamedBindingReference<String>(name: "date")
        let optionalDate = XLNamedBindingReference<String?>(name: "optionalDate")

        // Constructors with ordered modifiers.
        assertSQL(date.date(), "date(:date)")
        assertSQL(date.date(.startOfMonth), "date(:date, 'start of month')")
        assertSQL(date.time(.subsecond), "time(:date, 'subsec')")
        assertSQL(
            date.datetime(.months(1)),
            "datetime(:date, '+1 months')"
        )
        assertSQL(
            date.datetime(.months(1), .startOfMonth),
            "datetime(:date, '+1 months', 'start of month')"
        )
        assertSQL(date.julianDay(), "julianday(:date)")
        assertSQL(date.julianDay(.days(-3)), "julianday(:date, '-3 days')")
        assertSQL(date.unixEpoch(.utc), "unixepoch(:date, 'utc')")
        assertSQL(date.strftime("%Y-%m-%d"), "strftime('%Y-%m-%d', :date)")
        assertSQL(
            date.strftime("%Y", .years(1)),
            "strftime('%Y', :date, '+1 years')"
        )

        // A representative sweep of the modifier surface.
        assertSQL(date.datetime(.hours(6)), "datetime(:date, '+6 hours')")
        assertSQL(date.datetime(.minutes(-30)), "datetime(:date, '-30 minutes')")
        assertSQL(date.datetime(.seconds(90)), "datetime(:date, '+90 seconds')")
        assertSQL(date.datetime(.years(-2)), "datetime(:date, '-2 years')")
        assertSQL(date.date(.startOfYear), "date(:date, 'start of year')")
        assertSQL(date.date(.startOfDay), "date(:date, 'start of day')")
        assertSQL(date.date(.weekday(1)), "date(:date, 'weekday 1')")
        assertSQL(date.datetime(.months(1), .ceiling), "datetime(:date, '+1 months', 'ceiling')")
        assertSQL(date.datetime(.months(1), .floor), "datetime(:date, '+1 months', 'floor')")
        assertSQL(date.datetime(.localTime), "datetime(:date, 'localtime')")
        assertSQL(date.date(XLDateModifier("unixepoch")), "date(:date, 'unixepoch')")

        // Components render as an integer reinterpretation of strftime.
        assertSQL(date.year(), "CAST(strftime('%Y', :date) AS INTEGER)")
        assertSQL(date.month(), "CAST(strftime('%m', :date) AS INTEGER)")
        assertSQL(date.day(), "CAST(strftime('%d', :date) AS INTEGER)")
        assertSQL(date.hour(), "CAST(strftime('%H', :date) AS INTEGER)")
        assertSQL(date.minute(), "CAST(strftime('%M', :date) AS INTEGER)")
        assertSQL(date.second(), "CAST(strftime('%S', :date) AS INTEGER)")
        assertSQL(date.dayOfYear(), "CAST(strftime('%j', :date) AS INTEGER)")
        assertSQL(date.dayOfWeek(), "CAST(strftime('%w', :date) AS INTEGER)")
        assertSQL(date.weekOfYear(), "CAST(strftime('%W', :date) AS INTEGER)")

        // Optional receivers preserve optionality.
        assertSQL(optionalDate.datetime(.days(1)), "datetime(:optionalDate, '+1 days')")
        assertSQL(optionalDate.julianDay(), "julianday(:optionalDate)")
        assertSQL(optionalDate.unixEpoch(), "unixepoch(:optionalDate)")
        assertSQL(optionalDate.strftime("%Y"), "strftime('%Y', :optionalDate)")
        assertSQL(optionalDate.year(), "CAST(strftime('%Y', :optionalDate) AS INTEGER)")

        // Date operators (issue #63) compose over date-function results.
        assertSQL(
            date.julianDay() - date.julianDay(.days(-1)),
            "(julianday(:date) - julianday(:date, '-1 days'))"
        )
        assertSQL(date.date() < "2026-01-01", "(date(:date) < '2026-01-01')")
        assertSQL(date.date() >= "2026-01-01", "(date(:date) >= '2026-01-01')")
        assertSQL(date.year() != 2026, "(CAST(strftime('%Y', :date) AS INTEGER) != 2026)")

        assertExpressionType(date.date(), String.self)
        assertExpressionType(date.datetime(.months(1)), String.self)
        assertExpressionType(date.julianDay(), Double.self)
        assertExpressionType(date.unixEpoch(), TimeInterval.self)
        assertExpressionType(date.strftime("%Y"), String.self)
        assertExpressionType(date.year(), Int.self)
        assertExpressionType(optionalDate.datetime(.days(1)), String?.self)
        assertExpressionType(optionalDate.julianDay(), Double?.self)
        assertExpressionType(optionalDate.unixEpoch(), TimeInterval?.self)
        assertExpressionType(optionalDate.year(), Int?.self)
    }

    func testStringFunctionsAndOrderingTerms() {
        let text = XLNamedBindingReference<String>(name: "text")
        let optionalText = XLNamedBindingReference<String?>(name: "optionalText")
        let canonicalEncoder = XLiteEncoder(formatter: XLiteFormatter())

        XCTAssertEqual(
            canonicalEncoder.makeSQL(text.collate(.binary)).sql,
            "(:text COLLATE BINARY)"
        )
        XCTAssertEqual(
            canonicalEncoder.makeSQL(text.collate(.nocase)).sql,
            "(:text COLLATE NOCASE)"
        )
        XCTAssertEqual(
            canonicalEncoder.makeSQL(optionalText.collate(.rtrim)).sql,
            "(:optionalText COLLATE RTRIM)"
        )
        assertSQL(printf(format: "%s:%d", text, 7), "printf('%s:%d', :text, 7)")
        assertSQL(
            printf(format: "%s:%d", [text, 7]),
            "printf('%s:%d', :text, 7)"
        )

        XCTAssertEqual(encoder.makeSQL(text.ascending()).sql, ":text ASC")
        XCTAssertEqual(encoder.makeSQL(text.descending()).sql, ":text DESC")
        assertExpressionType(text.collate(.binary), String.self)
        assertExpressionType(optionalText.collate(.binary), String?.self)
    }

    func testTypeCastOverloadsAndRendering() {
        let boolean = XLNamedBindingReference<Bool>(name: "boolean")
        let optionalBoolean = XLNamedBindingReference<Bool?>(name: "optionalBoolean")
        let integer = XLNamedBindingReference<Int>(name: "integer")
        let optionalInteger = XLNamedBindingReference<Int?>(name: "optionalInteger")
        let real = XLNamedBindingReference<Double>(name: "real")
        let optionalReal = XLNamedBindingReference<Double?>(name: "optionalReal")
        let text = XLNamedBindingReference<String>(name: "text")
        let optionalText = XLNamedBindingReference<String?>(name: "optionalText")
        let data = XLNamedBindingReference<Data>(name: "data")
        let optionalData = XLNamedBindingReference<Data?>(name: "optionalData")

        assertExpressionType(boolean.toInt(), Int.self)
        assertExpressionType(optionalBoolean.toInt(), Int?.self)
        assertExpressionType(integer.toDouble(), Double.self)
        assertExpressionType(integer.toString(), String.self)
        assertExpressionType(optionalInteger.toDouble(), Double?.self)
        assertExpressionType(optionalInteger.toString(), String?.self)
        assertExpressionType(real.toInt(), Int.self)
        assertExpressionType(real.toString(), String.self)
        assertExpressionType(optionalReal.toInt(), Int?.self)
        assertExpressionType(optionalReal.toString(), String?.self)
        assertExpressionType(text.toInt(), Int.self)
        assertExpressionType(text.toDouble(), Double.self)
        assertExpressionType(text.toData(), Data.self)
        assertExpressionType(optionalText.toInt(), Int?.self)
        assertExpressionType(optionalText.toDouble(), Double?.self)
        assertExpressionType(optionalText.toData(), Data?.self)
        assertExpressionType(data.toString(), String.self)
        assertExpressionType(optionalData.toString(), String?.self)

        assertExpressionType(boolean.cast(to: Int.self), Int.self)
        assertExpressionType(optionalBoolean.cast(to: Int.self), Int?.self)
        assertExpressionType(integer.cast(to: Double.self), Double.self)
        assertExpressionType(integer.cast(to: String.self), String.self)
        assertExpressionType(optionalInteger.cast(to: Double.self), Double?.self)
        assertExpressionType(optionalInteger.cast(to: String.self), String?.self)
        assertExpressionType(real.cast(to: Int.self), Int.self)
        assertExpressionType(real.cast(to: String.self), String.self)
        assertExpressionType(optionalReal.cast(to: Int.self), Int?.self)
        assertExpressionType(optionalReal.cast(to: String.self), String?.self)
        assertExpressionType(text.cast(to: Int.self), Int.self)
        assertExpressionType(text.cast(to: Double.self), Double.self)
        assertExpressionType(text.cast(to: Data.self), Data.self)
        assertExpressionType(optionalText.cast(to: Int.self), Int?.self)
        assertExpressionType(optionalText.cast(to: Double.self), Double?.self)
        assertExpressionType(optionalText.cast(to: Data.self), Data?.self)
        assertExpressionType(data.cast(to: String.self), String.self)
        assertExpressionType(optionalData.cast(to: String.self), String?.self)

        assertSQL(boolean.toInt(), ":boolean")
        assertSQL(integer.toDouble(), "CAST(:integer AS REAL)")
        assertSQL(real.toInt(), "CAST(:real AS INTEGER)")
        assertSQL(text.toData(), "CAST(:text AS BLOB)")
        assertSQL(data.toString(), "CAST(:data AS TEXT)")
        assertSQL(optionalInteger.toString(), "CAST(:optionalInteger AS TEXT)")

        assertSQL(12.cast(to: String.self), "CAST(12 AS TEXT)")
        assertSQL(boolean.cast(to: Int.self), ":boolean")
        assertSQL(integer.cast(to: Double.self), "CAST(:integer AS REAL)")
        assertSQL(real.cast(to: Int.self), "CAST(:real AS INTEGER)")
        assertSQL(text.cast(to: Data.self), "CAST(:text AS BLOB)")
        assertSQL(data.cast(to: String.self), "CAST(:data AS TEXT)")
        assertSQL(
            optionalInteger.cast(to: String.self),
            "CAST(:optionalInteger AS TEXT)"
        )
    }

    private func assertSQL<T>(
        _ expression: any XLExpression<T>,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T: XLLiteral {
        XCTAssertEqual(encoder.makeSQL(expression).sql, expected, file: file, line: line)
    }

    private func assertExpressionType<T>(_: any XLExpression<T>, _: T.Type) {
    }
}
