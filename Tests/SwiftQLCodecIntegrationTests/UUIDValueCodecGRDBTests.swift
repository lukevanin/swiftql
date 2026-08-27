import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@testable import SwiftQL


/// One schema, two `UUID` properties, two different SQLite representations,
/// no wrapper structs -- backed by real SQLite via GRDB.
@SQLTable(name: "UUIDCodecRecord")
private struct UUIDCodecRecord: Equatable {
    let id: UUID
    let legacyBadgeID: UUID
    let note: UUID?
}


/// Real GRDB/SQLite round-trip coverage for the built-in
/// ``XLUUIDValueCodec`` presets. Contract-level (fake-driver-free) behavior
/// lives in `UUIDValueCodecContractTests.swift`; this file exercises literal
/// SQL text, named-binding parameters, `INSERT`, `UPDATE`, `SELECT`,
/// equality, `UNIQUE` indexing, optional/NULL, and result decoding against a
/// real SQLite database.
final class UUIDValueCodecGRDBTests: XCTestCase {

    func testOneSchemaUsesBothUUIDPresetsForDifferentPropertiesWithoutWrapperStructs() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry()
            .registering(XLUUIDValueCodec.text)
            .registering(XLUUIDValueCodec.blob)
        // Deliberately no `defaultCodecKeys`: both presets target the same
        // `(UUID, sqlite)` pair, so a shared default would be ambiguous (see
        // `UUIDValueCodecContractTests.testRegisteringBothPresetsAsDefaultsIsRejectedAsAmbiguous`).
        // Each property below selects its preset explicitly via
        // `configuration.staticResultField(..., selection: .explicit(...))`
        // instead. Issue #66's `@SQLCodec` attribute (now available) is an
        // alternative, declaration-site way to make the same per-property
        // choice; this test exercises the explicit-selection path directly
        // rather than through that macro.
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
                    CREATE TABLE UUIDCodecRecord (
                        id TEXT NOT NULL,
                        legacyBadgeID BLOB NOT NULL,
                        note TEXT,
                        UNIQUE (id),
                        UNIQUE (legacyBadgeID)
                    )
                    """
            )
        }

        let schema = XLSchema()
        let table = schema.table(UUIDCodecRecord.self, as: "record")
        let dialect = database.dialect
        let layout = try UUIDCodecRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            id: configuration.staticResultField(
                UUID.self,
                selecting: table.id,
                storedAs: String.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["uuid-codec", "id"]
                ),
                using: dialect,
                selection: .explicit(XLUUIDValueCodec.text.identity.key)
            ),
            legacyBadgeID: configuration.staticResultField(
                UUID.self,
                selecting: table.legacyBadgeID,
                storedAs: Data.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["uuid-codec", "legacyBadgeID"]
                ),
                using: dialect,
                selection: .explicit(XLUUIDValueCodec.blob.identity.key)
            ),
            note: configuration.staticResultField(
                UUID?.self,
                selecting: table.note,
                storedAs: String?.self,
                identifiedBy: XLQuerySlotIdentity(
                    path: ["uuid-codec", "note"]
                ),
                using: dialect,
                selection: .explicit(XLUUIDValueCodec.text.identity.key)
            )
        )

        XCTAssertEqual(
            layout.metadata.fields.map(\.result.codecIdentity?.key),
            [
                XLUUIDValueCodec.text.identity.key,
                XLUUIDValueCodec.blob.identity.key,
                XLUUIDValueCodec.text.identity.key,
            ]
        )

        let first = UUIDCodecRecord(
            id: UUID(uuidString: "E02F7C60-8C7F-4C68-8B62-6F0F1A2B3C4D")!,
            legacyBadgeID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            note: nil
        )
        let second = UUIDCodecRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            legacyBadgeID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            note: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )

        // INSERT: both codecs encode independently in one row.
        for record in [first, second] {
            let encoded = try layout.encode(record)
            try fixture.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO UUIDCodecRecord (id, legacyBadgeID, note)
                        VALUES (?, ?, ?)
                        """,
                    arguments: StatementArguments(encoded.map(\.databaseValue))
                )
            }
        }

        // Literal: the text preset's canonical output and the blob preset's
        // exact 16-byte layout are both valid inline SQLite literals, not
        // only bound-parameter values.
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO UUIDCodecRecord (id, legacyBadgeID, note)
                    VALUES (
                        'e02f7c60-0000-0000-0000-000000000001',
                        X'11111111000000000000000000000002',
                        NULL
                    )
                    """
            )
        }
        let literalRow = try fixture.pool.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, legacyBadgeID FROM UUIDCodecRecord
                    WHERE id = 'e02f7c60-0000-0000-0000-000000000001'
                    """
            )
        }
        let literalRecord = try XCTUnwrap(literalRow)
        let decodedLiteralID = try XLUUIDValueCodec.text.decode(
            .text(literalRecord["id"]),
            using: dialect,
            context: XLValueCodingContext(site: .result, path: XLValueCodingPath("id"))
        )
        let decodedLiteralBadge = try XLUUIDValueCodec.blob.decode(
            .blob(literalRecord["legacyBadgeID"]),
            using: dialect,
            context: XLValueCodingContext(site: .result, path: XLValueCodingPath("legacyBadgeID"))
        )
        XCTAssertEqual(
            decodedLiteralID,
            UUID(uuidString: "e02f7c60-0000-0000-0000-000000000001")
        )
        XCTAssertEqual(
            decodedLiteralBadge,
            UUID(uuidString: "11111111-0000-0000-0000-000000000002")
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: "DELETE FROM UUIDCodecRecord WHERE id = ?",
                arguments: ["e02f7c60-0000-0000-0000-000000000001"]
            )
        }

        // Indexing + equality: the UNIQUE indexes on both the TEXT and the
        // BLOB column reject a duplicate, at the row level (`first`'s
        // representation is not just Swift-equal but also SQL `=`-equal).
        XCTAssertThrowsError(
            try fixture.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO UUIDCodecRecord (id, legacyBadgeID, note)
                        VALUES (?, ?, NULL)
                        """,
                    arguments: StatementArguments(
                        try layout.encode(first).map(\.databaseValue)
                    )
                )
            }
        ) { error in
            guard let databaseError = error as? DatabaseError else {
                return XCTFail("Expected a GRDB DatabaseError, received \(error).")
            }
            XCTAssertEqual(
                databaseError.extendedResultCode,
                .SQLITE_CONSTRAINT_UNIQUE,
                "Expected a UNIQUE constraint failure, received \(databaseError)."
            )
        }

        // SELECT + result decoding: fetch every row through the generated
        // static layout and decode both UUID representations back.
        let selectAll = sql { _ in
            Select(layout)
            From(table)
            OrderBy(table.id.ascending())
        }
        let selectAllEncoding = try XLiteEncoder(dialect: dialect)
            .makeValidatedSQL(selectAll)
        let selectAllDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "uuid-codec", "select-all"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: selectAllEncoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .many
        )
        let preparedSelectAll = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: selectAllDescriptor,
                layout: layout
            )
        )
        let allRows = try preparedSelectAll.fetchAll(
            bindings: preparedSelectAll.makeInvocationBindings()
        )
        // Text ordering is lexicographic BINARY collation over the lowercase
        // hyphenated string, not creation order or hex magnitude: `second`'s
        // id starts with the digit `2` (0x32), which sorts before `first`'s
        // id, which starts with the lowercased letter `e` (0x65).
        XCTAssertEqual(allRows, [second, first])

        // Named binding + equality: a contextual capture matching the TEXT
        // preset selects one row by its `id` column through a real bound
        // `:` parameter, not an inline literal.
        let idCapture = try database.queryCapture(
            UUID.self,
            matching: table.id.staticStorageExpression(as: String.self),
            identifiedBy: XLQuerySlotIdentity(
                path: ["uuid-codec", "lookup", "id"]
            ),
            selection: .explicit(XLUUIDValueCodec.text.identity.key)
        )
        let selectByID = sql { _ in
            Select(layout)
            From(table)
            Where(table.id.staticStorageExpression(as: String.self) == idCapture)
        }
        let selectByIDEncoding = try XLiteEncoder(dialect: dialect)
            .makeValidatedSQL(selectByID)
        let selectByIDDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "uuid-codec", "select-by-id"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: selectByIDEncoding),
            parameters: [try idCapture.staticQueryParameter(in: selectByIDEncoding)],
            results: layout.metadata.results,
            cardinality: .exactlyOne
        )
        let preparedSelectByID = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: selectByIDDescriptor,
                layout: layout
            )
        )
        let secondByID = try preparedSelectByID.fetchExactlyOne(
            bindings: try preparedSelectByID.makeInvocationBindings(
                idCapture.argument(second.id)
            )
        )
        XCTAssertEqual(secondByID, second)

        // UPDATE: rewrite the BLOB column for a row addressed by its TEXT
        // column, exercising both presets together in one statement.
        let updatedBadgeID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        try fixture.pool.write { db in
            try db.execute(
                sql: "UPDATE UUIDCodecRecord SET legacyBadgeID = ? WHERE id = ?",
                arguments: StatementArguments([
                    try XLUUIDValueCodec.blob.encode(
                        updatedBadgeID,
                        using: dialect,
                        context: XLValueCodingContext(
                            site: .parameter,
                            path: XLValueCodingPath("legacyBadgeID")
                        )
                    ).databaseValue,
                    try XLUUIDValueCodec.text.encode(
                        second.id,
                        using: dialect,
                        context: XLValueCodingContext(
                            site: .parameter,
                            path: XLValueCodingPath("id")
                        )
                    ).databaseValue,
                ])
            )
        }
        let updatedSecond = try preparedSelectByID.fetchExactlyOne(
            bindings: try preparedSelectByID.makeInvocationBindings(
                idCapture.argument(second.id)
            )
        )
        XCTAssertEqual(
            updatedSecond,
            UUIDCodecRecord(
                id: second.id,
                legacyBadgeID: updatedBadgeID,
                note: second.note
            )
        )

        // Optional/NULL: `first.note` was persisted as SQL NULL and decoded
        // back to `nil`; `second.note` (now `updatedSecond.note`) survived a
        // present value through the same nullable TEXT field.
        XCTAssertNil(allRows.last?.note)
        XCTAssertEqual(allRows.first?.note, second.note)
        XCTAssertEqual(updatedSecond.note, second.note)
    }
}


private func makeFixture() throws -> TemporaryDatabaseFixture {
    try TemporaryDatabaseFixture.make(named: "uuid-codec")
}
