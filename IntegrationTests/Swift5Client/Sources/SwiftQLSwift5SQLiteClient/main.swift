// Issue #790: a client that depends on the SwiftQLSQLite product alone, with
// no GRDB, in Swift 5 language mode. Its models expand the dialect-less model
// macros, whose expansions name SwiftQLQuery, SwiftQLCore, and SwiftQLSQLite,
// so this target is the end-to-end check, from outside the package, that the
// macros qualify every name with a module a SQLite-only client can see.
import SwiftQLSQLite

#if compiler(<6.0)
#error("The downstream compatibility fixture must use the supported Swift 6 compiler.")
#endif

#if swift(>=6.0)
#error("The downstream compatibility fixture must remain in Swift 5 language mode.")
#endif

@SQLTable(name: "DownstreamSQLitePerson")
struct Person: Equatable {
    let id: String
    let name: String
    let age: Int
    let level: Level
}

@SQLResult
struct PersonSummary: Equatable {
    let name: String
    let age: Int
}

/// An enum declared with SQLite's v1 name, which is now a composition of the
/// dialect-neutral requirements and SQLite's expression protocol.
enum Level: Int, XLEnum {
    typealias T = Self

    case junior = 0
    case senior = 1

    static func sqlDefault() -> Level {
        .junior
    }
}

enum FixtureError: Error {
    case unexpectedSQL(String)
}

let statement = sql { schema in
    let person = schema.table(Person.self)
    Select(PersonSummary.columns(name: person.name, age: person.age))
    From(person)
    Where(person.age >= 18 && person.level == Level.senior)
    OrderBy(person.name.collate(.nocase).ascending())
}

let encoder = XLiteEncoder(formatter: XLiteFormatter())
let rendered = encoder.makeSQL(statement).sql
let expected = #"SELECT "t0"."name" AS "name", "t0"."age" AS "age" FROM "DownstreamSQLitePerson" AS "t0" WHERE (("t0"."age" >= 18) AND ("t0"."level" == 1)) ORDER BY ("t0"."name" COLLATE NOCASE) ASC"#
guard rendered == expected else {
    throw FixtureError.unexpectedSQL(rendered)
}

print("SWIFTQL_DOWNSTREAM_SWIFT5_SQLITE_CLIENT ok")
