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


// `XLLogger` is `Sendable` (issue #792). The lock supplies the safety the
// conformance states.
private final class ColumnReadTestLogger: XLLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    var errorMessages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func log(level: XLLogLevel, message: String) {
        guard case .error = level else {
            return
        }
        lock.lock()
        messages.append(message)
        lock.unlock()
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
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "database.sqlite",
            isDirectory: false
        )
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

    func testValuesAdapterReadsIntrinsicValuesAndOptionalNullFromARow() throws {
        let row = try fetchRow(sql: "SELECT 42, 1.5, 'text', X'00FF', NULL")
        let reader = GRDBValuesAdapter(row: row)

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
        let rowReader = GRDBValuesAdapter(
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

    func testValuesAdapterThrowsStructuredErrorsFromARow() throws {
        let reader = GRDBValuesAdapter(row: try fetchRow(sql: "SELECT NULL, 'text'"))

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

    /// A decode failure must end the stream, not only throw once (issue
    /// #792). Decoding moved out of the GRDB observation, and
    /// `AsyncThrowingStream`'s `unfolding` wrapper calls its closure again
    /// after a throw, so the stream ends itself.
    func testStreamDecodeErrorEndsTheStream() async throws {
        try createTestTableWithInvalidMiddleRow()
        let request = database.makeRequest(with: orderedTestTableStatement())

        await assertStreamEndsAfterDecodeFailure(request.stream())
    }

    /// The single-row stream follows the same terminal rule (issue #792).
    func testStreamOneDecodeErrorEndsTheStream() async throws {
        try createTestTableWithInvalidFirstRow()
        let request = database.makeRequest(with: orderedTestTableStatement())

        await assertStreamEndsAfterDecodeFailure(request.streamOne())
    }

    /// Records that the deadline below expired, so a stream that never ends is
    /// reported as a failure rather than hanging the job.
    ///
    /// The flag is necessary because cancelling the probe task also ends the
    /// stream. Without it, a timed-out run and a correct run look the same.
    private actor StreamDeadlineFlag {
        private(set) var didExpire = false

        func markExpired() {
            didExpire = true
        }
    }

    /// Asserts that the first pull reports the expected decode error and that
    /// the next pull ends the stream.
    private func assertStreamEndsAfterDecodeFailure<Element: Sendable>(
        _ stream: AsyncThrowingStream<Element, Error>,
        seconds: Double = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let expectedError = nullIntegerReadError()
        let flag = StreamDeadlineFlag()
        let probe = Task { () -> Bool in
            var iterator = stream.makeAsyncIterator()
            do {
                let first = try await iterator.next()
                XCTFail(
                    "Expected a row-decoding failure, received \(String(describing: first)).",
                    file: file,
                    line: line
                )
                return false
            }
            catch {
                XCTAssertEqual(error as? XLColumnReadError, expectedError, file: file, line: line)
            }
            return try await iterator.next() == nil
        }
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            await flag.markExpired()
            probe.cancel()
        }
        let didEnd = (try? await probe.value) ?? false
        deadline.cancel()

        let didExpire = await flag.didExpire
        XCTAssertFalse(
            didExpire,
            "The stream did not end within \(seconds) seconds of the decode failure.",
            file: file,
            line: line
        )
        if !didExpire {
            XCTAssertTrue(didEnd, "A decode failure must end the stream.", file: file, line: line)
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

    private func createTestTableWithInvalidFirstRow() throws {
        try databasePool.write { database in
            try database.execute(sql: "CREATE TABLE Test (id TEXT NOT NULL, value INTEGER)")
            try database.execute(
                sql: "INSERT INTO Test (id, value) VALUES ('1-invalid', NULL)"
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
