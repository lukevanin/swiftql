import Combine
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


private struct LegacyReadRequest: XLRequest {

    let rows: [Int]

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
        Just(rows)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func publishOne() -> AnyPublisher<Int?, Error> {
        Just(rows.first)
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
