import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@testable import SwiftQL


/// Real GRDB/SQLite round-trip coverage for the numeric `Date` presets in
/// `Sources/SwiftQL/SQLiteNumericDateCodecs.swift`. This mirrors
/// `ContextualValueCodecGRDBTests.swift`'s style: a low-level
/// `GRDBDatabaseDriver` connection prepares and binds raw SQL directly, so
/// these tests exercise real SQLite storage, affinity, and date/time
/// functions without depending on the property-level codec selection
/// mechanism tracked separately in issue #66.
///
/// Pure Swift-level codec behavior (identity, ambiguity, non-finite/overflow
/// errors, storage-mismatch errors, optional/NULL mapping) is covered in
/// `SQLiteNumericDateCodecContractTests.swift` in this same target; this file
/// focuses on what only a real database can prove: literal SQL rendering
/// through bound parameters, INSERT/UPDATE/SELECT, ordering comparisons,
/// coexistence of two presets in one schema, and `julianday()`/`datetime()`
/// interoperability.
final class SQLiteNumericDateCodecGRDBTests: XCTestCase {

    private let dialect = XLSQLiteDialect()

    private func makeConfiguration() throws -> XLValueCodingConfiguration {
        try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registeringSQLiteNumericDateCodecs()
        )
    }

    // MARK: - Insert / update / select / decode round trips

    func testAllThreePresetsRoundTripInsertUpdateSelectThroughRealSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: """
                            CREATE TABLE numeric_dates (
                                id INTEGER PRIMARY KEY,
                                milliseconds_value INTEGER NOT NULL,
                                seconds_value REAL NOT NULL,
                                julian_day_value REAL NOT NULL
                            )
                            """
                    )
                )
            )
        }

        let original = Date(timeIntervalSince1970: 1_700_000_000.25)
        let insertContext = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("insert"))
        let milliseconds = try encode(
            original,
            preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            configuration: configuration,
            context: insertContext
        )
        let seconds = try encode(
            original,
            preset: XLSQLiteNumericDateCodec.UnixSeconds.key,
            configuration: configuration,
            context: insertContext
        )
        let julianDay = try encode(
            original,
            preset: XLSQLiteNumericDateCodec.JulianDay.key,
            configuration: configuration,
            context: insertContext
        )

        try driver.withWriteConnection { connection in
            var statement = try connection.prepare(
                logicalStatement(
                    databaseIdentifier: databaseIdentifier,
                    sql: """
                        INSERT INTO numeric_dates
                            (id, milliseconds_value, seconds_value, julian_day_value)
                        VALUES
                            (1, :milliseconds_value, :seconds_value, :julian_day_value)
                        """
                )
            )
            statement = try connection.bind(milliseconds, to: .named("milliseconds_value"), in: statement)
            statement = try connection.bind(seconds, to: .named("seconds_value"), in: statement)
            statement = try connection.bind(julianDay, to: .named("julian_day_value"), in: statement)
            try connection.execute(statement)
        }

        let selected = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: """
                                SELECT
                                    milliseconds_value, typeof(milliseconds_value),
                                    seconds_value, typeof(seconds_value),
                                    julian_day_value, typeof(julian_day_value)
                                FROM numeric_dates WHERE id = 1
                                """
                        )
                    )
                )
            )
        }
        XCTAssertEqual(selected[1], .text("integer"))
        XCTAssertEqual(selected[3], .text("real"))
        XCTAssertEqual(selected[5], .text("real"))

        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("select"))
        XCTAssertEqual(
            try decode(
                selected[0],
                preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                configuration: configuration,
                context: resultContext
            ),
            original
        )
        XCTAssertEqual(
            try decode(
                selected[2],
                preset: XLSQLiteNumericDateCodec.UnixSeconds.key,
                configuration: configuration,
                context: resultContext
            ),
            original
        )
        let decodedJulianDay = try decode(
            selected[4],
            preset: XLSQLiteNumericDateCodec.JulianDay.key,
            configuration: configuration,
            context: resultContext
        )
        XCTAssertEqual(decodedJulianDay.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.001)

        // UPDATE with a second date, then re-select and decode.
        let updated = Date(timeIntervalSince1970: -12_345.5)
        let updateContext = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("update"))
        let updatedMilliseconds = try encode(
            updated,
            preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            configuration: configuration,
            context: updateContext
        )
        try driver.withWriteConnection { connection in
            var statement = try connection.prepare(
                logicalStatement(
                    databaseIdentifier: databaseIdentifier,
                    sql: "UPDATE numeric_dates SET milliseconds_value = :milliseconds_value WHERE id = 1"
                )
            )
            statement = try connection.bind(
                updatedMilliseconds,
                to: .named("milliseconds_value"),
                in: statement
            )
            try connection.execute(statement)
        }
        let reselected = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT milliseconds_value FROM numeric_dates WHERE id = 1"
                        )
                    )
                )
            )
        }
        XCTAssertEqual(
            try decode(
                reselected[0],
                preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                configuration: configuration,
                context: resultContext
            ),
            updated
        )
    }

    // MARK: - Ordering / comparison

    func testEachPresetPreservesChronologicalOrderingUnderSQLComparison() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        let dates = [
            Date(timeIntervalSince1970: -1_000_000), // before the epoch
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 500_000.75),
            Date(timeIntervalSince1970: 2_000_000_000),
        ]

        for preset in [
            XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            XLSQLiteNumericDateCodec.UnixSeconds.key,
            XLSQLiteNumericDateCodec.JulianDay.key,
        ] {
            let columnType = preset == XLSQLiteNumericDateCodec.UnixMilliseconds.key
                ? "INTEGER"
                : "REAL"
            try driver.withWriteConnection { connection in
                try connection.execute(
                    connection.prepare(
                        logicalStatement(databaseIdentifier: databaseIdentifier, sql: "DROP TABLE IF EXISTS ordering_probe")
                    )
                )
                try connection.execute(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "CREATE TABLE ordering_probe (value \(columnType) NOT NULL)"
                        )
                    )
                )
            }

            let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("ordering"))
            // Insert in reverse-chronological order so a correct ORDER BY
            // proves the numeric encoding, not insertion order.
            for date in dates.reversed() {
                let encoded = try encode(
                    date,
                    preset: preset,
                    configuration: configuration,
                    context: context
                )
                try driver.withWriteConnection { connection in
                    var statement = try connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "INSERT INTO ordering_probe (value) VALUES (:value)"
                        )
                    )
                    statement = try connection.bind(encoded, to: .named("value"), in: statement)
                    try connection.execute(statement)
                }
            }

            let orderedRows = try driver.withReadConnection { connection in
                try connection.fetchAll(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT value FROM ordering_probe ORDER BY value ASC"
                        )
                    )
                )
            }
            let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("ordering"))
            let orderedDates = try orderedRows.map {
                try decode(
                    $0[0],
                    preset: preset,
                    configuration: configuration,
                    context: resultContext
                )
            }
            for (decoded, expected) in zip(orderedDates, dates) {
                XCTAssertEqual(
                    decoded.timeIntervalSince1970,
                    expected.timeIntervalSince1970,
                    accuracy: 0.01,
                    "\(preset) did not preserve chronological ordering"
                )
            }
        }
    }

    // MARK: - Optional / NULL

    func testOptionalColumnsRoundTripNullAndPresentValuesThroughRealSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: "CREATE TABLE optional_dates (id INTEGER PRIMARY KEY, seconds_value REAL)"
                    )
                )
            )
        }

        let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("optional"))
        let presentDate = Date(timeIntervalSince1970: 100)
        let presentValue = try configuration.encodeOptional(
            presentDate,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key)
        )
        let nullValue = try configuration.encodeOptional(
            Optional<Date>.none,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key)
        )

        try driver.withWriteConnection { connection in
            var insertPresent = try connection.prepare(
                logicalStatement(
                    databaseIdentifier: databaseIdentifier,
                    sql: "INSERT INTO optional_dates (id, seconds_value) VALUES (1, :seconds_value)"
                )
            )
            insertPresent = try connection.bind(presentValue, to: .named("seconds_value"), in: insertPresent)
            try connection.execute(insertPresent)

            var insertNull = try connection.prepare(
                logicalStatement(
                    databaseIdentifier: databaseIdentifier,
                    sql: "INSERT INTO optional_dates (id, seconds_value) VALUES (2, :seconds_value)"
                )
            )
            insertNull = try connection.bind(nullValue, to: .named("seconds_value"), in: insertNull)
            try connection.execute(insertNull)
        }

        let rows = try driver.withReadConnection { connection in
            try connection.fetchAll(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: "SELECT seconds_value FROM optional_dates ORDER BY id ASC"
                    )
                )
            )
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][0], .null)

        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("optional"))
        let decodedPresent: Date? = try configuration.decodeOptional(
            Date.self,
            from: rows[0][0],
            using: dialect,
            context: resultContext,
            selection: XLValueCodecSelection(explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key)
        )
        let decodedNull: Date? = try configuration.decodeOptional(
            Date.self,
            from: rows[1][0],
            using: dialect,
            context: resultContext,
            selection: XLValueCodecSelection(explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key)
        )
        XCTAssertEqual(decodedPresent, presentDate)
        XCTAssertNil(decodedNull)
    }

    // MARK: - Coexistence of two representations in one schema

    func testTwoNumericDateColumnsCoexistInOneSchemaWithIndependentCodecs() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: """
                            CREATE TABLE events (
                                id INTEGER PRIMARY KEY,
                                created_at_milliseconds INTEGER NOT NULL,
                                updated_at_julian_day REAL NOT NULL
                            )
                            """
                    )
                )
            )
        }

        let createdAt = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01T00:00:00Z
        let updatedAt = Date(timeIntervalSince1970: 1_000_000_000)
        let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("events"))
        let createdAtValue = try encode(
            createdAt,
            preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
            configuration: configuration,
            context: context
        )
        let updatedAtValue = try encode(
            updatedAt,
            preset: XLSQLiteNumericDateCodec.JulianDay.key,
            configuration: configuration,
            context: context
        )

        try driver.withWriteConnection { connection in
            var statement = try connection.prepare(
                logicalStatement(
                    databaseIdentifier: databaseIdentifier,
                    sql: """
                        INSERT INTO events (id, created_at_milliseconds, updated_at_julian_day)
                        VALUES (1, :created_at_milliseconds, :updated_at_julian_day)
                        """
                )
            )
            statement = try connection.bind(
                createdAtValue,
                to: .named("created_at_milliseconds"),
                in: statement
            )
            statement = try connection.bind(
                updatedAtValue,
                to: .named("updated_at_julian_day"),
                in: statement
            )
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: """
                                SELECT created_at_milliseconds, updated_at_julian_day
                                FROM events WHERE id = 1
                                """
                        )
                    )
                )
            )
        }
        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("events"))
        XCTAssertEqual(
            try decode(
                row[0],
                preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                configuration: configuration,
                context: resultContext
            ),
            createdAt
        )
        let decodedUpdatedAt = try decode(
            row[1],
            preset: XLSQLiteNumericDateCodec.JulianDay.key,
            configuration: configuration,
            context: resultContext
        )
        XCTAssertEqual(
            decodedUpdatedAt.timeIntervalSince1970,
            updatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    // MARK: - SQLite date/time-function interoperability

    func testJulianDayPresetIsConsumedDirectlyByDateTimeFunctionsWithoutModifiers() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        // SQLite interprets a bare REAL argument to date()/datetime() as a
        // Julian day number, which is exactly this preset's storage
        // convention, so no modifier is required.
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT datetime(2440587.5), date(2440587.5)"
                        )
                    )
                )
            )
        }
        XCTAssertEqual(row[0], .text("1970-01-01 00:00:00"))
        XCTAssertEqual(row[1], .text("1970-01-01"))
    }

    func testUnixSecondsPresetRequiresTheUnixepochModifier() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT datetime(1700000000, 'unixepoch'), julianday(1700000000, 'unixepoch')"
                        )
                    )
                )
            )
        }
        XCTAssertEqual(row[0], .text("2023-11-14 22:13:20"))
        guard case .real(let julianDay) = row[1] else {
            return XCTFail("Expected a REAL julian day, got \(String(describing: row[1])).")
        }
        XCTAssertEqual(julianDay, 1_700_000_000 / 86_400 + 2_440_587.5, accuracy: 1e-6)
    }

    func testUnixMillisecondsPresetRequiresDivisionBeforeTheUnixepochModifier() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        // The stored value is milliseconds, so SQL must divide by 1000.0
        // before applying the 'unixepoch' modifier (which expects seconds).
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT datetime(1700000000000 / 1000.0, 'unixepoch')"
                        )
                    )
                )
            )
        }
        XCTAssertEqual(row[0], .text("2023-11-14 22:13:20"))
    }

    // MARK: - Malformed / wrong-storage stored values

    func testDecodingAValueSQLiteStoredWithTheWrongTypeAffinityFailsStructurally() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: "CREATE TABLE malformed_dates (milliseconds_value INTEGER)"
                    )
                )
            )
            // SQLite's INTEGER affinity only converts text that looks like a
            // number; a non-numeric string is stored verbatim as TEXT.
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: "INSERT INTO malformed_dates (milliseconds_value) VALUES ('not-a-timestamp')"
                    )
                )
            )
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(
                            databaseIdentifier: databaseIdentifier,
                            sql: "SELECT milliseconds_value, typeof(milliseconds_value) FROM malformed_dates"
                        )
                    )
                )
            )
        }
        XCTAssertEqual(row[1], .text("text"))

        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("malformed"))
        XCTAssertThrowsError(
            try decode(
                row[0],
                preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                configuration: configuration,
                context: resultContext
            )
        ) { error in
            guard case .storageMismatch? = error as? XLValueCodecError else {
                return XCTFail("Expected a storage-mismatch error, received \(error).")
            }
        }
    }

    func testDecodingAnOverflowingRealExpressionFailsStructurally() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        // A computed SQL expression can overflow to IEEE 754 infinity even
        // though no bound parameter ever carried a non-finite value.
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(databaseIdentifier: databaseIdentifier, sql: "SELECT 1.0e308 * 1.0e308, typeof(1.0e308 * 1.0e308)")
                    )
                )
            )
        }
        XCTAssertEqual(row[1], .text("real"))

        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("overflow"))
        XCTAssertThrowsError(
            try decode(
                row[0],
                preset: XLSQLiteNumericDateCodec.UnixSeconds.key,
                configuration: configuration,
                context: resultContext
            )
        ) { error in
            guard case .decodingFailed(_, _, let message)? = error as? XLValueCodecError else {
                return XCTFail("Expected a decoding-failed error, received \(error).")
            }
            // `XLValueCodec` wraps a thrown error with `String(describing:)`,
            // which renders the enum case (not `errorDescription`), so assert
            // against that exact rendering rather than a loosely-matched
            // substring.
            XCTAssertEqual(
                message,
                String(
                    describing: XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                        preset: XLSQLiteNumericDateCodec.UnixSeconds.key.id,
                        value: .positiveInfinity
                    )
                )
            )
        }
    }

    func testJulianDayRejectsAFiniteStoredValueThatOverflowsWhenConvertedToUnixSeconds() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier
        // This REAL value is finite, but converting it from a julian-day
        // number back to unix seconds (`(value - epoch) * 86400`) overflows
        // to IEEE 754 infinity.
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(
                        logicalStatement(databaseIdentifier: databaseIdentifier, sql: "SELECT 1.0e304, typeof(1.0e304)")
                    )
                )
            )
        }
        XCTAssertEqual(row[1], .text("real"))

        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("julian-day-overflow"))
        XCTAssertThrowsError(
            try decode(
                row[0],
                preset: XLSQLiteNumericDateCodec.JulianDay.key,
                configuration: configuration,
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
    }

    // MARK: - Boundary and randomized representative dates

    func testRepresentativeDatesRoundTripThroughRealSQLiteForEveryPreset() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try makeConfiguration()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let databaseIdentifier = driver.databaseIdentifier

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: """
                            CREATE TABLE representative_dates (
                                milliseconds_value INTEGER,
                                seconds_value REAL,
                                julian_day_value REAL
                            )
                            """
                    )
                )
            )
        }

        let parameterContext = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("representative"))
        let resultContext = XLValueCodingContext(site: .result, path: XLValueCodingPath("representative"))

        for date in SQLiteNumericDateCodecContractTests.representativeDates() {
            let milliseconds = try encode(
                date,
                preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                configuration: configuration,
                context: parameterContext
            )
            let seconds = try encode(
                date,
                preset: XLSQLiteNumericDateCodec.UnixSeconds.key,
                configuration: configuration,
                context: parameterContext
            )
            let julianDay = try encode(
                date,
                preset: XLSQLiteNumericDateCodec.JulianDay.key,
                configuration: configuration,
                context: parameterContext
            )

            let row = try driver.withWriteConnection { connection -> [XLSQLiteValue] in
                var insert = try connection.prepare(
                    logicalStatement(
                        databaseIdentifier: databaseIdentifier,
                        sql: """
                            INSERT INTO representative_dates
                                (milliseconds_value, seconds_value, julian_day_value)
                            VALUES
                                (:milliseconds_value, :seconds_value, :julian_day_value)
                            RETURNING
                                milliseconds_value, seconds_value, julian_day_value
                            """
                    )
                )
                insert = try connection.bind(milliseconds, to: .named("milliseconds_value"), in: insert)
                insert = try connection.bind(seconds, to: .named("seconds_value"), in: insert)
                insert = try connection.bind(julianDay, to: .named("julian_day_value"), in: insert)
                return try XCTUnwrap(connection.fetchOne(insert))
            }

            XCTAssertEqual(
                try decode(
                    row[0],
                    preset: XLSQLiteNumericDateCodec.UnixMilliseconds.key,
                    configuration: configuration,
                    context: resultContext
                ).timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: 0.0005 + 1e-9,
                "unix-milliseconds round trip through SQLite exceeded its documented bound for \(date)"
            )
            XCTAssertEqual(
                try decode(
                    row[1],
                    preset: XLSQLiteNumericDateCodec.UnixSeconds.key,
                    configuration: configuration,
                    context: resultContext
                ).timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: Swift.max(date.timeIntervalSince1970.ulp, .leastNormalMagnitude) * 8,
                "unix-seconds round trip through SQLite exceeded its documented bound for \(date)"
            )
            guard case .real(let julianDayValue) = julianDay else {
                return XCTFail("Expected a REAL julian day value.")
            }
            let julianDayTolerance = julianDayValue.ulp
                * XLSQLiteNumericDateCodec.JulianDay.secondsPerDay
                * 8
            XCTAssertEqual(
                try decode(
                    row[2],
                    preset: XLSQLiteNumericDateCodec.JulianDay.key,
                    configuration: configuration,
                    context: resultContext
                ).timeIntervalSince1970,
                date.timeIntervalSince1970,
                accuracy: julianDayTolerance,
                "julian-day round trip through SQLite exceeded its documented bound for \(date)"
            )
        }
    }

    // MARK: - Helpers

    private func encode(
        _ date: Date,
        preset: XLValueCodecKey,
        configuration: XLValueCodingConfiguration,
        context: XLValueCodingContext
    ) throws -> XLSQLiteValue {
        try configuration.encode(
            date,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(explicitCodecKey: preset)
        )
    }

    private func decode(
        _ value: XLSQLiteValue,
        preset: XLValueCodecKey,
        configuration: XLValueCodingConfiguration,
        context: XLValueCodingContext
    ) throws -> Date {
        try configuration.decode(
            Date.self,
            from: value,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(explicitCodecKey: preset)
        )
    }

    private func logicalStatement(
        databaseIdentifier: XLDatabaseIdentifier,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }

    private func makeFixture() throws -> TemporaryDatabaseFixture {
        try TemporaryDatabaseFixture.make(named: "numeric-date-codec")
    }
}
