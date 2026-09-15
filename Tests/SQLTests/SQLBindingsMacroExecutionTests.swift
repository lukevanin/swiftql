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


/// Covers the value shapes the demo binds: UUID text through a custom type, a
/// Bool, an enum, and an optional.
@SQLBindings
struct TestJobPacketBindings {
    var owner: MyUUID
    var includesAll: Bool
    var priority: JobPriority
    var previousState: JobState?
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

    /// The generated packet is the packet the demo built by hand before
    /// `@SQLBindings`: the same keys, slots, and normalized values, and the
    /// same rows when executed.
    func testGeneratedPacketMatchesHandWrittenSlotLookupPacket() throws {
        try database.makeRequest(with: sqlCreate(Job.self)).execute()
        let job = Job(id: "job-1", priority: .high, state: .queued, previousState: nil)
        try database.makeRequest(with: sqlInsert(job)).execute()

        let owner = MyUUID(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        let statement = sql { schema in
            let job = schema.table(Job.self)
            Select(job)
            From(job)
            Where(
                TestJobPacketBindings.owner == owner
                && job.priority == TestJobPacketBindings.priority
                && (job.previousState == TestJobPacketBindings.previousState
                    || TestJobPacketBindings.includesAll == true)
            )
        }
        let request = database.makeRequest(with: statement)
        let layout = request.parameterLayout

        func slot(_ name: String) throws -> XLParameterSlot {
            try XCTUnwrap(layout.slot(for: .named(name)))
        }
        let handWritten = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try XLInvocationBinding(slot: slot("owner"), value: .text(owner.wrappedValue.uuidString)),
                try XLInvocationBinding(slot: slot("includesAll"), value: .integer(1)),
                try XLInvocationBinding(slot: slot("priority"), value: .integer(Int64(JobPriority.high.rawValue))),
                try XLInvocationBinding(slot: slot("previousState"), value: .null),
            ]
        ).validatingComplete()
        let generated = try TestJobPacketBindings(
            owner: owner,
            includesAll: true,
            priority: .high,
            previousState: nil
        ).bindings(for: request)

        XCTAssertEqual(generated.bindings.map(\.slot.key), handWritten.bindings.map(\.slot.key))
        XCTAssertEqual(generated.bindings.map(\.slot), handWritten.bindings.map(\.slot))
        XCTAssertEqual(generated.bindings.map(\.value), handWritten.bindings.map(\.value))
        XCTAssertEqual(generated, handWritten)
        XCTAssertEqual(
            generated.binding(for: .named("owner"))?.value,
            .text("6F9619FF-8B86-D011-B42D-00C04FC964FF")
        )
        XCTAssertEqual(generated.binding(for: .named("previousState"))?.slot.nullability, .nullable)

        XCTAssertEqual(try request.fetchAll(bindings: generated), [job])
        XCTAssertEqual(try request.fetchAll(bindings: handWritten), [job])
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

    /// A write without `RETURNING` prepares an `XLWriteRequest`, which is not
    /// an `XLRequest`, and still takes its packet from `bindings(for:)`.
    func testWriteRequestWithoutReturningBindsPacket() throws {
        try createTestTable()
        try insert(TestTable(id: "alpha", value: 1))
        try insert(TestTable(id: "beta", value: 2))

        let statement = sql { schema in
            let table = schema.into(TestTable.self)
            Update(table)
            Setting(table) { row in
                row.value = TestValueUpdateBindings.value
            }
            Where(table.id == TestValueUpdateBindings.id)
        }
        let request = database.makeRequest(with: statement)
        try request.execute(
            bindings: TestValueUpdateBindings(id: "alpha", value: 10)
                .bindings(for: request)
        )

        let allRows = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: allRows).fetchAll(),
            [TestTable(id: "alpha", value: 10), TestTable(id: "beta", value: 2)]
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
