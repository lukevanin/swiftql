import Foundation
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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
                    try driver.withReadConnection { connection in
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
                let row = try driver.withReadConnection { connection in
                    var statement = try connection.prepare(logicalStatement)
                    statement = try connection.bind(
                        testCase.value,
                        to: .named("value"),
                        in: statement
                    )
                    return try XCTUnwrap(connection.fetchOne(statement))
                }
                let streamedRows = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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
        let row = try driver.withReadConnection { connection in
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
        let streamedRows = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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
        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }

        var earlyRows: [[XLSQLiteValue]] = []
        var replayAfterStop: [[XLSQLiteValue]] = []
        var invocationCountAtStop = 0
        try driver.withReadConnection { connection in
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
            try driver.withReadConnection { connection in
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
        let first = try driver.withReadConnection { connection in
            try connection.fetchOne(connection.prepare(select))
        }
        XCTAssertEqual(first?.first, .integer(1))
        XCTAssertEqual(probe.invocationCount - countBeforeFirst, 1)

        let countBeforeAll = probe.invocationCount
        let all = try driver.withReadConnection { connection in
            try connection.fetchAll(connection.prepare(select))
        }
        XCTAssertEqual(
            all.map(\.first),
            (1 ... 5).map { .integer(Int64($0)) }
        )
        XCTAssertEqual(probe.invocationCount - countBeforeAll, 5)

        let countBeforeEmpty = probe.invocationCount
        let noRows = try driver.withReadConnection { connection in
            try connection.fetchAll(connection.prepare(empty))
        }
        XCTAssertTrue(noRows.isEmpty)
        XCTAssertEqual(probe.invocationCount, countBeforeEmpty)
    }

    func testSharedSQLiteAffinityCasesAssertValueTypeAndState() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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

        try driver.withWriteConnection { connection in
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

        let row = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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

        let repeatedRow = try driver.withReadConnection { connection in
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

        let nullRow = try driver.withReadConnection { connection in
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
        let missingRow = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
            dialect: XLSQLiteDialect()
        )
        let overflow = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value"
        )
        let overflowRow = try driver.withReadConnection { connection in
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
        let invalidUTF8Row = try driver.withReadConnection { connection in
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
        let rows = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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

        let result = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(
            for: driver,
            sql: "SELECT :value"
        )

        try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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
            let row = try driver.withReadConnection { connection in
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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
            try driver.withReadConnection { connection in
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
            try driver.withReadConnection { connection in
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
            try driver.withReadConnection { connection in
                _ = try connection.prepare(validIdentity)
            }
        ) { error in
            XCTAssertTrue(
                error is DatabaseError,
                "A real GRDB preparation failure must retain its original error type."
            )
        }

        XCTAssertThrowsError(
            try driver.withReadConnection { connection in
                _ = try connection.prepareValidated(validIdentity)
            }
        ) { error in
            guard case let .prepareFailure(actualDriver, message)? = error as? XLDatabaseContractError else {
                return XCTFail("Expected a structured prepare failure, received \(error).")
            }
            XCTAssertEqual(actualDriver, driverIdentifier)
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testPhysicalStatementCannotCrossConnectionScopes() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
            dialect: XLSQLiteDialect()
        )
        let logicalStatement = makeLogicalStatement(for: driver, sql: "SELECT 1")
        let physicalStatement = try driver.withReadConnection { connection in
            try connection.prepare(logicalStatement)
        }

        XCTAssertThrowsError(
            try driver.withReadConnection { connection in
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
            databasePool: fixture.databasePool,
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

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
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

        try driver.withWriteConnection { connection in
            let createStatement = try connection.prepare(create)
            try connection.execute(createStatement)
        }

        let committedCount = try driver.withTransaction { connection -> XLSQLiteValue in
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
            try driver.withTransaction { connection in
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

        let countAfterRollback = try driver.withReadConnection { connection in
            let countStatement = try connection.prepare(count)
            return try XCTUnwrap(connection.fetchOne(countStatement)?.first)
        }
        XCTAssertEqual(countAfterRollback, .integer(1))
    }

    private var sqliteRequirement: XLDialectRequirement {
        XLDialectRequirement(
            identity: XLSQLiteDialect.identity,
            capabilities: [.namedBindings]
        )
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
    ) throws -> Fixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-grdb-driver-contract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let databasePool = try DatabasePool(
            path: directoryURL.appendingPathComponent("database.sqlite").path,
            configuration: configuration
        )
        return Fixture(
            directoryURL: directoryURL,
            databasePool: databasePool
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


private struct Fixture {
    let directoryURL: URL
    let databasePool: DatabasePool

    func tearDown() {
        try? databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
