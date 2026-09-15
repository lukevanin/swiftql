//
//  SQLBindingsMacroExecutionTests.swift
//  SwiftQL
//
//  Runtime tests for the `@SQLBindings` macro (issue #663): a statement value
//  uses the generated typed references, and the generated packet builders
//  bind the property values for a real SQLite request.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLBindings
struct TestRowsBindings {
    var id: String
    var minimumValue: Int
}


@SQLBindings
struct TestNullableValueBindings {
    var value: Int?
}


@SQLBindings
struct TestValueUpdateBindings {
    var id: String
    var value: Int
}


/// Property names that the generated members could collide with: a keyword,
/// and the names of the generated builder method and its layout parameter.
@SQLBindings
struct TestAwkwardNameBindings {
    var `default`: String
    var layout: Int
    var bindings: Int
}


final class XLBindingsMacroExecutionTests: XCTestCase {

    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    func testPacketBindsEveryPropertyUnderItsOwnName() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "alpha", value: 5))
        try insert(TestTable(id: "beta", value: 9))

        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(
                table.id == TestRowsBindings.id
                && table.value >= TestRowsBindings.minimumValue
            )
            OrderBy(table.value.ascending())
        }
        let request = database.makeRequest(with: statement)

        XCTAssertEqual(
            request.parameterLayout.slots.map(\.key),
            [.named("id"), .named("minimumValue")]
        )
        XCTAssertEqual(
            try request.fetchAll(
                bindings: TestRowsBindings(id: "alpha", minimumValue: 2)
                    .bindings(for: request)
            ),
            [TestTable(id: "alpha", value: 5)]
        )
        XCTAssertEqual(
            try request.fetchAll(
                bindings: TestRowsBindings(id: "alpha", minimumValue: 0)
                    .bindings(in: request.parameterLayout)
            ),
            [TestTable(id: "alpha", value: 1), TestTable(id: "alpha", value: 5)]
        )
    }

    func testPropertyOrderDoesNotHaveToMatchTheStatement() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 5))

        // The statement reads `minimumValue` before `id`, the reverse of the
        // struct's declaration order.
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(
                table.value >= TestRowsBindings.minimumValue
                && table.id == TestRowsBindings.id
            )
        }
        let request = database.makeRequest(with: statement)
        let packet = try TestRowsBindings(id: "alpha", minimumValue: 5)
            .bindings(for: request)

        XCTAssertEqual(packet.bindings.map(\.slot.key), [.named("minimumValue"), .named("id")])
        XCTAssertEqual(try request.fetchAll(bindings: packet), [TestTable(id: "alpha", value: 5)])
    }

    func testNilOptionalPropertyIsAPresentSQLNull() throws {
        try createNullablesTable()
        try insert(TestNullablesTable(id: "alpha", value: 3))

        let statement = sql { schema in
            let table = schema.table(TestNullablesTable.self)
            Select(table)
            From(table)
            Where(table.value == TestNullableValueBindings.value)
        }
        let request = database.makeRequest(with: statement)

        let nullPacket = try TestNullableValueBindings(value: nil).bindings(for: request)
        XCTAssertTrue(nullPacket.isComplete)
        XCTAssertEqual(nullPacket.binding(for: .named("value"))?.value, .null)
        XCTAssertEqual(request.parameterLayout.slots.map(\.nullability), [.nullable])

        XCTAssertEqual(
            try request.fetchAll(
                bindings: TestNullableValueBindings(value: 3).bindings(for: request)
            ),
            [TestNullablesTable(id: "alpha", value: 3)]
        )
    }

    func testWriteStatementWithReturningBindsPacket() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        let schema = XLSchema()
        let table = schema.into(TestTable.self)
        let statement = update(table)
            .set { row in
                row.value = TestValueUpdateBindings.value
            }
            .where(table.id == TestValueUpdateBindings.id)
            .returning(schema.table(TestTable.self))
        let request = database.makeRequest(with: statement)

        XCTAssertEqual(
            try request.fetchAll(
                bindings: TestValueUpdateBindings(id: "beta", value: 20)
                    .bindings(for: request)
            ),
            [TestTable(id: "beta", value: 20)]
        )
        let allRows = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: allRows).fetchAll(),
            [TestTable(id: "alpha", value: 1), TestTable(id: "beta", value: 20)]
        )
    }

    func testAwkwardPropertyNamesBindAndExecute() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 4))
        try insert(TestTable(id: "alpha", value: 8))

        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(
                table.id == TestAwkwardNameBindings.default
                && table.value >= TestAwkwardNameBindings.layout
                && table.value <= TestAwkwardNameBindings.bindings
            )
        }
        let request = database.makeRequest(with: statement)

        XCTAssertEqual(
            try request.fetchAll(
                bindings: TestAwkwardNameBindings(default: "alpha", layout: 3, bindings: 5)
                    .bindings(for: request)
            ),
            [TestTable(id: "alpha", value: 4)]
        )
    }

    /// A binding the struct declares but the statement never reads is a
    /// mistake the compiler cannot see, so building the packet reports it.
    func testStatementThatDoesNotUseADeclaredBindingThrows() throws {
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == TestRowsBindings.id)
        }
        let request = database.makeRequest(with: statement)

        XCTAssertThrowsError(
            try TestRowsBindings(id: "alpha", minimumValue: 1).bindings(for: request)
        ) { error in
            guard
                case .parameterDeclarationNotInLayout(let declaration)? =
                    error as? XLInvocationBindingError
            else {
                return XCTFail("Expected parameterDeclarationNotInLayout, received \(error).")
            }
            XCTAssertEqual(declaration.key, .named("minimumValue"))
        }
    }

    /// A statement that reads a binding the struct does not declare leaves
    /// the packet incomplete, which is reported before execution.
    func testStatementWithAnUndeclaredBindingThrowsMissingBindings() throws {
        let other = XLNamedBindingReference<Int>(name: "other")
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(
                table.id == TestRowsBindings.id
                && table.value >= TestRowsBindings.minimumValue
                && table.value <= other
            )
        }
        let request = database.makeRequest(with: statement)

        XCTAssertThrowsError(
            try TestRowsBindings(id: "alpha", minimumValue: 1).bindings(for: request)
        ) { error in
            guard
                case .missingBindings(let slots)? = error as? XLInvocationBindingError
            else {
                return XCTFail("Expected missingBindings, received \(error).")
            }
            XCTAssertEqual(slots.map(\.key), [.named("other")])
        }
    }

    // MARK: - Fixtures

    private func createTestTable() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
    }

    private func createNullablesTable() throws {
        try database.makeRequest(with: sqlCreate(TestNullablesTable.self)).execute()
    }

    private func insert(_ row: TestTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }

    private func insert(_ row: TestNullablesTable) throws {
        try database.makeRequest(with: sqlInsert(row)).execute()
    }
}
