import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest

import SwiftQL


// Issue #651: `@SQLTable` accepts a column whose type has no `XLEncodable` conformance, such as
// a `Date` that only a contextual codec can encode. The generated v1 `MetaInsert(row)` and
// `UpdateRequest.makeUpdate()` paths used to trap on such a value. They now record a typed
// `XLSQLValueEncodingError` on the builder, so preparation throws before SQLite sees the
// statement.
//
// The column uses a file-private value type rather than `Date`. `Package.swift` keeps this
// target from *compiling* against SQLTests, but `swift test` loads every test target into one
// `SwiftQLPackageTests` bundle, so at run time the bridge's dynamic `as? any XLEncodable` cast
// still finds SQLTests' retroactive `extension Date: XLCustomType`. A `Date` column therefore
// encodes as a literal in this process instead of reaching the failure path.


private struct ContextualOnlyStamp: Equatable {
    let seconds: Int
}


private enum ContextualOnlyStampCodecError: Error {
    case invalidValue
}


/// A real contextual codec for the column, so the fixture is a valid codec-only column rather
/// than an unsupported type.
private let contextualOnlyStampCodec = XLValueCodec<ContextualOnlyStamp, XLSQLiteDialect>(
    key: XLValueCodecKey(id: "tests.contextual-only-legacy-write.stamp", version: 1),
    valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.contextual-only-stamp"),
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
    encode: { value, _, _ in
        .integer(Int64(value.seconds))
    },
    decode: { value, _, _ in
        guard case .integer(let seconds) = value else {
            throw ContextualOnlyStampCodecError.invalidValue
        }
        return ContextualOnlyStamp(seconds: Int(seconds))
    }
)


@SQLTable(name: "ContextualOnlyLegacyWriteRecord")
private struct ContextualOnlyLegacyWriteRecord: Equatable {
    let id: Int

    @SQLCodec(contextualOnlyStampCodec.identity.key)
    var recordedAt: ContextualOnlyStamp
}


final class ContextualOnlyLegacyWriteGRDBTests: XCTestCase {

    private static let expectedError = XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(
        valueType: String(reflecting: ContextualOnlyStamp.self)
    )

    private var fixture: TemporaryDatabaseFixture!
    private var configuration: XLValueCodingConfiguration!
    private var database: GRDBDatabase!

    override func setUpWithError() throws {
        fixture = try TemporaryDatabaseFixture.make(named: "contextual-only-legacy-write")
        configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(contextualOnlyStampCodec)
        )
        database = try GRDBDatabase(
            databasePool: fixture.pool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE ContextualOnlyLegacyWriteRecord (
                        id INTEGER NOT NULL,
                        recordedAt INTEGER NOT NULL
                    )
                    """
            )
        }
    }

    override func tearDown() {
        database = nil
        configuration = nil
        fixture?.tearDown()
        fixture = nil
    }

    private func rowCount() throws -> Int {
        try fixture.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ContextualOnlyLegacyWriteRecord") ?? -1
        }
    }

    func testFixtureColumnIsAValidCodecOnlyColumn() throws {
        // The declared codec resolves through the database's configuration and encodes the
        // value, so the column is usable through the static-layout path.
        let table = XLSchema().table(ContextualOnlyLegacyWriteRecord.self, as: "record")
        let field = try ContextualOnlyLegacyWriteRecord.staticResultField(
            recordedAt: table.recordedAt,
            storedAs: Int.self,
            identifiedBy: XLQuerySlotIdentity(
                path: ["tests", "contextual-only-legacy-write", "recorded-at"]
            ),
            using: database.dialect,
            configuration: configuration
        )
        XCTAssertEqual(field.selectedCodecIdentity?.key, contextualOnlyStampCodec.identity.key)
    }

    func testErrorMessageNamesTheValueTypeAndTheStaticLayoutPath() {
        XCTAssertEqual(
            XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(
                valueType: "Foundation.Date"
            ).errorDescription,
            "Cannot write Foundation.Date through the v1 MetaInsert/MetaUpdate path: the type does not conform to XLEncodable, so only a contextual codec can encode it. Encode the row through XLStaticRowLayout instead."
        )
    }

    func testInsertValuesRowWithContextualOnlyColumnThrowsTypedError() throws {
        let row = ContextualOnlyLegacyWriteRecord(
            id: 1,
            recordedAt: ContextualOnlyStamp(seconds: 1_700_000_000)
        )
        let statement = sql { schema in
            let record = schema.table(ContextualOnlyLegacyWriteRecord.self)
            Insert(record)
            Values(row)
        }

        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(statement)
        XCTAssertEqual(encoding.valueEncodingError, Self.expectedError)
        XCTAssertThrowsError(
            try XLiteEncoder(formatter: XLiteFormatter()).makeValidatedSQL(statement)
        ) { error in
            XCTAssertEqual(error as? XLSQLValueEncodingError, Self.expectedError)
        }

        XCTAssertThrowsError(try database.makeRequest(with: statement).execute()) { error in
            XCTAssertEqual(error as? XLSQLValueEncodingError, Self.expectedError)
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                Self.expectedError.errorDescription
            )
        }
        XCTAssertThrowsError(try database.makeRequest(with: sqlInsert(row)).execute()) { error in
            XCTAssertEqual(error as? XLSQLValueEncodingError, Self.expectedError)
        }
        XCTAssertEqual(try rowCount(), 0)
    }

    func testUpdateRequestMakeUpdateWithContextualOnlyColumnThrowsTypedError() throws {
        try fixture.pool.write { db in
            try db.execute(
                sql: "INSERT INTO ContextualOnlyLegacyWriteRecord (id, recordedAt) VALUES (1, 42)"
            )
        }
        let request = ContextualOnlyLegacyWriteRecord.UpdateRequest(
            recordedAt: ContextualOnlyStamp(seconds: 1_700_000_000)
        )
        let statement = sql { schema in
            let record = schema.into(ContextualOnlyLegacyWriteRecord.self)
            Update(record)
            Setting(request.makeUpdate())
            Where(record.id == 1)
        }

        XCTAssertEqual(
            XLiteEncoder(formatter: XLiteFormatter()).makeSQL(statement).valueEncodingError,
            Self.expectedError
        )
        XCTAssertThrowsError(try database.makeRequest(with: statement).execute()) { error in
            XCTAssertEqual(error as? XLSQLValueEncodingError, Self.expectedError)
        }
        let stored = try fixture.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT recordedAt FROM ContextualOnlyLegacyWriteRecord")
        }
        XCTAssertEqual(stored, 42)
    }
}
