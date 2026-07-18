import Foundation
import GRDB
import XCTest
@testable import SwiftQL


private struct NoDefaultCustomLiteral:
    Equatable,
    Sendable,
    XLCustomType
{
    typealias T = Self

    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(reader: XLColumnReader, at index: Int) throws {
        let stored = try reader.readText(at: index)
        guard stored.hasPrefix("v1:") else {
            throw NoDefaultLiteralTestError.invalidCustomLiteral(stored)
        }
        self.value = String(stored.dropFirst(3))
    }

    func bind(context: inout XLBindingContext) {
        context.bindText(value: "v1:\(value)")
    }

    func makeSQL(context: inout XLBuilder) {
        context.text("v1:\(value)")
    }
}


private enum NoDefaultLiteralState: String, Sendable, XLEnum {
    typealias T = Self

    case queued
    case ready
}


private struct ExplicitLegacyDefaultLiteral:
    Equatable,
    XLCustomType
{
    typealias T = Self

    let value: String

    static func sqlDefault() -> Self {
        Self(value: "explicit-legacy-default")
    }

    init(value: String) {
        self.value = value
    }

    init(reader: XLColumnReader, at index: Int) throws {
        self.value = try reader.readText(at: index)
    }

    func bind(context: inout XLBindingContext) {
        context.bindText(value: value)
    }

    func makeSQL(context: inout XLBuilder) {
        context.text(value)
    }
}


@SQLTable(name: "NoDefaultLiteralRecord")
private struct NoDefaultLiteralRecord: Equatable {
    let custom: NoDefaultCustomLiteral
    let state: NoDefaultLiteralState
}


final class NoDefaultLiteralStaticLayoutGRDBTests: XCTestCase {

    func testNoDefaultCustomLiteralAndEnumRoundTripThroughStaticLayout() throws {
        let fixture = try NoDefaultLiteralFixture()
        defer { fixture.tearDown() }

        let customAdapter = XLV1LiteralCodec<NoDefaultCustomLiteral>(
            key: XLValueCodecKey(
                id: "tests.no-default-literal.custom",
                version: 1
            ),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.no-default-literal.custom"
            ),
            storageClass: .text
        )
        let enumAdapter = XLV1LiteralCodec<NoDefaultLiteralState>(
            key: XLValueCodecKey(
                id: "tests.no-default-literal.state",
                version: 1
            ),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.no-default-literal.state"
            ),
            storageClass: .text
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(customAdapter.codec)
                .registering(enumAdapter.codec)
        )
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let table = XLSchema().table(
            NoDefaultLiteralRecord.self,
            as: "record"
        )
        let layout = try NoDefaultLiteralRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            custom: configuration.staticResultField(
                NoDefaultCustomLiteral.self,
                selecting: table.custom,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["no-default-literal", "custom"]
                ),
                using: database.dialect,
                selection: .explicit(customAdapter.codec.identity.key)
            ),
            state: configuration.staticResultField(
                NoDefaultLiteralState.self,
                selecting: table.state,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["no-default-literal", "state"]
                ),
                using: database.dialect,
                selection: .explicit(enumAdapter.codec.identity.key)
            )
        )

        let expected = NoDefaultLiteralRecord(
            custom: NoDefaultCustomLiteral("alpha"),
            state: .ready
        )
        let encoded = try layout.encode(expected)
        XCTAssertEqual(encoded, [.text("v1:alpha"), .text("ready")])

        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE NoDefaultLiteralRecord (
                        custom TEXT NOT NULL,
                        state TEXT NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO NoDefaultLiteralRecord (custom, state)
                    VALUES (?, ?)
                    """,
                arguments: StatementArguments(encoded.map(\.databaseValue))
            )
        }

        let statement = sql { _ in
            Select(layout)
            From(table)
        }
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(statement)
        let expectedSQL =
            #"SELECT "record"."custom" AS "custom", "record"."state" AS "state" "#
            + #"FROM "NoDefaultLiteralRecord" AS "record""#
        XCTAssertEqual(
            encoding.sql,
            expectedSQL
        )
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "no-default-literal", "static-layout"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let prepared = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: descriptor,
                layout: layout
            )
        )

        XCTAssertEqual(
            try prepared.fetchExactlyOne(
                bindings: prepared.makeInvocationBindings()
            ),
            expected
        )
    }

    func testExplicitLegacyDefaultRemainsTheProtocolWitness() {
        XCTAssertEqual(
            legacyDefault(ExplicitLegacyDefaultLiteral.self),
            ExplicitLegacyDefaultLiteral(value: "explicit-legacy-default")
        )
    }
}


private enum NoDefaultLiteralTestError: Error {
    case invalidCustomLiteral(String)
}


private struct NoDefaultLiteralFixture {
    let url: URL
    let pool: DatabasePool

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        pool = try DatabasePool(path: url.path)
    }

    func tearDown() {
        try? pool.close()
        try? FileManager.default.removeItem(at: url)
    }
}


private func legacyDefault<Value>(_: Value.Type) -> Value
where Value: XLLiteral {
    Value.sqlDefault()
}
