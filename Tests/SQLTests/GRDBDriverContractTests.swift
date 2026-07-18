import Foundation
import GRDB
import XCTest
@testable import SwiftQL


@SQLTable(name: "GRDBDriverContractRecord")
struct GRDBDriverContractRecord: Equatable {
    let id: String
    let value: Int
}


final class GRDBDriverContractTests: XCTestCase {

    private enum TransactionAbort: Error, Equatable {
        case requested
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

    private func makeFixture() throws -> Fixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-grdb-driver-contract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let databasePool = try DatabasePool(
            path: directoryURL.appendingPathComponent("database.sqlite").path
        )
        return Fixture(
            directoryURL: directoryURL,
            databasePool: databasePool
        )
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
