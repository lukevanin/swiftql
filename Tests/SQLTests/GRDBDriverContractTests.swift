import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@testable import SwiftQL
import SwiftQLSQLiteConformanceFixtures


@SQLTable(name: "GRDBDriverContractRecord")
struct GRDBDriverContractRecord: Equatable {
    let id: String
    let value: Int
}


final class GRDBDriverContractTests: XCTestCase {

    private enum TransactionAbort: Error, Equatable {
        case requested
    }

    func testSharedSQLiteStorageCasesRoundTripWithTypeofEvidence() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value, typeof(:value), length(:value)"
        )

        for testCase in SQLiteValueConformanceFixtures.storageCases {
            switch testCase.expectation {
            case .bindingRejected:
                XCTAssertThrowsError(
                    try driver.withBlockingReadConnection { connection in
                        let statement = try connection.prepare(logicalStatement)
                        _ = try connection.bind(
                            testCase.value,
                            to: .named("value"),
                            in: statement
                        )
                    },
                    testCase.id.rawValue
                ) { error in
                    XCTAssertEqual(
                        error as? XLSQLValueEncodingError,
                        .realBindingWouldBecomeNull(
                            value: .notANumber,
                            valueType: String(reflecting: Double.self),
                            context: XLValueCodingContext(
                                site: .parameter,
                                path: XLValueCodingPath("value")
                            )
                        ),
                        testCase.id.rawValue
                    )
                }
            case .roundTrip:
                let row = try driver.withBlockingReadConnection { connection in
                    var statement = try connection.prepare(logicalStatement)
                    statement = try connection.bind(
                        testCase.value,
                        to: .named("value"),
                        in: statement
                    )
                    return try XCTUnwrap(connection.fetchOne(statement))
                }
                let streamedRows = try driver.withBlockingReadConnection { connection in
                    var statement = try connection.prepare(logicalStatement)
                    statement = try connection.bind(
                        testCase.value,
                        to: .named("value"),
                        in: statement
                    )
                    var rows: [[XLSQLiteValue]] = []
                    try connection.forEachRow(statement) { values in
                        rows.append(values)
                        return .advance
                    }
                    return rows
                }
                XCTAssertEqual(
                    streamedRows,
                    [row],
                    testCase.id.rawValue
                )
                XCTAssertEqual(row[0], testCase.value, testCase.id.rawValue)
                XCTAssertEqual(
                    row[1],
                    .text(testCase.expectedStorage.rawValue),
                    testCase.id.rawValue
                )
                if case .blob(let data) = testCase.value {
                    XCTAssertEqual(
                        row[2],
                        .integer(Int64(data.count)),
                        testCase.id.rawValue
                    )
                }
            }
        }
    }

    func testSharedUnicodeCasePreservesCanonicalVariantsWithoutConflatingBytes() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let composed = "é"
        let decomposed = "e\u{301}"
        XCTAssertEqual(
            composed,
            decomposed,
            SQLiteValueConformanceCaseID.unicodeText.rawValue
        )

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let statement = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT
                    :composed, hex(:composed),
                    :decomposed, hex(:decomposed),
                    :composed = :decomposed
                """
        )
        let row = try driver.withBlockingReadConnection { connection in
            var prepared = try connection.prepare(statement)
            prepared = try connection.bind(
                .text(composed),
                to: .named("composed"),
                in: prepared
            )
            prepared = try connection.bind(
                .text(decomposed),
                to: .named("decomposed"),
                in: prepared
            )
            return try XCTUnwrap(connection.fetchOne(prepared))
        }
        let streamedRows = try driver.withBlockingReadConnection { connection in
            var prepared = try connection.prepare(statement)
            prepared = try connection.bind(
                .text(composed),
                to: .named("composed"),
                in: prepared
            )
            prepared = try connection.bind(
                .text(decomposed),
                to: .named("decomposed"),
                in: prepared
            )
            var rows: [[XLSQLiteValue]] = []
            try connection.forEachRow(prepared) { values in
                rows.append(values)
                return .advance
            }
            return rows
        }

        XCTAssertEqual(
            streamedRows,
            [row],
            SQLiteValueConformanceCaseID.unicodeText.rawValue
        )
        XCTAssertEqual(row[0], .text(composed))
        XCTAssertEqual(row[1], .text("C3A9"))
        XCTAssertEqual(row[2], .text(decomposed))
        XCTAssertEqual(row[3], .text("65CC81"))
        XCTAssertEqual(
            row[4],
            .integer(0),
            SQLiteValueConformanceCaseID.unicodeText.rawValue
        )
    }

    func testCursorStreamBoundsSteppingAndReleasesConnectionOnStopAndError() throws {
        let probe = GRDBStreamStepProbe()
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    GRDBStreamStepProbe.functionName,
                    argumentCount: 1
                ) { values in
                    probe.observe(values[0])
                }
            )
        }
        let fixture = try makeFixture(configuration: configuration)
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: "CREATE TABLE stream_rows (id INTEGER PRIMARY KEY)"
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: "INSERT INTO stream_rows (id) VALUES (1), (2), (3), (4), (5)"
        )
        let select = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT id, \(GRDBStreamStepProbe.functionName)(id)
                FROM stream_rows
                ORDER BY id
                """
        )
        let empty = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT id, \(GRDBStreamStepProbe.functionName)(id)
                FROM stream_rows
                WHERE id < 0
                """
        )
        try driver.withBlockingWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }

        var earlyRows: [[XLSQLiteValue]] = []
        var replayAfterStop: [[XLSQLiteValue]] = []
        var invocationCountAtStop = 0
        try driver.withBlockingReadConnection { connection in
            let statement = try connection.prepare(select)
            try connection.forEachRow(statement) { row in
                earlyRows.append(row)
                return earlyRows.count == 2 ? .stop : .advance
            }
            invocationCountAtStop = probe.invocationCount
            replayAfterStop = try connection.fetchAll(statement)
        }
        XCTAssertEqual(earlyRows.map(\.first), [.integer(1), .integer(2)])
        XCTAssertEqual(invocationCountAtStop, 2)
        XCTAssertEqual(
            replayAfterStop.map(\.first),
            (1 ... 5).map { .integer(Int64($0)) }
        )
        XCTAssertEqual(probe.invocationCount, 7)

        let countBeforeError = probe.invocationCount
        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                let statement = try connection.prepare(select)
                try connection.forEachRow(statement) { row in
                    if row.first == .integer(3) {
                        throw TransactionAbort.requested
                    }
                    return .advance
                }
            }
        ) { error in
            XCTAssertEqual(error as? TransactionAbort, .requested)
        }
        XCTAssertEqual(probe.invocationCount - countBeforeError, 3)

        let countBeforeFirst = probe.invocationCount
        let first = try driver.withBlockingReadConnection { connection in
            try connection.fetchOne(connection.prepare(select))
        }
        XCTAssertEqual(first?.first, .integer(1))
        XCTAssertEqual(probe.invocationCount - countBeforeFirst, 1)

        let countBeforeAll = probe.invocationCount
        let all = try driver.withBlockingReadConnection { connection in
            try connection.fetchAll(connection.prepare(select))
        }
        XCTAssertEqual(
            all.map(\.first),
            (1 ... 5).map { .integer(Int64($0)) }
        )
        XCTAssertEqual(probe.invocationCount - countBeforeAll, 5)

        let countBeforeEmpty = probe.invocationCount
        let noRows = try driver.withBlockingReadConnection { connection in
            try connection.fetchAll(connection.prepare(empty))
        }
        XCTAssertTrue(noRows.isEmpty)
        XCTAssertEqual(probe.invocationCount, countBeforeEmpty)
    }

    /// Issue #641: with no cursor open, preparing the same SQL twice on one
    /// physical connection reuses GRDB's cached statement. While a cursor
    /// over that statement is open, a second connection value over the same
    /// physical connection -- the shape a nested request on a transaction
    /// scope has -- gets its own statement, and the cache is used again once
    /// the cursor ends.
    func testStatementCacheIsReusedUnlessAnOpenCursorIsSteppingTheCachedStatement() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: "CREATE TABLE cached_rows (id INTEGER PRIMARY KEY)"
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: "INSERT INTO cached_rows (id) VALUES (1), (2), (3)"
        )
        let select = makeLogicalStatement(
            for: driver,
            sql: "SELECT id FROM cached_rows ORDER BY id"
        )
        try driver.withBlockingWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }

        try fixture.pool.read { database in
            var outer = driver.makeConnection(database)
            var nested = driver.makeConnection(database)

            let first = try outer.prepare(select)
            let second = try nested.prepare(select)
            XCTAssertTrue(
                first.sharesGRDBStatement(with: second),
                "With no cursor open, the statement cache must be used."
            )

            var outerRows: [[XLSQLiteValue]] = []
            try outer.forEachRow(first) { row in
                outerRows.append(row)
                // A reset outer cursor restarts forever; stop instead of hanging.
                guard outerRows.count <= 3 else {
                    XCTFail("The outer cursor restarted: a nested prepare reset its statement.")
                    return .stop
                }
                let nestedStatement = try nested.prepare(select)
                XCTAssertFalse(
                    nestedStatement.sharesGRDBStatement(with: first),
                    "A statement with an open cursor must not be handed to a nested request."
                )
                XCTAssertEqual(try nested.fetchAll(nestedStatement).count, 3)
                return .advance
            }
            XCTAssertEqual(outerRows.map(\.first), [.integer(1), .integer(2), .integer(3)])

            let afterCursor = try nested.prepare(select)
            XCTAssertTrue(
                afterCursor.sharesGRDBStatement(with: first),
                "The open-cursor mark must be removed when the cursor ends."
            )

            XCTAssertThrowsError(
                try outer.forEachRow(first) { _ in
                    throw TransactionAbort.requested
                }
            )
            XCTAssertTrue(
                try nested.prepare(select).sharesGRDBStatement(with: first),
                "A throwing body must not leave the statement marked."
            )
        }
    }

    /// Issue #641: the pull-based stepper behind `withResultSet` has its own
    /// open-cursor mark. On a pinned connection -- the transaction-scope shape
    /// -- an early return from the callback and a thrown callback must both
    /// remove that mark, so the next same-SQL prepare reuses the cache.
    func testValuesStepperRemovesItsOpenCursorMarkOnEarlyReturnAndOnThrow() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: "CREATE TABLE stepper_rows (id INTEGER PRIMARY KEY)"
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: "INSERT INTO stepper_rows (id) VALUES (1), (2), (3)"
        )
        let select = makeLogicalStatement(
            for: driver,
            sql: "SELECT id FROM stepper_rows ORDER BY id"
        )
        try driver.withBlockingWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }

        try fixture.pool.write { database in
            let box = GRDBPinnedConnectionBox(database)
            defer { box.invalidate() }
            // A pinned driver has its own database identifier, so its logical
            // statement is built for it. The SQL is the same, so it maps to the
            // same cached GRDB statement as `select`.
            let pinnedDriver = driver.pinned(to: box)
            let executor = GRDBInvocationExecutor(
                driver: pinnedDriver,
                logicalStatement: makeLogicalStatement(
                    for: pinnedDriver,
                    sql: "SELECT id FROM stepper_rows ORDER BY id"
                )
            )
            let packet = try executor.sqlitePacket(
                XLInvocationBindings<XLSQLiteValue>(
                    layout: executor.parameterLayout,
                    bindings: []
                ).validatingComplete()
            )
            var connection = driver.makeConnection(database)
            let reference = try connection.prepare(select)

            let firstRow = try executor.withValuesStepper(
                packet: packet,
                requiresWriteConnection: false
            ) { stepper -> [XLSQLiteValue]? in
                XCTAssertFalse(
                    try connection.prepare(select).sharesGRDBStatement(with: reference),
                    "The stepper's statement must be marked while its callback runs."
                )
                // Return early, with rows still left in the cursor.
                return try stepper()
            }
            XCTAssertEqual(firstRow, [.integer(1)])
            XCTAssertTrue(
                try connection.prepare(select).sharesGRDBStatement(with: reference),
                "An early return must remove the open-cursor mark."
            )

            XCTAssertThrowsError(
                try executor.withValuesStepper(
                    packet: packet,
                    requiresWriteConnection: false
                ) { stepper -> Void in
                    _ = try stepper()
                    throw TransactionAbort.requested
                }
            ) { error in
                XCTAssertEqual(error as? TransactionAbort, .requested)
            }
            XCTAssertTrue(
                try connection.prepare(select).sharesGRDBStatement(with: reference),
                "A thrown callback must remove the open-cursor mark."
            )
        }
    }

    func testSharedSQLiteAffinityCasesAssertValueTypeAndState() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: """
                CREATE TABLE value_affinity (
                    id TEXT PRIMARY KEY,
                    integer_value INTEGER,
                    text_value TEXT,
                    real_value REAL
                )
                """
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: """
                INSERT INTO value_affinity (
                    id, integer_value, text_value, real_value
                ) VALUES (
                    :id, :integer_value, :text_value, :real_value
                )
                """
        )
        let select = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT
                    integer_value, typeof(integer_value),
                    text_value, typeof(text_value),
                    real_value, typeof(real_value)
                FROM value_affinity
                WHERE id = 'affinity'
                """
        )

        try driver.withBlockingWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            statement = try connection.bind(
                .text("affinity"),
                to: .named("id"),
                in: statement
            )
            statement = try connection.bind(
                .text("42"),
                to: .named("integer_value"),
                in: statement
            )
            statement = try connection.bind(
                .integer(42),
                to: .named("text_value"),
                in: statement
            )
            statement = try connection.bind(
                .integer(42),
                to: .named("real_value"),
                in: statement
            )
            try connection.execute(statement)
        }

        let row = try driver.withBlockingReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }
        XCTAssertEqual(
            Array(row[0 ... 1]),
            [.integer(42), .text("integer")],
            SQLiteValueConformanceCaseID.numericTextIntegerAffinity.rawValue
        )
        XCTAssertEqual(
            Array(row[2 ... 3]),
            [.text("42"), .text("text")],
            SQLiteValueConformanceCaseID.integerTextAffinity.rawValue
        )
        XCTAssertEqual(
            Array(row[4 ... 5]),
            [.real(42), .text("real")],
            SQLiteValueConformanceCaseID.integerRealAffinity.rawValue
        )
    }

    func testSharedNamedRepeatedAndNullVersusMissingCases() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let repeated = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value, :value, typeof(:value)"
        )
        let noRow = makeLogicalStatement(
            for: driver,
            sql: "SELECT NULL WHERE 0"
        )

        let repeatedRow = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(repeated)
            statement = try connection.bind(
                .text("shared"),
                to: .named("value"),
                in: statement
            )
            return try XCTUnwrap(connection.fetchOne(statement))
        }
        XCTAssertEqual(
            repeatedRow,
            [.text("shared"), .text("shared"), .text("text")],
            SQLiteValueConformanceCaseID.repeatedNamedBinding.rawValue
        )
        XCTAssertEqual(
            repeatedRow[0],
            .text("shared"),
            SQLiteValueConformanceCaseID.namedBinding.rawValue
        )

        let nullRow = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(repeated)
            statement = try connection.bind(
                .null,
                to: .named("value"),
                in: statement
            )
            return try XCTUnwrap(connection.fetchOne(statement))
        }
        XCTAssertEqual(
            nullRow,
            [.null, .null, .text("null")],
            SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue
        )
        let missingRow = try driver.withBlockingReadConnection { connection in
            try connection.fetchOne(connection.prepare(noRow))
        }
        XCTAssertNil(
            missingRow,
            SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue
        )
    }

    func testSharedMalformedValueCasesReturnStructuredErrorsAfterRealSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let overflow = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value"
        )
        let overflowRow = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(overflow)
            statement = try connection.bind(
                .real(Double(Int64.max)),
                to: .named("value"),
                in: statement
            )
            return try XCTUnwrap(connection.fetchOne(statement))
        }
        XCTAssertThrowsError(
            try XLSQLiteValueReader(values: overflowRow).readInteger(at: 0),
            SQLiteValueConformanceCaseID.integerOverflow.rawValue
        ) { error in
            XCTAssertEqual(
                error as? XLColumnReadError,
                XLColumnReadError(
                    index: 0,
                    expectedType: "Int",
                    failure: .typeMismatch(actualType: "REAL")
                )
            )
        }

        let invalidUTF8 = try XCTUnwrap(
            SQLiteValueConformanceFixtures.storageCases.first {
                $0.id == .invalidUTF8Blob
            }
        )
        let invalidUTF8Row = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(overflow)
            statement = try connection.bind(
                invalidUTF8.value,
                to: .named("value"),
                in: statement
            )
            return try XCTUnwrap(connection.fetchOne(statement))
        }
        XCTAssertThrowsError(
            try XLSQLiteValueReader(values: invalidUTF8Row).readText(at: 0),
            invalidUTF8.id.rawValue
        ) { error in
            XCTAssertEqual(
                error as? XLColumnReadError,
                XLColumnReadError(
                    index: 0,
                    expectedType: "String",
                    failure: .typeMismatch(actualType: "BLOB")
                )
            )
        }

        let values = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT 0 AS position, 7 AS value
                UNION ALL
                SELECT 1 AS position, 'invalid' AS value
                ORDER BY position
                """
        )
        let rows = try driver.withBlockingReadConnection { connection in
            try connection.fetchAll(connection.prepare(values))
        }
        XCTAssertEqual(
            try XLSQLiteValueReader(values: rows[0]).readInteger(at: 1),
            7,
            SQLiteValueConformanceCaseID.decodeAfterValidRow.rawValue
        )
        XCTAssertThrowsError(
            try XLSQLiteValueReader(values: rows[1]).readInteger(at: 1),
            SQLiteValueConformanceCaseID.decodeAfterValidRow.rawValue
        ) { error in
            XCTAssertEqual(
                error as? XLColumnReadError,
                XLColumnReadError(
                    index: 1,
                    expectedType: "Int",
                    failure: .typeMismatch(actualType: "TEXT")
                )
            )
        }
    }

    func testAllSQLiteStorageClassesRoundTripThroughOneLogicalStatement() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let values: [(String, XLSQLiteValue)] = [
            ("nullValue", .null),
            ("integerValue", .integer(Int64.max - 17)),
            ("realValue", .real(42.125)),
            ("textValue", .text("SwiftQL — 你好 🌍")),
            ("blobValue", .blob(Data([0x00, 0x01, 0x7f, 0x80, 0xff]))),
        ]
        let logicalStatement = makeLogicalStatement(
            for: driver,
            sql: """
                SELECT
                    :nullValue,
                    :integerValue,
                    :realValue,
                    :textValue,
                    :blobValue
                """
        )

        let result = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(logicalStatement)
            for (name, value) in values {
                statement = try connection.bind(
                    value,
                    to: .named(name),
                    in: statement
                )
            }
            return try XCTUnwrap(connection.fetchOne(statement))
        }

        XCTAssertEqual(result, values.map { $0.1 })
        XCTAssertEqual(
            result.map(\.storageType),
            [.null, .integer, .real, .text, .blob]
        )
    }

    func testRealBindingRejectsNaNBeforeSQLiteCanNormalizeItToNull() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value"
        )

        try driver.withBlockingReadConnection { connection in
            let statement = try connection.prepare(logicalStatement)
            XCTAssertThrowsError(
                try connection.bind(
                    .real(.nan),
                    to: .named("value"),
                    in: statement
                )
            ) { error in
                XCTAssertEqual(
                    error as? XLSQLValueEncodingError,
                    .realBindingWouldBecomeNull(
                        value: .notANumber,
                        valueType: String(reflecting: Double.self),
                        context: XLValueCodingContext(
                            site: .parameter,
                            path: XLValueCodingPath("value")
                        )
                    )
                )
            }
        }
    }

    func testSQLiteRealBindingsPreserveInfinitiesAndFiniteEdges() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value, typeof(:value)"
        )
        let values = [
            Double.infinity,
            -Double.infinity,
            Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude,
            Double.leastNonzeroMagnitude,
            -Double.leastNonzeroMagnitude,
            -0.0,
        ]

        for value in values {
            let row = try driver.withBlockingReadConnection { connection in
                var statement = try connection.prepare(logicalStatement)
                statement = try connection.bind(
                    .real(value),
                    to: .named("value"),
                    in: statement
                )
                return try XCTUnwrap(connection.fetchOne(statement))
            }
            guard case .real(let actual) = row[0] else {
                return XCTFail("Expected REAL for \(value), received \(row[0]).")
            }
            XCTAssertEqual(actual, value)
            XCTAssertEqual(row[1], .text("real"))
        }
    }

    func testConnectionRejectsMismatchesBeforePhysicalPreparation() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let actualDatabaseIdentifier = driver.databaseIdentifier
        let driverIdentifier = driver.driverIdentifier
        let invalidSQL = "THIS IS NOT VALID SQL"
        let wrongDatabaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
        let databaseMismatch = XLLogicalPreparedStatement(
            databaseIdentifier: wrongDatabaseIdentifier,
            dialectRequirement: sqliteRequirement,
            sql: invalidSQL
        )

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                _ = try connection.prepare(databaseMismatch)
            }
        ) { error in
            XCTAssertEqual(
                error as? XLDatabaseContractError,
                .driverMismatch(
                    expectedDatabase: wrongDatabaseIdentifier,
                    actualDatabase: actualDatabaseIdentifier,
                    driver: driverIdentifier
                )
            )
        }

        let otherDialect = XLDialectIdentifier(rawValue: "test.other-dialect")
        let dialectMismatch = XLLogicalPreparedStatement(
            databaseIdentifier: actualDatabaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: otherDialect),
            sql: invalidSQL
        )

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                _ = try connection.prepare(dialectMismatch)
            }
        ) { error in
            XCTAssertEqual(
                error as? XLDatabaseContractError,
                .dialectMismatch(
                    expected: otherDialect,
                    actual: XLSQLiteDialect.identity
                )
            )
        }

        let validIdentity = makeLogicalStatement(for: driver, sql: invalidSQL)
        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                _ = try connection.prepare(validIdentity)
            }
        ) { error in
            // Issue #679: the driver reports a real preparation failure as the
            // portable error, keeping GRDB's error as the underlying one.
            guard let error = error as? XLDatabaseError else {
                return XCTFail("Expected an XLDatabaseError, received \(error).")
            }
            XCTAssertEqual(error.code, .other)
            XCTAssertEqual(error.nativeCode, 1)
            XCTAssertEqual(error.driver, driverIdentifier)
            XCTAssertEqual(error.sql, invalidSQL)
            XCTAssertTrue(error.underlying is DatabaseError)
        }

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                _ = try connection.prepareValidated(validIdentity)
            }
        ) { error in
            // An XLDatabaseError is already structured, so the validated
            // helper passes it through rather than flattening it to text.
            guard let error = error as? XLDatabaseError else {
                return XCTFail("Expected an XLDatabaseError, received \(error).")
            }
            XCTAssertEqual(error.code, .other)
            XCTAssertEqual(error.driver, driverIdentifier)
        }
    }

    func testPhysicalStatementCannotCrossConnectionScopes() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(for: driver, sql: "SELECT 1")
        let physicalStatement = try driver.withBlockingReadConnection { connection in
            try connection.prepare(logicalStatement)
        }

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                _ = try connection.fetchOne(physicalStatement)
            }
        ) { error in
            guard case let .prepareFailure(actualDriver, message)? = error as? XLDatabaseContractError else {
                return XCTFail("Expected physical-statement ownership failure, received \(error).")
            }
            XCTAssertEqual(actualDriver, driver.driverIdentifier)
            XCTAssertTrue(message.contains("owning connection"))
        }
    }

    func testLegacyDatabaseExposesSQLiteDialectAndExecutesThroughDriverContract() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            formatter: XLiteFormatter(),
            logger: nil
        )

        XCTAssertEqual(database.dialect.descriptor.identity, XLSQLiteDialect.identity)
        XCTAssertTrue(
            database.dialect.descriptor.capabilities.contains([
                .namedBindings,
                .indexedBindings,
            ])
        )
        XCTAssertEqual(database.driverIdentifier.rawValue, "grdb")

        try database.makeRequest(
            with: sqlCreate(GRDBDriverContractRecord.self)
        ).execute()
        let expected = GRDBDriverContractRecord(id: "contract", value: 42)
        try database.makeRequest(with: sqlInsert(expected)).execute()

        let query = sql { schema in
            let record = schema.table(GRDBDriverContractRecord.self)
            Select(record)
            From(record)
        }
        XCTAssertEqual(
            try database.makeRequest(with: query).fetchOne(),
            expected
        )
    }

    func testDriverTransactionCommitsAndRollsBackOnOneConnectionScope() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: """
                CREATE TABLE contract_transaction (
                    id TEXT PRIMARY KEY,
                    value INTEGER NOT NULL
                )
                """
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: "INSERT INTO contract_transaction (id, value) VALUES (:id, :value)"
        )
        let count = makeLogicalStatement(
            for: driver,
            sql: "SELECT COUNT(*) FROM contract_transaction"
        )

        try driver.withBlockingWriteConnection { connection in
            let createStatement = try connection.prepare(create)
            try connection.execute(createStatement)
        }

        let committedCount = try driver.withBlockingTransaction { connection -> XLSQLiteValue in
            var insertStatement = try connection.prepare(insert)
            insertStatement = try connection.bind(
                .text("committed"),
                to: .named("id"),
                in: insertStatement
            )
            insertStatement = try connection.bind(
                .integer(1),
                to: .named("value"),
                in: insertStatement
            )
            try connection.execute(insertStatement)

            let countStatement = try connection.prepare(count)
            let row = try XCTUnwrap(connection.fetchOne(countStatement))
            return try XCTUnwrap(row.first)
        }
        XCTAssertEqual(committedCount, .integer(1))

        var countSeenBeforeRollback: XLSQLiteValue?
        XCTAssertThrowsError(
            try driver.withBlockingTransaction { connection in
                var insertStatement = try connection.prepare(insert)
                insertStatement = try connection.bind(
                    .text("rolled-back"),
                    to: .named("id"),
                    in: insertStatement
                )
                insertStatement = try connection.bind(
                    .integer(2),
                    to: .named("value"),
                    in: insertStatement
                )
                try connection.execute(insertStatement)

                let countStatement = try connection.prepare(count)
                let row = try XCTUnwrap(connection.fetchOne(countStatement))
                countSeenBeforeRollback = row.first
                throw TransactionAbort.requested
            }
        ) { error in
            XCTAssertEqual(error as? TransactionAbort, .requested)
        }
        XCTAssertEqual(countSeenBeforeRollback, .integer(2))

        let countAfterRollback = try driver.withBlockingReadConnection { connection in
            let countStatement = try connection.prepare(count)
            return try XCTUnwrap(connection.fetchOne(countStatement)?.first)
        }
        XCTAssertEqual(countAfterRollback, .integer(1))
    }

    /// Issue #679: a scope maps what GRDB throws around the operation, but the
    /// operation's own error is the caller's and is rethrown as it was thrown,
    /// even when it is a GRDB `DatabaseError`.
    func testOperationsOwnDatabaseErrorPassesThroughEveryScopeUnchanged() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let selectOne = makeLogicalStatement(for: driver, sql: "SELECT 1")
        @Sendable func ownError() -> DatabaseError {
            DatabaseError(resultCode: .SQLITE_CONSTRAINT, message: "thrown by the operation")
        }
        func assertUnchanged(_ scope: String, _ error: any Error) {
            XCTAssertFalse(error is XLDatabaseError, "\(scope) mapped the operation's error.")
            let error = error as? DatabaseError
            XCTAssertEqual(error?.resultCode, .SQLITE_CONSTRAINT, scope)
            XCTAssertEqual(error?.message, "thrown by the operation", scope)
        }

        let blockingScopes: [(String, () throws -> Void)] = [
            ("withBlockingReadConnection", { try driver.withBlockingReadConnection { _ in throw ownError() } }),
            ("withBlockingWriteConnection", { try driver.withBlockingWriteConnection { _ in throw ownError() } }),
            ("withBlockingTransaction", { try driver.withBlockingTransaction { _ in throw ownError() } }),
            ("GRDBDatabase.withTransaction", { try database.withTransaction { _ in throw ownError() } }),
            ("forEachRow callback", {
                try driver.withBlockingReadConnection { connection in
                    let statement = try connection.prepare(selectOne)
                    try connection.forEachRow(statement) { _ in throw ownError() }
                }
            }),
        ]
        for (scope, run) in blockingScopes {
            XCTAssertThrowsError(try run()) { error in
                assertUnchanged(scope, error)
            }
        }

        do {
            try await driver.withReadConnection { _ in throw ownError() }
            XCTFail("withReadConnection returned.")
        }
        catch {
            assertUnchanged("withReadConnection", error)
        }
        do {
            try await driver.withWriteConnection { _ in throw ownError() }
            XCTFail("withWriteConnection returned.")
        }
        catch {
            assertUnchanged("withWriteConnection", error)
        }
        do {
            try await driver.withTransaction(.deferred) { _ in throw ownError() }
            XCTFail("withTransaction returned.")
        }
        catch {
            assertUnchanged("withTransaction", error)
        }
    }

    /// Issue #679: an interruption and a rolled-back transaction are
    /// different portable codes, since `SQLITE_ABORT` also follows a
    /// conflict clause that rolled the transaction back.
    func testInterruptAndAbortHaveTheirOwnPortableCodes() {
        let interrupt = XLDatabaseError(DatabaseError(resultCode: .SQLITE_INTERRUPT), driver: .grdb)
        XCTAssertEqual(interrupt.code, .interrupted)
        for resultCode in [ResultCode.SQLITE_ABORT, .SQLITE_ABORT_ROLLBACK] {
            let error = XLDatabaseError(DatabaseError(resultCode: resultCode), driver: .grdb)
            XCTAssertEqual(error.code, .aborted, "\(resultCode)")
            XCTAssertEqual(error.nativeCode, resultCode.rawValue)
        }
    }

    /// Issue #679: reporting the inserted row id must not change what SQL
    /// inside the statement sees from `last_insert_rowid()`.
    func testExecuteLeavesLastInsertRowIDVisibleToTheStatement() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let statements = [
            "CREATE TABLE rowid_parent (id INTEGER PRIMARY KEY)",
            "CREATE TABLE rowid_child (id INTEGER PRIMARY KEY, parent INTEGER)",
            "INSERT INTO rowid_parent (id) VALUES (7)",
            "INSERT INTO rowid_child (parent) VALUES (last_insert_rowid())",
            "UPDATE rowid_child SET parent = parent + 1 WHERE rowid = last_insert_rowid()",
        ].map { makeLogicalStatement(for: driver, sql: $0) }
        let selectParent = makeLogicalStatement(for: driver, sql: "SELECT parent FROM rowid_child")

        let (results, parent) = try driver.withBlockingWriteConnection { connection in
            let results = try statements.map { try connection.execute(connection.prepare($0)) }
            let parent = try connection.fetchOne(connection.prepare(selectParent))?.first
            return (results, parent)
        }

        XCTAssertEqual(parent, .integer(8), "The child read the parent's row id, and the update found the child.")
        XCTAssertEqual(results.map(\.lastInsertedRowID), [nil, nil, 7, 1, nil])
        XCTAssertEqual(results.map(\.rowsAffected), [0, 0, 1, 1, 1])
    }

    /// Issue #679: a `COMMIT` that fails is GRDB's failure, not the
    /// operation's, so the scope reports it as the portable error.
    func testFailingCommitIsReportedAsAPortableError() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let createParent = makeLogicalStatement(
            for: driver,
            sql: "CREATE TABLE commit_parent (id INTEGER PRIMARY KEY)"
        )
        let createChild = makeLogicalStatement(
            for: driver,
            sql: """
                CREATE TABLE commit_child (
                    parent INTEGER REFERENCES commit_parent (id)
                        DEFERRABLE INITIALLY DEFERRED
                )
                """
        )
        let insertOrphan = makeLogicalStatement(
            for: driver,
            sql: "INSERT INTO commit_child (parent) VALUES (1)"
        )
        try driver.withBlockingWriteConnection { connection in
            _ = try connection.execute(connection.prepare(createParent))
            _ = try connection.execute(connection.prepare(createChild))
        }

        XCTAssertThrowsError(
            try driver.withBlockingTransaction { connection in
                // The deferred foreign key is checked only at COMMIT, so the
                // operation itself succeeds.
                _ = try connection.execute(connection.prepare(insertOrphan))
            }
        ) { error in
            guard let error = error as? XLDatabaseError else {
                return XCTFail("Expected an XLDatabaseError, received \(error).")
            }
            XCTAssertEqual(error.code, .constraint)
            XCTAssertEqual(error.driver, driver.driverIdentifier)
        }
    }

    private var sqliteRequirement: XLDialectRequirement {
        XLDialectRequirement(
            identity: XLSQLiteDialect.identity,
            capabilities: [.namedBindings]
        )
    }

    func testReusedNormalizationBufferDoesNotAliasRetainedRows() throws {
        // The cursor loop reuses one normalization buffer across rows. A consumer
        // that retains each streamed row (via the callback, or via the eager
        // `fetchAll`/`collectAllRows` shim) must still see distinct, correct
        // values for every row — copy-on-write gives the retained row its own
        // storage when the buffer is refilled for the next row.
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.pool,
            dialect: XLSQLiteDialect()
        )
        let create = makeLogicalStatement(
            for: driver,
            sql: "CREATE TABLE buffer_rows (id INTEGER PRIMARY KEY, label TEXT)"
        )
        let insert = makeLogicalStatement(
            for: driver,
            sql: """
                INSERT INTO buffer_rows (id, label) VALUES
                (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e'), (6, 'f')
                """
        )
        let select = makeLogicalStatement(
            for: driver,
            sql: "SELECT id, label FROM buffer_rows ORDER BY id"
        )
        try driver.withBlockingWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }

        let expected: [[XLSQLiteValue]] = (1 ... 6).map { index in
            [.integer(Int64(index)), .text(String(UnicodeScalar(UInt8(96 + index))))]
        }

        var retainedByCallback: [[XLSQLiteValue]] = []
        var eagerlyCollected: [[XLSQLiteValue]] = []
        try driver.withBlockingReadConnection { connection in
            let statement = try connection.prepare(select)
            try connection.forEachRow(statement) { row in
                retainedByCallback.append(row)
                return .advance
            }
            eagerlyCollected = try connection.fetchAll(statement)
        }

        XCTAssertEqual(retainedByCallback, expected)
        XCTAssertEqual(eagerlyCollected, expected)
    }

    private func makeLogicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: sqliteRequirement,
            sql: sql
        )
    }

    private func makeFixture(
        configuration: Configuration = Configuration()
    ) throws -> TemporaryDatabaseFixture {
        try TemporaryDatabaseFixture.make(
            named: "grdb-driver-contract",
            configuration: configuration
        )
    }
}


private final class GRDBStreamStepProbe: @unchecked Sendable {

    static let functionName = "swiftql_stream_step_probe"

    private let lock = NSLock()

    private var invocationCountValue = 0

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCountValue
    }

    func observe(_ value: DatabaseValue) -> Int64? {
        lock.lock()
        invocationCountValue += 1
        lock.unlock()
        return Int64.fromDatabaseValue(value)
    }
}
