import Foundation
import GRDB
import XCTest
@testable import SwiftQL


private enum StaticLayoutState: Equatable, Sendable {
    case ready
    case paused
}


private struct StaticLayoutMarker: Equatable, Sendable {
    let value: String
}


@SQLTable(name: "StaticLayoutRecord")
private struct StaticLayoutRecord: Equatable {
    let timestamp: Date
    let state: StaticLayoutState
    let note: Date?
    let left: StaticLayoutMarker
    let right: StaticLayoutMarker
}


@SQLResult
private struct EmptyStaticLayoutRow: Equatable {
}


@SQLTable(name: "StaticProjectionSource")
private struct StaticProjectionSource: Equatable {
    let raw: String
    let amount: Int
}


@SQLResult
private struct StaticProjectionRow: Equatable {
    let decorated: StaticLayoutMarker
    let incremented: Int
}


private struct ManualStaticLayoutRow: Equatable {
    let value: String
}


@SQLTable(name: "StaticStreamSource")
private struct StaticStreamSource: Equatable {
    let id: Int
}


private struct StaticStreamRow: Equatable {
    let id: Int
}


private struct _SwiftQLStaticDialect: Equatable, Sendable {
    let value: String
}


private struct StaticIdentifierBox<Value>: Equatable, Sendable
where Value: Equatable & Sendable {
    let value: Value
}


@SQLResult
private struct StaticPropertyTypeIdentifierCollisionRow: Equatable {
    let direct: _SwiftQLStaticDialect
    let nested: StaticIdentifierBox<_SwiftQLStaticDialect>
}


@SQLResult
private struct _swiftQLRowReader: Equatable {
    let value: String
}


// Compiles the generated layout factory against every reserved-looking name
// used by its deterministic allocator. Outer generic spellings must remain
// the property value types, while method generics and locals avoid shadowing.
@SQLResult
private struct StaticGeneratedNameCollision<
    Dialect,
    _SwiftQLStaticDialect,
    _SwiftQLStaticStorage0
> {
    let dialect: Dialect
    let staticDialect: _SwiftQLStaticDialect
    let storage: _SwiftQLStaticStorage0
    let _swiftQLStaticField0: String
    let _swiftQLStaticReader: String
    let _swiftQLStaticRow: String
}


private struct TrappingDefaultLiteral:
    Equatable,
    Sendable,
    XLExpression,
    XLLiteral
{
    typealias T = Self

    let rawValue: String

    static func sqlDefault() -> Self {
        fatalError("static layout construction called sqlDefault()")
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(reader: XLFieldReader) throws {
        self.rawValue = try reader.readText()
    }

    func bind(context: inout XLBindingContext) {
        context.bindText(value: rawValue)
    }

    func makeSQL(context: inout XLBuilder) {
        context.text(rawValue)
    }
}


@SQLResult
private struct TrappingDefaultRow: Equatable {
    let value: TrappingDefaultLiteral
}


final class StaticRowLayoutGRDBTests: XCTestCase {

    func testGeneratedLayoutPreservesConcretePropertyTypeIdentifiers() throws {
        let storage = XLValueStorageIdentifier(rawValue: "text")
        let directCodec = XLValueCodec<
            _SwiftQLStaticDialect,
            XLSQLiteDialect
        >(
            key: XLValueCodecKey(
                id: "tests.static-layout.identifier.direct",
                version: 1
            ),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.static-layout.identifier-direct"
            ),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storage,
            encode: { value, _, _ in .text("direct:\(value.value)") },
            decode: { value, _, _ in
                guard case .text(let text) = value,
                      text.hasPrefix("direct:") else {
                    throw StaticRowLayoutTestError.invalidValue
                }
                return _SwiftQLStaticDialect(
                    value: String(text.dropFirst("direct:".count))
                )
            }
        )
        let nestedCodec = XLValueCodec<
            StaticIdentifierBox<_SwiftQLStaticDialect>,
            XLSQLiteDialect
        >(
            key: XLValueCodecKey(
                id: "tests.static-layout.identifier.nested",
                version: 1
            ),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.static-layout.identifier-nested"
            ),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storage,
            encode: { value, _, _ in
                .text("nested:\(value.value.value)")
            },
            decode: { value, _, _ in
                guard case .text(let text) = value,
                      text.hasPrefix("nested:") else {
                    throw StaticRowLayoutTestError.invalidValue
                }
                return StaticIdentifierBox(
                    value: _SwiftQLStaticDialect(
                        value: String(text.dropFirst("nested:".count))
                    )
                )
            }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(directCodec)
                .registering(nestedCodec)
        )
        let dependency = XLSelectResultDependency()
        let layout = try StaticPropertyTypeIdentifierCollisionRow
            .staticRowLayout(
                using: XLSQLiteDialect.self,
                direct: configuration.staticResultField(
                    _SwiftQLStaticDialect.self,
                    selecting: XLColumnResult<_SwiftQLStaticDialect>(
                        dependency: dependency,
                        as: "direct"
                    ),
                    storedAs: String.self,
                    identifiedBy: XLQuerySlotIdentity(
                        path: ["identifier-collision", "direct"]
                    ),
                    using: XLSQLiteDialect(),
                    selection: .explicit(directCodec.identity.key)
                ),
                nested: configuration.staticResultField(
                    StaticIdentifierBox<_SwiftQLStaticDialect>.self,
                    selecting: XLColumnResult<
                        StaticIdentifierBox<_SwiftQLStaticDialect>
                    >(
                        dependency: dependency,
                        as: "nested"
                    ),
                    storedAs: String.self,
                    identifiedBy: XLQuerySlotIdentity(
                        path: ["identifier-collision", "nested"]
                    ),
                    using: XLSQLiteDialect(),
                    selection: .explicit(nestedCodec.identity.key)
                )
            )
        let expected = StaticPropertyTypeIdentifierCollisionRow(
            direct: _SwiftQLStaticDialect(value: "one"),
            nested: StaticIdentifierBox(
                value: _SwiftQLStaticDialect(value: "two")
            )
        )

        XCTAssertEqual(
            layout.metadata.fields.map(\.alias),
            ["direct", "nested"]
        )
        XCTAssertEqual(
            try layout.encode(expected),
            [.text("direct:one"), .text("nested:two")]
        )
        XCTAssertEqual(
            try layout.decode([.text("direct:one"), .text("nested:two")]),
            expected
        )
    }

    func testGeneratedLegacyReaderReservesNominalTypeIdentifier() throws {
        let expression = XLColumnResult<String>(
            dependency: XLSelectResultDependency(),
            as: "value"
        )
        let generated = _swiftQLRowReader.SQLReader(value: expression)
        let reader = XLColumnValuesRowReader<_swiftQLRowReader>()
        reader.reset(
            reader: XLSQLiteValueReader(values: [.text("round-trip")])
        )

        XCTAssertEqual(
            try generated.readRow(reader: reader),
            _swiftQLRowReader(value: "round-trip")
        )
    }

    func testGeneratedResultLayoutProjectsComputedAliasesWithCapturedInvocation() throws {
        let fixture = try StaticRowLayoutFixture()
        defer { fixture.tearDown() }

        let markerCodec = makeStaticLayoutCodecs().left
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(markerCodec)
        )
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE StaticProjectionSource (
                        raw TEXT NOT NULL,
                        amount INTEGER NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO StaticProjectionSource (raw, amount)
                    VALUES ('left:other', 3), ('left:same', 7)
                    """
            )
        }

        let table = XLSchema().table(
            StaticProjectionSource.self,
            as: "projection"
        )
        let decoratedField = try configuration.staticResultField(
            StaticLayoutMarker.self,
            selecting: table.raw + "-projected",
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(
                path: ["static-layout", "decorated"]
            ),
            using: database.dialect,
            selection: .explicit(markerCodec.identity.key)
        )
        let layout = try StaticProjectionRow.staticRowLayout(
            using: XLSQLiteDialect.self,
            decorated: decoratedField,
            incremented: XLStaticSelectField<
                Int,
                Int,
                XLSQLiteDialect
            >.intrinsic(
                selecting: table.amount + 1,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "incremented"]
                )
            )
        )
        let markerCapture = try database.queryCapture(
            StaticLayoutMarker.self,
            matching: decoratedField.expression,
            identifiedBy: XLQuerySlotIdentity(
                path: ["static-layout", "matching-marker"]
            ),
            selection: decoratedField.codecSelection
        )

        XCTAssertEqual(
            layout.metadata.fields.map(\.alias),
            ["decorated", "incremented"]
        )
        XCTAssertEqual(
            layout.metadata.fields.map(\.result.codecIdentity?.key),
            [markerCodec.identity.key, nil]
        )
        XCTAssertEqual(
            markerCapture.storageIdentifier,
            decoratedField.storageIdentifier
        )
        XCTAssertEqual(
            markerCapture.declaration.codecIdentity,
            decoratedField.selectedCodecIdentity
        )

        let statement = sql { _ in
            Select(layout)
            From(table)
            Where(table.raw == markerCapture)
        }
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(statement)
        XCTAssertTrue(
            encoding.sql.contains(
                "(\"projection\".\"raw\" || '-projected') AS \"decorated\""
            )
        )
        XCTAssertTrue(
            encoding.sql.contains(
                "(\"projection\".\"amount\" + 1) AS \"incremented\""
            )
        )

        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-layout", "captured-projection"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [
                try markerCapture.staticQueryParameter(in: encoding),
            ],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let prepared = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: descriptor,
                layout: layout
            )
        )
        let bindings = try prepared.makeInvocationBindings(
            markerCapture.argument(StaticLayoutMarker(value: "same"))
        )

        XCTAssertEqual(prepared.parameterLayout.count, 1)
        XCTAssertEqual(bindings.bindingCount, 1)
        XCTAssertEqual(
            try prepared.fetchExactlyOne(bindings: bindings),
            StaticProjectionRow(
                decorated: StaticLayoutMarker(value: "same-projected"),
                incremented: 8
            )
        )
    }

    func testGeneratedLayoutRoundTripsPlainValuesWithDistinctPerFieldCodecs() throws {
        let fixture = try StaticRowLayoutFixture()
        defer { fixture.tearDown() }

        let codecs = makeStaticLayoutCodecs()
        let registry = try XLValueCodecRegistry()
            .registering(codecs.date)
            .registering(codecs.state)
            .registering(codecs.left)
            .registering(codecs.right)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )

        let schema = XLSchema()
        let table = schema.table(StaticLayoutRecord.self, as: "record")
        let dialect = database.dialect
        let layout = try StaticLayoutRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            timestamp: configuration.staticResultField(
                Date.self,
                selecting: table.timestamp,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "when"]
                ),
                using: dialect,
                selection: .explicit(codecs.date.identity.key)
            ),
            state: configuration.staticResultField(
                StaticLayoutState.self,
                selecting: table.state,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "state"]
                ),
                using: dialect,
                selection: .explicit(codecs.state.identity.key)
            ),
            note: configuration.staticResultField(
                Date?.self,
                selecting: table.note,
                storedAs: String?.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "note"]
                ),
                using: dialect,
                selection: .explicit(codecs.date.identity.key)
            ),
            left: configuration.staticResultField(
                StaticLayoutMarker.self,
                selecting: table.left,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "left"]
                ),
                using: dialect,
                selection: .explicit(codecs.left.identity.key)
            ),
            right: configuration.staticResultField(
                StaticLayoutMarker.self,
                selecting: table.right,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["static-layout", "right"]
                ),
                using: dialect,
                selection: .explicit(codecs.right.identity.key)
            )
        )

        let expected = StaticLayoutRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_123),
            state: .ready,
            note: nil,
            left: StaticLayoutMarker(value: "same"),
            right: StaticLayoutMarker(value: "same")
        )
        let encoded = try layout.encode(expected)
        XCTAssertEqual(
            encoded,
            [
                .text("1700000123"),
                .text("ready"),
                .null,
                .text("left:same"),
                .text("right:same"),
            ]
        )
        XCTAssertEqual(
            layout.metadata.fields.map(\.result.codecIdentity?.key),
            [
                codecs.date.identity.key,
                codecs.state.identity.key,
                codecs.date.identity.key,
                codecs.left.identity.key,
                codecs.right.identity.key,
            ]
        )
        XCTAssertEqual(
            layout.metadata.fields.map(\.alias),
            ["timestamp", "state", "note", "left", "right"]
        )

        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE StaticLayoutRecord (
                        timestamp TEXT NOT NULL,
                        state TEXT NOT NULL,
                        note TEXT,
                        left TEXT NOT NULL,
                        right TEXT NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO StaticLayoutRecord
                        (timestamp, state, note, left, right)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: StatementArguments(
                    encoded.map(\.databaseValue)
                )
            )
        }

        let statement = sql { _ in
            Select(layout)
            From(table)
        }
        let encoding = try XLiteEncoder(dialect: dialect)
            .makeValidatedSQL(statement)
        XCTAssertEqual(
            encoding.sql,
            "SELECT \"record\".\"timestamp\" AS \"timestamp\", \"record\".\"state\" AS \"state\", \"record\".\"note\" AS \"note\", \"record\".\"left\" AS \"left\", \"record\".\"right\" AS \"right\" FROM \"StaticLayoutRecord\" AS \"record\""
        )

        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-layout", "plain-values"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .many
        )
        let typed = try XLTypedStaticQueryDescriptor(
            descriptor: descriptor,
            layout: layout
        )
        let prepared = try database.prepareInvocation(with: typed)
        let bindings = try prepared.makeInvocationBindings()

        XCTAssertEqual(try prepared.fetchAll(bindings: bindings), [expected])
    }

    func testTypedStaticFetchAllStopsSteppingAtMiddleRowDecodeFailure() throws {
        let probe = StaticRowLayoutStepProbe()
        var poolConfiguration = Configuration()
        poolConfiguration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    StaticRowLayoutStepProbe.functionName,
                    argumentCount: 1
                ) { values in
                    probe.observe(values[0])
                }
            )
        }
        let fixture = try StaticRowLayoutFixture(
            configuration: poolConfiguration
        )
        defer { fixture.tearDown() }

        try fixture.pool.write { database in
            try database.execute(
                sql: "CREATE TABLE StaticStreamSource (id INTEGER PRIMARY KEY)"
            )
            try database.execute(
                sql: "INSERT INTO StaticStreamSource (id) VALUES (1), (2), (3)"
            )
        }

        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: XLValueCodingConfiguration(),
            formatter: XLiteFormatter(),
            logger: nil
        )
        let table = XLSchema().table(StaticStreamSource.self, as: "source")
        let field = try XLStaticSelectField<
            Int,
            Int,
            XLSQLiteDialect
        >.intrinsic(
            selecting: XLFunction<Int>(
                name: StaticRowLayoutStepProbe.functionName,
                parameters: [table.id]
            ),
            identifiedBy: XLQuerySlotIdentity(
                path: ["static-layout", "streamed-id"]
            )
        ).positioned(at: 0, alias: "id")
        let layout = try XLStaticRowLayout<
            StaticStreamRow,
            XLSQLiteDialect
        >(
            fields: [try field.erased()],
            decode: { reader in
                let id = try field.read(from: reader)
                guard id != 2 else {
                    throw StaticRowLayoutTestError.decodeRejected
                }
                return StaticStreamRow(id: id)
            },
            encode: { [.integer(Int64($0.id))] }
        )
        let statement = sql { _ in
            Select(layout)
            From(table)
            OrderBy(table.id.ascending())
        }
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(statement)
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-layout", "streaming-decode-failure"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .many
        )
        let prepared = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: descriptor,
                layout: layout
            )
        )

        XCTAssertThrowsError(
            try prepared.fetchAll(
                bindings: prepared.makeInvocationBindings()
            )
        ) { error in
            XCTAssertEqual(
                error as? StaticRowLayoutTestError,
                .decodeRejected
            )
        }
        XCTAssertEqual(probe.invocationCount, 2)
        XCTAssertEqual(
            try fixture.pool.read { database in
                try Int.fetchOne(database, sql: "SELECT 42")
            },
            42
        )
    }

    func testGeneratedConstructionCallsNeitherSQLDefaultNorDecodeInitializer() throws {
        let key = XLValueCodecKey(
            id: "tests.static-layout.trapping",
            version: 1
        )
        let codec = XLValueCodec<TrappingDefaultLiteral, XLSQLiteDialect>(
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.trapping-default"
            ),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
            encode: { value, _, _ in .text(value.rawValue) },
            decode: { value, _, _ in
                guard case .text(let text) = value else {
                    throw StaticRowLayoutTestError.invalidValue
                }
                return TrappingDefaultLiteral(rawValue: text)
            }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec)
        )
        let dependency = XLSelectResultDependency()
        let expression = XLColumnResult<TrappingDefaultLiteral>(
            dependency: dependency,
            as: "value"
        )
        var decodeCount = 0
        let field = try configuration.staticResultField(
            TrappingDefaultLiteral.self,
            selecting: expression,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(
                path: ["static-layout", "trapping-value"]
            ),
            using: XLSQLiteDialect(),
            selection: .explicit(key)
        )
        let generated = try TrappingDefaultRow.staticRowLayout(
            using: XLSQLiteDialect.self,
            value: field
        )
        let positioned = field.positioned(at: 0, alias: "value")
        let observed = try XLStaticRowLayout<
            TrappingDefaultRow,
            XLSQLiteDialect
        >(
            fields: [try positioned.erased()],
            decode: { reader in
                decodeCount += 1
                return TrappingDefaultRow(
                    value: try positioned.read(from: reader)
                )
            },
            encode: { row in [try positioned.encode(row.value)] }
        )

        _ = Select(generated)
        let encoding = XLiteEncoder(dialect: XLSQLiteDialect()).makeSQL(
            Select(observed)
        )

        XCTAssertEqual(encoding.sql, "SELECT \"value\" AS \"value\"")
        XCTAssertEqual(decodeCount, 0)
        XCTAssertEqual(
            try observed.decode([.text("decoded")]),
            TrappingDefaultRow(
                value: TrappingDefaultLiteral(rawValue: "decoded")
            )
        )
        XCTAssertEqual(decodeCount, 1)
    }

    func testGeneratedEmptyLayoutIsValueFreeUntilDecode() throws {
        let layout = try EmptyStaticLayoutRow.staticRowLayout(
            using: XLSQLiteDialect.self
        )

        XCTAssertTrue(layout.metadata.fields.isEmpty)
        XCTAssertEqual(try layout.encode(EmptyStaticLayoutRow()), [])
        _ = Select(layout)
        XCTAssertEqual(try layout.decode([]), EmptyStaticLayoutRow())
    }

    func testManualLayoutClosuresCannotBypassFieldValidation() throws {
        let positioned = try XLStaticSelectField<
            String,
            String,
            XLSQLiteDialect
        >.intrinsic(
            selecting: XLColumnResult<String>(
                dependency: XLSelectResultDependency(),
                as: "value"
            ),
            identifiedBy: XLQuerySlotIdentity(
                path: ["static-layout", "manual-validation"]
            )
        ).positioned(at: 0, alias: "value")
        let erased = try positioned.erased()
        let layout = try XLStaticRowLayout<
            ManualStaticLayoutRow,
            XLSQLiteDialect
        >(
            fields: [erased],
            decode: { _ in ManualStaticLayoutRow(value: "ignored") },
            encode: { _ in [.integer(1)] }
        )

        XCTAssertThrowsError(try layout.decode([.null])) { error in
            XCTAssertEqual(
                error as? XLStaticRowLayoutError,
                .nullForRequiredField(field: erased.metadata)
            )
        }
        XCTAssertThrowsError(
            try layout.encode(ManualStaticLayoutRow(value: "ignored"))
        ) { error in
            XCTAssertEqual(
                error as? XLStaticRowLayoutError,
                .storageMismatch(
                    field: erased.metadata,
                    actual: XLValueStorageIdentifier(rawValue: "integer")
                )
            )
        }
    }
}


private enum StaticRowLayoutTestError: Error, Equatable {
    case invalidValue
    case decodeRejected
}


private struct StaticRowLayoutFixture {
    let url: URL
    let pool: DatabasePool

    init(configuration: Configuration = Configuration()) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        pool = try DatabasePool(
            path: url.path,
            configuration: configuration
        )
    }

    func tearDown() {
        try? pool.close()
        try? FileManager.default.removeItem(at: url)
    }
}


private final class StaticRowLayoutStepProbe: @unchecked Sendable {

    static let functionName = "swiftql_static_row_layout_step_probe"

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


private func makeStaticLayoutCodecs() -> (
    date: XLValueCodec<Date, XLSQLiteDialect>,
    state: XLValueCodec<StaticLayoutState, XLSQLiteDialect>,
    left: XLValueCodec<StaticLayoutMarker, XLSQLiteDialect>,
    right: XLValueCodec<StaticLayoutMarker, XLSQLiteDialect>
) {
    let storage = XLValueStorageIdentifier(rawValue: "text")
    let date = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.static-layout.date", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.date"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: storage,
        encode: { value, _, _ in
            .text(String(Int64(value.timeIntervalSince1970)))
        },
        decode: { value, _, _ in
            guard case .text(let text) = value,
                  let seconds = TimeInterval(text) else {
                throw StaticRowLayoutTestError.invalidValue
            }
            return Date(timeIntervalSince1970: seconds)
        }
    )
    let state = XLValueCodec<StaticLayoutState, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.static-layout.state", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "tests.static-layout-state"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: storage,
        encode: { value, _, _ in
            .text(value == .ready ? "ready" : "paused")
        },
        decode: { value, _, _ in
            guard case .text(let text) = value else {
                throw StaticRowLayoutTestError.invalidValue
            }
            switch text {
            case "ready": return .ready
            case "paused": return .paused
            default: throw StaticRowLayoutTestError.invalidValue
            }
        }
    )
    func markerCodec(
        key: String,
        prefix: String
    ) -> XLValueCodec<StaticLayoutMarker, XLSQLiteDialect> {
        XLValueCodec(
            key: XLValueCodecKey(id: key, version: 1),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.static-layout-marker"
            ),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storage,
            encode: { value, _, _ in
                .text("\(prefix):\(value.value)")
            },
            decode: { value, _, _ in
                guard case .text(let text) = value,
                      text.hasPrefix("\(prefix):") else {
                    throw StaticRowLayoutTestError.invalidValue
                }
                return StaticLayoutMarker(
                    value: String(text.dropFirst(prefix.count + 1))
                )
            }
        )
    }
    return (
        date,
        state,
        markerCodec(key: "tests.static-layout.marker.left", prefix: "left"),
        markerCodec(key: "tests.static-layout.marker.right", prefix: "right")
    )
}
