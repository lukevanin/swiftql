import Foundation
import XCTest
@testable import SwiftQL


/// Pure Swift-level contract tests for the numeric SQLite `Date` presets
/// defined in `Sources/SwiftQL/SQLiteNumericDateCodecs.swift`. These mirror
/// `Tests/SwiftQLCoreTests/ValueCodecContractTests.swift`'s style: no real
/// SQLite connection is involved, only `XLValueCodec`/`XLValueCodingConfiguration`
/// calls against `XLSQLiteDialect`. Real-database round trips, SQL
/// comparisons, and date-function interoperability live in
/// `SQLiteNumericDateCodecGRDBTests.swift` in this same target.
final class SQLiteNumericDateCodecContractTests: XCTestCase {

    private let dialect = XLSQLiteDialect()

    private let parameterContext = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath(["fixture", "date"])
    )

    private let resultContext = XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath(["fixture", "date"])
    )

    // MARK: - Identity

    func testPresetsHaveDistinctKeysAndDeclaredStorageClasses() {
        XCTAssertEqual(
            XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            XLValueCodecKey(id: "com.swiftql.date.unix-milliseconds", version: 1)
        )
        XCTAssertEqual(
            XLSQLiteNumericDateCodec.UnixSeconds.key,
            XLValueCodecKey(id: "com.swiftql.date.unix-seconds", version: 1)
        )
        XCTAssertEqual(
            XLSQLiteNumericDateCodec.JulianDay.key,
            XLValueCodecKey(id: "com.swiftql.date.julian-day", version: 1)
        )

        let keys = [
            XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            XLSQLiteNumericDateCodec.UnixSeconds.key,
            XLSQLiteNumericDateCodec.JulianDay.key,
        ]
        XCTAssertEqual(Set(keys).count, keys.count, "Every preset must have a distinct key.")

        XCTAssertEqual(
            XLSQLiteNumericDateCodec.UnixMilliseconds.codec.identity.storageIdentifier,
            XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.integer.rawValue)
        )
        XCTAssertEqual(
            XLSQLiteNumericDateCodec.UnixSeconds.codec.identity.storageIdentifier,
            XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.real.rawValue)
        )
        XCTAssertEqual(
            XLSQLiteNumericDateCodec.JulianDay.codec.identity.storageIdentifier,
            XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.real.rawValue)
        )

        for codec in [
            XLSQLiteNumericDateCodec.UnixMilliseconds.codec.identity,
            XLSQLiteNumericDateCodec.UnixSeconds.codec.identity,
            XLSQLiteNumericDateCodec.JulianDay.codec.identity,
        ] {
            XCTAssertEqual(codec.dialectIdentifier, XLSQLiteDialect.identity)
            XCTAssertEqual(codec.valueTypeIdentifier, XLSQLiteNumericDateCodec.valueTypeIdentifier)
        }
    }

    // MARK: - No implicit default

    func testRegisteringAllPresetsNeverCreatesAnImplicitDefault() throws {
        let registry = try XLValueCodecRegistry().registeringSQLiteNumericDateCodecs()
        let configuration = try XLValueCodingConfiguration(registry: registry)

        XCTAssertThrowsError(
            try configuration.encode(
                Date(timeIntervalSince1970: 0),
                using: dialect,
                context: parameterContext
            )
        ) { error in
            guard case .ambiguousCodec(_, _, let candidates, _)? = error as? XLValueCodecError else {
                return XCTFail("Expected an ambiguous-codec error, received \(error).")
            }
            XCTAssertEqual(
                Set(candidates),
                Set([
                    XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                    XLSQLiteNumericDateCodec.UnixSeconds.key,
                    XLSQLiteNumericDateCodec.JulianDay.key,
                ])
            )
        }
    }

    func testExplicitSelectionDisambiguatesAmongAllThreePresets() throws {
        let registry = try XLValueCodecRegistry().registeringSQLiteNumericDateCodecs()
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)

        XCTAssertEqual(
            try configuration.encode(
                date,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: XLSQLiteNumericDateCodec.UnixMilliseconds.key
                )
            ),
            .integer(1_700_000_000_500)
        )
        XCTAssertEqual(
            try configuration.encode(
                date,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key
                )
            ),
            .real(1_700_000_000.5)
        )
        XCTAssertEqual(
            try configuration.encode(
                date,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: XLSQLiteNumericDateCodec.JulianDay.key
                )
            ),
            .real(1_700_000_000.5 / 86_400 + 2_440_587.5)
        )
    }

    // MARK: - Round trips at documented boundaries

    func testUnixMillisecondsRoundTripsRepresentativeDatesWithinDocumentedBound() throws {
        for date in Self.representativeDates() {
            let encoded = try XLSQLiteNumericDateCodec.UnixMilliseconds.codec.encode(
                date,
                using: dialect,
                context: parameterContext
            )
            let decoded = try XLSQLiteNumericDateCodec.UnixMilliseconds.codec.decode(
                encoded,
                using: dialect,
                context: resultContext
            )
            // Documented bound: rounding to the nearest millisecond introduces
            // at most 0.5 ms of error; allow a small additional margin for
            // Date's own Double representation error.
            XCTAssertEqual(
                decoded.timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: 0.0005 + 1e-9,
                "unix-milliseconds round trip exceeded its documented 0.5 ms bound for \(date)"
            )
        }
    }

    func testUnixSecondsRoundTripsRepresentativeDatesWithinDocumentedBound() throws {
        for date in Self.representativeDates() {
            let encoded = try XLSQLiteNumericDateCodec.UnixSeconds.codec.encode(
                date,
                using: dialect,
                context: parameterContext
            )
            let decoded = try XLSQLiteNumericDateCodec.UnixSeconds.codec.decode(
                encoded,
                using: dialect,
                context: resultContext
            )
            // Documented bound: no explicit rounding, so error is at the
            // unit-in-the-last-place level of the input's own Double
            // representation. Use a small constant multiple of that value's
            // ULP as a generous, still-tight tolerance.
            let tolerance = Swift.max(date.timeIntervalSince1970.ulp, .leastNormalMagnitude) * 8
            XCTAssertEqual(
                decoded.timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: tolerance,
                "unix-seconds round trip exceeded its documented ULP-level bound for \(date)"
            )
        }
    }

    func testJulianDayRoundTripsRepresentativeDatesWithinDocumentedBound() throws {
        for date in Self.representativeDates() {
            let encoded = try XLSQLiteNumericDateCodec.JulianDay.codec.encode(
                date,
                using: dialect,
                context: parameterContext
            )
            let decoded = try XLSQLiteNumericDateCodec.JulianDay.codec.decode(
                encoded,
                using: dialect,
                context: resultContext
            )
            guard case .real(let julianDay) = encoded else {
                XCTFail("Expected a REAL julian day value.")
                continue
            }
            // Documented bound: adding the ~2,440,587.5 day offset consumes
            // mantissa bits, so the error is a multiple of the *julian day*
            // value's own ULP, amplified back into seconds by the
            // seconds-per-day factor used to invert the transform.
            let tolerance = julianDay.ulp * XLSQLiteNumericDateCodec.JulianDay.secondsPerDay * 8
            XCTAssertEqual(
                decoded.timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: tolerance,
                "julian-day round trip exceeded its documented ULP-level bound for \(date)"
            )
        }
    }

    /// Near-epoch, far-future, far-past, and seeded-random representative
    /// dates used to quantify round-trip error, as required by issue #62's
    /// "Done when" criteria. The random dates use a fixed seed so the suite
    /// stays deterministic across runs.
    static func representativeDates() -> [Date] {
        var generator = SeededGenerator(seed: 62)
        var dates: [Date] = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 0.123_456),
            Date(timeIntervalSince1970: -0.654_321),
            Date(timeIntervalSince1970: 1_700_000_000.789),
            Date(timeIntervalSince1970: 253_402_300_799), // 9999-12-31T23:59:59Z
            Date(timeIntervalSince1970: -62_135_596_800), // 0001-01-01T00:00:00Z
        ]
        for _ in 0 ..< 20 {
            let seconds = Double.random(
                in: -62_135_596_800 ... 253_402_300_799,
                using: &generator
            )
            dates.append(Date(timeIntervalSince1970: seconds))
        }
        return dates
    }

    // MARK: - Non-finite input

    func testEncodingNonFiniteDatesFailsForEveryPreset() {
        let presets: [(name: String, codec: XLValueCodec<Date, XLSQLiteDialect>)] = [
            ("unix-milliseconds", XLSQLiteNumericDateCodec.UnixMilliseconds.codec),
            ("unix-seconds", XLSQLiteNumericDateCodec.UnixSeconds.codec),
            ("julian-day", XLSQLiteNumericDateCodec.JulianDay.codec),
        ]
        let nonFiniteDates: [(Date, XLNonFiniteRealValue)] = [
            (Date(timeIntervalSince1970: .nan), .notANumber),
            (Date(timeIntervalSince1970: .infinity), .positiveInfinity),
            (Date(timeIntervalSince1970: -.infinity), .negativeInfinity),
        ]

        for preset in presets {
            for (date, classification) in nonFiniteDates {
                assertEncodingFailed(
                    try preset.codec.encode(date, using: dialect, context: parameterContext),
                    codec: preset.codec.identity.key,
                    message: String(
                        describing: XLSQLiteNumericDateCodecError.nonFiniteDate(
                            preset: preset.codec.identity.key.id,
                            value: classification
                        )
                    ),
                    file: #filePath,
                    line: #line
                )
            }
        }
    }

    func testDecodingNonFiniteRealValuesFailsForRealPresets() {
        for preset in [
            XLSQLiteNumericDateCodec.UnixSeconds.codec,
            XLSQLiteNumericDateCodec.JulianDay.codec,
        ] {
            for (value, classification) in [
                (XLSQLiteValue.real(.nan), XLNonFiniteRealValue.notANumber),
                (XLSQLiteValue.real(.infinity), .positiveInfinity),
                (XLSQLiteValue.real(-.infinity), .negativeInfinity),
            ] {
                assertDecodingFailed(
                    try preset.decode(value, using: dialect, context: resultContext),
                    codec: preset.identity.key,
                    message: String(
                        describing: XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                            preset: preset.identity.key.id,
                            value: classification
                        )
                    )
                )
            }
        }
    }

    func testUnixMillisecondsRejectsOverflow() {
        // Any date whose millisecond count cannot fit in Int64 must be
        // rejected rather than silently wrapped or truncated.
        let farBeyondInt64Milliseconds = Date(
            timeIntervalSince1970: Double(Int64.max) / 1000 * 10
        )
        XCTAssertThrowsError(
            try XLSQLiteNumericDateCodec.UnixMilliseconds.codec.encode(
                farBeyondInt64Milliseconds,
                using: dialect,
                context: parameterContext
            )
        ) { error in
            guard case .encodingFailed(_, _, let message)? = error as? XLValueCodecError else {
                return XCTFail("Expected an encoding-failed error, received \(error).")
            }
            // `XLValueCodec` wraps a thrown error with `String(describing:)`,
            // which renders the enum case (not `errorDescription`), so assert
            // against that exact rendering rather than a loosely-matched
            // substring.
            XCTAssertEqual(
                message,
                String(
                    describing: XLSQLiteNumericDateCodecError.millisecondsOutOfRange(
                        preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key.id,
                        timeIntervalSince1970: farBeyondInt64Milliseconds.timeIntervalSince1970
                    )
                )
            )
        }
    }

    func testJulianDayRejectsAFiniteStoredValueThatOverflowsOnDecode() {
        // A stored julian-day REAL can be finite while still being far too
        // large for `(julianDay - epoch) * secondsPerDay` to stay finite.
        // Decoding must fail structurally instead of returning a Date backed
        // by a non-finite time interval.
        let finiteButOverflowing = XLSQLiteValue.real(1e304)
        XCTAssertTrue(finiteButOverflowing.storageType == .real)
        XCTAssertThrowsError(
            try XLSQLiteNumericDateCodec.JulianDay.codec.decode(
                finiteButOverflowing,
                using: dialect,
                context: resultContext
            )
        ) { error in
            guard case .decodingFailed(_, _, let message)? = error as? XLValueCodecError else {
                return XCTFail("Expected a decoding-failed error, received \(error).")
            }
            XCTAssertEqual(
                message,
                String(
                    describing: XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                        preset: XLSQLiteNumericDateCodec.JulianDay.key.id,
                        value: .positiveInfinity
                    )
                )
            )
        }

        // A value just below that threshold still decodes successfully.
        XCTAssertNoThrow(
            try XLSQLiteNumericDateCodec.JulianDay.codec.decode(
                .real(1e303),
                using: dialect,
                context: resultContext
            )
        )
    }

    // MARK: - Storage-class coercion

    func testDecodingTheWrongStorageClassFailsBeforeThePresetsDecodeClosureRuns() {
        assertCodecError(
            try XLSQLiteNumericDateCodec.UnixMilliseconds.codec.decode(
                .real(1234),
                using: dialect,
                context: resultContext
            ),
            equals: .storageMismatch(
                codec: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                expected: XLSQLiteNumericDateCodec.UnixMilliseconds.storageIdentifier,
                actual: XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.real.rawValue),
                context: resultContext
            )
        )
        assertCodecError(
            try XLSQLiteNumericDateCodec.UnixSeconds.codec.decode(
                .integer(1234),
                using: dialect,
                context: resultContext
            ),
            equals: .storageMismatch(
                codec: XLSQLiteNumericDateCodec.UnixSeconds.key,
                expected: XLSQLiteNumericDateCodec.UnixSeconds.storageIdentifier,
                actual: XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.integer.rawValue),
                context: resultContext
            )
        )
        assertCodecError(
            try XLSQLiteNumericDateCodec.JulianDay.codec.decode(
                .text("2440587.5"),
                using: dialect,
                context: resultContext
            ),
            equals: .storageMismatch(
                codec: XLSQLiteNumericDateCodec.JulianDay.key,
                expected: XLSQLiteNumericDateCodec.JulianDay.storageIdentifier,
                actual: XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.text.rawValue),
                context: resultContext
            )
        )
    }

    // MARK: - Optional / NULL

    func testOptionalEncodingAndDecodingMapDirectlyToSQLNull() throws {
        let registry = try XLValueCodecRegistry()
            .registering(XLSQLiteNumericDateCodec.UnixSeconds.codec)
        let configuration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [XLSQLiteNumericDateCodec.UnixSeconds.key]
        )

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

        let date = Date(timeIntervalSince1970: 42)
        let encoded = try configuration.encodeOptional(
            date,
            using: dialect,
            context: parameterContext
        )
        XCTAssertEqual(encoded, .real(42))
        let decodedDate: Date? = try configuration.decodeOptional(
            Date.self,
            from: encoded,
            using: dialect,
            context: resultContext
        )
        XCTAssertEqual(decodedDate, date)
    }

    // MARK: - Coexistence

    func testTwoNumericPresetsCoexistWithIndependentMetadataInOneConfiguration() throws {
        let registry = try XLValueCodecRegistry()
            .registering(XLSQLiteNumericDateCodec.UnixMilliseconds.codec)
            .registering(XLSQLiteNumericDateCodec.JulianDay.codec)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let createdAtContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["event", "createdAtMilliseconds"])
        )
        let updatedAtContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["event", "updatedAtJulianDay"])
        )
        let date = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01T00:00:00Z

        let createdAtCodec = try configuration.resolvedCodec(
            for: Date.self,
            using: dialect,
            context: createdAtContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: XLSQLiteNumericDateCodec.UnixMilliseconds.key
            )
        )
        let updatedAtCodec = try configuration.resolvedCodec(
            for: Date.self,
            using: dialect,
            context: updatedAtContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: XLSQLiteNumericDateCodec.JulianDay.key
            )
        )

        XCTAssertNotEqual(createdAtCodec.identity.key, updatedAtCodec.identity.key)
        XCTAssertNotEqual(
            createdAtCodec.identity.storageIdentifier,
            updatedAtCodec.identity.storageIdentifier
        )
        XCTAssertEqual(try createdAtCodec.encode(date), .integer(946_684_800_000))
        XCTAssertEqual(try updatedAtCodec.encode(date), .real(2_451_544.5))
    }

    // MARK: - Assertion helpers

    private func assertCodecError<T>(
        _ expression: @autoclosure () throws -> T,
        equals expected: XLValueCodecError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLValueCodecError, expected, file: file, line: line)
        }
    }

    private func assertEncodingFailed<T>(
        _ expression: @autoclosure () throws -> T,
        codec: XLValueCodecKey,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .encodingFailed(codec: codec, context: parameterContext, message: message),
                file: file,
                line: line
            )
        }
    }

    private func assertDecodingFailed<T>(
        _ expression: @autoclosure () throws -> T,
        codec: XLValueCodecKey,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .decodingFailed(codec: codec, context: resultContext, message: message),
                file: file,
                line: line
            )
        }
    }
}


/// A minimal deterministic `RandomNumberGenerator` (splitmix64) so
/// round-trip-error sampling stays reproducible across CI runs.
private struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
