import CSQLite
import GRDB
import XCTest

@testable import SwiftQLSQLiteBuildValidationPrototype


final class SQLitePrepareV3ProbeTests: XCTestCase {
    typealias Support = SQLiteBuildValidationTestSupport

    func testEmptyCommentSingleTrailingCommentAndMultipleStatementTails() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            assertProbeError(sql: "", expected: .emptyStatement, database: database)
            assertProbeError(
                sql: "-- comment only\n/* and another comment */",
                expected: .emptyStatement,
                database: database
            )

            let single = try SQLitePrepareV3Probe.prepare(
                sql: "SELECT 1 AS one",
                in: database
            )
            XCTAssertEqual(single.physicalParameterCount, 0)
            XCTAssertEqual(single.parameters, [])
            XCTAssertEqual(
                single.columns,
                [SQLitePreparedColumn(index: 0, name: "one", declaredType: nil)]
            )
            XCTAssertTrue(single.isReadOnly)

            let trailingComment = try SQLitePrepareV3Probe.prepare(
                sql: "SELECT 1 AS one; -- accepted trailing comment\n/* done */",
                in: database
            )
            XCTAssertEqual(trailingComment, single)

            assertProbeError(
                sql: "SELECT 1; SELECT 2",
                expected: .multipleStatements,
                database: database
            )
        }
    }

    func testInvalidTailSyntaxMissingTableAndMissingColumnPreserveSQLiteFailure() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            for sql in [
                "SELECT 1; SELECT FROM",
                "SELECT FROM",
                "SELECT * FROM definitely_missing_table",
                "SELECT definitely_missing_column FROM Customers",
            ] {
                XCTAssertThrowsError(
                    try SQLitePrepareV3Probe.prepare(sql: sql, in: database)
                ) { error in
                    guard case .sqlitePrepare(
                        let resultCode,
                        let extendedResultCode,
                        let message
                    ) = error as? SQLitePrepareV3ProbeError else {
                        return XCTFail(
                            "Expected SQLite preparation failure for \(sql), received \(error)"
                        )
                    }
                    XCTAssertEqual(resultCode, SQLITE_ERROR)
                    XCTAssertNotEqual(extendedResultCode, SQLITE_OK)
                    XCTAssertFalse(message.isEmpty)
                }
            }
        }
    }

    func testEmbeddedNULIsRejectedBeforeSQLiteCanTruncateIt() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            assertProbeError(
                sql: "SELECT 1\0; SELECT 2",
                expected: .embeddedNUL,
                database: database
            )
        }
    }

    func testBindingMetadataIncludesHighestIndexGapsRepeatedNamesAndAnonymousAmbiguity() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            let shape = try SQLitePrepareV3Probe.prepare(
                sql: "SELECT :name, ?3, :name, @other, $cash",
                in: database
            )
            XCTAssertEqual(shape.physicalParameterCount, 5)
            XCTAssertEqual(shape.parameters, [
                SQLitePreparedParameter(physicalIndex: 1, name: ":name"),
                SQLitePreparedParameter(physicalIndex: 2, name: nil),
                SQLitePreparedParameter(physicalIndex: 3, name: "?3"),
                SQLitePreparedParameter(physicalIndex: 4, name: "@other"),
                SQLitePreparedParameter(physicalIndex: 5, name: "$cash"),
            ])
            XCTAssertEqual(shape.columns.count, 5)

            let anonymous = try SQLitePrepareV3Probe.prepare(
                sql: "SELECT ?, ?",
                in: database
            )
            XCTAssertEqual(anonymous.physicalParameterCount, 2)
            XCTAssertEqual(anonymous.parameters.map(\.name), [nil, nil])
        }
    }

    func testNorthwindResultAliasesCountAndDeclaredTypeEvidence() throws {
        try Support.withReadOnlyNorthwindDatabase { database in
            let shape = try SQLitePrepareV3Probe.prepare(
                sql: """
                    SELECT CustomerID AS customer_id,
                           CompanyName AS company_name,
                           LENGTH(CompanyName) AS company_name_length
                    FROM Customers
                    """,
                in: database
            )

            XCTAssertEqual(shape.columns.count, 3)
            XCTAssertEqual(
                shape.columns.map(\.name),
                ["customer_id", "company_name", "company_name_length"]
            )
            XCTAssertEqual(shape.columns.map(\.declaredType), ["TEXT", "TEXT", nil])
            XCTAssertTrue(shape.isReadOnly)
        }
    }

    private func assertProbeError(
        sql: String,
        expected: SQLitePrepareV3ProbeError,
        database: GRDB.Database,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SQLitePrepareV3Probe.prepare(sql: sql, in: database),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SQLitePrepareV3ProbeError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
