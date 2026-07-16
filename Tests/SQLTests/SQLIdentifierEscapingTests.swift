import GRDB
import XCTest
import SwiftQL


final class XLIdentifierEscapingTests: XCTestCase {

    func testIdentifierModesEscapeTheirClosingDelimiters() {
        XCTAssertEqual(encodedName(#"a"b"#, using: .sqlite), #""a""b""#)
        XCTAssertEqual(encodedName("a`b", using: .mysqlCompatible), "`a``b`")
        XCTAssertEqual(encodedName("ordinary", using: .microsoftCompatible), "[ordinary]")
        XCTAssertEqual(encodedName("a]b", using: .microsoftCompatible), #""a]b""#)
        XCTAssertEqual(encodedName(#"a]"b"#, using: .microsoftCompatible), #""a]""b""#)
    }

    func testScopedNamesQuoteEachComponentWithoutSplittingDots() {
        let encoder = makeEncoder(using: .sqlite)
        let name = XLQualifiedTableName(
            schema: XLSchemaName(name: "schema.with space"),
            name: "table.with.dot"
        )
        let encoding = encoder.makeSQL(name)

        XCTAssertEqual(encoding.sql, #""schema.with space"."table.with.dot""#)
        XCTAssertEqual(encoding.entities, ["table.with.dot"])
    }

    func testSafeIdentifierModesExecuteHostileTableColumnAndAliases() throws {
        let hostileName = #"select weird.name "quote" `tick` ] ; DROP TABLE sentinel; --"#
        let columnName = #"value.with space "quote" `tick` ]"#
        let tableAlias = #"from.alias "quote" `tick` ]"#
        let resultAlias = #"result.alias "quote" `tick` ] UNION ALL SELECT 'injected' --"#
        let payload = "intended value"

        for mode in safeModes {
            let databaseQueue = try DatabaseQueue()
            let tableSQL = encodedName(hostileName, using: mode)
            let columnSQL = encodedName(columnName, using: mode)
            let tableAliasSQL = encodedName(tableAlias, using: mode)
            let resultAliasSQL = encodedName(resultAlias, using: mode)

            try databaseQueue.write { database in
                try database.execute(sql: "CREATE TABLE sentinel (value TEXT NOT NULL)")
                try database.execute(sql: "CREATE TABLE \(tableSQL) (\(columnSQL) TEXT NOT NULL)")
                try database.execute(
                    sql: "INSERT INTO \(tableSQL) (\(columnSQL)) VALUES (?)",
                    arguments: [payload]
                )

                let rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT \(tableAliasSQL).\(columnSQL) AS \(resultAliasSQL)
                        FROM \(tableSQL) AS \(tableAliasSQL)
                        """
                )
                XCTAssertEqual(rows.count, 1, "The hostile identifier added a clause in mode: \(mode)")
                let row = try XCTUnwrap(rows.first)
                let value: String = row[resultAlias]
                XCTAssertEqual(value, payload, "Failed mode: \(mode)")
                XCTAssertEqual(Array(row.columnNames), [resultAlias], "Failed mode: \(mode)")

                XCTAssertEqual(
                    try String.fetchOne(
                        database,
                        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [hostileName]
                    ),
                    hostileName,
                    "Failed mode: \(mode)"
                )
                XCTAssertEqual(
                    try String.fetchAll(
                        database,
                        sql: "SELECT name FROM pragma_table_info(?)",
                        arguments: [hostileName]
                    ),
                    [columnName],
                    "Failed mode: \(mode)"
                )
                XCTAssertEqual(
                    try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'sentinel'"
                    ),
                    1,
                    "The hostile identifier altered a separate statement in mode: \(mode)"
                )
            }
        }
    }

    func testMicrosoftCompatibleBracketSyntaxExecutesHostileName() throws {
        let hostileName = #"select weird.name "quote" `tick` ; DROP TABLE sentinel; --"#
        let tableSQL = encodedName(hostileName, using: .microsoftCompatible)
        let databaseQueue = try DatabaseQueue()

        XCTAssertEqual(tableSQL, "[\(hostileName)]")
        try databaseQueue.write { database in
            try database.execute(sql: "CREATE TABLE sentinel (value TEXT NOT NULL)")
            try database.execute(sql: "CREATE TABLE \(tableSQL) (value TEXT NOT NULL)")
            try database.execute(sql: "INSERT INTO \(tableSQL) (value) VALUES ('intended value')")

            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(tableSQL)"), 1)
            XCTAssertEqual(
                try String.fetchOne(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [hostileName]
                ),
                hostileName
            )
            XCTAssertEqual(
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'sentinel'"
                ),
                1
            )
        }
    }

    func testNoEscapePreservesTrustedStaticInput() {
        let trustedName = "main.StaticTable"
        XCTAssertEqual(encodedName(trustedName, using: .noEscape), trustedName)
    }

    private var safeModes: [XLiteFormatter.IdentifierFormattingOptions] {
        [.sqlite, .mysqlCompatible, .microsoftCompatible]
    }

    private func encodedName(
        _ name: String,
        using mode: XLiteFormatter.IdentifierFormattingOptions
    ) -> String {
        makeEncoder(using: mode).makeSQL(XLName(name)).sql
    }

    private func makeEncoder(
        using mode: XLiteFormatter.IdentifierFormattingOptions
    ) -> XLiteEncoder {
        XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: mode)
        )
    }
}
