import Foundation
import GRDB
import XCTest
@testable import SwiftQL
import SwiftQLSQLiteConformanceFixtures


@SQLTable(name: "CodecSnapshotRecord")
private struct CodecSnapshotRecord: Equatable {
    let id: Int
}


final class ContextualValueCodecGRDBTests: XCTestCase {

    func testTwoRawDateCodecsRoundTripThroughSQLiteWithDeclaredStorage() throws {
        XCTAssertFalse(hasVisibleV1LiteralConformance(Date.self))

        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let codecs = makeDateCodecs()
        let registry = try XLValueCodecRegistry()
            .registering(codecs.text)
            .registering(codecs.integer)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry
        )
        let database = try GRDBDatabase(
            databasePool: fixture.databasePool,
            codingConfiguration: codingConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        var driver = GRDBDatabaseDriver(
            databasePool: database.databasePool,
            dialect: database.dialect
        )
        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        let textContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["coded_dates", "text_value"])
        )
        let integerContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["coded_dates", "integer_value"])
        )

        // Contextual conversion happens before the adapter-neutral driver sees
        // either value. No Date wrapper or retroactive conformance is involved.
        let textParameterCodec = try database.codingConfiguration.resolvedCodec(
            for: Date.self,
            using: database.dialect,
            context: textContext,
            selection: XLValueCodecSelection(explicitCodecKey: codecs.text.identity.key)
        )
        let integerParameterCodec = try database.codingConfiguration.resolvedCodec(
            for: Date.self,
            using: database.dialect,
            context: integerContext,
            selection: XLValueCodecSelection(explicitCodecKey: codecs.integer.identity.key)
        )
        let textValue = try textParameterCodec.encode(expected)
        let integerValue = try integerParameterCodec.encode(expected)
        let createStatement = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE coded_dates (
                    text_value TEXT NOT NULL,
                    integer_value INTEGER NOT NULL
                )
                """
        )
        let insertStatement = logicalStatement(
            for: driver,
            sql: """
                INSERT INTO coded_dates (text_value, integer_value)
                VALUES (:text_value, :integer_value)
                """
        )
        let selectStatement = logicalStatement(
            for: driver,
            sql: """
                SELECT
                    text_value,
                    integer_value,
                    typeof(text_value),
                    typeof(integer_value)
                FROM coded_dates
                """
        )

        try driver.withWriteConnection { connection in
            try connection.execute(
                connection.prepare(createStatement)
            )

            var insert = try connection.prepare(insertStatement)
            insert = try connection.bind(
                textValue,
                to: .named("text_value"),
                in: insert
            )
            insert = try connection.bind(
                integerValue,
                to: .named("integer_value"),
                in: insert
            )
            try connection.execute(insert)
        }

        let normalized = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(
                    connection.prepare(selectStatement)
                )
            )
        }

        XCTAssertEqual(normalized[0], textValue)
        XCTAssertEqual(normalized[1], integerValue)
        XCTAssertEqual(normalized[2], .text("text"))
        XCTAssertEqual(normalized[3], .text("integer"))

        // Decoding starts only after GRDB has normalized SQLite storage into
        // dialect values, so both codec storage checks run at the same boundary.
        let textResultCodec = try database.codingConfiguration.resolvedCodec(
            for: Date.self,
            using: database.dialect,
            context: XLValueCodingContext(
                site: .result,
                path: textContext.path
            ),
            selection: XLValueCodecSelection(explicitCodecKey: codecs.text.identity.key)
        )
        let integerResultCodec = try database.codingConfiguration.resolvedCodec(
            for: Date.self,
            using: database.dialect,
            context: XLValueCodingContext(
                site: .result,
                path: integerContext.path
            ),
            selection: XLValueCodecSelection(explicitCodecKey: codecs.integer.identity.key)
        )
        let decodedText = try textResultCodec.decode(normalized[0])
        let decodedInteger = try integerResultCodec.decode(normalized[1])

        XCTAssertEqual(decodedText, expected)
        XCTAssertEqual(decodedInteger, expected)
    }

    func testDatabaseAndRequestsKeepImmutableConfigurationSnapshot() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let codecs = makeDateCodecs()
        let originalRegistry = try XLValueCodecRegistry()
            .registering(codecs.text)
        let originalConfiguration = try XLValueCodingConfiguration(
            registry: originalRegistry,
            defaultCodecKeys: [codecs.text.identity.key]
        )
        let database = try GRDBDatabase(
            databasePool: fixture.databasePool,
            codingConfiguration: originalConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )

        let query = sql { schema in
            let record = schema.table(CodecSnapshotRecord.self)
            Select(record)
            From(record)
        }
        let queryRequest = try XCTUnwrap(
            database.makeRequest(with: query) as? GRDBRequest<CodecSnapshotRecord>
        )
        let writeRequest = try XCTUnwrap(
            database.makeRequest(
                with: sqlCreate(CodecSnapshotRecord.self)
            ) as? GRDBWriteRequest
        )

        // Registry/configuration derivation is copy-on-write. It cannot mutate
        // the database or request snapshots that already captured the original.
        let derivedRegistry = try originalRegistry.registering(codecs.integer)
        let derivedConfiguration = try XLValueCodingConfiguration(
            registry: derivedRegistry,
            defaultCodecKeys: [codecs.integer.identity.key]
        )
        XCTAssertEqual(
            derivedConfiguration.registry.identities.map(\.key),
            [codecs.integer.identity.key, codecs.text.identity.key].sorted(by: codecKeyOrder)
        )

        for snapshot in [
            database.codingConfiguration,
            queryRequest.codingConfiguration,
            writeRequest.codingConfiguration,
        ] {
            XCTAssertEqual(snapshot.registry.identities.map(\.key), [codecs.text.identity.key])
            XCTAssertEqual(snapshot.defaultCodecKeys, [codecs.text.identity.key])
        }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath("concurrent")
        )
        let snapshot = database.codingConfiguration
        let resolvedSnapshot = try snapshot.resolvedCodec(
            for: Date.self,
            using: XLSQLiteDialect(),
            context: context
        )
        let storageClasses = try await withThrowingTaskGroup(
            of: XLSQLiteStorageClass.self,
            returning: [XLSQLiteStorageClass].self
        ) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    try resolvedSnapshot.encode(date).storageType
                }
            }
            var results: [XLSQLiteStorageClass] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(storageClasses.count, 32)
        XCTAssertTrue(storageClasses.allSatisfy { $0 == .text })
        let derivedSnapshot = try derivedConfiguration.resolvedCodec(
            for: Date.self,
            using: XLSQLiteDialect(),
            context: context
        )
        XCTAssertEqual(try derivedSnapshot.encode(date).storageType, .integer)
    }

    func testV1LiteralAdapterPreservesLegacyBindingAndReading() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let key = XLValueCodecKey(id: "test.legacy-epoch", version: 1)
        let adapter = XLV1LiteralCodec<LegacyEpoch>(
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "test.LegacyEpoch"),
            storageClass: .integer
        )
        let registry = try XLValueCodecRegistry().registering(adapter.codec)
        let configuration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [key]
        )
        let context = XLValueCodingContext(
            site: .property,
            path: XLValueCodingPath("legacy_epoch")
        )

        let encoded = try configuration.encode(
            LegacyEpoch(value: 42),
            using: XLSQLiteDialect(),
            context: context
        )
        XCTAssertEqual(encoded, .integer(42))
        XCTAssertEqual(
            try configuration.decode(
                LegacyEpoch.self,
                from: encoded,
                using: XLSQLiteDialect(),
                context: context
            ),
            LegacyEpoch(value: 42)
        )

        let incorrectlyDeclared = XLV1LiteralCodec<LegacyEpoch>(
            key: XLValueCodecKey(id: "test.legacy-epoch-text", version: 1),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "test.LegacyEpoch"),
            storageClass: .text
        )
        let invalidConfiguration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(incorrectlyDeclared.codec),
            defaultCodecKeys: [incorrectlyDeclared.codec.identity.key]
        )
        XCTAssertThrowsError(
            try invalidConfiguration.encode(
                LegacyEpoch(value: 42),
                using: XLSQLiteDialect(),
                context: context
            )
        ) { error in
            guard case .storageMismatch? = error as? XLValueCodecError else {
                return XCTFail("Expected declared-storage failure, received \(error).")
            }
        }

        // The original pool initializer remains available and keeps the v1
        // empty-configuration behavior for existing consumers.
        let legacyDatabase = try GRDBDatabase(
            databasePool: fixture.databasePool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        XCTAssertTrue(legacyDatabase.codingConfiguration.registry.identities.isEmpty)
    }

    func testURLAndBuilderOverloadsCaptureConfigurationWithoutChangingOldSignatures() throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let codecs = makeDateCodecs()
        let registry = try XLValueCodecRegistry().registering(codecs.text)
        let configuration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [codecs.text.identity.key]
        )

        let urlDatabase = try GRDBDatabase(
            url: directoryURL.appendingPathComponent("url.sqlite"),
            codingConfiguration: configuration,
            logger: nil
        )
        XCTAssertEqual(
            urlDatabase.codingConfiguration.defaultCodecKeys,
            [codecs.text.identity.key]
        )
        try urlDatabase.databasePool.close()

        let builder = try GRDBDatabaseBuilder(
            url: directoryURL.appendingPathComponent("builder.sqlite"),
            codingConfiguration: configuration,
            configuration: GRDB.Configuration(),
            logger: nil
        )
        let builtDatabase = try builder.build()
        XCTAssertEqual(
            builtDatabase.codingConfiguration.defaultCodecKeys,
            [codecs.text.identity.key]
        )
        try builtDatabase.databasePool.close()

        // Both pre-1.2 URL and builder declarations still type-check unchanged.
        let oldURLDatabase = try GRDBDatabase(
            url: directoryURL.appendingPathComponent("old-url.sqlite"),
            logger: nil
        )
        XCTAssertTrue(oldURLDatabase.codingConfiguration.registry.identities.isEmpty)
        try oldURLDatabase.databasePool.close()

        let oldBuilder = try GRDBDatabaseBuilder(
            url: directoryURL.appendingPathComponent("old-builder.sqlite"),
            configuration: GRDB.Configuration(),
            logger: nil
        )
        let oldBuiltDatabase = try oldBuilder.build()
        XCTAssertTrue(oldBuiltDatabase.codingConfiguration.registry.identities.isEmpty)
        try oldBuiltDatabase.databasePool.close()
    }

    func testSharedValueCasesUseNamedDefaultEnumAndOptionalCodecsThroughGRDB() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let textCodec = makeSharedConformanceTextCodec()
        let integerCodec = makeSharedConformanceIntegerCodec()
        let registry = try XLValueCodecRegistry()
            .registering(textCodec)
            .registering(integerCodec)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [integerCodec.identity.key]
        )
        let dialect = XLSQLiteDialect()
        let textParameterContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.namedTextCodec.rawValue
            )
        )
        let integerParameterContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.defaultIntegerCodec.rawValue
            )
        )
        let optionalParameterContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue
            )
        )
        let textValue = try codingConfiguration.encode(
            SharedConformanceMode.ready,
            using: dialect,
            context: textParameterContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: textCodec.identity.key
            )
        )
        let integerValue = try codingConfiguration.encode(
            SharedConformanceMode.waiting,
            using: dialect,
            context: integerParameterContext
        )
        let optionalValue = try codingConfiguration.encodeOptional(
            Optional<SharedConformanceMode>.none,
            using: dialect,
            context: optionalParameterContext
        )

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
            dialect: dialect
        )
        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE shared_value_codecs (
                    text_value TEXT NOT NULL,
                    integer_value INTEGER NOT NULL,
                    optional_value TEXT
                )
                """
        )
        let insert = logicalStatement(
            for: driver,
            sql: """
                INSERT INTO shared_value_codecs (
                    text_value, integer_value, optional_value
                ) VALUES (
                    :text_value, :integer_value, :optional_value
                )
                """
        )
        let select = logicalStatement(
            for: driver,
            sql: """
                SELECT
                    text_value, typeof(text_value),
                    integer_value, typeof(integer_value),
                    optional_value, typeof(optional_value)
                FROM shared_value_codecs
                """
        )
        let selectMismatch = logicalStatement(
            for: driver,
            sql: "SELECT 1, typeof(1)"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            statement = try connection.bind(
                textValue,
                to: .named("text_value"),
                in: statement
            )
            statement = try connection.bind(
                integerValue,
                to: .named("integer_value"),
                in: statement
            )
            statement = try connection.bind(
                optionalValue,
                to: .named("optional_value"),
                in: statement
            )
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }
        let streamedRows = try driver.withReadConnection { connection in
            let statement = try connection.prepare(select)
            var rows: [[XLSQLiteValue]] = []
            try connection.forEachRow(statement) { values in
                rows.append(values)
                return .advance
            }
            return rows
        }
        XCTAssertEqual(
            streamedRows,
            [row],
            [
                SQLiteValueConformanceCaseID.namedTextCodec.rawValue,
                SQLiteValueConformanceCaseID.defaultIntegerCodec.rawValue,
                SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue,
            ].joined(separator: ", ")
        )
        XCTAssertEqual(
            Array(row[0 ... 1]),
            [.text("ready"), .text("text")],
            SQLiteValueConformanceCaseID.namedTextCodec.rawValue
        )
        XCTAssertEqual(
            Array(row[2 ... 3]),
            [.integer(2), .text("integer")],
            SQLiteValueConformanceCaseID.defaultIntegerCodec.rawValue
        )
        XCTAssertEqual(
            Array(row[4 ... 5]),
            [.null, .text("null")],
            SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue
        )

        let decodedText: SharedConformanceMode = try codingConfiguration.decode(
            SharedConformanceMode.self,
            from: row[0],
            using: dialect,
            context: XLValueCodingContext(
                site: .result,
                path: textParameterContext.path
            ),
            selection: XLValueCodecSelection(
                explicitCodecKey: textCodec.identity.key
            )
        )
        let decodedInteger: SharedConformanceMode = try codingConfiguration.decode(
            SharedConformanceMode.self,
            from: row[2],
            using: dialect,
            context: XLValueCodingContext(
                site: .result,
                path: integerParameterContext.path
            )
        )
        let decodedOptional: SharedConformanceMode? = try codingConfiguration.decodeOptional(
            SharedConformanceMode.self,
            from: row[4],
            using: dialect,
            context: XLValueCodingContext(
                site: .result,
                path: optionalParameterContext.path
            )
        )
        XCTAssertEqual(
            decodedText,
            .ready,
            SQLiteValueConformanceCaseID.textRawValueEnum.rawValue
        )
        XCTAssertEqual(decodedInteger, .waiting)
        XCTAssertNil(decodedOptional)

        let mismatchRow = try driver.withReadConnection { connection in
            try XCTUnwrap(
                connection.fetchOne(connection.prepare(selectMismatch))
            )
        }
        let mismatchContext = XLValueCodingContext(
            site: .result,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.storageMismatch.rawValue
            )
        )
        XCTAssertEqual(
            mismatchRow,
            [.integer(1), .text("integer")],
            SQLiteValueConformanceCaseID.storageMismatch.rawValue
        )
        XCTAssertThrowsError(
            try codingConfiguration.decode(
                SharedConformanceMode.self,
                from: mismatchRow[0],
                using: dialect,
                context: mismatchContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: textCodec.identity.key
                )
            ),
            SQLiteValueConformanceCaseID.storageMismatch.rawValue
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: textCodec.identity.key,
                    expected: textCodec.identity.storageIdentifier,
                    actual: XLValueStorageIdentifier(rawValue: "integer"),
                    context: mismatchContext
                )
            )
        }
    }

    private func makeDateCodecs() -> (
        text: XLValueCodec<Date, XLSQLiteDialect>,
        integer: XLValueCodec<Date, XLSQLiteDialect>
    ) {
        let valueTypeIdentifier = XLValueTypeIdentifier(rawValue: "foundation.Date")
        let text = XLValueCodec<Date, XLSQLiteDialect>(
            key: XLValueCodecKey(id: "test.date-text", version: 1),
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
            encode: { value, _, _ in
                .text(String(value.timeIntervalSince1970))
            },
            decode: { value, _, _ in
                guard case .text(let text) = value,
                      let seconds = TimeInterval(text) else {
                    throw DateCodecFixtureError.invalidText
                }
                return Date(timeIntervalSince1970: seconds)
            }
        )
        let integer = XLValueCodec<Date, XLSQLiteDialect>(
            key: XLValueCodecKey(id: "test.date-integer", version: 1),
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
            encode: { value, _, _ in
                .integer(Int64(value.timeIntervalSince1970))
            },
            decode: { value, _, _ in
                guard case .integer(let seconds) = value else {
                    throw DateCodecFixtureError.invalidInteger
                }
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }
        )
        return (text, integer)
    }

    private func logicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(
                identity: XLSQLiteDialect.identity
            ),
            sql: sql
        )
    }

    private func makeFixture() throws -> CodecFixture {
        let directoryURL = try makeDirectory()
        return CodecFixture(
            directoryURL: directoryURL,
            databasePool: try DatabasePool(
                path: directoryURL.appendingPathComponent("database.sqlite").path
            )
        )
    }

    private func makeDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-codec-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return directoryURL
    }
}


private enum DateCodecFixtureError: Error {
    case invalidText
    case invalidInteger
}


private enum SharedConformanceMode: String, Equatable, Sendable {
    case ready
    case waiting
}


private func makeSharedConformanceTextCodec() -> XLValueCodec<
    SharedConformanceMode,
    XLSQLiteDialect
> {
    XLValueCodec(
        key: XLValueCodecKey(id: "conformance.shared-mode-text", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "swiftql.conformance.shared-mode"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            .text(value.rawValue)
        },
        decode: { value, _, _ in
            guard case .text(let rawValue) = value,
                  let mode = SharedConformanceMode(rawValue: rawValue) else {
                throw DateCodecFixtureError.invalidText
            }
            return mode
        }
    )
}


private func makeSharedConformanceIntegerCodec() -> XLValueCodec<
    SharedConformanceMode,
    XLSQLiteDialect
> {
    XLValueCodec(
        key: XLValueCodecKey(id: "conformance.shared-mode-integer", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "swiftql.conformance.shared-mode"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
        encode: { value, _, _ in
            .integer(value == .ready ? 1 : 2)
        },
        decode: { value, _, _ in
            switch value {
            case .integer(1):
                return .ready
            case .integer(2):
                return .waiting
            default:
                throw DateCodecFixtureError.invalidInteger
            }
        }
    )
}


private struct LegacyEpoch: Equatable, XLLiteral, Sendable {

    let value: Int

    static func sqlDefault() -> Self {
        Self(value: 0)
    }

    func bind(context: inout XLBindingContext) {
        context.bindInteger(value: value)
    }

    init(value: Int) {
        self.value = value
    }

    init(reader: XLColumnReader, at index: Int) throws {
        self.value = try reader.readInteger(at: index)
    }
}


private struct CodecFixture {
    let directoryURL: URL
    let databasePool: DatabasePool

    func tearDown() {
        try? databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}


private func codecKeyOrder(_ lhs: XLValueCodecKey, _ rhs: XLValueCodecKey) -> Bool {
    if lhs.id == rhs.id {
        return lhs.version < rhs.version
    }
    return lhs.id < rhs.id
}


/// Uses compile-time overload selection so the assertion is not affected by
/// retroactive conformances loaded from other test modules into one XCTest bundle.
private func hasVisibleV1LiteralConformance<Value>(_: Value.Type) -> Bool {
    false
}


private func hasVisibleV1LiteralConformance<Value>(
    _: Value.Type
) -> Bool where Value: XLLiteral {
    true
}
