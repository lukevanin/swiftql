import Foundation
import GRDB
import XCTest
@testable import SwiftQL


/// Real SQLite round trips for ``XLDateTextCodec``. Pure encode/decode logic
/// that needs no database connection lives in `DateTextCodecContractTests.swift`.
final class DateTextCodecGRDBTests: XCTestCase {

    // MARK: - Standard preset: literal, insert, update, select, NULL, decode

    func testStandardPresetRoundTripsInsertUpdateSelectAndOptionalNullThroughRealSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [XLDateTextCodec.standardKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let inserted = Date(timeIntervalSince1970: 1_700_000_000.123)
        let updated = Date(timeIntervalSince1970: 1_700_000_500.5)
        let parameterContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["events", "occurred_at"])
        )

        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE events (
                    id INTEGER PRIMARY KEY,
                    occurred_at TEXT NOT NULL,
                    closed_at TEXT
                )
                """
        )
        let insert = logicalStatement(
            for: driver,
            sql: """
                INSERT INTO events (id, occurred_at, closed_at)
                VALUES (:id, :occurred_at, :closed_at)
                """
        )
        let update = logicalStatement(
            for: driver,
            sql: "UPDATE events SET occurred_at = :occurred_at WHERE id = :id"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT occurred_at, typeof(occurred_at), closed_at, typeof(closed_at) FROM events WHERE id = :id"
        )

        let insertedValue = try configuration.encode(
            inserted,
            using: dialect,
            context: parameterContext
        )
        let nullValue = try configuration.encodeOptional(
            Optional<Date>.none,
            using: dialect,
            context: parameterContext
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))

            var insertStatement = try connection.prepare(insert)
            insertStatement = try connection.bind(.integer(1), to: .named("id"), in: insertStatement)
            insertStatement = try connection.bind(
                insertedValue,
                to: .named("occurred_at"),
                in: insertStatement
            )
            insertStatement = try connection.bind(
                nullValue,
                to: .named("closed_at"),
                in: insertStatement
            )
            try connection.execute(insertStatement)
        }

        let firstRow = try driver.withReadConnection { connection -> [XLSQLiteValue] in
            var selectStatement = try connection.prepare(select)
            selectStatement = try connection.bind(.integer(1), to: .named("id"), in: selectStatement)
            return try XCTUnwrap(connection.fetchOne(selectStatement))
        }
        XCTAssertEqual(firstRow[0], .text("2023-11-14T22:13:20.123Z"))
        XCTAssertEqual(firstRow[1], .text("text"))
        XCTAssertEqual(firstRow[2], .null)
        XCTAssertEqual(firstRow[3], .text("null"))
        // Millisecond-precision text round-trips to millisecond accuracy, not
        // bit-identically: `Date` itself cannot exactly represent an
        // arbitrary literal like `1_700_000_000.123` at this magnitude, so
        // the nearest representable `Double` already differs from the
        // stored text's exact meaning by a sub-microsecond residual.
        XCTAssertEqual(
            try configuration.decode(
                Date.self,
                from: firstRow[0],
                using: dialect,
                context: XLValueCodingContext(site: .result, path: parameterContext.path)
            ).timeIntervalSince1970,
            inserted.timeIntervalSince1970,
            accuracy: 0.001
        )
        let decodedClosedAt: Date? = try configuration.decodeOptional(
            Date.self,
            from: firstRow[2],
            using: dialect,
            context: XLValueCodingContext(site: .result, path: parameterContext.path)
        )
        XCTAssertNil(decodedClosedAt)

        let updatedValue = try configuration.encode(updated, using: dialect, context: parameterContext)
        try driver.withWriteConnection { connection in
            var updateStatement = try connection.prepare(update)
            updateStatement = try connection.bind(.integer(1), to: .named("id"), in: updateStatement)
            updateStatement = try connection.bind(
                updatedValue,
                to: .named("occurred_at"),
                in: updateStatement
            )
            try connection.execute(updateStatement)
        }

        let updatedRow = try driver.withReadConnection { connection -> [XLSQLiteValue] in
            var selectStatement = try connection.prepare(select)
            selectStatement = try connection.bind(.integer(1), to: .named("id"), in: selectStatement)
            return try XCTUnwrap(connection.fetchOne(selectStatement))
        }
        XCTAssertEqual(updatedRow[0], .text("2023-11-14T22:21:40.500Z"))
        XCTAssertEqual(
            try configuration.decode(
                Date.self,
                from: updatedRow[0],
                using: dialect,
                context: XLValueCodingContext(site: .result, path: parameterContext.path)
            ).timeIntervalSince1970,
            updated.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    // MARK: - Standard preset: literal + binding through the request facade

    func testStandardPresetRoundTripsThroughContextualBindingAndTheRequestFacade() throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [XLDateTextCodec.standardKey]
        )
        let database = try GRDBDatabase(
            url: directoryURL.appendingPathComponent("fixture.sqlite"),
            codingConfiguration: configuration,
            logger: nil
        )
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoffParameter = try database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "cutoff"
        )
        let request = database.makeRequest(with: sql { _ in Select(cutoffParameter) })
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: request.parameterLayout,
            bindings: [try cutoffParameter.encode(cutoff, in: request.parameterLayout)]
        ).validatingComplete()

        XCTAssertEqual(try request.fetchOne(bindings: bindings), "2023-11-14T22:13:20.000Z")
    }

    // MARK: - Ordering

    func testStandardPresetOrdersLexicographicallyLikeChronologicalOrderThroughSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [XLDateTextCodec.standardKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("moments"))
        let dates = [
            Date(timeIntervalSince1970: 1_700_000_000.5),
            Date(timeIntervalSince1970: -1_000_000_000),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_700_000_000.001),
            Date(timeIntervalSince1970: 253_000_000_000),
        ]

        let create = logicalStatement(
            for: driver,
            sql: "CREATE TABLE moments (moment TEXT NOT NULL)"
        )
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO moments (moment) VALUES (:moment)"
        )
        let selectOrdered = logicalStatement(
            for: driver,
            sql: "SELECT moment FROM moments ORDER BY moment ASC"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            for date in dates {
                var statement = try connection.prepare(insert)
                let value = try configuration.encode(date, using: dialect, context: context)
                statement = try connection.bind(value, to: .named("moment"), in: statement)
                try connection.execute(statement)
            }
        }

        let orderedRows = try driver.withReadConnection { connection -> [[XLSQLiteValue]] in
            var rows: [[XLSQLiteValue]] = []
            try connection.forEachRow(connection.prepare(selectOrdered)) { values in
                rows.append(values)
                return .advance
            }
            return rows
        }
        let orderedTexts: [String] = try orderedRows.map {
            guard case .text(let text) = $0[0] else {
                throw XCTSkip("Expected TEXT storage")
            }
            return text
        }
        let expectedTexts = try dates.sorted().map { date -> String in
            guard case .text(let text) = try configuration.encode(date, using: dialect, context: context) else {
                throw XCTSkip("Expected TEXT storage")
            }
            return text
        }

        XCTAssertEqual(orderedTexts, expectedTexts)
    }

    // MARK: - SQLite date/time function interaction

    func testStandardPresetTextIsDirectlyReadableBySQLiteDateTimeFunctions() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [XLDateTextCodec.standardKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("readings"))
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)

        let create = logicalStatement(
            for: driver,
            sql: "CREATE TABLE readings (taken_at TEXT NOT NULL)"
        )
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO readings (taken_at) VALUES (:taken_at)"
        )
        // `date`, `strftime`, and `julianday` all parse the standard preset's
        // text directly; `>` and `BETWEEN` compare it against SQL date-string
        // literals without a dialect conversion expression.
        let select = logicalStatement(
            for: driver,
            sql: """
                SELECT
                    date(taken_at),
                    strftime('%Y-%m-%d %H:%M:%f', taken_at),
                    julianday(taken_at) > julianday('2023-01-01T00:00:00.000Z'),
                    taken_at > '2023-01-01T00:00:00.000Z',
                    taken_at BETWEEN '2023-01-01T00:00:00.000Z' AND '2024-01-01T00:00:00.000Z'
                FROM readings
                """
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            let value = try configuration.encode(date, using: dialect, context: context)
            statement = try connection.bind(value, to: .named("taken_at"), in: statement)
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }
        XCTAssertEqual(row[0], .text("2023-11-14"))
        XCTAssertEqual(row[1], .text("2023-11-14 22:13:20.123"))
        XCTAssertEqual(row[2], .integer(1))
        XCTAssertEqual(row[3], .integer(1))
        XCTAssertEqual(row[4], .integer(1))
    }

    // MARK: - A named custom codec coexists with the standard preset

    func testStandardAndCustomCodecsCoexistForTwoDatePropertiesInOneSchema() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let secondsOnlyFormat = try XLDateTextFormat(fractionalSecondDigits: 0)
        let secondsOnlyKey = XLValueCodecKey(id: "test.date-text.seconds-only", version: 1)
        let secondsOnlyCodec = XLDateTextCodec.custom(key: secondsOnlyKey, format: secondsOnlyFormat)
        let registry = try XLValueCodecRegistry()
            .registering(XLDateTextCodec.standard)
            .registering(secondsOnlyCodec)
        // Both codecs target the same stable Swift value-type identity, so
        // neither can be a database default at the same time (that would be
        // a rejected `duplicateDefault`); each property selects explicitly.
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let startedContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["sessions", "started_at"])
        )
        let completedContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["sessions", "completed_at"])
        )
        let started = Date(timeIntervalSince1970: 1_700_000_000.123)
        let completed = Date(timeIntervalSince1970: 1_700_000_061)

        let startedValue = try configuration.encode(
            started,
            using: dialect,
            context: startedContext,
            selection: XLValueCodecSelection(explicitCodecKey: XLDateTextCodec.standardKey)
        )
        let completedValue = try configuration.encode(
            completed,
            using: dialect,
            context: completedContext,
            selection: XLValueCodecSelection(explicitCodecKey: secondsOnlyKey)
        )

        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE sessions (
                    started_at TEXT NOT NULL,
                    completed_at TEXT NOT NULL
                )
                """
        )
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO sessions (started_at, completed_at) VALUES (:started_at, :completed_at)"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT started_at, completed_at FROM sessions"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            statement = try connection.bind(startedValue, to: .named("started_at"), in: statement)
            statement = try connection.bind(completedValue, to: .named("completed_at"), in: statement)
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }
        XCTAssertEqual(row[0], .text("2023-11-14T22:13:20.123Z"))
        XCTAssertEqual(row[1], .text("2023-11-14T22:14:21Z"))

        // Millisecond precision round-trips to millisecond accuracy (see the
        // comment in the insert/update/select test above for why exact
        // `Date` equality is not the right assertion here).
        XCTAssertEqual(
            try configuration.decode(
                Date.self,
                from: row[0],
                using: dialect,
                context: XLValueCodingContext(site: .result, path: startedContext.path),
                selection: XLValueCodecSelection(explicitCodecKey: XLDateTextCodec.standardKey)
            ).timeIntervalSince1970,
            started.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try configuration.decode(
                Date.self,
                from: row[1],
                using: dialect,
                context: XLValueCodingContext(site: .result, path: completedContext.path),
                selection: XLValueCodecSelection(explicitCodecKey: secondsOnlyKey)
            ),
            completed
        )
    }

    // MARK: - Structured errors carry codec and property context

    func testInvalidStoredTextFailsToDecodeWithCodecAndPropertyContext() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
            defaultCodecKeys: [XLDateTextCodec.standardKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: dialect)
        let resultContext = XLValueCodingContext(
            site: .result,
            path: XLValueCodingPath(["corrupt", "when"])
        )

        let create = logicalStatement(
            for: driver,
            sql: "CREATE TABLE corrupt (moment TEXT NOT NULL)"
        )
        let insertGarbage = logicalStatement(
            for: driver,
            sql: "INSERT INTO corrupt (moment) VALUES ('not-a-date')"
        )
        let selectWrongStorage = logicalStatement(
            for: driver,
            sql: "SELECT 1700000000"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT moment FROM corrupt"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insertGarbage))
        }
        let storedRow = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }

        XCTAssertThrowsError(
            try configuration.decode(
                Date.self,
                from: storedRow[0],
                using: dialect,
                context: resultContext
            )
        ) { error in
            guard case .decodingFailed(let codec, let context, let message)? = error as? XLValueCodecError else {
                return XCTFail("Expected decodingFailed, received \(error).")
            }
            XCTAssertEqual(codec, XLDateTextCodec.standardKey)
            XCTAssertEqual(context, resultContext)
            XCTAssertTrue(message.contains("not-a-date"), message)
        }

        // A storage-class mismatch (INTEGER where the codec declared TEXT) is
        // rejected before the codec's own decode closure ever runs.
        let integerRow = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(selectWrongStorage)))
        }
        XCTAssertThrowsError(
            try configuration.decode(
                Date.self,
                from: integerRow[0],
                using: dialect,
                context: resultContext
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: XLDateTextCodec.standardKey,
                    expected: XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.text.rawValue),
                    actual: XLValueStorageIdentifier(rawValue: XLSQLiteStorageClass.integer.rawValue),
                    context: resultContext
                )
            )
        }
    }

    // MARK: - Fixtures

    private func logicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }

    private func makeFixture() throws -> DateTextCodecFixture {
        let directoryURL = try makeDirectory()
        return DateTextCodecFixture(
            directoryURL: directoryURL,
            pool: try DatabasePool(
                path: directoryURL.appendingPathComponent("database.sqlite").path
            )
        )
    }

    private func makeDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-date-text-codec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return directoryURL
    }
}


private struct DateTextCodecFixture {
    let directoryURL: URL
    let pool: DatabasePool

    func tearDown() {
        try? pool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
