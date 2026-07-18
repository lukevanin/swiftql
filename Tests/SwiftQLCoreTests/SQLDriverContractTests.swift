import Foundation
import XCTest

import SwiftQLCore
import SwiftQLSQLiteConformanceFixtures


final class SQLDriverContractTests: XCTestCase {

    private enum OperationAbort: Error, Equatable {
        case requested
    }

    func testFakeDriverUsesItsOwnTransportAroundDialectValues() throws {
        let recorder = DriverRecorder()
        let databaseIdentifier = databaseID(1)
        var connection = FakeConnection(
            connectionID: 7,
            databaseIdentifier: databaseIdentifier,
            recorder: recorder
        )
        let logical = logicalStatement(databaseIdentifier: databaseIdentifier)
        let token = LogicalToken(rawValue: "transport-independent 🧪")

        var physical = try connection.prepareValidated(logical)
        physical = try connection.bindValidated(
            token.encode(),
            to: .named("token"),
            in: physical
        )

        XCTAssertEqual(
            physical.wireBindings[.named("token")],
            .utf8(Array(token.rawValue.utf8))
        )
        let row = try XCTUnwrap(try connection.fetchOneValidated(physical))
        XCTAssertEqual(try LogicalToken.decode(row[0], column: 0), token)
        XCTAssertEqual(recorder.boundConnectionIDs, [7])
    }

    func testDriverNeutralRowStreamStopsWithoutVisitingLaterRowsAndRemainsReusable() throws {
        let recorder = DriverRecorder()
        let databaseIdentifier = databaseID(10)
        let rows: [[XLSQLiteValue]] = [
            [.integer(1), .text("first")],
            [.integer(2), .text("second")],
            [.integer(3), .text("third")],
        ]
        var connection = FakeConnection(
            connectionID: 8,
            databaseIdentifier: databaseIdentifier,
            recorder: recorder,
            resultRows: rows
        )
        let statement = try connection.prepareValidated(
            logicalStatement(databaseIdentifier: databaseIdentifier)
        )
        var visited: [[XLSQLiteValue]] = []

        try connection.forEachRow(statement) { row in
            visited.append(row)
            return visited.count == 2 ? .stop : .advance
        }

        XCTAssertEqual(visited, Array(rows.prefix(2)))
        XCTAssertEqual(recorder.streamedRows, Array(rows.prefix(2)))

        recorder.streamedRows.removeAll()
        XCTAssertThrowsError(
            try connection.forEachRow(statement) { row in
                if row == rows[1] {
                    throw OperationAbort.requested
                }
                return .advance
            }
        ) { error in
            XCTAssertEqual(error as? OperationAbort, .requested)
        }
        XCTAssertEqual(recorder.streamedRows, Array(rows.prefix(2)))

        recorder.streamedRows.removeAll()
        XCTAssertEqual(try connection.fetchOne(statement), rows[0])
        XCTAssertEqual(recorder.streamedRows, [rows[0]])

        recorder.streamedRows.removeAll()
        XCTAssertEqual(try connection.fetchAll(statement), rows)
        XCTAssertEqual(recorder.streamedRows, rows)
    }

    func testLogicalStatementCreatesConnectionOwnedPhysicalStatements() throws {
        let recorder = DriverRecorder()
        let databaseIdentifier = databaseID(2)
        var driver = FakePoolDriver(
            databaseIdentifier: databaseIdentifier,
            connectionIDs: [11, 22],
            recorder: recorder
        )
        let logical = logicalStatement(databaseIdentifier: databaseIdentifier)

        let first = try driver.withReadConnection { connection in
            try connection.prepareValidated(logical)
        }
        let second = try driver.withReadConnection { connection in
            try connection.prepareValidated(logical)
        }

        XCTAssertEqual(first.sql, logical.sql)
        XCTAssertEqual(second.sql, logical.sql)
        XCTAssertNotEqual(first.connectionID, second.connectionID)
        XCTAssertNotEqual(first.statementID, second.statementID)
        XCTAssertEqual(recorder.preparedConnectionIDs, [11, 22])

        var foreignConnection = FakeConnection(
            connectionID: second.connectionID,
            databaseIdentifier: databaseIdentifier,
            recorder: recorder
        )
        assertError(
            try foreignConnection.bindValidated(
                .integer(1),
                to: .indexed(0),
                in: first
            ),
            equals: .bindFailure(
                driver: FakeConnection.driverID,
                key: .indexed(0),
                message: "physical statement belongs to connection 11"
            )
        )
    }

    func testDatabaseAndDialectMismatchesStopBeforePhysicalWork() {
        let recorder = DriverRecorder()
        let connectionDatabase = databaseID(3)
        var connection = FakeConnection(
            connectionID: 31,
            databaseIdentifier: connectionDatabase,
            recorder: recorder
        )

        assertError(
            try prepare(
                logicalStatement(databaseIdentifier: databaseID(4)),
                on: &connection
            ),
            equals: .driverMismatch(
                expectedDatabase: databaseID(4),
                actualDatabase: connectionDatabase,
                driver: FakeConnection.driverID
            )
        )

        let otherDialect = XLDialectIdentifier(rawValue: "other-sql")
        assertError(
            try prepare(
                XLLogicalPreparedStatement(
                    databaseIdentifier: connectionDatabase,
                    dialectRequirement: XLDialectRequirement(identity: otherDialect),
                    sql: "SELECT 1"
                ),
                on: &connection
            ),
            equals: .dialectMismatch(
                expected: otherDialect,
                actual: XLSQLiteDialect.identity
            )
        )

        XCTAssertTrue(recorder.preparedConnectionIDs.isEmpty)
        XCTAssertTrue(recorder.boundConnectionIDs.isEmpty)
        XCTAssertTrue(recorder.executedConnectionIDs.isEmpty)

    }

    func testTransactionPinsPrepareBindAndExecuteToOneConnection() throws {
        let recorder = DriverRecorder()
        let databaseIdentifier = databaseID(5)
        var driver = FakePoolDriver(
            databaseIdentifier: databaseIdentifier,
            connectionIDs: [41, 42],
            recorder: recorder
        )
        let logical = logicalStatement(databaseIdentifier: databaseIdentifier)

        let identities = try driver.withValidatedTransaction { connection -> (Int, Int) in
            var physical = try connection.prepareValidated(logical)
            physical = try connection.bindValidated(
                .text("transaction"),
                to: .named("value"),
                in: physical
            )
            try connection.executeValidated(physical)
            return (connection.connectionID, physical.connectionID)
        }

        XCTAssertEqual(identities.0, identities.1)
        XCTAssertEqual(recorder.transactionConnectionIDs, [41])
        XCTAssertEqual(recorder.preparedConnectionIDs, [41])
        XCTAssertEqual(recorder.boundConnectionIDs, [41])
        XCTAssertEqual(recorder.executedConnectionIDs, [41])
    }

    func testValidatedTransactionPreservesOperationErrors() {
        var driver = FakePoolDriver(
            databaseIdentifier: databaseID(9),
            connectionIDs: [43],
            recorder: DriverRecorder()
        )

        XCTAssertThrowsError(
            try driver.withValidatedTransaction { _ in
                throw OperationAbort.requested
            }
        ) { error in
            XCTAssertEqual(error as? OperationAbort, .requested)
        }
    }

    func testSharedTransactionFixturesCoverEveryStableCaseAndCapability() throws {
        let fixtures = SQLiteTransactionConformanceFixtures.cases

        XCTAssertEqual(
            Set(fixtures.map(\.id)),
            Set(SQLiteTransactionConformanceCaseID.allCases)
        )
        XCTAssertEqual(fixtures.count, SQLiteTransactionConformanceCaseID.allCases.count)
        XCTAssertNoThrow(
            try SQLiteTransactionConformanceFixtures.require(
                .explicitRollbackByError
            )
        )
        for (capability, disposition) in
            SQLiteTransactionConformanceFixtures.capabilities
            where !disposition.isSupported
        {
            XCTAssertNotNil(
                disposition.blockingIssue,
                capability.rawValue
            )
        }

        let nestedDisposition = try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.capabilities[
                .nestedTransactionOrSavepoint
            ]
        )
        XCTAssertFalse(nestedDisposition.isSupported)
        XCTAssertEqual(nestedDisposition.blockingIssue, 113)
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
                    reason: nestedDisposition.reason
                ),
                SQLiteTransactionConformanceCaseID
                    .nestedTransactionCapability.rawValue
            )
        }
    }

    func testSharedTransactionStateOracleRejectsBrokenCommitAndRollback() throws {
        let before = SQLiteTransactionStateSnapshot(rowIDs: ["seed"])
        let commit = try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.casesByID[
                .multipleStatementCommit
            ]
        )
        let rollback = try XCTUnwrap(
            SQLiteTransactionConformanceFixtures.casesByID[
                .bodyErrorRollback
            ]
        )

        XCTAssertNoThrow(
            try commit.validate(
                before: before,
                after: commit.expectedState(from: before)
            )
        )
        XCTAssertNoThrow(
            try rollback.validate(before: before, after: before)
        )

        XCTAssertThrowsError(
            try commit.validate(before: before, after: before)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTransactionStateViolation,
                .unexpectedState(
                    caseID: commit.id,
                    expected: commit.expectedState(from: before),
                    actual: before
                )
            )
        }

        let leakedRollbackRows = rollback.expectedState(from: before)
            .rows + rollback.insertedRows
        XCTAssertThrowsError(
            try rollback.validate(
                before: before,
                after: SQLiteTransactionStateSnapshot(
                    rows: leakedRollbackRows
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTransactionStateViolation,
                .unexpectedState(
                    caseID: rollback.id,
                    expected: before,
                    actual: SQLiteTransactionStateSnapshot(
                        rows: leakedRollbackRows
                    )
                )
            )
        }

        let leakedUpdateState = SQLiteTransactionStateSnapshot(
            rows: [
                SQLiteTransactionStateRow(id: "seed", value: 999),
            ]
        )
        XCTAssertThrowsError(
            try rollback.validate(before: before, after: leakedUpdateState)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTransactionStateViolation,
                .unexpectedState(
                    caseID: rollback.id,
                    expected: before,
                    actual: leakedUpdateState
                )
            )
        }
    }

    func testTransportFailuresMapToStructuredContractErrors() throws {
        let recorder = DriverRecorder()
        let databaseIdentifier = databaseID(6)
        let logical = logicalStatement(databaseIdentifier: databaseIdentifier)
        var connection = FakeConnection(
            connectionID: 51,
            databaseIdentifier: databaseIdentifier,
            recorder: recorder,
            failure: .prepare
        )

        assertError(
            try connection.prepareValidated(logical),
            equals: .prepareFailure(driver: FakeConnection.driverID, message: "prepare")
        )

        connection.failure = nil
        var physical = try connection.prepareValidated(logical)
        connection.failure = .bind
        assertError(
            try connection.bindValidated(.integer(9), to: .indexed(0), in: physical),
            equals: .bindFailure(
                driver: FakeConnection.driverID,
                key: .indexed(0),
                message: "bind"
            )
        )

        connection.failure = .unsupportedValue
        assertError(
            try connection.bindValidated(.blob(Data([0xff])), to: .indexed(0), in: physical),
            equals: .unsupportedDialectValue(
                dialect: XLSQLiteDialect.identity,
                storageType: "blob"
            )
        )

        connection.failure = nil
        physical = try connection.bindValidated(.integer(9), to: .indexed(0), in: physical)
        connection.failure = .execute
        assertError(
            try connection.executeValidated(physical),
            equals: .executeFailure(driver: FakeConnection.driverID, message: "execute")
        )
        assertError(
            try connection.fetchAllValidated(physical),
            equals: .executeFailure(driver: FakeConnection.driverID, message: "execute")
        )

        assertError(
            try LogicalToken.decode(.integer(1), column: 3),
            equals: .decodeFailure(
                dialect: XLSQLiteDialect.identity,
                column: 3,
                message: "expected TEXT, received integer"
            )
        )

        var driver = FakePoolDriver(
            databaseIdentifier: databaseIdentifier,
            connectionIDs: [61],
            recorder: DriverRecorder(),
            failTransaction: true
        )
        assertError(
            try driver.withValidatedTransaction { _ in () },
            equals: .transactionFailure(driver: FakeConnection.driverID, message: "transaction")
        )
    }

    func testEveryErrorCategoryHasAStableDescription() {
        let dialect = XLSQLiteDialect.identity
        let driver = FakeConnection.driverID
        let database = databaseID(7)
        let errors: [XLDatabaseContractError] = [
            .unsupportedDialectValue(dialect: dialect, storageType: "native"),
            .driverMismatch(
                expectedDatabase: database,
                actualDatabase: databaseID(8),
                driver: driver
            ),
            .dialectMismatch(
                expected: dialect,
                actual: XLDialectIdentifier(rawValue: "other")
            ),
            .capabilityMismatch(
                dialect: dialect,
                required: [.namedBindings],
                available: []
            ),
            .versionMismatch(
                dialect: dialect,
                minimum: XLDialectVersion(3, 40),
                actual: nil
            ),
            .prepareFailure(driver: driver, message: "prepare"),
            .bindFailure(driver: driver, key: .named("id"), message: "bind"),
            .executeFailure(driver: driver, message: "execute"),
            .transactionFailure(driver: driver, message: "transaction"),
            .decodeFailure(dialect: dialect, column: 0, message: "decode"),
        ]

        XCTAssertEqual(errors.count, 10)
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
            XCTAssertEqual(error, error)
        }
    }

    private func logicalStatement(
        databaseIdentifier: XLDatabaseIdentifier
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(
                identity: XLSQLiteDialect.identity,
                minimumVersion: XLDialectVersion(3, 35),
                capabilities: [.namedBindings]
            ),
            sql: "SELECT :token",
            entities: ["Token"]
        )
    }

    private func databaseID(_ suffix: UInt8) -> XLDatabaseIdentifier {
        let uuid = UUID(uuid: (
            0, 0, 0, 0,
            0, 0,
            0, 0,
            0, 0, 0, 0, 0, 0, 0, suffix
        ))
        return XLDatabaseIdentifier(rawValue: uuid)
    }

    private func assertError<T>(
        _ expression: @autoclosure () throws -> T,
        equals expected: XLDatabaseContractError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLDatabaseContractError, expected, file: file, line: line)
        }
    }

    private func prepare<Connection>(
        _ statement: XLLogicalPreparedStatement,
        on connection: inout Connection
    ) throws -> Connection.PhysicalStatement where Connection: XLDatabaseDriverConnection {
        try connection.prepare(statement)
    }
}


private struct LogicalToken: Equatable {

    let rawValue: String

    func encode() -> XLSQLiteValue {
        .text(rawValue)
    }

    static func decode(_ value: XLSQLiteValue, column: Int) throws -> Self {
        guard case .text(let rawValue) = value else {
            throw XLDatabaseContractError.decodeFailure(
                dialect: XLSQLiteDialect.identity,
                column: column,
                message: "expected TEXT, received \(value.storageType.rawValue)"
            )
        }
        return Self(rawValue: rawValue)
    }
}


private enum FakeWireValue: Equatable {
    case null
    case signedDecimal(String)
    case ieee754(UInt64)
    case utf8([UInt8])
    case bytes([UInt8])

    init(_ value: XLSQLiteValue) {
        switch value {
        case .null:
            self = .null
        case .integer(let value):
            self = .signedDecimal(String(value))
        case .real(let value):
            self = .ieee754(value.bitPattern)
        case .text(let value):
            self = .utf8(Array(value.utf8))
        case .blob(let value):
            self = .bytes(Array(value))
        }
    }

    var dialectValue: XLSQLiteValue {
        switch self {
        case .null:
            return .null
        case .signedDecimal(let value):
            return .integer(Int64(value)!)
        case .ieee754(let bitPattern):
            return .real(Double(bitPattern: bitPattern))
        case .utf8(let value):
            return .text(String(decoding: value, as: UTF8.self))
        case .bytes(let value):
            return .blob(Data(value))
        }
    }
}


private struct FakePhysicalStatement {
    let connectionID: Int
    let statementID: Int
    let sql: String
    var wireBindings: [XLBindingKey: FakeWireValue] = [:]
}


private final class DriverRecorder {
    var nextStatementID = 0
    var preparedConnectionIDs: [Int] = []
    var boundConnectionIDs: [Int] = []
    var executedConnectionIDs: [Int] = []
    var transactionConnectionIDs: [Int] = []
    var streamedRows: [[XLSQLiteValue]] = []
}


private enum FakeFailure: Error, Equatable, CustomStringConvertible {
    case prepare
    case bind
    case execute
    case transaction
    case unsupportedValue

    var description: String {
        switch self {
        case .prepare:
            return "prepare"
        case .bind:
            return "bind"
        case .execute:
            return "execute"
        case .transaction:
            return "transaction"
        case .unsupportedValue:
            return "unsupported value"
        }
    }
}


private struct FakeConnection:
    XLDatabaseDriverConnection,
    XLStreamingDatabaseDriverConnection
{

    static let driverID = XLDriverIdentifier(rawValue: "fake-second-transport")

    let connectionID: Int
    let databaseIdentifier: XLDatabaseIdentifier
    let recorder: DriverRecorder
    var failure: FakeFailure?
    let resultRows: [[XLSQLiteValue]]?

    let driverIdentifier = FakeConnection.driverID
    let dialect = XLSQLiteDialect(
        version: XLDialectVersion(3, 46),
        capabilities: XLSQLiteDialect.standardCapabilities
    )

    init(
        connectionID: Int,
        databaseIdentifier: XLDatabaseIdentifier,
        recorder: DriverRecorder,
        failure: FakeFailure? = nil,
        resultRows: [[XLSQLiteValue]]? = nil
    ) {
        self.connectionID = connectionID
        self.databaseIdentifier = databaseIdentifier
        self.recorder = recorder
        self.failure = failure
        self.resultRows = resultRows
    }

    mutating func preparePhysical(
        _ validatedStatement: XLValidatedLogicalPreparedStatement
    ) throws -> FakePhysicalStatement {
        if failure == .prepare {
            throw FakeFailure.prepare
        }
        let statement = validatedStatement.logicalStatement
        let statementID = recorder.nextStatementID
        recorder.nextStatementID += 1
        recorder.preparedConnectionIDs.append(connectionID)
        return FakePhysicalStatement(
            connectionID: connectionID,
            statementID: statementID,
            sql: statement.sql
        )
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: FakePhysicalStatement
    ) throws -> FakePhysicalStatement {
        guard statement.connectionID == connectionID else {
            throw XLDatabaseContractError.bindFailure(
                driver: driverIdentifier,
                key: key,
                message: "physical statement belongs to connection \(statement.connectionID)"
            )
        }
        if failure == .unsupportedValue {
            throw XLDatabaseContractError.unsupportedDialectValue(
                dialect: dialect.descriptor.identity,
                storageType: value.storageType.rawValue
            )
        }
        if failure == .bind {
            throw FakeFailure.bind
        }
        var result = statement
        result.wireBindings[key] = FakeWireValue(value)
        recorder.boundConnectionIDs.append(connectionID)
        return result
    }

    mutating func fetchAll(
        _ statement: FakePhysicalStatement
    ) throws -> [[XLSQLiteValue]] {
        try collectAllRows(statement)
    }

    mutating func fetchOne(
        _ statement: FakePhysicalStatement
    ) throws -> [XLSQLiteValue]? {
        try collectFirstRow(statement)
    }

    mutating func forEachRow(
        _ statement: FakePhysicalStatement,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        guard statement.connectionID == connectionID else {
            throw FakeFailure.execute
        }
        if failure == .execute {
            throw FakeFailure.execute
        }
        let rows = resultRows ?? [orderedValues(in: statement)]
        for row in rows {
            recorder.streamedRows.append(row)
            if try body(row) == .stop {
                return
            }
        }
    }

    mutating func execute(_ statement: FakePhysicalStatement) throws {
        guard statement.connectionID == connectionID else {
            throw FakeFailure.execute
        }
        if failure == .execute {
            throw FakeFailure.execute
        }
        recorder.executedConnectionIDs.append(connectionID)
    }

    private func orderedValues(in statement: FakePhysicalStatement) -> [XLSQLiteValue] {
        statement.wireBindings
            .sorted { bindingSortKey($0.key) < bindingSortKey($1.key) }
            .map { $0.value.dialectValue }
    }

    private func bindingSortKey(_ key: XLBindingKey) -> String {
        switch key {
        case .named(let name):
            return "n:\(name)"
        case .indexed(let index):
            return "i:\(index)"
        }
    }
}


private struct FakePoolDriver: XLDatabaseDriver {

    let driverIdentifier = FakeConnection.driverID
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect: XLSQLiteDialect
    var connections: [FakeConnection]
    var nextReadConnection = 0
    var failTransaction: Bool
    let recorder: DriverRecorder

    init(
        databaseIdentifier: XLDatabaseIdentifier,
        connectionIDs: [Int],
        recorder: DriverRecorder,
        failTransaction: Bool = false
    ) {
        self.databaseIdentifier = databaseIdentifier
        self.dialect = XLSQLiteDialect(
            version: XLDialectVersion(3, 46),
            capabilities: XLSQLiteDialect.standardCapabilities
        )
        self.connections = connectionIDs.map {
            FakeConnection(
                connectionID: $0,
                databaseIdentifier: databaseIdentifier,
                recorder: recorder
            )
        }
        self.failTransaction = failTransaction
        self.recorder = recorder
    }

    mutating func withReadConnection<Result>(
        _ operation: (inout FakeConnection) throws -> Result
    ) throws -> Result {
        let index = nextReadConnection % connections.count
        nextReadConnection += 1
        return try operation(&connections[index])
    }

    mutating func withWriteConnection<Result>(
        _ operation: (inout FakeConnection) throws -> Result
    ) throws -> Result {
        try operation(&connections[0])
    }

    mutating func withTransaction<Result>(
        _ operation: (inout FakeConnection) throws -> Result
    ) throws -> Result {
        if failTransaction {
            throw FakeFailure.transaction
        }
        recorder.transactionConnectionIDs.append(connections[0].connectionID)
        return try operation(&connections[0])
    }
}
