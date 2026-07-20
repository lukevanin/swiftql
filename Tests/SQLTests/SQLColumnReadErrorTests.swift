import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import GRDB
import XCTest
@testable import SwiftQL


enum ColumnReadTestStatus: Int, XLEnum {
    typealias T = Self

    case ready = 1

    static func sqlDefault() -> ColumnReadTestStatus {
        .ready
    }
}


@SQLTable(name: "ColumnReadStatus")
struct ColumnReadStatusRow: Equatable {
    let status: ColumnReadTestStatus
}


struct ColumnReadIntegerFunction: XLCustomFunction {
    typealias T = Int

    static let definition = XLCustomFunctionDefinition(
        name: "columnReadInteger",
        numberOfArguments: 1
    )

    private let value: any XLExpression<Int?>

    init(_ value: any XLExpression<Int?>) {
        self.value = value
    }

    func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: value.makeSQL)
        }
    }

    static func execute(reader: XLColumnReader) throws -> Int {
        try reader.readInteger(at: 0)
    }
}


private final class ColumnReadTestLogger: XLLogger {
    private(set) var errorMessages: [String] = []

    func log(level: XLLogLevel, message: String) {
        if case .error = level {
            errorMessages.append(message)
        }
    }
}


final class XLColumnReadErrorTests: XCTestCase {
    private var database: GRDBDatabase!
    private var databasePool: DatabasePool!
    private var databaseDirectoryURL: URL!
    private var logger: ColumnReadTestLogger!
    private var streamStepProbe: ColumnReadStreamStepProbe!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        logger = ColumnReadTestLogger()
        streamStepProbe = ColumnReadStreamStepProbe()
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appending(path: "database.sqlite", directoryHint: .notDirectory)
        var configuration = Configuration()
        let streamStepProbe = try XCTUnwrap(streamStepProbe)
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    ColumnReadStreamStepProbe.functionName,
                    argumentCount: 1
                ) { values in
                    streamStepProbe.observe(values[0])
                }
            )
        }
        var builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: configuration,
            logger: logger
        )
        builder.addFunction(ColumnReadIntegerFunction.self)
        database = try builder.build()
        databasePool = database.databasePool
    }

    override func tearDown() {
        cancellables.removeAll()
        databasePool = nil
        database = nil
        logger = nil
        streamStepProbe = nil
        try? FileManager.default.removeItem(at: databaseDirectoryURL)
        databaseDirectoryURL = nil
    }

    func testGRDBRowAdapterReadsIntrinsicValuesAndOptionalNull() throws {
        let row = try fetchRow(sql: "SELECT 42, 1.5, 'text', X'00FF', NULL")
        let reader = GRDBRowAdapter(row: row)

        XCTAssertEqual(try reader.readInteger(at: 0), 42)
        XCTAssertEqual(try reader.readReal(at: 1), 1.5)
        XCTAssertEqual(try reader.readText(at: 2), "text")
        XCTAssertEqual(try reader.readBlob(at: 3), Data([0x00, 0xff]))
        XCTAssertTrue(try reader.isNull(at: 4))
        XCTAssertNil(
            try Int?(reader: XLFieldReader(reader: reader, at: 4))
        )
    }

    func testAdaptersUseStorageClassConversionsConsistently() throws {
        let rowReader = GRDBRowAdapter(
            row: try fetchRow(sql: "SELECT 42, 42.75, X'74657874', 'blob'")
        )
        let valuesReader = GRDBValuesAdapter(values: [
            42.databaseValue,
            42.75.databaseValue,
            Data("text".utf8).databaseValue,
            "blob".databaseValue,
        ])

        for reader in [rowReader as any XLColumnReader, valuesReader as any XLColumnReader] {
            XCTAssertEqual(try reader.readReal(at: 0), 42)
            XCTAssertEqual(try reader.readInteger(at: 1), 42)
            XCTAssertEqual(try reader.readText(at: 2), "text")
            XCTAssertEqual(try reader.readBlob(at: 3), Data("blob".utf8))
            assertColumnReadError(
                try reader.readText(at: 0),
                equals: XLColumnReadError(
                    index: 0,
                    expectedType: "String",
                    failure: .typeMismatch(actualType: "INTEGER")
                )
            )
        }
    }

    func testGRDBRowAdapterThrowsStructuredErrors() throws {
        let reader = GRDBRowAdapter(row: try fetchRow(sql: "SELECT NULL, 'text'"))

        assertColumnReadError(
            try reader.readInteger(at: 0),
            equals: XLColumnReadError(
                index: 0,
                expectedType: "Int",
                failure: .nullValue
            )
        )
        assertColumnReadError(
            try reader.readInteger(at: 1),
            equals: XLColumnReadError(
                index: 1,
                expectedType: "Int",
                failure: .typeMismatch(actualType: "TEXT")
            )
        )
        assertColumnReadError(
            try reader.readInteger(at: 2),
            equals: XLColumnReadError(
                index: 2,
                expectedType: "Int",
                failure: .indexOutOfBounds(valueCount: 2)
            )
        )
        assertColumnReadError(
            try reader.isNull(at: -1),
            equals: XLColumnReadError(
                index: -1,
                expectedType: nil,
                failure: .indexOutOfBounds(valueCount: 2)
            )
        )
    }

    func testGRDBValuesAdapterThrowsStructuredErrors() {
        let reader = GRDBValuesAdapter(values: [DatabaseValue.null, "text".databaseValue])

        assertColumnReadError(
            try reader.readInteger(at: 0),
            equals: XLColumnReadError(
                index: 0,
                expectedType: "Int",
                failure: .nullValue
            )
        )
        assertColumnReadError(
            try reader.readInteger(at: 1),
            equals: XLColumnReadError(
                index: 1,
                expectedType: "Int",
                failure: .typeMismatch(actualType: "TEXT")
            )
        )
        assertColumnReadError(
            try reader.readInteger(at: 2),
            equals: XLColumnReadError(
                index: 2,
                expectedType: "Int",
                failure: .indexOutOfBounds(valueCount: 2)
            )
        )
    }

    func testFetchOnePropagatesNullReadError() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE Test (id TEXT NOT NULL, value INTEGER)")
            try database.execute(sql: "INSERT INTO Test (id, value) VALUES ('row', NULL)")
        }
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
        }

        assertColumnReadError(
            try database.makeRequest(with: statement).fetchOne(),
            equals: XLColumnReadError(
                index: 1,
                expectedType: "Int",
                failure: .nullValue
            )
        )
    }

    func testFetchAllFailsAtomicallyOnMiddleRowDecodeError() throws {
        try createTestTableWithInvalidMiddleRow()
        let statement = orderedTestTableStatement()
        let expectedError = nullIntegerReadError()

        assertColumnReadError(
            try database.makeRequest(with: statement).fetchAll(),
            equals: expectedError
        )
        XCTAssertTrue(
            logger.errorMessages.contains { $0.contains(expectedError.localizedDescription) },
            "Expected the decode failure to be logged before it was rethrown."
        )
    }

    func testFetchAllDecodeFailureStopsSQLiteAndLeavesPoolReusable() throws {
        try databasePool.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE TestStorage (
                        id TEXT PRIMARY KEY,
                        value INTEGER
                    )
                    """
            )
            try database.execute(
                sql: """
                    INSERT INTO TestStorage (id, value) VALUES
                        ('1-valid', 1),
                        ('2-invalid', NULL),
                        ('3-must-not-step', 3)
                    """
            )
            try database.execute(
                sql: """
                    CREATE VIEW Test AS
                    SELECT
                        id,
                        \(ColumnReadStreamStepProbe.functionName)(value) AS value
                    FROM TestStorage
                    """
            )
        }

        assertColumnReadError(
            try database.makeRequest(
                with: orderedTestTableStatement()
            ).fetchAll(),
            equals: nullIntegerReadError()
        )
        XCTAssertEqual(
            streamStepProbe.invocationCount,
            2,
            "Typed decoding must fail before SQLite steps the third row."
        )
        XCTAssertEqual(
            try databasePool.read { database in
                try Int.fetchOne(database, sql: "SELECT 42")
            },
            42
        )
    }

    func testPublisherFailsOnMiddleRowDecodeErrorWithoutEmittingPartialResults() throws {
        try createTestTableWithInvalidMiddleRow()
        let statement = orderedTestTableStatement()
        let failureExpectation = expectation(description: "initial decode failure")
        var receivedError: Error?

        database.makeRequest(with: statement).publish()
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        receivedError = error
                    case .finished:
                        XCTFail("Expected a row-decoding failure, received normal completion.")
                    }
                    failureExpectation.fulfill()
                },
                receiveValue: { rows in
                    XCTFail("Expected a row-decoding failure, received \(rows).")
                }
            )
            .store(in: &cancellables)

        wait(for: [failureExpectation], timeout: 2)
        XCTAssertEqual(receivedError as? XLColumnReadError, nullIntegerReadError())
    }

    func testPublisherPropagatesRefreshDecodeErrorWithoutEmittingPartialResults() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE Test (id TEXT NOT NULL, value INTEGER)")
            try database.execute(
                sql: """
                    INSERT INTO Test (id, value) VALUES
                        ('1-valid', 1),
                        ('2-invalid-later', 2),
                        ('3-valid', 3)
                    """
            )
        }
        let initialExpectation = expectation(description: "valid initial value")
        let failureExpectation = expectation(description: "refresh decode failure")
        var receivedValues: [[TestTable]] = []
        var receivedError: Error?

        database.makeRequest(with: orderedTestTableStatement()).publish()
            .removeDuplicates()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                        failureExpectation.fulfill()
                    }
                },
                receiveValue: { rows in
                    receivedValues.append(rows)
                    if receivedValues.count == 1 {
                        initialExpectation.fulfill()
                    }
                }
            )
            .store(in: &cancellables)

        wait(for: [initialExpectation], timeout: 2)
        try databasePool.write { database in
            try database.execute(
                sql: "UPDATE Test SET value = NULL WHERE id = '2-invalid-later'"
            )
        }
        wait(for: [failureExpectation], timeout: 2)

        XCTAssertEqual(receivedError as? XLColumnReadError, nullIntegerReadError())
        XCTAssertEqual(
            receivedValues,
            [[
                TestTable(id: "1-valid", value: 1),
                TestTable(id: "2-invalid-later", value: 2),
                TestTable(id: "3-valid", value: 3),
            ]]
        )
    }

    func testEnumReaderRejectsUnknownRawValue() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE ColumnReadStatus (status INTEGER NOT NULL)")
            try database.execute(sql: "INSERT INTO ColumnReadStatus (status) VALUES (99)")
        }
        let statement = sql { schema in
            let table = schema.table(ColumnReadStatusRow.self)
            Select(table)
            From(table)
        }

        assertColumnReadError(
            try database.makeRequest(with: statement).fetchOne(),
            equals: XLColumnReadError(
                index: 0,
                expectedType: "ColumnReadTestStatus",
                failure: .invalidValue(actualValue: "99")
            )
        )
    }

    func testEnumReaderAcceptsKnownRawValue() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE ColumnReadStatus (status INTEGER NOT NULL)")
            try database.execute(sql: "INSERT INTO ColumnReadStatus (status) VALUES (1)")
        }
        let statement = sql { schema in
            let table = schema.table(ColumnReadStatusRow.self)
            Select(table)
            From(table)
        }

        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            ColumnReadStatusRow(status: .ready)
        )
    }

    func testCustomFunctionTurnsNullReadIntoSQLiteError() throws {
        XCTAssertThrowsError(
            try databasePool.read { database in
                try Int.fetchOne(database, sql: "SELECT columnReadInteger(NULL)")
            }
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("Cannot read NULL value at index 0 as Int."), message)
        }
    }

    private func fetchRow(sql: String) throws -> Row {
        try databasePool.read { database in
            try XCTUnwrap(Row.fetchOne(database, sql: sql))
        }
    }

    private func createTestTableWithInvalidMiddleRow() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE Test (id TEXT NOT NULL, value INTEGER)")
            try database.execute(
                sql: """
                    INSERT INTO Test (id, value) VALUES
                        ('1-valid', 1),
                        ('2-invalid', NULL),
                        ('3-valid', 3)
                    """
            )
        }
    }

    private func orderedTestTableStatement() -> any XLQueryStatement<TestTable> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    private func nullIntegerReadError() -> XLColumnReadError {
        XLColumnReadError(
            index: 1,
            expectedType: "Int",
            failure: .nullValue
        )
    }

    private func assertColumnReadError<T>(
        _ expression: @autoclosure () throws -> T,
        equals expectedError: XLColumnReadError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLColumnReadError, expectedError, file: file, line: line)
        }
    }
}


private final class ColumnReadStreamStepProbe: @unchecked Sendable {

    static let functionName = "swiftql_column_read_stream_probe"

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
