//
//  PostgreSQLGoldenRenderingTests.swift
//
//  The acceptance gate for the dialect rendering seam (#673, #674, #675).
//
//  Every case here renders one statement twice: once through SQLite and once
//  through PostgreSQL. The nodes, the builder, and the encoder are identical
//  in both passes. Only the dialect differs, so any difference in the output
//  is the seam doing its job.
//
//  The PostgreSQL text is pinned in
//  `Conformance/PostgreSQL/GOLDEN.sql`. Set
//  SWIFTQL_UPDATE_POSTGRESQL_GOLDEN=1 to rewrite it after an intended change,
//  then read the diff before committing.
//
//  This is a rendering proof. There is no driver, no transport, and no live
//  server, and SwiftQL does not claim PostgreSQL support.
//

import Foundation
import SwiftQLTestSupport
import XCTest
import SwiftQL


@SQLTable(name: "Person")
struct GoldenPerson: Equatable {
    let id: String
    let name: String
    let nickname: String?
    let age: Int
    let avatar: Data
}


@SQLResult
struct GoldenNameRow: Equatable {
    let name: String
}


final class PostgreSQLGoldenRenderingTests: XCTestCase {

    // MARK: - The corpus

    ///
    /// One statement rendered through both dialects.
    ///
    private struct Case {
        let name: String
        let statement: any XLEncodable
        let sqlite: String

        /// Written into the golden file when this case renders legal SQL
        /// whose meaning differs from the SQLite rendering.
        var warning: String? = nil
    }

    private func corpus() -> [Case] {


        return [
            Case(
                name: "select-all",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0""#
            ),
            Case(
                name: "equality-on-non-optional",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                    Where(person.age == 42)
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0" WHERE ("t0"."age" == 42)"#
            ),
            Case(
                name: "null-safe-equality-on-optional",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                    Where(person.nickname == person.name)
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0" WHERE ("t0"."nickname" IS "t0"."name")"#
            ),
            Case(
                name: "null-test",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                    Where(person.nickname.isNull())
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0" WHERE ("t0"."nickname" ISNULL)"#
            ),
            Case(
                name: "regex-match",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                    Where(person.name.regexp("^A.*n$"))
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0" WHERE ("t0"."name" REGEXP '^A.*n$')"#
            ),
            Case(
                name: "collate-binary",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Select(GoldenNameRow.columns(name: person.name))
                    From(person)
                    Where(person.name.collate(.binary) == person.name)
                },
                sqlite: #"SELECT "t0"."name" AS "name" FROM "Person" AS "t0" WHERE (("t0"."name" COLLATE BINARY) == "t0"."name")"#
            ),
            Case(
                name: "insert-with-values",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Insert(person)
                    Values(
                        GoldenPerson.MetaInsert(
                            GoldenPerson(
                                id: "a",
                                name: "Ada",
                                nickname: nil,
                                age: 36,
                                avatar: Data([0x01])
                            )
                        )
                    )
                },
                sqlite: #"INSERT INTO "Person" AS "t0" ("id","name","nickname","age","avatar") VALUES ('a','Ada',NULL,36,x'01')"#
            ),
            Case(
                name: "insert-or-ignore",
                statement: sql { schema in
                    let person = schema.table(GoldenPerson.self)
                    Insert(person, or: .ignore)
                    Values(
                        GoldenPerson.MetaInsert(
                            GoldenPerson(
                                id: "a",
                                name: "Ada",
                                nickname: nil,
                                age: 36,
                                avatar: Data([0x01])
                            )
                        )
                    )
                },
                // SQLite carries the conflict algorithm in the opening
                // keyword. PostgreSQL cannot, and the golden file shows it
                // rendering a plain INSERT: gap G4.
                sqlite: #"INSERT OR IGNORE INTO "Person" AS "t0" ("id","name","nickname","age","avatar") VALUES ('a','Ada',NULL,36,x'01')"#,
                warning: "GAP G4: the OR IGNORE conflict algorithm is dropped. "
                    + "This statement raises on conflict instead of skipping "
                    + "the row. A driver must refuse it, not run it."
            ),
            Case(
                name: "blob-literal",
                statement: LiteralProbe(data: Data([0xde, 0xad, 0xbe, 0xef])),
                sqlite: "x'deadbeef'"
            ),
            Case(
                name: "text-literal-with-quote",
                statement: TextProbe(text: "O'Hara"),
                sqlite: "'O''Hara'"
            ),
            Case(
                name: "conditional",
                statement: ConditionalProbe(),
                sqlite: "IIF(1, 2, 3)"
            ),
            Case(
                name: "named-parameter-twice",
                statement: RepeatedParameterProbe(),
                sqlite: ":alpha :alpha"
            ),
            Case(
                name: "mixed-parameters",
                statement: MixedParameterProbe(),
                sqlite: ":alpha ?5 :beta"
            ),
        ]
    }

    // MARK: - The gate

    func testSQLiteCorpusIsUnchanged() {
        let encoder = XLiteEncoder(formatter: XLiteFormatter())
        for testCase in corpus() {
            XCTAssertEqual(
                encoder.makeSQL(testCase.statement).sql,
                testCase.sqlite,
                "SQLite rendering changed for \(testCase.name)"
            )
        }
    }

    func testPostgreSQLRenderingMatchesTheGoldenFile() throws {
        let encoder = XLDialectEncoder(dialect: XLPostgreSQLDialect())

        var rendered = ""
        for testCase in corpus() {
            rendered += "-- \(testCase.name)\n"
            if let warning = testCase.warning {
                rendered += "-- !! \(warning)\n"
            }
            rendered += encoder.makeSQL(testCase.statement).sql
            rendered += "\n\n"
        }

        let goldenURL = try swiftQLRepositoryRootURL()
            .appendingPathComponent("Conformance")
            .appendingPathComponent("PostgreSQL")
            .appendingPathComponent("GOLDEN.sql")

        if ProcessInfo.processInfo.environment["SWIFTQL_UPDATE_POSTGRESQL_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: goldenURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try (Self.header + rendered).write(to: goldenURL, atomically: true, encoding: .utf8)
            return
        }

        let expected = try String(contentsOf: goldenURL, encoding: .utf8)
        XCTAssertEqual(
            Self.header + rendered,
            expected,
            "PostgreSQL rendering drifted from the golden file"
        )
    }

    // MARK: - The claims the golden file makes

    func testPostgreSQLSpellsThePlaceholdersPositionally() {
        let encoder = XLDialectEncoder(dialect: XLPostgreSQLDialect())

        // Two references to one name are one parameter, so both render `$1`.
        let repeated = encoder.makeSQL(RepeatedParameterProbe())
        XCTAssertEqual(repeated.sql, "$1 $1")
        XCTAssertEqual(repeated.parameterLayout.slots.count, 1)
        XCTAssertEqual(repeated.parameterLayout.occurrences.count, 2)

        // A statement written with named parameters needs only positional
        // binding once PostgreSQL has rendered it.
        XCTAssertEqual(
            repeated.dialectRequirement.capabilities,
            [.indexedBindings]
        )

        // An explicit SwiftQL index does not survive as a wire position.
        XCTAssertEqual(encoder.makeSQL(MixedParameterProbe()).sql, "$1 $2 $3")
    }

    func testPostgreSQLRequiresNoRegisteredFunctionForARegexMatch() {
        let encoder = XLDialectEncoder(dialect: XLPostgreSQLDialect())
        let statement = sql { schema in
            let person = schema.table(GoldenPerson.self)
            Select(GoldenNameRow.columns(name: person.name))
            From(person)
            Where(person.name.regexp("^A.*n$"))
        }
        XCTAssertTrue(encoder.makeSQL(statement).customFunctions.isEmpty)
    }

    private static let header = """
        -- Golden PostgreSQL rendering for the v2 dialect seam (#675).
        --
        -- Generated by PostgreSQLGoldenRenderingTests. Do not edit by hand:
        -- run the suite with SWIFTQL_UPDATE_POSTGRESQL_GOLDEN=1 instead.
        --
        -- A rendering proof only. SwiftQL has no PostgreSQL driver and claims
        -- no PostgreSQL support. Known gaps are recorded in
        -- Documentation/Architecture/PostgreSQLRenderingGaps.md.


        """
}


// MARK: - Literal and parameter probes


private struct LiteralProbe: XLEncodable {

    let data: Data

    func makeSQL(context: inout XLBuilder) {
        context.blob(data)
    }
}


private struct TextProbe: XLEncodable {

    let text: String

    func makeSQL(context: inout XLBuilder) {
        context.text(text)
    }
}


private struct ConditionalProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.conditional(
            .immediateIf,
            condition: { $0.integer(1) },
            whenTrue: { $0.integer(2) },
            whenFalse: { $0.integer(3) }
        )
    }
}


private struct RepeatedParameterProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding(XLName("alpha"))
        context.namedBinding(XLName("alpha"))
    }
}


private struct MixedParameterProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding(XLName("alpha"))
        context.indexedBinding(4)
        context.namedBinding(XLName("beta"))
    }
}
