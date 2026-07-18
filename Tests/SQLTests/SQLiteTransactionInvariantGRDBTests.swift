import Foundation
import GRDB
import XCTest

@testable import SwiftQL
import SwiftQLSQLiteConformanceFixtures


final class GRDBDriverContractTests_TransactionInvariants: XCTestCase {

    private enum RollbackSignal: Error, Equatable {
        case explicit
        case bodyFailure
        case earlyExit
    }

    func testSharedCommitCasesVerifyDurableStateReturnValuesAndVisibility() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = makeDriver(fixture.databasePool)
        try createSchema(using: &driver)

        var before = try snapshot(using: &driver)
        let empty = try transactionCase(.emptyCommit)
        let emptyResult = try driver.withValidatedTransaction { _ in
            empty.id.rawValue
        }
        XCTAssertEqual(emptyResult, empty.id.rawValue)
        var after = try snapshot(using: &driver)
        try empty.validate(before: before, after: after)

        before = after
        let multiple = try transactionCase(.multipleStatementCommit)
        let multipleInsert = insertStatement(for: driver)
        let select = selectStatement(for: driver)
        let insideCount = try driver.withValidatedTransaction { connection in
            for rowID in multiple.insertedRowIDs {
                try insert(
                    id: rowID,
                    value: SQLiteTransactionStateRow.conformanceValue,
                    statement: multipleInsert,
                    connection: &connection
                )
            }
            return try connection.fetchAll(connection.prepare(select)).count
        }
        XCTAssertEqual(insideCount, 2, multiple.id.rawValue)
        after = try snapshot(using: &driver)
        try multiple.validate(before: before, after: after)

        before = after
        let returnValue = try transactionCase(.returnValue)
        let returnInsert = insertStatement(for: driver)
        let returned = try driver.withValidatedTransaction { connection in
            try insert(
                id: try XCTUnwrap(returnValue.insertedRowIDs.first),
                value: SQLiteTransactionStateRow.conformanceValue,
                statement: returnInsert,
                connection: &connection
            )
            return (returnValue.id, 253)
        }
        XCTAssertEqual(returned.0, .returnValue)
        XCTAssertEqual(returned.1, 253)
        after = try snapshot(using: &driver)
        try returnValue.validate(before: before, after: after)

        before = after
        let pinning = try transactionCase(.connectionPinning)
        let pinningInsert = insertStatement(for: driver)
        let pinningSelect = selectStatement(for: driver)
        let pinnedRows = try driver.withValidatedTransaction { connection in
            try insert(
                id: try XCTUnwrap(pinning.insertedRowIDs.first),
                value: SQLiteTransactionStateRow.conformanceValue,
                statement: pinningInsert,
                connection: &connection
            )
            return try connection.fetchAll(connection.prepare(pinningSelect))
        }
        XCTAssertTrue(
            pinnedRows.contains { $0.first == .text(pinning.id.rawValue) },
            pinning.id.rawValue
        )
        after = try snapshot(using: &driver)
        try pinning.validate(before: before, after: after)

        before = after
        let pinnedVisibility = try transactionCase(.pinnedConnectionVisibility)
        let visibilityInsert = insertStatement(for: driver)
        let visibilitySelect = selectStatement(for: driver)
        let visibleInside = try driver.withValidatedTransaction { connection in
            let rowID = try XCTUnwrap(pinnedVisibility.insertedRowIDs.first)
            try insert(
                id: rowID,
                value: SQLiteTransactionStateRow.conformanceValue,
                statement: visibilityInsert,
                connection: &connection
            )
            let rows = try connection.fetchAll(connection.prepare(visibilitySelect))
            return rows.contains { $0.first == .text(rowID) }
        }
        XCTAssertTrue(visibleInside, pinnedVisibility.id.rawValue)
        after = try snapshot(using: &driver)
        try pinnedVisibility.validate(before: before, after: after)

        before = after
        let poolVisibility = try transactionCase(.pooledCommitVisibility)
        let poolInsert = insertStatement(for: driver)
        try driver.withValidatedTransaction { connection in
            try insert(
                id: try XCTUnwrap(poolVisibility.insertedRowIDs.first),
                value: SQLiteTransactionStateRow.conformanceValue,
                statement: poolInsert,
                connection: &connection
            )
        }
        after = try snapshot(using: &driver)
        try poolVisibility.validate(before: before, after: after)
    }

    func testSharedRollbackCasesPreserveCauseStateAndConnectionReuse() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = makeDriver(fixture.databasePool)
        try createSchema(using: &driver)
        try commitSeed(using: &driver)

        try assertRollback(
            .explicitRollback,
            driver: &driver,
            operation: { _ in throw RollbackSignal.explicit },
            errorAssertion: { error in
                XCTAssertEqual(error as? RollbackSignal, .explicit)
            }
        )

        try assertRollback(
            .bodyErrorRollback,
            driver: &driver,
            operation: { _ in throw RollbackSignal.bodyFailure },
            errorAssertion: { error in
                XCTAssertEqual(error as? RollbackSignal, .bodyFailure)
            }
        )

        let duplicateSeed = insertStatement(for: driver)
        try assertRollback(
            .constraintFailureRollback,
            driver: &driver,
            operation: { connection in
                try self.insert(
                    id: "seed",
                    value: 999,
                    statement: duplicateSeed,
                    connection: &connection
                )
            },
            errorAssertion: { error in
                XCTAssertEqual(
                    (error as? DatabaseError)?.resultCode,
                    .SQLITE_CONSTRAINT
                )
            }
        )

        let bindFailure = logicalStatement(for: driver, sql: "SELECT :value")
        try assertRollback(
            .bindFailureRollback,
            driver: &driver,
            operation: { connection in
                let statement = try connection.prepare(bindFailure)
                _ = try connection.bind(
                    .real(.nan),
                    to: .named("value"),
                    in: statement
                )
            },
            errorAssertion: { error in
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
        )

        let invalidValue = logicalStatement(
            for: driver,
            sql: "SELECT 'not-an-integer'"
        )
        try assertRollback(
            .decodeFailureRollback,
            driver: &driver,
            operation: { connection in
                let row = try XCTUnwrap(
                    connection.fetchOne(connection.prepare(invalidValue))
                )
                _ = try XLSQLiteValueReader(values: row).readInteger(at: 0)
            },
            errorAssertion: { error in
                XCTAssertEqual(
                    error as? XLColumnReadError,
                    XLColumnReadError(
                        index: 0,
                        expectedType: "Int",
                        failure: .typeMismatch(actualType: "TEXT")
                    )
                )
            }
        )

        let invalidSQL = logicalStatement(
            for: driver,
            sql: "INSERT definitely not valid SQL"
        )
        try assertRollback(
            .driverFailureRollback,
            driver: &driver,
            operation: { connection in
                _ = try connection.prepare(invalidSQL)
            },
            errorAssertion: { error in
                XCTAssertEqual(
                    (error as? DatabaseError)?.resultCode,
                    .SQLITE_ERROR
                )
            }
        )

        try assertRollback(
            .earlyExitRollback,
            driver: &driver,
            operation: { _ in throw RollbackSignal.earlyExit },
            errorAssertion: { error in
                XCTAssertEqual(error as? RollbackSignal, .earlyExit)
            }
        )

        try assertRollback(
            .pooledRollbackVisibility,
            driver: &driver,
            operation: { _ in throw RollbackSignal.explicit },
            errorAssertion: { error in
                XCTAssertEqual(error as? RollbackSignal, .explicit)
            }
        )

        let reuse = try transactionCase(.postFailureReuse)
        let beforeReuse = try snapshot(using: &driver)
        let reuseInsert = insertStatement(for: driver)
        try driver.withValidatedTransaction { connection in
            try insert(
                id: try XCTUnwrap(reuse.insertedRowIDs.first),
                value: SQLiteTransactionStateRow.conformanceValue,
                statement: reuseInsert,
                connection: &connection
            )
        }
        try reuse.validate(
            before: beforeReuse,
            after: try snapshot(using: &driver)
        )
    }

    func testUnsupportedCapabilitiesFailBeforePoolReentryAndLeaveStateUnchanged() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var driver = makeDriver(fixture.databasePool)
        try createSchema(using: &driver)
        try commitSeed(using: &driver)
        let before = try snapshot(using: &driver)
        let nested = try transactionCase(.nestedTransactionCapability)
        let disposition = try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.capabilities[
                .nestedTransactionOrSavepoint
            ]
        )

        XCTAssertThrowsError(
            try SQLiteTransactionConformanceFixtures.require(
                .nestedTransactionOrSavepoint
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTransactionCapabilityError,
                .unsupported(
                    capability: .nestedTransactionOrSavepoint,
                    blockingIssue: 113,
                    reason: disposition.reason
                ),
                nested.id.rawValue
            )
        }
        try nested.validate(
            before: before,
            after: try snapshot(using: &driver)
        )

        let single = try transactionCase(.singleConnectionVisibilityCapability)
        let singleDisposition = try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.capabilities[
                .singleConnectionDriver
            ]
        )
        XCTAssertThrowsError(
            try SQLiteTransactionConformanceFixtures.require(
                .singleConnectionDriver
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTransactionCapabilityError,
                .unsupported(
                    capability: .singleConnectionDriver,
                    blockingIssue: 113,
                    reason: singleDisposition.reason
                ),
                single.id.rawValue
            )
        }
        try single.validate(
            before: before,
            after: try snapshot(using: &driver)
        )
    }

    func testIndependentDatabasesCommitWithoutCrossContamination() async throws {
        let firstFixture = try makeFixture()
        let secondFixture = try makeFixture()
        defer {
            firstFixture.tearDown()
            secondFixture.tearDown()
        }

        let caseFixture = try transactionCase(.independentDatabases)
        let firstID = "\(caseFixture.id.rawValue).first"
        let secondID = "\(caseFixture.id.rawValue).second"
        let pools = [firstFixture.databasePool, secondFixture.databasePool]
        let rowIDs = [firstID, secondID]

        let results = try await withThrowingTaskGroup(
            of: (Int, SQLiteTransactionStateSnapshot).self
        ) { group in
            for index in pools.indices {
                let pool = pools[index]
                let rowID = rowIDs[index]
                group.addTask {
                    (
                        index,
                        try Self.commitIndependentRow(
                            rowID,
                            databasePool: pool
                        )
                    )
                }
            }

            var snapshots: [Int: SQLiteTransactionStateSnapshot] = [:]
            for try await (index, snapshot) in group {
                snapshots[index] = snapshot
            }
            return snapshots
        }

        let empty = SQLiteTransactionStateSnapshot(rowIDs: [])
        try SQLiteTransactionConformanceCase(
            id: caseFixture.id,
            expectation: caseFixture.expectation,
            insertedRowIDs: [firstID]
        ).validate(
            before: empty,
            after: try XCTUnwrap(results[0])
        )
        try SQLiteTransactionConformanceCase(
            id: caseFixture.id,
            expectation: caseFixture.expectation,
            insertedRowIDs: [secondID]
        ).validate(
            before: empty,
            after: try XCTUnwrap(results[1])
        )
    }

    private func assertRollback(
        _ id: SQLiteTransactionConformanceCaseID,
        driver: inout GRDBDatabaseDriver,
        operation: (inout GRDBDatabaseDriverConnection) throws -> Void,
        errorAssertion: (Error) -> Void
    ) throws {
        let testCase = try transactionCase(id)
        let before = try snapshot(using: &driver)
        let statement = insertStatement(for: driver)

        XCTAssertThrowsError(
            try driver.withValidatedTransaction { connection in
                try insert(
                    id: try XCTUnwrap(testCase.insertedRowIDs.first),
                    value: SQLiteTransactionStateRow.conformanceValue,
                    statement: statement,
                    connection: &connection
                )
                try operation(&connection)
            },
            id.rawValue
        ) { error in
            errorAssertion(error)
        }

        try testCase.validate(
            before: before,
            after: try snapshot(using: &driver)
        )
    }

    private func createSchema(using driver: inout GRDBDatabaseDriver) throws {
        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE transaction_contract (
                    id TEXT PRIMARY KEY,
                    value INTEGER NOT NULL
                )
                """
        )
        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
        }
    }

    private func commitSeed(using driver: inout GRDBDatabaseDriver) throws {
        let statement = insertStatement(for: driver)
        try driver.withValidatedTransaction { connection in
            try insert(
                id: "seed",
                value: 0,
                statement: statement,
                connection: &connection
            )
        }
    }

    private func insert(
        id: String,
        value: Int64,
        statement: XLLogicalPreparedStatement,
        connection: inout GRDBDatabaseDriverConnection
    ) throws {
        var physical = try connection.prepare(statement)
        physical = try connection.bind(.text(id), to: .named("id"), in: physical)
        physical = try connection.bind(
            .integer(value),
            to: .named("value"),
            in: physical
        )
        try connection.execute(physical)
    }

    private func snapshot(
        using driver: inout GRDBDatabaseDriver
    ) throws -> SQLiteTransactionStateSnapshot {
        let select = selectStatement(for: driver)
        return try driver.withReadConnection { connection in
            let rows = try connection.fetchAll(connection.prepare(select))
            let stateRows = try rows.map { row in
                guard case .text(let rowID) = try XCTUnwrap(row.first) else {
                    throw XLColumnReadError(
                        index: 0,
                        expectedType: "String",
                        failure: .typeMismatch(actualType: "non-TEXT")
                    )
                }
                guard case .integer(let value) = try XCTUnwrap(row.last) else {
                    throw XLColumnReadError(
                        index: 1,
                        expectedType: "Int64",
                        failure: .typeMismatch(actualType: "non-INTEGER")
                    )
                }
                return SQLiteTransactionStateRow(id: rowID, value: value)
            }
            return SQLiteTransactionStateSnapshot(rows: stateRows)
        }
    }

    private func transactionCase(
        _ id: SQLiteTransactionConformanceCaseID
    ) throws -> SQLiteTransactionConformanceCase {
        try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.casesByID[id],
            id.rawValue
        )
    }

    private func insertStatement(
        for driver: GRDBDatabaseDriver
    ) -> XLLogicalPreparedStatement {
        logicalStatement(
            for: driver,
            sql: "INSERT INTO transaction_contract (id, value) VALUES (:id, :value)"
        )
    }

    private func selectStatement(
        for driver: GRDBDatabaseDriver
    ) -> XLLogicalPreparedStatement {
        logicalStatement(
            for: driver,
            sql: "SELECT id, value FROM transaction_contract ORDER BY id"
        )
    }

    private func logicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        Self.logicalStatement(for: driver, sql: sql)
    }

    private static func logicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(
                identity: XLSQLiteDialect.identity,
                capabilities: [.namedBindings]
            ),
            sql: sql
        )
    }

    private func makeDriver(_ databasePool: DatabasePool) -> GRDBDatabaseDriver {
        GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: XLSQLiteDialect()
        )
    }

    private func makeFixture() throws -> SQLiteTransactionFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "swiftql-transaction-contract-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return SQLiteTransactionFixture(
            directoryURL: directoryURL,
            databasePool: try DatabasePool(
                path: directoryURL.appendingPathComponent("database.sqlite").path
            )
        )
    }

    private static func commitIndependentRow(
        _ rowID: String,
        databasePool: DatabasePool
    ) throws -> SQLiteTransactionStateSnapshot {
        var driver = GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: XLSQLiteDialect()
        )
        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE transaction_contract (
                    id TEXT PRIMARY KEY,
                    value INTEGER NOT NULL
                )
                """
        )
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO transaction_contract (id, value) VALUES (:id, 253)"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT id, value FROM transaction_contract ORDER BY id"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
        }
        try driver.withValidatedTransaction { connection in
            var physical = try connection.prepare(insert)
            physical = try connection.bind(
                .text(rowID),
                to: .named("id"),
                in: physical
            )
            try connection.execute(physical)
        }
        return try driver.withReadConnection { connection in
            let rows = try connection.fetchAll(connection.prepare(select))
            return SQLiteTransactionStateSnapshot(
                rows: try rows.map { row in
                    guard case .text(let rowID) = try XCTUnwrap(row.first) else {
                        throw XLColumnReadError(
                            index: 0,
                            expectedType: "String",
                            failure: .typeMismatch(actualType: "non-TEXT")
                        )
                    }
                    guard case .integer(let value) = try XCTUnwrap(row.last) else {
                        throw XLColumnReadError(
                            index: 1,
                            expectedType: "Int64",
                            failure: .typeMismatch(actualType: "non-INTEGER")
                        )
                    }
                    return SQLiteTransactionStateRow(id: rowID, value: value)
                }
            )
        }
    }
}


private struct SQLiteTransactionFixture {
    let directoryURL: URL
    let databasePool: DatabasePool

    func tearDown() {
        try? databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
