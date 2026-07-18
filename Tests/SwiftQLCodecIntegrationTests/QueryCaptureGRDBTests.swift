import Foundation
import GRDB
import XCTest

@testable import SwiftQL


@SQLTable(name: "QueryCaptureDateRecord")
private struct QueryCaptureDateRecord: Equatable {
    let storedDate: String
}


final class QueryCaptureGRDBTests: XCTestCase {

    func testIntrinsicValuesAndNullRoundTripWithoutInterpolation() throws {
        let fixture = try makeQueryCaptureDatabase()
        defer { fixture.tearDown() }
        try fixture.database.databasePool.write { database in
            try database.execute(sql: "CREATE TABLE injection_guard (id INTEGER)")
        }

        let dangerous = "x'); DROP TABLE injection_guard; -- \"quoted\""
        let text = try XLQueryCapture<String, String, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "text"])
        )
        XCTAssertEqual(
            try executeScalar(
                dangerous,
                capture: text,
                database: fixture.database,
                definition: ["tests", "query-capture", "text"]
            ),
            .text(dangerous)
        )
        let tableCount = try fixture.database.databasePool.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'injection_guard'"
            )
        }
        XCTAssertEqual(tableCount, 1)

        let nullable = try XLQueryCapture<String, String?, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "null"])
            )
        XCTAssertEqual(
            try executeNullableScalar(
                nil,
                capture: nullable,
                database: fixture.database,
                definition: ["tests", "query-capture", "null"]
            ),
            .null
        )

        let blob = try XLQueryCapture<Data, Data, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "blob"])
        )
        let blobValue = Data([0x00, 0x27, 0xff, 0x3b])
        XCTAssertEqual(
            try executeScalar(
                blobValue,
                capture: blob,
                database: fixture.database,
                definition: ["tests", "query-capture", "blob"]
            ),
            .blob(blobValue)
        )

        let boolean = try XLQueryCapture<Bool, Bool, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "bool"])
        )
        XCTAssertEqual(
            try executeScalar(
                true,
                capture: boolean,
                database: fixture.database,
                definition: ["tests", "query-capture", "bool"]
            ),
            .integer(1)
        )
        let integer = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "int"])
        )
        XCTAssertEqual(
            try executeScalar(
                Int.max,
                capture: integer,
                database: fixture.database,
                definition: ["tests", "query-capture", "int"]
            ),
            .integer(Int64.max)
        )
        let real = try XLQueryCapture<Double, Double, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["intrinsic", "real"])
        )
        XCTAssertEqual(
            try executeScalar(
                1234.5,
                capture: real,
                database: fixture.database,
                definition: ["tests", "query-capture", "real"]
            ),
            .real(1234.5)
        )
    }

    func testRepeatedAndDistinctCapturesPreserveLogicalCountAndOrder() throws {
        let fixture = try makeQueryCaptureDatabase()
        defer { fixture.tearDown() }
        let repeated = try XLQueryCapture<String, String, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["repeat", "value"])
            )
        let repeatedEncoding = try customEncoding(
            sql: "SELECT :\(try namedKey(repeated)) = :\(try namedKey(repeated))"
        ) { builder in
            repeated.makeSQL(context: &builder)
            repeated.makeSQL(context: &builder)
        }
        let repeatedDescriptor = try descriptor(
            definition: ["tests", "query-capture", "repeated"],
            encoding: repeatedEncoding,
            parameters: [repeated.staticQueryParameter(in: repeatedEncoding)],
            resultStorage: [.integer]
        )
        let preparedRepeated = try fixture.database.prepareInvocation(
            with: repeatedDescriptor
        )
        let repeatedPacket = try preparedRepeated.makeInvocationBindings(
            repeated.argument("same")
        )
        XCTAssertEqual(repeatedPacket.bindingCount, 1)
        XCTAssertEqual(preparedRepeated.parameterLayout.count, 1)
        XCTAssertEqual(
            try preparedRepeated.fetchExactlyOneValues(bindings: repeatedPacket),
            [.integer(1)]
        )

        let first = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["distinct", "first"])
        )
        let second = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["distinct", "second"])
        )
        let distinctEncoding = try customEncoding(
            sql: "SELECT :\(try namedKey(first)), :\(try namedKey(second))"
        ) { builder in
            first.makeSQL(context: &builder)
            second.makeSQL(context: &builder)
        }
        let distinctDescriptor = try descriptor(
            definition: ["tests", "query-capture", "distinct"],
            encoding: distinctEncoding,
            parameters: [
                first.staticQueryParameter(in: distinctEncoding),
                second.staticQueryParameter(in: distinctEncoding),
            ],
            resultStorage: [.integer, .integer]
        )
        let preparedDistinct = try fixture.database.prepareInvocation(
            with: distinctDescriptor
        )
        let distinctPacket = try preparedDistinct.makeInvocationBindings(
            arguments: [
                // Supply out of order; the immutable packet canonicalizes by
                // the renderer's first-use logical order.
                second.argument(7),
                first.argument(7),
            ]
        )
        XCTAssertEqual(distinctPacket.bindingCount, 2)
        XCTAssertEqual(
            distinctPacket.bindings.map(\.slot.key),
            [first.declaration.key, second.declaration.key]
        )
        XCTAssertEqual(
            try preparedDistinct.fetchExactlyOneValues(bindings: distinctPacket),
            [.integer(7), .integer(7)]
        )
    }

    func testContextualDateUUIDAndCollectionUseStorageConstrainedCodecs() throws {
        let codecs = makeContextualCodecs()
        let registry = try XLValueCodecRegistry()
            .registering(codecs.dateInteger)
            .registering(codecs.dateText)
            .registering(codecs.uuidText)
            .registering(codecs.uuidArrayJSON)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let fixture = try makeQueryCaptureDatabase(configuration: configuration)
        defer { fixture.tearDown() }

        // Date has two registered representations and no default. The String
        // SQL expression constrains inference to the unique TEXT codec.
        let date = try fixture.database.queryCapture(
            Date.self,
            expressedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["contextual", "date"])
        )
        let uuid = try fixture.database.queryCapture(
            UUID.self,
            expressedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["contextual", "uuid"])
        )
        let collection = try fixture.database.queryCapture(
            [UUID].self,
            expressedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["contextual", "uuids"])
        )
        XCTAssertEqual(date.declaration.codecIdentity?.key, codecs.dateText.identity.key)

        let encoding = try customEncoding(
            sql: "SELECT :\(try namedKey(date)), :\(try namedKey(uuid)), value FROM json_each(:\(try namedKey(collection)))"
        ) { builder in
            date.makeSQL(context: &builder)
            uuid.makeSQL(context: &builder)
            collection.makeSQL(context: &builder)
        }
        let descriptor = try descriptor(
            definition: ["tests", "query-capture", "contextual-collection"],
            encoding: encoding,
            parameters: [
                date.staticQueryParameter(in: encoding),
                uuid.staticQueryParameter(in: encoding),
                collection.staticQueryParameter(in: encoding),
            ],
            resultStorage: [.text, .text, .text],
            cardinality: .many
        )
        let prepared = try fixture.database.prepareInvocation(with: descriptor)
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_123)
        let expectedUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let values = [
            UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!,
        ]
        let packet = try prepared.makeInvocationBindings {
            try $0.bind(values, to: collection)
            try $0.bind(expectedUUID, to: uuid)
            try $0.bind(expectedDate, to: date)
        }

        XCTAssertEqual(packet.bindingCount, 3)
        XCTAssertEqual(
            packet.bindings.map { $0.slot.codecIdentity?.key },
            [
                codecs.dateText.identity.key,
                codecs.uuidText.identity.key,
                codecs.uuidArrayJSON.identity.key,
            ]
        )
        let rows = try prepared.fetchAllValues(bindings: packet)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0[0] }, Array(
            repeating: .text(String(expectedDate.timeIntervalSince1970)),
            count: 2
        ))
        XCTAssertEqual(rows.map { $0[1] }, Array(
            repeating: .text(expectedUUID.uuidString.lowercased()),
            count: 2
        ))
        XCTAssertEqual(
            rows.map { $0[2] },
            values.map { .text($0.uuidString.lowercased()) }
        )
        // A collection remains one scalar logical parameter. Runtime size does
        // not alter SQL text, placeholder count, or static query identity.
        XCTAssertEqual(prepared.parameterLayout.count, 3)
    }

    func testTypedColumnCaptureExecutesWithFreshImmutableArguments() throws {
        let codecs = makeContextualCodecs()
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(codecs.dateInteger)
                .registering(codecs.dateText)
        )
        let fixture = try makeQueryCaptureDatabase(configuration: configuration)
        defer { fixture.tearDown() }
        let firstDate = Date(timeIntervalSince1970: 1_700_000_111)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_222)
        try fixture.database.databasePool.write { database in
            try database.execute(
                sql: "CREATE TABLE QueryCaptureDateRecord (storedDate TEXT NOT NULL)"
            )
            try database.execute(
                sql: "INSERT INTO QueryCaptureDateRecord (storedDate) VALUES (?), (?)",
                arguments: [
                    String(firstDate.timeIntervalSince1970),
                    String(secondDate.timeIntervalSince1970),
                ]
            )
        }

        let schema = XLSchema()
        let record = schema.table(QueryCaptureDateRecord.self)
        let capture = try fixture.database.queryCapture(
            Date.self,
            matching: record.storedDate,
            identifiedBy: XLQuerySlotIdentity(
                path: ["typed-column", "stored-date"]
            )
        )
        let expression = select(record.storedDate)
            .from(record)
            .where(record.storedDate == capture)
        let encoding = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(expression)
        let queryDescriptor = try descriptor(
            definition: ["tests", "query-capture", "typed-column"],
            encoding: encoding,
            parameters: [capture.staticQueryParameter(in: encoding)],
            resultStorage: [.text]
        )
        let prepared = try fixture.database.prepareInvocation(
            with: queryDescriptor
        )
        let stableIdentity = prepared.identity

        let firstPacket = try prepared.makeInvocationBindings(
            capture.argument(firstDate)
        )
        XCTAssertEqual(
            try prepared.fetchExactlyOneValues(bindings: firstPacket),
            [.text(String(firstDate.timeIntervalSince1970))]
        )
        let secondPacket = try prepared.makeInvocationBindings(
            capture.argument(secondDate)
        )
        XCTAssertEqual(
            try prepared.fetchExactlyOneValues(bindings: secondPacket),
            [.text(String(secondDate.timeIntervalSince1970))]
        )

        XCTAssertEqual(prepared.identity, stableIdentity)
        XCTAssertEqual(prepared.parameterLayout.count, 1)
        XCTAssertEqual(capture.storageIdentifier.rawValue, "text")
        XCTAssertEqual(capture.declaration.codecIdentity, codecs.dateText.identity)
        XCTAssertNotEqual(firstPacket.bindings[0].value, secondPacket.bindings[0].value)
    }

    func testBuilderReportsMissingDuplicateAndForeignCaptures() throws {
        let fixture = try makeQueryCaptureDatabase()
        defer { fixture.tearDown() }
        let capture = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["diagnostic", "value"])
        )
        let prepared = try prepareScalar(
            capture: capture,
            database: fixture.database,
            definition: ["tests", "query-capture", "diagnostics"]
        )

        XCTAssertThrowsError(try prepared.makeInvocationBindings { _ in }) {
            error in
            guard case .missingBindings(let slots) =
                    error as? XLInvocationBindingError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(slots.map(\.key), [capture.declaration.key])
        }
        XCTAssertThrowsError(try prepared.makeInvocationBindings {
            try $0.bind(1, to: capture)
            try $0.bind(2, to: capture)
        }) { error in
            guard case .duplicateBinding(let slot) =
                    error as? XLInvocationBindingError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(slot.key, capture.declaration.key)
        }

        let missing = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["diagnostic", "missing"])
        )
        XCTAssertThrowsError(try prepared.makeInvocationBindings {
            try $0.bind(1, to: missing)
        }) { error in
            guard case .parameterNotFound(_, let identity) =
                    error as? GRDBStaticQueryError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(identity, missing.identity)
        }

        let conflicting = try XLQueryCapture<String, String, XLSQLiteDialect>
            .intrinsic(identifiedBy: capture.identity)
        XCTAssertThrowsError(try prepared.makeInvocationBindings {
            try $0.bind("wrong", to: conflicting)
        }) { error in
            XCTAssertEqual(
                error as? XLQueryCaptureError,
                .descriptorMetadataMismatch(
                    query: prepared.identity,
                    identity: capture.identity,
                    expectedSlot: prepared.parameterLayout.slots[0],
                    expectedStorage: capture.storageIdentifier,
                    actualDeclaration: conflicting.declaration,
                    actualStorage: conflicting.storageIdentifier
                )
            )
        }
    }

    func testIntrinsicDoubleRejectsValuesSQLiteWouldNormalizeToNull() throws {
        let fixture = try makeQueryCaptureDatabase()
        defer { fixture.tearDown() }
        let capture = try XLQueryCapture<Double, Double, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["diagnostic", "real"])
            )
        let prepared = try prepareScalar(
            capture: capture,
            database: fixture.database,
            definition: ["tests", "query-capture", "non-finite"]
        )

        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try prepared.makeInvocationBindings {
                try $0.bind(value, to: capture)
            }) { error in
                guard case .nonFiniteReal(let identity, _) =
                        error as? XLQueryCaptureError else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(identity, capture.identity)
            }
        }
    }

    func testPreparedCaptureBuildsFreshPacketsConcurrently() async throws {
        let fixture = try makeQueryCaptureDatabase()
        defer { fixture.tearDown() }
        let capture = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["concurrent", "value"])
        )
        let prepared = try prepareScalar(
            capture: capture,
            database: fixture.database,
            definition: ["tests", "query-capture", "concurrent"]
        )

        let results = try await withThrowingTaskGroup(
            of: Int64.self,
            returning: [Int64].self
        ) { group in
            for value in 0 ..< 32 {
                group.addTask {
                    let packet = try prepared.makeInvocationBindings(
                        capture.argument(value)
                    )
                    guard packet.bindingCount == 1,
                          case .integer(let result) = try prepared
                            .fetchExactlyOneValues(bindings: packet)[0] else {
                        throw QueryCaptureFixtureError.invalidValue
                    }
                    return result
                }
            }
            var values: [Int64] = []
            for try await value in group {
                values.append(value)
            }
            return values.sorted()
        }
        XCTAssertEqual(results, (0 ..< 32).map(Int64.init))
    }

    func testInvocationUsesPreparedCodecSnapshotNotCaptureFactoryCodec() throws {
        let factoryProbe = QueryCaptureEncodingProbe()
        let preparedProbe = QueryCaptureEncodingProbe()
        let factoryCodec = snapshotTokenCodec(probe: factoryProbe)
        let preparedCodec = snapshotTokenCodec(probe: preparedProbe)
        XCTAssertEqual(factoryCodec.identity, preparedCodec.identity)
        let factoryConfiguration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(factoryCodec)
        )
        let preparedConfiguration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(preparedCodec)
        )
        let capture = try factoryConfiguration.queryCapture(
            SnapshotToken.self,
            expressedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["snapshot", "token"]),
            using: XLSQLiteDialect()
        )
        let queryDescriptor = try scalarDescriptor(
            capture: capture,
            definition: ["tests", "query-capture", "prepared-snapshot"]
        )
        let preparedFixture = try makeQueryCaptureDatabase(
            configuration: preparedConfiguration
        )
        defer { preparedFixture.tearDown() }
        let prepared = try preparedFixture.database.prepareInvocation(
            with: queryDescriptor
        )

        let packet = try prepared.makeInvocationBindings {
            try $0.bind(SnapshotToken(value: "prepared"), to: capture)
        }
        XCTAssertEqual(packet.bindings.map(\.value), [.text("prepared")])
        XCTAssertEqual(factoryProbe.count, 0)
        XCTAssertEqual(preparedProbe.count, 1)
        XCTAssertThrowsError(try prepared.makeInvocationBindings {
            try $0.bind(SnapshotToken(value: "first"), to: capture)
            try $0.bind(SnapshotToken(value: "duplicate"), to: capture)
        }) { error in
            guard case .duplicateBinding = error as? XLInvocationBindingError else {
                return XCTFail("Unexpected duplicate error: \(error)")
            }
        }
        XCTAssertEqual(
            preparedProbe.count,
            2,
            "Duplicate preflight must not invoke contextual codec logic"
        )

        let missingFixture = try makeQueryCaptureDatabase()
        defer { missingFixture.tearDown() }
        XCTAssertThrowsError(try missingFixture.database.prepareInvocation(
            with: queryDescriptor
        )) { error in
            guard case .preparedCodecUnavailable =
                    error as? XLInvocationBindingError else {
                return XCTFail("Unexpected missing-codec error: \(error)")
            }
        }

        let mismatchedCodec = snapshotTokenCodec(
            probe: QueryCaptureEncodingProbe(),
            valueTypeIdentifier: "tests.SnapshotToken.changed"
        )
        let mismatchedConfiguration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(mismatchedCodec)
        )
        let mismatchedFixture = try makeQueryCaptureDatabase(
            configuration: mismatchedConfiguration
        )
        defer { mismatchedFixture.tearDown() }
        XCTAssertThrowsError(try mismatchedFixture.database.prepareInvocation(
            with: queryDescriptor
        )) { error in
            guard case .preparedCodecIdentityMismatch =
                    error as? XLInvocationBindingError else {
                return XCTFail("Unexpected mismatched-codec error: \(error)")
            }
        }
    }
}


private enum QueryCaptureFixtureError: Error {
    case invalidValue
}


private struct QueryCaptureDatabaseFixture {
    let directory: URL
    let database: GRDBDatabase

    func tearDown() {
        try? database.databasePool.close()
        try? FileManager.default.removeItem(at: directory)
    }
}


private func makeQueryCaptureDatabase(
    configuration: XLValueCodingConfiguration? = nil
) throws -> QueryCaptureDatabaseFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-query-capture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    let database = try GRDBDatabase(
        databasePool: DatabasePool(
            path: directory.appendingPathComponent("database.sqlite").path
        ),
        codingConfiguration: try configuration ?? XLValueCodingConfiguration(),
        formatter: XLiteFormatter(),
        logger: nil
    )
    return QueryCaptureDatabaseFixture(directory: directory, database: database)
}


private func executeScalar<Input, Literal>(
    _ value: Input,
    capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>,
    database: GRDBDatabase,
    definition: [String]
) throws -> XLSQLiteValue where Literal: XLLiteral {
    let prepared = try prepareScalar(
        capture: capture,
        database: database,
        definition: definition
    )
    let packet = try prepared.makeInvocationBindings(capture.argument(value))
    XCTAssertEqual(packet.bindingCount, 1)
    return try prepared.fetchExactlyOneValues(bindings: packet)[0]
}


private func executeNullableScalar<Input, Wrapped>(
    _ value: Input?,
    capture: XLQueryCapture<Input, Wrapped?, XLSQLiteDialect>,
    database: GRDBDatabase,
    definition: [String]
) throws -> XLSQLiteValue where Wrapped: XLLiteral {
    let prepared = try prepareScalar(
        capture: capture,
        database: database,
        definition: definition
    )
    let packet = try prepared.makeInvocationBindings(capture.argument(value))
    return try prepared.fetchExactlyOneValues(bindings: packet)[0]
}


private func prepareScalar<Input, Literal>(
    capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>,
    database: GRDBDatabase,
    definition: [String]
) throws -> GRDBPreparedStaticQuery where Literal: XLLiteral {
    try database.prepareInvocation(
        with: scalarDescriptor(capture: capture, definition: definition)
    )
}


private func scalarDescriptor<Input, Literal>(
    capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>,
    definition: [String]
) throws -> XLStaticQueryDescriptor where Literal: XLLiteral {
    let encoding = try customEncoding(
        sql: "SELECT :\(try namedKey(capture))"
    ) { builder in
        capture.makeSQL(context: &builder)
    }
    let queryDescriptor = try descriptor(
        definition: definition,
        encoding: encoding,
        parameters: [capture.staticQueryParameter(in: encoding)],
        resultStorage: [XLSQLiteStorageClass(
            rawValue: capture.storageIdentifier.rawValue
        )!],
        resultNullability: [capture.declaration.nullability]
    )
    return queryDescriptor
}


private func descriptor(
    definition: [String],
    encoding: XLEncoding,
    parameters: [XLStaticQueryParameterMetadata],
    resultStorage: [XLSQLiteStorageClass],
    resultNullability: [XLParameterNullability]? = nil,
    cardinality: XLQueryCardinality = .exactlyOne
) throws -> XLStaticQueryDescriptor {
    let nullability = resultNullability
        ?? Array(repeating: .required, count: resultStorage.count)
    let results = try XLStaticQueryResultMetadata(slots: zip(
        resultStorage,
        nullability
    ).enumerated().map { index, pair in
        XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(index),
            identity: try XLQuerySlotIdentity(
                path: definition + ["result", String(index)]
            ),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.query-capture.result.\(pair.0.rawValue)"
            ),
            valueTypeName: pair.0.rawValue,
            nullability: pair.1,
            codecIdentity: nil,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: pair.0.rawValue
            ),
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath(definition + ["result", String(index)])
            )
        )
    })
    return try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: definition,
            version: 1
        ),
        statement: XLStaticStatementDefinition(validating: encoding),
        parameters: parameters,
        results: results,
        cardinality: cardinality
    )
}


private func customEncoding(
    sql: String,
    render: @escaping (inout XLBuilder) -> Void
) throws -> XLEncoding {
    let rendered = try XLiteEncoder(dialect: XLSQLiteDialect())
        .makeValidatedSQL(QueryCaptureLayoutProbe(render: render))
    return XLEncoding(
        sql: sql,
        entities: [],
        dialectRequirement: rendered.dialectRequirement,
        parameterLayout: rendered.parameterLayout,
        parameterLayoutError: rendered.parameterLayoutError
    )
}


private struct QueryCaptureLayoutProbe: XLEncodable {
    let render: (inout XLBuilder) -> Void

    func makeSQL(context: inout XLBuilder) {
        render(&context)
    }
}


private func namedKey<Input, Literal>(
    _ capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>
) throws -> String where Literal: XLLiteral {
    guard case .named(let name) = capture.declaration.key else {
        throw QueryCaptureFixtureError.invalidValue
    }
    return name
}


private func makeContextualCodecs() -> (
    dateText: XLValueCodec<Date, XLSQLiteDialect>,
    dateInteger: XLValueCodec<Date, XLSQLiteDialect>,
    uuidText: XLValueCodec<UUID, XLSQLiteDialect>,
    uuidArrayJSON: XLValueCodec<[UUID], XLSQLiteDialect>
) {
    let text = XLValueStorageIdentifier(rawValue: "text")
    let dateType = XLValueTypeIdentifier(rawValue: "foundation.Date")
    let dateText = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.query-capture.date-text", version: 1),
        valueTypeIdentifier: dateType,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: text,
        encode: { value, _, _ in
            .text(String(value.timeIntervalSince1970))
        },
        decode: { value, _, _ in
            guard case .text(let value) = value,
                  let seconds = TimeInterval(value) else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return Date(timeIntervalSince1970: seconds)
        }
    )
    let dateInteger = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.query-capture.date-integer", version: 1),
        valueTypeIdentifier: dateType,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
        encode: { value, _, _ in .integer(Int64(value.timeIntervalSince1970)) },
        decode: { value, _, _ in
            guard case .integer(let seconds) = value else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
    )
    let uuidText = XLValueCodec<UUID, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.query-capture.uuid-text", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.UUID"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: text,
        encode: { value, _, _ in .text(value.uuidString.lowercased()) },
        decode: { value, _, _ in
            guard case .text(let value) = value,
                  let uuid = UUID(uuidString: value) else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return uuid
        }
    )
    let uuidArrayJSON = XLValueCodec<[UUID], XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.query-capture.uuid-json", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "foundation.UUID-array"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: text,
        encode: { values, _, _ in
            let data = try JSONSerialization.data(
                withJSONObject: values.map { $0.uuidString.lowercased() }
            )
            guard let json = String(data: data, encoding: .utf8) else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return .text(json)
        },
        decode: { value, _, _ in
            guard case .text(let json) = value,
                  let data = json.data(using: .utf8),
                  let strings = try JSONSerialization.jsonObject(with: data)
                    as? [String] else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return try strings.map {
                guard let value = UUID(uuidString: $0) else {
                    throw QueryCaptureFixtureError.invalidValue
                }
                return value
            }
        }
    )
    return (dateText, dateInteger, uuidText, uuidArrayJSON)
}


private struct SnapshotToken {
    let value: String
}


private final class QueryCaptureEncodingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}


private func snapshotTokenCodec(
    probe: QueryCaptureEncodingProbe,
    valueTypeIdentifier: String = "tests.SnapshotToken"
) -> XLValueCodec<SnapshotToken, XLSQLiteDialect> {
    XLValueCodec(
        key: XLValueCodecKey(
            id: "tests.query-capture.snapshot-token",
            version: 1
        ),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: valueTypeIdentifier
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            probe.record()
            return .text(value.value)
        },
        decode: { value, _, _ in
            guard case .text(let value) = value else {
                throw QueryCaptureFixtureError.invalidValue
            }
            return SnapshotToken(value: value)
        }
    )
}
