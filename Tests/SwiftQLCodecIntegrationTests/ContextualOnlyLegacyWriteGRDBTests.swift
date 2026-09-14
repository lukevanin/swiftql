import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest

import SwiftQL


// Issue #651: `@SQLTable` accepts a column whose type has no `XLLiteral` conformance, such as
// a `Date` that only a contextual codec can encode. The generated v1 `MetaInsert(row)` and
// `UpdateRequest.makeUpdate()` paths used to trap on such a value. They now record a typed
// `XLSQLValueEncodingError` on the builder, so preparation throws before SQLite sees the
// statement.
//
// The column uses a file-private value type rather than `Date`: every test target shares one
// test process, and the legacy SQLTests suite retroactively conforms `Date` to
// `XLCustomType`, which the bridge's dynamic `XLEncodable` cast would then find.


private struct ContextualOnlyStamp: Equatable {
    let seconds: Int
}


@SQLTable(name: "ContextualOnlyLegacyWriteRecord")
private struct ContextualOnlyLegacyWriteRecord: Equatable {
    let id: Int
    var recordedAt: ContextualOnlyStamp
}


final class ContextualOnlyLegacyWriteGRDBTests: XCTestCase {

    private static let expectedError = XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(
        valueType: String(reflecting: ContextualOnlyStamp.self)
    )

    private var fixture: TemporaryDatabaseFixture!
    private var database: GRDBDatabase!

    override func setUpWithError() throws {
        fixture = try TemporaryDatabaseFixture.make(named: "contextual-only-legacy-write")
        database = try GRDBDatabase(
            databasePool: fixture.pool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE ContextualOnlyLegacyWriteRecord (
                        id INTEGER NOT NULL,
                        recordedAt TEXT NOT NULL
                    )
                    """
            )
        }
    }

    override func tearDown() {
        database = nil
        fixture?.tearDown()
        fixture = nil
    }

    private func rowCount() throws -> Int {
        try fixture.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ContextualOnlyLegacyWriteRecord") ?? -1
        }
    }

    func testErrorMessageNamesTheValueTypeAndTheStaticLayoutPath() {
        XCTAssertEqual(
            XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(
                valueType: "Foundation.Date"
            ).errorDescription,
            "Cannot write Foundation.Date through the v1 MetaInsert/MetaUpdate path: it is a contextual-only SQL value with no XLLiteral conformance. Encode the row through XLStaticRowLayout instead."
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
                sql: "INSERT INTO ContextualOnlyLegacyWriteRecord (id, recordedAt) VALUES (1, 'original')"
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
            try String.fetchOne(db, sql: "SELECT recordedAt FROM ContextualOnlyLegacyWriteRecord")
        }
        XCTAssertEqual(stored, "original")
    }
}
