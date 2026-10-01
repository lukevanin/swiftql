#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import Foundation
import GRDB
import SwiftQL
import XCTest


final class SQLRequestCompatibilityTests: XCTestCase {

    func testScalarSelectAcceptsAnUnconstrainedLogicalResultType() throws {
        let expression = LegacyContextOnlyExpression()
        let direct: Select<LegacyContextOnlyValue> = Select(expression)
        let built: Select<LegacyContextOnlyValue> = Select { expression }
        let functional: XLQuerySelectStatement<LegacyContextOnlyValue> =
            select(expression)
        let factored: XLQuerySelectStatement<LegacyContextOnlyValue> =
            XLWithStatement([]).select(expression)
        let dynamic: QueryBuilder<LegacyContextOnlyValue> = QueryBuilder(
            select: expression
        )
        let encoder = XLiteEncoder(dialect: XLSQLiteDialect())

        XCTAssertEqual(encoder.makeSQL(direct).sql, "SELECT NULL")
        XCTAssertEqual(encoder.makeSQL(built).sql, "SELECT NULL")
        XCTAssertEqual(encoder.makeSQL(functional).sql, "SELECT NULL")
        XCTAssertEqual(encoder.makeSQL(factored).sql, "SELECT NULL")
        _ = dynamic

        XCTAssertThrowsError(
            try direct.readRow(reader: LegacyManualRowReader())
        ) { error in
            guard case .staticLayoutRequired(let valueType, let alias) =
                    error as? XLStaticRowReadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(valueType.contains("LegacyContextOnlyValue"))
            XCTAssertEqual(alias, "c0")
        }
    }

    func testScalarSelectKeepsLegacyLiteralRowDecoding() throws {
        let reader = LegacyManualRowReader()
        let statement = Select(42)

        XCTAssertEqual(try statement.readRow(reader: reader), Int.sqlDefault())
        XCTAssertEqual(reader.readCount, 1)
    }

    func testLegacyRowReaderConformerKeepsOriginalColumnRequirement() throws {
        let reader = LegacyManualRowReader()

        let value: Int = try reader.staticColumn(42, alias: "value")

        XCTAssertEqual(value, Int.sqlDefault())
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertThrowsError(
            try reader.staticColumn(
                LegacyContextOnlyExpression(),
                alias: "contextual"
            ) as LegacyContextOnlyValue
        ) { error in
            guard case .staticLayoutRequired(let valueType, let alias) =
                    error as? XLStaticRowReadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(valueType.contains("LegacyContextOnlyValue"))
            XCTAssertEqual(alias, "contextual")
        }
        XCTAssertEqual(reader.readCount, 1)
    }

    func testStaticColumnBridgePreservesQueryStatementParenthesization() {
        let statement = Select(LegacyQueryStatementProjection())
        let encoding = XLiteEncoder(dialect: XLSQLiteDialect()).makeSQL(
            statement
        )

        XCTAssertEqual(encoding.sql, "SELECT (SELECT 1) AS \"value\"")
    }

    func testLegacyReadConformerUsesDefaultPacketRequirements() throws {
        var request = LegacyReadRequest(rows: [82])
        let parameter = XLNamedBindingReference<Int>(name: "value")
        request.set(parameter, 41)

        XCTAssertEqual(request.assignedValue, 41)
        XCTAssertEqual(request.parameterLayout, .empty)

        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        XCTAssertEqual(try request.fetchAll(bindings: packet), [82])
        XCTAssertEqual(try request.fetchOne(bindings: packet), 82)

        let slot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("value"),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("value")
            )
        )
        let layout = try XLParameterLayout(slots: [slot])
        let nonemptyPacket = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .integer(1))]
        )

        XCTAssertThrowsError(try request.fetchOne(bindings: nonemptyPacket)) { error in
            guard case .unsupportedInvocationBindings(
                let requestType,
                let rejectedLayout
            ) = error as? XLRequestBindingError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(requestType.contains("LegacyReadRequest"))
            XCTAssertEqual(rejectedLayout, layout)
        }
    }

    // MARK: - #684 one-line publisher bridge and stream compatibility defaults
    //
    // `LegacyReadRequest` has only Combine publishers of its own, like a third-party `XLRequest`
    // conformer written before #684. It implements `stream()`/`streamOne()` in one line each with
    // `XLPublisherAsyncBridge`, and takes the `bindings:` stream members from the protocol's
    // compatibility defaults. These tests prove the bridge stays lazy (the publisher is not made
    // merely by calling `stream()`), ends with the publisher, and that the defaults validate packets.

    func testLegacyReadConformerStreamBridgesItsPublisherLazily() async throws {
        let request = LegacyReadRequest(rows: [82])

        // Constructing the stream performs no work: the publisher is made only once the stream is
        // iterated below.
        let stream = request.stream()
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)
        var iterator = stream.makeAsyncIterator()
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)

        let first = try await iterator.next()
        XCTAssertEqual(first, [82])
        XCTAssertEqual(request.publishCallCounter.publishCount, 1)

        // `Just`-backed publishers deliver exactly one value then finish: the bridge must end
        // iteration afterward, not hang or repeat.
        let second = try await iterator.next()
        XCTAssertNil(second)
        XCTAssertEqual(
            request.publishCallCounter.publishCount,
            1,
            "Resuming iteration after natural completion must not re-subscribe."
        )
    }

    func testLegacyReadConformerStreamOneBridgesItsPublisherLazily() async throws {
        let request = LegacyReadRequest(rows: [82])
        let stream = request.streamOne()
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)
        var iterator = stream.makeAsyncIterator()
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)

        let first = try await iterator.next()
        XCTAssertEqual(first, 82)
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 1)

        // `second` is `Int??` here (the stream's own `Row?` element, wrapped again by
        // `AsyncIteratorProtocol.next()`'s end-of-stream optional) -- XCTAssertEqual against
        // `nil` compares it directly as `Equatable`, unlike `XCTAssertNil`, which would
        // implicitly (and, per the compiler, ambiguously) coerce it to `Any?` first.
        let second = try await iterator.next()
        XCTAssertEqual(second, nil)
        XCTAssertEqual(
            request.publishCallCounter.publishOneCount,
            1,
            "Resuming iteration after natural completion must not re-subscribe."
        )
    }

    func testLegacyReadConformerStreamBindingsDefaultObservesThroughStream() async throws {
        let request = LegacyReadRequest(rows: [82])
        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)

        let stream = request.stream(bindings: packet)
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, [82])
        XCTAssertEqual(request.publishCallCounter.publishCount, 1)
        let second = try await iterator.next()
        XCTAssertNil(second)

        var oneIterator = request.streamOne(bindings: packet).makeAsyncIterator()
        let firstRow = try await oneIterator.next()
        XCTAssertEqual(firstRow, 82)
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 1)
    }

    func testLegacyReadConformerStreamBindingsRejectsUnsupportedPacketLazily() async throws {
        let request = LegacyReadRequest(rows: [82])
        let (nonemptyPacket, layout) = try Self.nonemptyPacket()

        let stream = request.stream(bindings: nonemptyPacket)
        var iterator = stream.makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("Expected unsupportedInvocationBindings.")
        }
        catch let error as XLRequestBindingError {
            guard case .unsupportedInvocationBindings(let requestType, let rejectedLayout) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(requestType.contains("LegacyReadRequest"))
            XCTAssertEqual(rejectedLayout, layout)
        }
        XCTAssertEqual(
            request.publishCallCounter.publishCount,
            0,
            "A rejected packet must not start the adapter's observation."
        )

        var oneIterator = request.streamOne(bindings: nonemptyPacket).makeAsyncIterator()
        do {
            _ = try await oneIterator.next()
            XCTFail("Expected unsupportedInvocationBindings.")
        }
        catch let error as XLRequestBindingError {
            guard case .unsupportedInvocationBindings = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)
    }

    /// The `bindings:` publish members of a conformer without packets fail on a nonempty packet,
    /// as they did when they were the compatibility defaults themselves, because they are built on
    /// the stream defaults above.
    func testLegacyReadConformerPublishBindingsRejectsUnsupportedPacket() throws {
        let request = LegacyReadRequest(rows: [82])
        let (nonemptyPacket, _) = try Self.nonemptyPacket()
        let failed = expectation(description: "publisher fails")
        failed.expectedFulfillmentCount = 2
        let errors = LockedErrors()
        let rowsCancellable = request.publish(bindings: nonemptyPacket).sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errors.append(error)
                    failed.fulfill()
                }
            },
            receiveValue: { _ in XCTFail("A rejected packet must not deliver rows.") }
        )
        let rowCancellable = request.publishOne(bindings: nonemptyPacket).sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errors.append(error)
                    failed.fulfill()
                }
            },
            receiveValue: { _ in XCTFail("A rejected packet must not deliver a row.") }
        )
        wait(for: [failed], timeout: 5)
        rowsCancellable.cancel()
        rowCancellable.cancel()

        XCTAssertEqual(errors.read().count, 2)
        for error in errors.read() {
            guard case .unsupportedInvocationBindings? = error as? XLRequestBindingError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)
    }

    private static func nonemptyPacket() throws -> (XLInvocationBindings<XLSQLiteValue>, XLParameterLayout) {
        let slot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("value"),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("value")
            )
        )
        let layout = try XLParameterLayout(slots: [slot])
        let packet = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .integer(1))]
        )
        return (packet, layout)
    }

    func testLegacyWriteConformerUsesDefaultPacketRequirement() throws {
        var request = LegacyWriteRequest()
        let parameter = XLNamedBindingReference<Int>(name: "value")
        request.set(parameter, 41)

        XCTAssertEqual(request.assignedValue, 41)
        XCTAssertEqual(request.parameterLayout, .empty)

        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        try request.execute(bindings: packet)
    }

    // MARK: - #681 async view compatibility defaults
    //
    // `LegacyReadRequest` and `LegacyWriteRequest` predate `XLRequest.async`, like a
    // third-party conformer. The protocol-extension default runs their synchronous
    // methods, so awaiting them returns what calling them returns.

    func testLegacyReadConformerAsyncViewCallsTheSynchronousFetches() async throws {
        let request = LegacyReadRequest(rows: [82, 83])
        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)

        let all = try await request.async.fetchAll()
        let allBound = try await request.async.fetchAll(bindings: packet)
        let atMostOne = try await request.async.fetchAtMost(1, bindings: packet)
        let one = try await request.async.fetchOne()
        let oneBound = try await request.async.fetchOne(bindings: packet)

        XCTAssertEqual(all, [82, 83])
        XCTAssertEqual(allBound, [82, 83])
        XCTAssertEqual(atMostOne, [82])
        XCTAssertEqual(one, 82)
        XCTAssertEqual(oneBound, 82)
    }

    func testLegacyWriteConformerAsyncViewCallsTheSynchronousExecute() async throws {
        let request = LegacyWriteRequest()
        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)

        try await request.async.execute()
        try await request.async.execute(bindings: packet)
    }

    func testLegacyConformerAsyncViewsThrowCancellationErrorForACancelledTask() async {
        let readView = LegacyReadRequest(rows: [82]).async
        let writeView = LegacyWriteRequest().async

        let fetch = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await readView.fetchAll()
        }
        let execute = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            try await writeView.execute()
        }
        fetch.cancel()
        execute.cancel()

        switch await fetch.result {
        case .success(let rows):
            XCTFail("A cancelled task fetched \(rows).")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        switch await execute.result {
        case .success:
            XCTFail("A cancelled task executed the statement.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    func testLegacyMutatingSetStillExecutesGRDBRequest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-request-compatibility-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try GRDBDatabase(
            url: directory.appendingPathComponent("fixture.sqlite"),
            logger: nil
        )
        let parameter = XLNamedBindingReference<String>(name: "value")
        var request = database.makeRequest(
            with: sql { _ in Select(parameter) }
        )

        request.set(parameter, "legacy")

        XCTAssertEqual(try request.fetchOne(), "legacy")
    }

    func testLegacyMutatingSetExecutesCustomDirectNamedBindingExpression() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-direct-binding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try GRDBDatabase(
            url: directory.appendingPathComponent("fixture.sqlite"),
            logger: nil
        )
        let parameter = XLNamedBindingReference<String>(name: "legacyCustom")
        let expression = LegacyDirectNamedBindingExpression(name: "legacyCustom")
        var request = database.makeRequest(
            with: sql { _ in Select(expression) }
        )

        let slot = try XCTUnwrap(
            request.parameterLayout.slot(for: .named("legacyCustom"))
        )
        XCTAssertEqual(
            slot.valueTypeIdentifier,
            XLValueTypeIdentifier(rawValue: "swiftql.legacy-binding-value")
        )
        XCTAssertEqual(slot.nullability, .nullable)
        XCTAssertNil(slot.codecIdentity)

        request.set(parameter, "direct legacy binding")

        XCTAssertEqual(try request.fetchOne(), "direct legacy binding")
    }
}


private final class LegacyManualRowReader: XLRowReader {
    private(set) var readCount = 0

    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) -> T where T: XLLiteral {
        readCount += 1
        return T.sqlDefault()
    }
}


private struct LegacyContextOnlyValue {}


private struct LegacyContextOnlyExpression: XLExpression {
    typealias T = LegacyContextOnlyValue

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }
}


private struct LegacyQueryStatementProjection: XLRowReadable {
    typealias Row = Int

    func readRow(reader: XLRowReader) throws -> Int {
        try reader.staticColumn(
            LegacyDualQueryStatementExpression(),
            alias: "value"
        )
    }
}


private struct LegacyDualQueryStatementExpression:
    XLExpression,
    XLQueryStatement
{
    typealias T = Int
    typealias Row = Int

    let components = select(1).components

    func readRow(reader: XLRowReader) throws -> Int {
        try components.readRow(reader: reader)
    }
}


private struct LegacyDirectNamedBindingExpression: XLExpression {

    typealias T = String

    let name: XLName

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding(name)
    }
}


/// Records how many times `LegacyReadRequest` made each of its own publishers,
/// so tests can prove the `stream()`/`streamOne()` bridge is lazy rather than
/// merely asserting it delivers the right value (which would also pass under
/// eager subscription).
///
/// Locked because the bridge makes the publisher on the task that iterates
/// the stream.
private final class LegacyPublishCallCounter: @unchecked Sendable {

    private let lock = NSLock()

    private var counts = (publish: 0, publishOne: 0)

    var publishCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.publish
    }

    var publishOneCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.publishOne
    }

    func recordPublish() {
        lock.lock()
        counts.publish += 1
        lock.unlock()
    }

    func recordPublishOne() {
        lock.lock()
        counts.publishOne += 1
        lock.unlock()
    }
}


private final class LockedErrors: @unchecked Sendable {

    private let lock = NSLock()

    private var errors: [Error] = []

    func append(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }

    func read() -> [Error] {
        lock.lock()
        defer { lock.unlock() }
        return errors
    }
}


private struct LegacyReadRequest: XLRequest {

    let rows: [Int]

    let publishCallCounter = LegacyPublishCallCounter()

    private(set) var assignedValue: Int? = nil

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {
        assignedValue = value as? Int
    }

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {
        assignedValue = value as? Int
    }

    func fetchAll() throws -> [Int] {
        rows
    }

    func fetchOne() throws -> Int? {
        rows.first
    }

    /// This adapter's own publisher. It is not `publish()`: since #684 that is
    /// SwiftQL's, built on `stream()`, so bridging it here would recurse.
    func rowsPublisher() -> AnyPublisher<[Int], Error> {
        publishCallCounter.recordPublish()
        return Just(rows)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func rowPublisher() -> AnyPublisher<Int?, Error> {
        publishCallCounter.recordPublishOne()
        return Just(rows.first)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func stream() -> AsyncThrowingStream<[Int], Error> {
        XLPublisherAsyncBridge(makePublisher: { self.rowsPublisher() }).stream()
    }

    func streamOne() -> AsyncThrowingStream<Int?, Error> {
        XLPublisherAsyncBridge(makePublisher: { self.rowPublisher() }).stream()
    }
}


private struct LegacyWriteRequest: XLWriteRequest {

    private(set) var assignedValue: Int? = nil

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {
        assignedValue = value as? Int
    }

    mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {
        assignedValue = value as? Int
    }

    // Since issue #679, `execute()` reports what it did. A conformer written
    // before that returns a result it computes, or an empty one.
    func execute() throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .write)
    }
}
