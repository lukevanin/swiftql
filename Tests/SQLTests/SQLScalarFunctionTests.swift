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
