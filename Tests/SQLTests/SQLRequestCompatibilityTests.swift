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

    // MARK: - #308 stream()/streamOne() compatibility defaults
    //
    // `LegacyReadRequest` only implements `publish()`/`publishOne()`, exactly like a
    // third-party `XLRequest` conformer written before #308. These tests exercise the
    // protocol-extension default that bridges those Combine pipelines into
    // `AsyncThrowingStream`, proving it stays lazy (the underlying `publish()` is not
    // invoked merely by calling `stream()`) and does not recurse.

    func testLegacyReadConformerStreamBridgesFromPublishLazily() async throws {
        let request = LegacyReadRequest(rows: [82])

        // Constructing the stream performs no work: LegacyReadRequest.publish() is
        // invoked only once the stream is iterated below.
        let stream = request.stream()
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)
        var iterator = stream.makeAsyncIterator()
        XCTAssertEqual(request.publishCallCounter.publishCount, 0)

        let first = try await iterator.next()
        XCTAssertEqual(first, [82])
        XCTAssertEqual(request.publishCallCounter.publishCount, 1)

        // `Just`-backed publishers deliver exactly one value then finish: the
        // compatibility bridge must end iteration afterward, not hang or repeat.
        let second = try await iterator.next()
        XCTAssertNil(second)
        XCTAssertEqual(
            request.publishCallCounter.publishCount,
            1,
            "Resuming iteration after natural completion must not re-subscribe."
        )
    }

    func testLegacyReadConformerStreamOneBridgesFromPublishOneLazily() async throws {
        let request = LegacyReadRequest(rows: [82])
        let stream = request.streamOne()
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)
        var iterator = stream.makeAsyncIterator()
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 0)

        let first = try await iterator.next()
        XCTAssertEqual(first, 82)
        XCTAssertEqual(request.publishCallCounter.publishOneCount, 1)

        // `Just`-backed publishers deliver exactly one value then finish: the
        // compatibility bridge must end iteration afterward, not hang or repeat.
        let second = try await iterator.next()
        XCTAssertNil(second)
        XCTAssertEqual(
            request.publishCallCounter.publishOneCount,
            1,
            "Resuming iteration after natural completion must not re-subscribe."
        )
    }

    func testLegacyReadConformerStreamBindingsBridgesFromPublishBindingsLazily() async throws {
        let request = LegacyReadRequest(rows: [82])
        let packet = XLInvocationBindings<XLSQLiteValue>(layout: .empty)

        let stream = request.stream(bindings: packet)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, [82])

        // `Just`-backed publishers deliver exactly one value then finish: the
        // compatibility bridge must end iteration afterward, not hang or repeat.
        let second = try await iterator.next()
        XCTAssertNil(second)
    }

    func testLegacyReadConformerStreamBindingsRejectsUnsupportedPacketLazily() async throws {
        let request = LegacyReadRequest(rows: [82])
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


/// Records how many times `LegacyReadRequest.publish()`/`publishOne()` were
/// actually invoked, so tests can prove the `stream()`/`streamOne()`
/// compatibility bridge is lazy rather than merely asserting it delivers the
/// right value (which would also pass under eager subscription).
private final class LegacyPublishCallCounter {
    var publishCount = 0
    var publishOneCount = 0
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

    func publish() -> AnyPublisher<[Int], Error> {
        publishCallCounter.publishCount += 1
        return Just(rows)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func publishOne() -> AnyPublisher<Int?, Error> {
        publishCallCounter.publishOneCount += 1
        return Just(rows.first)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
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

    func execute() throws {}
}
