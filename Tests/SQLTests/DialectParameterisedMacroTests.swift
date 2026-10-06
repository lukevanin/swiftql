//
//  DialectParameterisedMacroTests.swift
//  SwiftQL
//
//  Issue #687: the code the macros generate carries the dialect as a
//  parameter instead of naming SQLite. One `@SQLTable` model builds and
//  round-trips its static layout against SQLite and against a fake second
//  dialect whose values are not SQLite's, through the generated
//  `staticRowLayout(using:...)` and the generated `@SQLCodec` field factory.
//
//  Issue #789: a model is queried in the one dialect it is declared for, so
//  the second dialect's query selects the columns of a second declaration.
//  The layout, the codecs, and the decoded row are still the one model's.
//  `@SQLBindings(dialect:)` encodes its packet for the fake dialect, and
//  `@SQLQuery(dialect:)` naming SQLite runs exactly as `@SQLQuery` does.
//
//  `scripts/ci/check-dialect-parameterised-macro-type-safety.sh` proves the
//  other half: a field or layout built for one dialect does not compile where
//  another dialect's is expected, and the error names both dialects.
//

import Foundation
import GRDB
// `@testable` only to reach a capture's intrinsic encoder, which no public
// API applies for a dialect without a request layer.
@_spi(GRDB) @testable import SwiftQL
import XCTest


// MARK: - A fake second dialect


/// Storage that is deliberately not SQLite's: no SQLite storage identifier
/// collides with these, so a value that took a SQLite path would fail.
enum FakeSecondDialectValue: XLDialectValue {
    case null
    case number(Int64)
    case decimal(Double)
    case string(String)
    case bytes(Data)

    var storageType: String {
        switch self {
        case .null:
            return "fake.null"
        case .number:
            return "fake.number"
        case .decimal:
            return "fake.decimal"
        case .string:
            return "fake.string"
        case .bytes:
            return "fake.bytes"
        }
    }
}


enum FakeSecondDialectError: Error, Equatable {
    case unexpectedValue(FakeSecondDialectValue, at: Int)
    case missingValue(at: Int)
}


/// A second dialect for the macro regression corpus. It renders SQL with
/// SQLite's formatter -- rendering is not what is under test -- and owns its
/// own value model, so everything that encodes or decodes a value has to go
/// through the dialect the generated code was given.
struct FakeSecondDialect: XLLiteralValueDialect, Hashable {

    typealias Value = FakeSecondDialectValue

    static let identity = XLDialectIdentifier(rawValue: "swiftql.tests.fake-second-dialect")

    let descriptor = XLDialectDescriptor(
        identity: FakeSecondDialect.identity,
        capabilities: [.namedBindings, .indexedBindings]
    )

    func makeFormatter() -> XLiteFormatter {
        XLiteFormatter()
    }

    func makeVocabulary() -> XLiteVocabulary {
        XLiteVocabulary()
    }

    func makePlaceholderAssigner() -> XLitePlaceholderAssigner {
        XLitePlaceholderAssigner()
    }

    func formatIdentifier(_ identifier: String) -> String {
        XLSQLiteDialect().formatIdentifier(identifier)
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        XLSQLiteDialect().formatQualifiedIdentifier(components)
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        XLSQLiteDialect().formatPlaceholder(placeholder)
    }

    func isNull(_ value: FakeSecondDialectValue) -> Bool {
        value == .null
    }

    var nullValue: FakeSecondDialectValue {
        .null
    }

    func stableStorageIdentifier(
        for value: FakeSecondDialectValue
    ) -> XLValueStorageIdentifier {
        XLValueStorageIdentifier(rawValue: value.storageType)
    }

    static func literalStorageIdentifier(
        for type: Any.Type
    ) -> XLValueStorageIdentifier? {
        let storage: String
        switch type {
        case is Bool.Type, is Bool?.Type, is Int.Type, is Int?.Type:
            storage = "fake.number"
        case is Double.Type, is Double?.Type:
            storage = "fake.decimal"
        case is String.Type, is String?.Type:
            storage = "fake.string"
        case is Data.Type, is Data?.Type:
            storage = "fake.bytes"
        default:
            return nil
        }
        return XLValueStorageIdentifier(rawValue: storage)
    }

    static func decodeLiteral<Literal>(
        _ type: Literal.Type,
        from value: FakeSecondDialectValue
    ) throws -> Literal where Literal: XLLiteral {
        try Literal(reader: FakeSecondDialectReader(values: [value]), at: 0)
    }

    static func encodeLiteral<Literal>(
        _ value: Literal,
        valueType: String,
        codingContext: XLValueCodingContext
    ) throws -> FakeSecondDialectValue where Literal: XLBindable {
        var context: any XLBindingContext = FakeSecondDialectCapture()
        value.bind(context: &context)
        return (context as! FakeSecondDialectCapture).value
    }

    static func isNullLiteral(_ value: FakeSecondDialectValue) -> Bool {
        value == .null
    }
}


private struct FakeSecondDialectCapture: XLBindingContext {

    var value = FakeSecondDialectValue.null

    mutating func bindNull() {
        value = .null
    }

    mutating func bindInteger(value: Int) {
        self.value = .number(Int64(value))
    }

    mutating func bindReal(value: Double) {
        self.value = .decimal(value)
    }

    mutating func bindText(value: String) {
        self.value = .string(value)
    }

    mutating func bindBlob(value: Data) {
        self.value = .bytes(value)
    }
}


private struct FakeSecondDialectReader: XLColumnReader {

    let values: [FakeSecondDialectValue]

    private func value(at index: Int) throws -> FakeSecondDialectValue {
        guard values.indices.contains(index) else {
            throw FakeSecondDialectError.missingValue(at: index)
        }
        return values[index]
    }

    func isNull(at index: Int) throws -> Bool {
        try value(at: index) == .null
    }

    func readInteger(at index: Int) throws -> Int {
        guard case .number(let number) = try value(at: index) else {
            throw FakeSecondDialectError.unexpectedValue(try value(at: index), at: index)
        }
        return Int(number)
    }

    func readReal(at index: Int) throws -> Double {
        guard case .decimal(let decimal) = try value(at: index) else {
            throw FakeSecondDialectError.unexpectedValue(try value(at: index), at: index)
        }
        return decimal
    }

    func readText(at index: Int) throws -> String {
        guard case .string(let string) = try value(at: index) else {
            throw FakeSecondDialectError.unexpectedValue(try value(at: index), at: index)
        }
        return string
    }

    func readBlob(at index: Int) throws -> Data {
        guard case .bytes(let bytes) = try value(at: index) else {
            throw FakeSecondDialectError.unexpectedValue(try value(at: index), at: index)
        }
        return bytes
    }
}


// MARK: - One model, declared once


/// Declared exactly as any other model. Nothing here names a dialect.
@SQLTable(name: "dialect_gauge")
struct DialectGauge: Equatable {
    var id: Int
    var label: String?
    @SQLCodec(DialectGaugeCodecs.reversedKey)
    var code: String
    @SQLCodec(DialectGaugeCodecs.reversedKey)
    var alias: String?
}


/// The same table, declared for the second dialect (issue #789). Its columns
/// are what a second-dialect query selects.
@SQLTable(name: "dialect_gauge", dialect: FakeSecondDialect.self)
struct FakeDialectGauge: Equatable {
    var id: Int
    var label: String?
    var code: String
    var alias: String?
}


/// The same codec key registered once per dialect: a text value stored
/// reversed. Each dialect's configuration registers its own.
enum DialectGaugeCodecs {

    static let reversedKey = XLValueCodecKey(
        id: "swiftql.tests.dialect-gauge.reversed",
        version: 1
    )

    static let reversedTextIdentifier = XLValueTypeIdentifier(rawValue: "swift.string")

    static let sqlite = XLValueCodec<String, XLSQLiteDialect>(
        key: reversedKey,
        valueTypeIdentifier: reversedTextIdentifier,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            .text(String(value.reversed()))
        },
        decode: { value, _, _ in
            guard case .text(let text) = value else {
                throw XLSQLiteValueReading.typeMismatch(value, at: 0, expectedType: "String")
            }
            return String(text.reversed())
        }
    )

    static let fake = XLValueCodec<String, FakeSecondDialect>(
        key: reversedKey,
        valueTypeIdentifier: reversedTextIdentifier,
        dialectIdentifier: FakeSecondDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "fake.string"),
        encode: { value, _, _ in
            .string(String(value.reversed()))
        },
        decode: { value, _, _ in
            guard case .string(let string) = value else {
                throw FakeSecondDialectError.unexpectedValue(value, at: 0)
            }
            return String(string.reversed())
        }
    )

    static func configuration<Dialect>(
        registering codec: XLValueCodec<String, Dialect>
    ) throws -> XLValueCodingConfiguration {
        try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registering(codec)
        )
    }
}


/// Builds the model's layout for any dialect, from columns of that dialect.
/// Its body is the call site a caller writes for SQLite, with the dialect
/// generic: the generated members absorb the parameter.
private func dialectGaugeLayout<Dialect>(
    using dialect: Dialect,
    id: any XLExpression<Int, Dialect>,
    label: any XLExpression<String?, Dialect>,
    code: any XLExpression<String, Dialect>,
    alias: any XLExpression<String?, Dialect>,
    configuration: XLValueCodingConfiguration
) throws -> XLStaticRowLayout<DialectGauge, Dialect>
where Dialect: XLLiteralValueDialect {
    try DialectGauge.staticRowLayout(
        using: Dialect.self,
        id: XLStaticSelectField<Int, Int, Dialect>.intrinsic(
            selecting: id,
            identifiedBy: XLQuerySlotIdentity(path: ["dialect-gauge", "id"]),
            using: dialect
        ),
        label: XLStaticSelectField<String?, String?, Dialect>.intrinsic(
            selecting: label,
            identifiedBy: XLQuerySlotIdentity(path: ["dialect-gauge", "label"]),
            using: dialect
        ),
        code: DialectGauge.staticResultField(
            code: code,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["dialect-gauge", "code"]),
            using: dialect,
            configuration: configuration
        ),
        alias: DialectGauge.staticResultField(
            alias: alias,
            storedAs: String?.self,
            identifiedBy: XLQuerySlotIdentity(path: ["dialect-gauge", "alias"]),
            using: dialect,
            configuration: configuration
        )
    )
}


/// The SQLite layout, selecting the SQLite model's columns.
private func dialectGaugeLayout(
    using dialect: XLSQLiteDialect,
    configuration: XLValueCodingConfiguration
) throws -> XLStaticRowLayout<DialectGauge, XLSQLiteDialect> {
    let gauge = XLSchema().table(DialectGauge.self)
    return try dialectGaugeLayout(
        using: dialect,
        id: gauge.id,
        label: gauge.label,
        code: gauge.code,
        alias: gauge.alias,
        configuration: configuration
    )
}


/// The second dialect's layout, selecting the second declaration's columns.
private func dialectGaugeLayout(
    using dialect: FakeSecondDialect,
    configuration: XLValueCodingConfiguration
) throws -> XLStaticRowLayout<DialectGauge, FakeSecondDialect> {
    let gauge = XLSchema(dialect: FakeSecondDialect.self).table(FakeDialectGauge.self)
    return try dialectGaugeLayout(
        using: dialect,
        id: gauge.id,
        label: gauge.label,
        code: gauge.code,
        alias: gauge.alias,
        configuration: configuration
    )
}


// MARK: - Declared queries and binding packets


@SQLBindings(dialect: FakeSecondDialect.self)
struct FakeSecondDialectGaugeBindings {
    var code: String
    var minimumID: Int
    var label: String?
}


extension GRDBDatabase {

    /// Names SQLite explicitly; expands and runs exactly as `@SQLQuery` does.
    @SQLQuery(dialect: XLSQLiteDialect.self)
    func explicitDialectRowsMatchingID(id: String) -> [TestTable] {
        sqlResult { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
    }
}


// MARK: - Tests


final class DialectParameterisedMacroTests: XCTestCase {

    private let gauge = DialectGauge(id: 7, label: nil, code: "abc", alias: "de")

    func testOneModelRoundTripsThroughSQLite() throws {
        let layout = try dialectGaugeLayout(
            using: XLSQLiteDialect(),
            configuration: DialectGaugeCodecs.configuration(
                registering: DialectGaugeCodecs.sqlite
            )
        )

        let values = try layout.encode(gauge)

        XCTAssertEqual(values, [.integer(7), .null, .text("cba"), .text("ed")])
        XCTAssertEqual(try layout.decode(values), gauge)
    }

    func testTheSameModelRoundTripsThroughASecondDialect() throws {
        let layout = try dialectGaugeLayout(
            using: FakeSecondDialect(),
            configuration: DialectGaugeCodecs.configuration(
                registering: DialectGaugeCodecs.fake
            )
        )

        let values = try layout.encode(gauge)

        XCTAssertEqual(values, [.number(7), .null, .string("cba"), .string("ed")])
        XCTAssertEqual(try layout.decode(values), gauge)
        XCTAssertEqual(
            try layout.decode([.number(8), .string("gauge"), .string("zyx"), .null]),
            DialectGauge(id: 8, label: "gauge", code: "xyz", alias: nil)
        )
    }

    func testEachDialectRecordsItsOwnStorageAndCodec() throws {
        let sqlite = try dialectGaugeLayout(
            using: XLSQLiteDialect(),
            configuration: DialectGaugeCodecs.configuration(
                registering: DialectGaugeCodecs.sqlite
            )
        )
        let fake = try dialectGaugeLayout(
            using: FakeSecondDialect(),
            configuration: DialectGaugeCodecs.configuration(
                registering: DialectGaugeCodecs.fake
            )
        )

        XCTAssertEqual(
            sqlite.metadata.fields.map(\.result.storageIdentifier.rawValue),
            ["integer", "text", "text", "text"]
        )
        XCTAssertEqual(
            fake.metadata.fields.map(\.result.storageIdentifier.rawValue),
            ["fake.number", "fake.string", "fake.string", "fake.string"]
        )
        XCTAssertEqual(
            sqlite.metadata.fields.map(\.result.codecIdentity?.dialectIdentifier),
            [nil, nil, XLSQLiteDialect.identity, XLSQLiteDialect.identity]
        )
        XCTAssertEqual(
            fake.metadata.fields.map(\.result.codecIdentity?.dialectIdentifier),
            [nil, nil, FakeSecondDialect.identity, FakeSecondDialect.identity]
        )
        XCTAssertEqual(
            sqlite.metadata.fields.map(\.alias),
            fake.metadata.fields.map(\.alias)
        )
    }

    func testASecondDialectRejectsAValueOfTheWrongStorage() throws {
        let layout = try dialectGaugeLayout(
            using: FakeSecondDialect(),
            configuration: DialectGaugeCodecs.configuration(
                registering: DialectGaugeCodecs.fake
            )
        )

        XCTAssertThrowsError(
            try layout.decode([.string("7"), .null, .string("cba"), .null])
        ) { error in
            guard case .storageMismatch(let field, let actual)? = error as? XLStaticRowLayoutError else {
                return XCTFail("Expected a storage mismatch, got \(error)")
            }
            XCTAssertEqual(field.alias, "id")
            XCTAssertEqual(actual.rawValue, "fake.string")
        }
    }

    func testIntrinsicCaptureAndContextualBindingTakeTheSecondDialect() throws {
        let identity = try XLQuerySlotIdentity(path: ["dialect-gauge", "minimum-id"])
        let intrinsic = try XLQueryCapture<Int, Int, FakeSecondDialect>.intrinsic(
            identifiedBy: identity,
            using: FakeSecondDialect()
        )
        let configuration = try DialectGaugeCodecs.configuration(
            registering: DialectGaugeCodecs.fake
        )
        let contextual = try configuration.queryCapture(
            String.self,
            expressedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["dialect-gauge", "code"]),
            using: FakeSecondDialect(),
            selection: .explicit(DialectGaugeCodecs.reversedKey)
        )
        let binding = try configuration.contextualBinding(
            String.self,
            expressedAs: String.self,
            named: XLName("code"),
            using: FakeSecondDialect(),
            selection: XLValueCodecSelection(explicitCodecKey: DialectGaugeCodecs.reversedKey)
        )

        XCTAssertEqual(intrinsic.dialectIdentifier, FakeSecondDialect.identity)
        XCTAssertEqual(intrinsic.storageIdentifier.rawValue, "fake.number")
        guard case .intrinsic(let encodeIntrinsic) = intrinsic.encoding else {
            return XCTFail("Expected an intrinsic capture encoder")
        }
        XCTAssertEqual(try encodeIntrinsic(3), .number(3))
        XCTAssertEqual(contextual.dialectIdentifier, FakeSecondDialect.identity)
        XCTAssertEqual(contextual.storageIdentifier.rawValue, "fake.string")

        let encoding = try XLDialectEncoder(dialect: FakeSecondDialect())
            .makeValidatedSQL(binding)
        let encoded = try binding.encode("abc", in: encoding.parameterLayout)
        XCTAssertEqual(encoded.value, .string("cba"))
    }

    func testBindingsPacketEncodesForTheDialectItNames() throws {
        let statement = sql { schema in
            let gauge = schema.table(DialectGauge.self)
            Select(gauge)
            From(gauge)
            Where(
                gauge.code == FakeSecondDialectGaugeBindings.code
                    && gauge.id >= FakeSecondDialectGaugeBindings.minimumID
                    && gauge.label == FakeSecondDialectGaugeBindings.label
            )
        }
        let encoding = try XLDialectEncoder(dialect: FakeSecondDialect())
            .makeValidatedSQL(statement)

        let packet: XLInvocationBindings<FakeSecondDialectValue> = try FakeSecondDialectGaugeBindings(
            code: "abc",
            minimumID: 3,
            label: nil
        ).bindings(in: encoding.parameterLayout)

        XCTAssertEqual(
            packet.bindings.map(\.value),
            [.string("abc"), .number(3), .null]
        )
    }

    func testDeclaredQueryNamingSQLiteRunsAsBefore() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        let pool = try DatabasePool(path: fileURL.path)
        defer {
            try? pool.close()
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }
        let database = try GRDBDatabase(
            databasePool: pool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "a", value: 1))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "b", value: 2))).execute()

        let rows = try database.fetchExplicitDialectRowsMatchingID(id: "b")
        XCTAssertEqual(rows, [TestTable(id: "b", value: 2)])

        let prepared = try database.explicitDialectRowsMatchingIDPreparedQuery(id: "a")
        XCTAssertEqual(prepared.bindings.bindings.map(\.value), [.text("a")])
    }
}
