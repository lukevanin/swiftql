import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@_spi(GRDB) @testable import SwiftQL
@testable import SwiftQLSQLite


@SQLTable(name: "CodecInferenceEvent")
private struct CodecInferenceEvent: Equatable {
    let id: Int
    let occurredAt: Date
}


private enum CodecInferenceFailure: Error {
    case invalidValue
}


private struct CodecInferenceUnregistered: Equatable {
    let rawValue: Int
}


/// Issue #691: a codec that is registered but not a default is chosen the same
/// way for a parameter and for a result column.
///
/// `XLDateTextCodec.standard` is registered below and no default is listed.
/// The `Date` property decoded through inference before this change, while a
/// `contextualBinding` for the same column threw `missingCodec`.
final class CodecInferenceGRDBTests: XCTestCase {

    private func makeDatabase(
        _ fixture: TemporaryDatabaseFixture
    ) throws -> GRDBDatabase {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard)
        )
        XCTAssertTrue(configuration.defaultCodecKeys.isEmpty)
        return try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )
    }

    func testUndefaultedCodecServesAParameterAndAResultColumnOfTheSameType() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "codec-inference")
        defer { fixture.tearDown() }
        let database = try makeDatabase(fixture)

        // The parameter side.
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000.125)
        let reference = try database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "occurredAt"
        )
        XCTAssertEqual(
            reference.declaration.codecIdentity,
            XLDateTextCodec.standard.identity
        )
        let request = database.makeRequest(with: sql { _ in Select(reference) })
        let packet = try XLInvocationBindings(
            layout: request.parameterLayout,
            bindings: [
                reference.encode(occurredAt, in: request.parameterLayout),
            ]
        )
        XCTAssertEqual(
            try request.fetchOne(bindings: packet),
            "2023-11-14T22:13:20.125Z"
        )

        // The result side, over the same text.
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE CodecInferenceEvent (
                        id INTEGER NOT NULL,
                        occurredAt TEXT NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: "INSERT INTO CodecInferenceEvent (id, occurredAt) VALUES (1, ?)",
                arguments: ["2023-11-14T22:13:20.125Z"]
            )
        }
        let table = XLSchema().table(CodecInferenceEvent.self, as: "event")
        let layout = try CodecInferenceEvent.staticRowLayout(
            using: XLSQLiteDialect.self,
            id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.id,
                identifiedBy: XLQuerySlotIdentity(path: ["codec-inference", "id"])
            ),
            occurredAt: database.codingConfiguration.staticResultField(
                Date.self,
                selecting: table.occurredAt,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["codec-inference", "occurred-at"]
                ),
                using: database.dialect
            )
        )
        XCTAssertEqual(
            layout.metadata.fields.map(\.result.codecIdentity),
            [nil, XLDateTextCodec.standard.identity]
        )
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(
                sql { _ in
                    Select(layout)
                    From(table)
                }
            )
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "codec-inference", "select"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let prepared = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(descriptor: descriptor, layout: layout)
        )
        let row = try prepared.fetchExactlyOne(
            bindings: prepared.makeInvocationBindings()
        )
        XCTAssertEqual(row.id, 1)
        XCTAssertEqual(
            row.occurredAt.timeIntervalSince1970,
            occurredAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    /// A second `Date` codec, storing an integer. The key is local to this test.
    private static let epochCodec = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.codec-inference.epoch", version: 1),
        valueTypeIdentifier: XLDateTextCodec.valueTypeIdentifier,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.integer.rawValue
        ),
        encode: { value, _, _ in .integer(Int64(value.timeIntervalSince1970)) },
        decode: { value, _, _ in
            guard case .integer(let seconds) = value else {
                throw CodecInferenceFailure.invalidValue
            }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
    )

    func testContextualBindingNarrowsTheLastTierByTheLiteralStorage() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "codec-inference-storage")
        defer { fixture.tearDown() }
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(XLDateTextCodec.standard)
                .registering(Self.epochCodec)
        )
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )

        // No default, two codecs: the literal's storage tells them apart, for a
        // parameter as for a result column.
        let textParameter = try database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "text"
        )
        let integerParameter = try database.contextualBinding(
            Date.self,
            expressedAs: Int.self,
            named: "integer"
        )
        XCTAssertEqual(
            textParameter.declaration.codecIdentity,
            XLDateTextCodec.standard.identity
        )
        XCTAssertEqual(
            integerParameter.declaration.codecIdentity,
            Self.epochCodec.identity
        )
        for (storedAs, expected) in [
            ("text", XLDateTextCodec.standard.identity),
            ("integer", Self.epochCodec.identity),
        ] {
            XCTAssertEqual(
                try configuration.resolvedCodec(
                    for: Date.self,
                    using: database.dialect,
                    context: XLValueCodingContext(
                        site: .result,
                        path: XLValueCodingPath(["codec-inference", storedAs])
                    ),
                    requiringStorage: XLValueStorageIdentifier(rawValue: storedAs)
                ).identity,
                expected
            )
        }

        // Without a literal, and so without a storage, the two stay ambiguous.
        XCTAssertThrowsError(
            try configuration.resolvedCodec(
                for: Date.self,
                using: database.dialect,
                context: XLValueCodingContext(
                    site: .parameter,
                    path: XLValueCodingPath(["codec-inference", "unconstrained"])
                )
            )
        ) { error in
            guard case .ambiguousCodec? = error as? XLValueCodecError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        // One codec, whose storage is not the literal's: it is named, not
        // selected and then rejected.
        let integerOnly = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: try XLValueCodingConfiguration(
                registry: try XLValueCodecRegistry().registering(Self.epochCodec)
            ),
            formatter: XLiteFormatter(),
            logger: nil
        )
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["codec-inference", "mismatch"])
        )
        XCTAssertThrowsError(
            try integerOnly.contextualBinding(
                Date.self,
                expressedAs: String.self,
                named: "mismatch",
                context: context
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .missingCodec(
                    valueType: String(reflecting: Date.self),
                    dialect: integerOnly.dialect.descriptor.identity,
                    candidates: [Self.epochCodec.identity.key],
                    context: context
                )
            )
        }
        XCTAssertNoThrow(
            try integerOnly.contextualBinding(
                Date.self,
                expressedAs: Int.self,
                named: "match"
            )
        )
    }

    func testMissingCodecNamesTheRegisteredCandidateForAMismatchedStorage() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "codec-inference-missing")
        defer { fixture.tearDown() }
        let database = try makeDatabase(fixture)

        // The registered codec stores TEXT; an INTEGER column has none.
        XCTAssertThrowsError(
            try database.codingConfiguration.resolvedCodec(
                for: Date.self,
                using: database.dialect,
                context: XLValueCodingContext(
                    site: .result,
                    path: XLValueCodingPath(["codec-inference", "epoch"])
                ),
                requiringStorage: XLValueStorageIdentifier(rawValue: "integer")
            )
        ) { error in
            XCTAssertEqual(
                (error as? XLQueryCodecSelectionError).map {
                    if case .missingCodecForStorage(_, _, _, let candidates, _) = $0 {
                        return candidates
                    }
                    return []
                },
                [XLDateTextCodec.standardKey]
            )
            XCTAssertTrue(
                error.localizedDescription.contains(
                    XLDateTextCodec.standardKey.description
                ),
                error.localizedDescription
            )
        }

        // A type with no codec registered says that none is.
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["unregistered"])
        )
        XCTAssertThrowsError(
            try database.contextualBinding(
                CodecInferenceUnregistered.self,
                expressedAs: String.self,
                named: "unregistered",
                context: context
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .missingCodec(
                    valueType: String(reflecting: CodecInferenceUnregistered.self),
                    dialect: database.dialect.descriptor.identity,
                    candidates: [],
                    context: context
                )
            )
        }
    }
}
