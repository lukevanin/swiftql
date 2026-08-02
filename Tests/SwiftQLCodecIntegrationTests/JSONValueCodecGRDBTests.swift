import Foundation
import GRDB
import XCTest
@testable import SwiftQL


/// Real GRDB/SQLite round trips for ``XLJSONValueCodec``. Value-level
/// behavior (round trips, NULL, malformed JSON, schema evolution, and
/// encoder/decoder failures) is covered without a database connection in
/// `JSONValueCodecContractTests`; this file confirms the same codecs behave
/// identically once real SQLite has stored and returned the bytes.
final class JSONValueCodecGRDBTests: XCTestCase {

    private let sampleProfile = JSONCodecFixtureProfile(
        name: "Ada Lovelace",
        tags: ["engineer", "mathematician"],
        address: JSONCodecFixtureAddress(street: "12 Analytical Ave", city: "London"),
        contact: .email("ada@example.com"),
        loyaltyPoints: 42
    )

    func testProfileRoundTripsAsTextAndBlobThroughRealSQLite() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry()
            .registering(jsonCodecFixtureProfileTextCodec)
            .registering(jsonCodecFixtureProfileBlobCodec)
        let codingConfiguration = try XLValueCodingConfiguration(registry: registry)
        let dialect = XLSQLiteDialect()

        var driver = GRDBDatabaseDriver(
            databasePool: fixture.databasePool,
            dialect: dialect
        )
        let create = logicalStatement(
            for: driver,
            sql: """
                CREATE TABLE json_profiles (
                    profile_text TEXT NOT NULL,
                    profile_blob BLOB NOT NULL
                )
                """
        )
        let insert = logicalStatement(
            for: driver,
            sql: """
                INSERT INTO json_profiles (profile_text, profile_blob)
                VALUES (:profile_text, :profile_blob)
                """
        )
        let select = logicalStatement(
            for: driver,
            sql: """
                SELECT
                    profile_text, typeof(profile_text),
                    profile_blob, typeof(profile_blob)
                FROM json_profiles
                """
        )

        let textValue = try codingConfiguration.encode(
            sampleProfile,
            using: dialect,
            context: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("profile_text")
            ),
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
        )
        let blobValue = try codingConfiguration.encode(
            sampleProfile,
            using: dialect,
            context: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("profile_blob")
            ),
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureBlobKey)
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            statement = try connection.bind(textValue, to: .named("profile_text"), in: statement)
            statement = try connection.bind(blobValue, to: .named("profile_blob"), in: statement)
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }

        XCTAssertEqual(row[1], .text("text"))
        XCTAssertEqual(row[3], .text("blob"))

        let decodedFromText = try codingConfiguration.decode(
            JSONCodecFixtureProfile.self,
            from: row[0],
            using: dialect,
            context: XLValueCodingContext(site: .result, path: XLValueCodingPath("profile_text")),
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
        )
        let decodedFromBlob = try codingConfiguration.decode(
            JSONCodecFixtureProfile.self,
            from: row[2],
            using: dialect,
            context: XLValueCodingContext(site: .result, path: XLValueCodingPath("profile_blob")),
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureBlobKey)
        )

        XCTAssertEqual(decodedFromText, sampleProfile)
        XCTAssertEqual(decodedFromBlob, sampleProfile)
    }

    func testNullColumnRoundTripsThroughRealSQLiteUsingOptionalComposition() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.databasePool, dialect: dialect)
        let create = logicalStatement(
            for: driver,
            sql: "CREATE TABLE optional_profiles (profile TEXT)"
        )
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO optional_profiles (profile) VALUES (:profile)"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT profile, typeof(profile) FROM optional_profiles"
        )
        let context = XLValueCodingContext(site: .parameter, path: XLValueCodingPath("profile"))

        // Optionality composes outside the nonoptional JSON codec: `nil`
        // becomes SQL `NULL` without the codec's encode closure running.
        let nullValue = try codingConfiguration.encodeOptional(
            Optional<JSONCodecFixtureProfile>.none,
            using: dialect,
            context: context
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            var statement = try connection.prepare(insert)
            statement = try connection.bind(nullValue, to: .named("profile"), in: statement)
            try connection.execute(statement)
        }

        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }
        XCTAssertEqual(row, [.null, .text("null")])

        let decoded: JSONCodecFixtureProfile? = try codingConfiguration.decodeOptional(
            JSONCodecFixtureProfile.self,
            from: row[0],
            using: dialect,
            context: XLValueCodingContext(site: .result, path: context.path)
        )
        XCTAssertNil(decoded)
    }

    func testMalformedStoredJSONFailsAtDecodeRatherThanReturningADefaultValue() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        let dialect = XLSQLiteDialect()
        var driver = GRDBDatabaseDriver(databasePool: fixture.databasePool, dialect: dialect)
        let create = logicalStatement(
            for: driver,
            sql: "CREATE TABLE corrupt_profiles (profile TEXT NOT NULL)"
        )
        // Bypasses the codec entirely to simulate a row corrupted or
        // hand-edited outside of SwiftQL, e.g. by direct SQL or an older,
        // incompatible application version.
        let insert = logicalStatement(
            for: driver,
            sql: "INSERT INTO corrupt_profiles (profile) VALUES ('{this is not json')"
        )
        let select = logicalStatement(
            for: driver,
            sql: "SELECT profile FROM corrupt_profiles"
        )

        try driver.withWriteConnection { connection in
            try connection.execute(connection.prepare(create))
            try connection.execute(connection.prepare(insert))
        }
        let row = try driver.withReadConnection { connection in
            try XCTUnwrap(connection.fetchOne(connection.prepare(select)))
        }

        XCTAssertThrowsError(
            try codingConfiguration.decode(
                JSONCodecFixtureProfile.self,
                from: row[0],
                using: dialect,
                context: XLValueCodingContext(
                    site: .result,
                    path: XLValueCodingPath("profile")
                )
            )
        ) { error in
            guard case .decodingFailed(let codec, _, let message)? =
                error as? XLValueCodecError else {
                return XCTFail("Expected a structured decodingFailed error, got \(error)")
            }
            XCTAssertEqual(codec, jsonCodecFixtureTextKey)
            XCTAssertTrue(message.contains("JSON decoding"))
        }
    }

    func testDatabaseSnapshotsTheRegisteredJSONCodecsImmutably() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let registry = try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        let database = try GRDBDatabase(
            databasePool: fixture.databasePool,
            codingConfiguration: codingConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )

        XCTAssertEqual(
            database.codingConfiguration.registry.identities.map(\.key),
            [jsonCodecFixtureTextKey]
        )
        XCTAssertEqual(database.codingConfiguration.defaultCodecKeys, [jsonCodecFixtureTextKey])
    }

    private func logicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            sql: sql
        )
    }

    private func makeFixture() throws -> JSONCodecFixtureDatabase {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-json-codec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return JSONCodecFixtureDatabase(
            directoryURL: directoryURL,
            databasePool: try DatabasePool(
                path: directoryURL.appendingPathComponent("database.sqlite").path
            )
        )
    }
}


private struct JSONCodecFixtureDatabase {
    let directoryURL: URL
    let databasePool: DatabasePool

    func tearDown() {
        try? databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
