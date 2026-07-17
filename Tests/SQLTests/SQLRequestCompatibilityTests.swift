import Combine
import Foundation
import GRDB
import SwiftQL
import XCTest


final class SQLRequestCompatibilityTests: XCTestCase {

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
