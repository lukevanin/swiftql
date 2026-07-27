import Foundation
import XCTest
@testable import SwiftQL


/// Pure encode/decode contract coverage for ``XLDateTextCodec``, independent
/// of any real SQLite connection. Real GRDB/SQLite round trips live in
/// `DateTextCodecGRDBTests.swift`.
final class DateTextCodecContractTests: XCTestCase {

    private let dialect = XLSQLiteDialect()

    private let parameterContext = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath(["fixture", "when"])
    )

    private let resultContext = XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath(["fixture", "when"])
    )

    // MARK: - Canonical bytes

    func testStandardPresetEncodesFixedWidthZeroPaddedUTCMillisecondText() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)

        XCTAssertEqual(
            try configuration.encode(date, using: dialect, context: parameterContext),
            .text("2023-11-14T22:13:20.123Z")
        )
    }

    func testStandardPresetRoundsSubMillisecondPrecisionToTheNearestMillisecond() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        // Rounds down within the same second: 999.4 microseconds past the
        // millisecond boundary is closer to .999 than to .1000.
        let withoutCarry = Date(timeIntervalSince1970: 1_700_000_000.9994)
        XCTAssertEqual(
            try configuration.encode(withoutCarry, using: dialect, context: parameterContext),
            .text("2023-11-14T22:13:20.999Z")
        )
    }

    func testStandardPresetCarriesARoundedMillisecondIntoTheNextSecond() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        // 999.6 ms rounds up to a full next second, not to a nonexistent
        // ".1000" fractional value.
        let date = Date(timeIntervalSince1970: 1_700_000_000.9996)

        XCTAssertEqual(
            try configuration.encode(date, using: dialect, context: parameterContext),
            .text("2023-11-14T22:13:21.000Z")
        )
    }

    func testStandardPresetRoundTripsThroughEncodeAndDecode() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)

        let encoded = try configuration.encode(date, using: dialect, context: parameterContext)
        let decoded: Date = try configuration.decode(
            Date.self,
            from: encoded,
            using: dialect,
            context: resultContext
        )
        // Truncated to millisecond precision by the standard preset.
        XCTAssertEqual(decoded.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
    }

    // MARK: - Explicit fixed offsets

    func testCustomFormatEmbedsAConfiguredFixedOffsetInsteadOfZ() throws {
        let format = try XLDateTextFormat(
            fractionalSecondDigits: 0,
            utcOffsetSeconds: 2 * 3600 + 30 * 60,
            usesZuluDesignatorForUTC: true
        )
        let codec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.plus-0230", version: 1),
            format: format
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [codec.identity.key]
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            try configuration.encode(date, using: dialect, context: parameterContext),
            .text("2023-11-15T00:43:20+02:30")
        )
        let decoded: Date = try configuration.decode(
            Date.self,
            from: .text("2023-11-15T00:43:20+02:30"),
            using: dialect,
            context: resultContext
        )
        XCTAssertEqual(decoded, date)
    }

    func testZeroOffsetRendersPlusZeroWhenZuluDesignatorIsDisabled() throws {
        let format = try XLDateTextFormat(
            fractionalSecondDigits: 0,
            utcOffsetSeconds: 0,
            usesZuluDesignatorForUTC: false
        )
        let codec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.explicit-plus-zero", version: 1),
            format: format
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [codec.identity.key]
        )

        XCTAssertEqual(
            try configuration.encode(
                Date(timeIntervalSince1970: 0),
                using: dialect,
                context: parameterContext
            ),
            .text("1970-01-01T00:00:00+00:00")
        )
    }

    func testNegativeOffsetsRoundTrip() throws {
        let format = try XLDateTextFormat(
            fractionalSecondDigits: 3,
            utcOffsetSeconds: -8 * 3600
        )
        let codec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.minus-0800", version: 1),
            format: format
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [codec.identity.key]
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let encoded = try configuration.encode(date, using: dialect, context: parameterContext)
        XCTAssertEqual(encoded, .text("2023-11-14T14:13:20.000-08:00"))
        XCTAssertEqual(
            try configuration.decode(
                Date.self,
                from: encoded,
                using: dialect,
                context: resultContext
            ),
            date
        )
    }

    // MARK: - Precision

    func testFractionalSecondDigitsZeroOmitsTheFractionalComponent() throws {
        let format = try XLDateTextFormat(fractionalSecondDigits: 0)
        let codec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.seconds", version: 1),
            format: format
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [codec.identity.key]
        )

        XCTAssertEqual(
            try configuration.encode(
                Date(timeIntervalSince1970: 1_700_000_000.999),
                using: dialect,
                context: parameterContext
            ),
            // Rounds to the nearest whole second, carrying past :20.
            .text("2023-11-14T22:13:21Z")
        )
    }

    func testFractionalSecondDigitsNineRetainsNanosecondPrecision() throws {
        let format = try XLDateTextFormat(fractionalSecondDigits: 9)
        let codec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.nanoseconds", version: 1),
            format: format
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [codec.identity.key]
        )

        let encoded = try configuration.encode(
            Date(timeIntervalSince1970: 1_700_000_000.123456),
            using: dialect,
            context: parameterContext
        )
        guard case .text(let text) = encoded else {
            return XCTFail("Expected TEXT storage")
        }
        XCTAssertTrue(text.hasPrefix("2023-11-14T22:13:20.123456"), text)
        XCTAssertTrue(text.hasSuffix("Z"))
    }

    func testUnsupportedFractionalSecondDigitsIsRejectedAtFormatConstruction() {
        XCTAssertThrowsError(try XLDateTextFormat(fractionalSecondDigits: 10)) { error in
            XCTAssertEqual(
                error as? XLDateTextCodecError,
                .unsupportedPrecision(fractionalSecondDigits: 10)
            )
        }
        XCTAssertThrowsError(try XLDateTextFormat(fractionalSecondDigits: -1)) { error in
            XCTAssertEqual(
                error as? XLDateTextCodecError,
                .unsupportedPrecision(fractionalSecondDigits: -1)
            )
        }
    }

    func testUnsupportedOffsetIsRejectedAtFormatConstruction() {
        XCTAssertThrowsError(try XLDateTextFormat(utcOffsetSeconds: 86_400)) { error in
            XCTAssertEqual(
                error as? XLDateTextCodecError,
                .unsupportedOffsetSeconds(86_400)
            )
        }
        XCTAssertThrowsError(try XLDateTextFormat(utcOffsetSeconds: -86_400)) { error in
            XCTAssertEqual(
                error as? XLDateTextCodecError,
                .unsupportedOffsetSeconds(-86_400)
            )
        }
    }

    // MARK: - Minimum and maximum supported dates

    func testMinimumAndMaximumSupportedDatesRoundTrip() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)

        XCTAssertEqual(
            try configuration.encode(
                XLDateTextCodec.minimumSupportedDate,
                using: dialect,
                context: parameterContext
            ),
            .text("0001-01-01T00:00:00.000Z")
        )
        XCTAssertEqual(
            try configuration.encode(
                XLDateTextCodec.maximumSupportedDate,
                using: dialect,
                context: parameterContext
            ),
            .text("9999-12-31T23:59:59.999Z")
        )
    }

    func testYearsOutsideTheSupportedRangeFailToEncode() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        let beforeMinimum = XLDateTextCodec.minimumSupportedDate.addingTimeInterval(-1)
        let afterMaximum = XLDateTextCodec.maximumSupportedDate.addingTimeInterval(1)

        for outOfRange in [beforeMinimum, afterMaximum] {
            XCTAssertThrowsError(
                try configuration.encode(outOfRange, using: dialect, context: parameterContext)
            ) { error in
                guard case .encodingFailed? = error as? XLValueCodecError else {
                    return XCTFail("Expected an encodingFailed wrapper, received \(error).")
                }
            }
        }
    }

    // MARK: - Ordering

    func testStandardPresetTextOrderingMatchesChronologicalOrdering() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)
        let dates = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_700_000_000.001),
            Date(timeIntervalSince1970: 1_700_000_000.5),
            Date(timeIntervalSince1970: 1_700_000_001),
            Date(timeIntervalSince1970: -1_000_000_000),
        ]
        let sortedByDate = dates.sorted()
        let encodedTexts = try sortedByDate.map { date -> String in
            guard case .text(let text) = try configuration.encode(
                date,
                using: dialect,
                context: parameterContext
            ) else {
                throw XCTSkip("Expected TEXT storage")
            }
            return text
        }

        XCTAssertEqual(encodedTexts, encodedTexts.sorted())
    }

    // MARK: - Errors

    func testInvalidTextFailsToDecodeWithCodecAndContext() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)

        for invalidText in [
            "not-a-date",
            "2023-13-01T00:00:00.000Z",  // month 13
            "2023-11-31T00:00:00.000Z",  // November has 30 days
            "2023-11-14T25:00:00.000Z",  // hour 25
            "2023-11-14 22:13:20.000Z",  // missing 'T' separator
            "",
        ] {
            XCTAssertThrowsError(
                try configuration.decode(
                    Date.self,
                    from: .text(invalidText),
                    using: dialect,
                    context: resultContext
                ),
                invalidText
            ) { error in
                guard case .decodingFailed(let codec, let context, _)? = error as? XLValueCodecError else {
                    return XCTFail("\(invalidText): expected a decodingFailed wrapper, received \(error).")
                }
                XCTAssertEqual(codec, XLDateTextCodec.standardKey)
                XCTAssertEqual(context, resultContext)
            }
        }
    }

    func testStorageClassMismatchIsReportedBeforeTheCodecClosureRuns() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)

        XCTAssertThrowsError(
            try configuration.decode(
                Date.self,
                from: .integer(1_700_000_000),
                using: dialect,
                context: resultContext
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: XLDateTextCodec.standardKey,
                    expected: XLValueStorageIdentifier(
                        rawValue: XLSQLiteStorageClass.text.rawValue
                    ),
                    actual: XLValueStorageIdentifier(
                        rawValue: XLSQLiteStorageClass.integer.rawValue
                    ),
                    context: resultContext
                )
            )
        }
    }

    func testNullIsRejectedByTheNonoptionalCodecButAcceptedByEncodeOptional() throws {
        let configuration = try makeConfiguration(defaultKey: XLDateTextCodec.standardKey)

        XCTAssertThrowsError(
            try configuration.decode(
                Date.self,
                from: .null,
                using: dialect,
                context: resultContext
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .unexpectedNull(codec: XLDateTextCodec.standardKey, context: resultContext)
            )
        }
        XCTAssertEqual(
            try configuration.encodeOptional(
                Optional<Date>.none,
                using: dialect,
                context: parameterContext
            ),
            .null
        )
        let decoded: Date? = try configuration.decodeOptional(
            Date.self,
            from: .null,
            using: dialect,
            context: resultContext
        )
        XCTAssertNil(decoded)
    }

    // MARK: - Two named codecs coexisting as database defaults

    func testStandardAndCustomCodecsCoexistAndAreSelectedExplicitly() throws {
        let customFormat = try XLDateTextFormat(fractionalSecondDigits: 0, utcOffsetSeconds: 0)
        let customCodec = XLDateTextCodec.custom(
            key: XLValueCodecKey(id: "test.date-text.coexisting-custom", version: 1),
            format: customFormat
        )
        let registry = try XLValueCodecRegistry()
            .registering(XLDateTextCodec.standard)
            .registering(customCodec)
        // Neither is a default: both `Date` codecs target the same stable
        // value-type identifier, so registering both as defaults would be a
        // rejected `duplicateDefault`. Two properties select explicitly instead.
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let date = Date(timeIntervalSince1970: 1_700_000_000.777)

        XCTAssertEqual(
            try configuration.encode(
                date,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: XLDateTextCodec.standardKey)
            ),
            .text("2023-11-14T22:13:20.777Z")
        )
        XCTAssertEqual(
            try configuration.encode(
                date,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: customCodec.identity.key)
            ),
            // Seconds-only precision rounds .777 up to the next whole second.
            .text("2023-11-14T22:13:21Z")
        )
    }

    private func makeConfiguration(
        defaultKey: XLValueCodecKey
    ) throws -> XLValueCodingConfiguration {
        try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [defaultKey]
        )
    }
}
