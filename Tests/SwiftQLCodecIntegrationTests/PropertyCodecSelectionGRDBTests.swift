import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest

@testable import SwiftQL


// Issue #66: real-SQLite proof that a property-level `@SQLCodec(_:)` selection is applied
// automatically wherever a generated `staticResultField(_:...)` convenience is used, with no
// hand-written `selection: .explicit(...)` at any call site. `PropertyCodecSelectionRecord`
// deliberately gives its two `Date` properties two *different* named codecs so the same Swift
// value type can carry two distinct storage conventions -- the scenario issue #66 exists to
// support. Neither codec is a real preset (issues #61/#62 own those); both are small,
// self-contained test doubles that follow the fake-codec pattern already used by
// `ValueCodecContractTests`/`StaticRowLayoutGRDBTests`.


private enum PropertyCodecSelectionTestError: Error, Equatable {
    case invalidValue
}


/// Two independent, real-SQLite-storage test codecs for `Date`, each using a different textual
/// convention. Neither is registered as a database default -- both are only ever reachable
/// through the `@SQLCodec` selection on `PropertyCodecSelectionRecord`'s own properties.
private enum PropertyCodecSelectionTestCodecs {

    static let epochSeconds = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.property-codec.epoch-seconds", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.date"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            .text(String(Int64(value.timeIntervalSince1970)))
        },
        decode: { value, _, _ in
            guard case .text(let text) = value, let seconds = TimeInterval(text) else {
                throw PropertyCodecSelectionTestError.invalidValue
            }
            return Date(timeIntervalSince1970: seconds)
        }
    )

    static let bracketedEpochSeconds = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.property-codec.bracketed-epoch-seconds", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.date"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            .text("[\(Int64(value.timeIntervalSince1970))]")
        },
        decode: { value, _, _ in
            guard
                case .text(let text) = value,
                text.hasFirstAndLastCharacter("[", "]"),
                let seconds = TimeInterval(text.dropFirst().dropLast())
            else {
                throw PropertyCodecSelectionTestError.invalidValue
            }
            return Date(timeIntervalSince1970: seconds)
        }
    )
}


extension String {
    fileprivate func hasFirstAndLastCharacter(_ first: Character, _ last: Character) -> Bool {
        self.first == first && self.last == last && count >= 2
    }
}


@SQLTable(name: "PropertyCodecSelectionRecord")
private struct PropertyCodecSelectionRecord: Equatable {
    let id: Int

    @SQLCodec(PropertyCodecSelectionTestCodecs.epochSeconds.identity.key)
    let createdAt: Date

    @SQLCodec(PropertyCodecSelectionTestCodecs.bracketedEpochSeconds.identity.key)
    let updatedAt: Date?
}


// A custom (`@SQLResult`) type -- not a physical table -- carrying its own `@SQLCodec`
// selection. Declared at file scope (rather than local to a test method) since attached
// extension macros cannot emit their extension for a type declared inside a function body.
@SQLResult
private struct AuditStamp: Equatable {
    @SQLCodec(PropertyCodecSelectionTestCodecs.epochSeconds.identity.key)
    let recordedAt: Date
}


final class PropertyCodecSelectionGRDBTests: XCTestCase {

    // MARK: - Declaration-level metadata

    func testGeneratedTypeExposesStableCodecKeysForAnnotatedPropertiesOnly() {
        XCTAssertEqual(
            PropertyCodecSelectionRecord._swiftQLPropertyCodecKeys,
            [
                "createdAt": PropertyCodecSelectionTestCodecs.epochSeconds.identity.key,
                "updatedAt": PropertyCodecSelectionTestCodecs.bracketedEpochSeconds.identity.key,
            ]
        )
    }

    // MARK: - Insert, update, projection, optional/NULL, and binding

    func testDeclaredSelectionAppliesAcrossInsertUpdateProjectionAndParameterBinding() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "property-codec-selection")
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry()
            .registering(PropertyCodecSelectionTestCodecs.epochSeconds)
            .registering(PropertyCodecSelectionTestCodecs.bracketedEpochSeconds)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )

        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE PropertyCodecSelectionRecord (
                        id INTEGER NOT NULL,
                        createdAt TEXT NOT NULL,
                        updatedAt TEXT
                    )
                    """
            )
        }

        let table = XLSchema().table(PropertyCodecSelectionRecord.self, as: "record")

        // Every call below is the generated, declaration-driven convenience: no call site ever
        // writes `selection: .explicit(...)` itself, unlike the manually-selected fields in
        // `StaticRowLayoutGRDBTests`.
        let createdAtField = try PropertyCodecSelectionRecord.staticResultField(
            createdAt: table.createdAt,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(
                path: ["tests", "property-codec", "created-at"]
            ),
            using: database.dialect,
            configuration: configuration
        )
        let updatedAtField = try PropertyCodecSelectionRecord.staticResultField(
            updatedAt: table.updatedAt,
            storedAs: String?.self,
            identifiedBy: XLQuerySlotIdentity(
                path: ["tests", "property-codec", "updated-at"]
            ),
            using: database.dialect,
            configuration: configuration
        )
        let layout = try PropertyCodecSelectionRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.id,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["tests", "property-codec", "id"]
                )
            ),
            createdAt: createdAtField,
            updatedAt: updatedAtField
        )

        XCTAssertEqual(
            layout.metadata.fields.map(\.result.codecIdentity?.key),
            [
                nil,
                PropertyCodecSelectionTestCodecs.epochSeconds.identity.key,
                PropertyCodecSelectionTestCodecs.bracketedEpochSeconds.identity.key,
            ]
        )

        // Insert: the row is written by encoding it through `layout`, which reuses the exact
        // codecs declared on the type. `updatedAt` starts `nil`, exercising the optional/NULL
        // path through the bracketed codec's nonoptional encode closure.
        let insertedRow = PropertyCodecSelectionRecord(
            id: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: nil
        )
        let insertValues = try layout.encode(insertedRow)
        XCTAssertEqual(
            insertValues,
            [.integer(1), .text("1700000000"), .null]
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO PropertyCodecSelectionRecord (id, createdAt, updatedAt)
                    VALUES (?, ?, ?)
                    """,
                arguments: StatementArguments(insertValues.map(\.databaseValue))
            )
        }

        // Projection: select the row back and confirm the round trip, still with `updatedAt`
        // `nil` (NULL survives through the bracketed codec's optional wrapper).
        let selectStatement = sql { _ in
            Select(layout)
            From(table)
        }
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(selectStatement)
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "property-codec", "select-all"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let preparedSelect = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(descriptor: descriptor, layout: layout)
        )
        XCTAssertEqual(
            try preparedSelect.fetchExactlyOne(bindings: preparedSelect.makeInvocationBindings()),
            insertedRow
        )

        // Update: encode a second row sharing the same `id` but a non-nil `updatedAt`, and bind
        // its `createdAt`/`updatedAt` values into a raw UPDATE -- proving the write direction
        // (not just SELECT projection) reuses the identical declared codecs.
        let updatedRow = PropertyCodecSelectionRecord(
            id: 1,
            createdAt: insertedRow.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let updateValues = try layout.encode(updatedRow)
        XCTAssertEqual(
            updateValues,
            [.integer(1), .text("1700000000"), .text("[1700000500]")]
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: "UPDATE PropertyCodecSelectionRecord SET createdAt = ?, updatedAt = ? WHERE id = ?",
                arguments: StatementArguments([
                    updateValues[1].databaseValue,
                    updateValues[2].databaseValue,
                    updateValues[0].databaseValue,
                ])
            )
        }
        XCTAssertEqual(
            try preparedSelect.fetchExactlyOne(bindings: preparedSelect.makeInvocationBindings()),
            updatedRow
        )

        // Binding: a query parameter captured with the *same* selection the property declared
        // (`createdAtField.codecSelection`, which is `.explicit(...)` the generated convenience
        // supplied) filters by the encoded `createdAt` value, matching the row written above.
        let createdAtCapture = try database.queryCapture(
            Date.self,
            matching: createdAtField.expression,
            identifiedBy: XLQuerySlotIdentity(
                path: ["tests", "property-codec", "created-at-filter"]
            ),
            selection: createdAtField.codecSelection
        )
        XCTAssertEqual(createdAtField.codecSelection, .explicit(PropertyCodecSelectionTestCodecs.epochSeconds.identity.key))
        let filterStatement = sql { _ in
            Select(layout)
            From(table)
            Where(createdAtField.expression == createdAtCapture)
        }
        let filterEncoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(filterStatement)
        let filterDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "property-codec", "select-filtered"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: filterEncoding),
            parameters: [
                try createdAtCapture.staticQueryParameter(in: filterEncoding),
            ],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let preparedFilter = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(descriptor: filterDescriptor, layout: layout)
        )
        let filterBindings = try preparedFilter.makeInvocationBindings(
            createdAtCapture.argument(insertedRow.createdAt)
        )
        XCTAssertEqual(
            try preparedFilter.fetchExactlyOne(bindings: filterBindings),
            updatedRow
        )
    }

    // MARK: - Custom result (`@SQLResult`) applies the same selection

    func testCustomResultTypeAppliesItsOwnDeclaredSelection() throws {
        let registry = try XLValueCodecRegistry()
            .registering(PropertyCodecSelectionTestCodecs.epochSeconds)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let dialect = XLSQLiteDialect()

        XCTAssertEqual(
            AuditStamp._swiftQLPropertyCodecKeys,
            ["recordedAt": PropertyCodecSelectionTestCodecs.epochSeconds.identity.key]
        )

        let table = XLSchema().table(PropertyCodecSelectionRecord.self, as: "record")
        let layout = try AuditStamp.staticRowLayout(
            using: XLSQLiteDialect.self,
            recordedAt: AuditStamp.staticResultField(
                recordedAt: table.createdAt,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["tests", "property-codec", "audit-stamp"]
                ),
                using: dialect,
                configuration: configuration
            )
        )

        let expected = AuditStamp(recordedAt: Date(timeIntervalSince1970: 42))
        let encoded = try layout.encode(expected)
        XCTAssertEqual(encoded, [.text("42")])
        XCTAssertEqual(try layout.decode(encoded), expected)
    }

    // MARK: - Runtime diagnostics reachable through the generated convenience

    func testUnregisteredCodecKeyIsDiagnosedAtPrepareTime() throws {
        // No codec is registered at all: resolution must fail with `.unknownCodec` naming the
        // exact key `@SQLCodec` declared, exercised through the generated convenience.
        let configuration = try XLValueCodingConfiguration()
        let table = XLSchema().table(PropertyCodecSelectionRecord.self, as: "record")

        XCTAssertThrowsError(
            try PropertyCodecSelectionRecord.staticResultField(
                createdAt: table.createdAt,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["tests", "property-codec", "unregistered"]
                ),
                using: XLSQLiteDialect(),
                configuration: configuration
            )
        ) { error in
            guard case .unknownCodec(let key, let source, _) = error as? XLValueCodecError else {
                return XCTFail("Expected .unknownCodec, received \(error)")
            }
            XCTAssertEqual(key, PropertyCodecSelectionTestCodecs.epochSeconds.identity.key)
            XCTAssertEqual(source, .explicit)
        }
    }

    func testCodecRegisteredForAnotherValueTypeIsDiagnosedAsValueTypeMismatch() throws {
        // Register a codec *under the exact same key* `createdAt` declares, but for `Int`
        // instead of `Date`. Resolution must fail with `.valueTypeMismatch`, proving "wrong
        // Swift value type" is caught even though the macro cannot see the registry at
        // expansion time.
        let mismatchedCodec = XLValueCodec<Int, XLSQLiteDialect>(
            key: PropertyCodecSelectionTestCodecs.epochSeconds.identity.key,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
            encode: { value, _, _ in .text(String(value)) },
            decode: { value, _, _ in
                guard case .text(let text) = value, let intValue = Int(text) else {
                    throw PropertyCodecSelectionTestError.invalidValue
                }
                return intValue
            }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(mismatchedCodec)
        )
        let table = XLSchema().table(PropertyCodecSelectionRecord.self, as: "record")

        XCTAssertThrowsError(
            try PropertyCodecSelectionRecord.staticResultField(
                createdAt: table.createdAt,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["tests", "property-codec", "mismatched"]
                ),
                using: XLSQLiteDialect(),
                configuration: configuration
            )
        ) { error in
            guard case .valueTypeMismatch = error as? XLValueCodecError else {
                return XCTFail("Expected .valueTypeMismatch, received \(error)")
            }
        }
    }
}
