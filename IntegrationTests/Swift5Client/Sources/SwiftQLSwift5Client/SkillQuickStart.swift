// The three regions below are the only Swift SKILL.md is allowed to show.
// They are compiled by this downstream Swift 5 consumer package and executed
// by `main.swift`, and `SQLSkillDocumentationTests` fails if SKILL.md and this
// file ever drift apart.

// swiftql-skill-example-begin: schema
import SwiftQL

@SQLTable(name: "SkillPerson")
struct SkillPerson: Equatable {
    var id: String
    var name: String
}

@SQLQueries
extension GRDBDatabase {

    // Generated executors become members of `GRDBDatabase`, never of this
    // container, so the container stays private to its file.
    private struct Query {

        // The return type chooses the cardinality: `[Row]` fetches every
        // match, `Row?` fetches zero or one, and a bare `Row` insists on
        // exactly one.
        func skillPeopleByName(name: String) -> [SkillPerson] {
            sqlResult { schema in
                let person = schema.table(SkillPerson.self)
                Select(person)
                From(person)
                Where(person.name == name)
            }
        }
    }
}
// swiftql-skill-example-end: schema

// swiftql-skill-example-begin: lifecycle
enum SkillQueryError: Error {
    case missingParameter(String)
}

// A request owns rendered SQL and an immutable parameter layout. Values for
// one call live in a separate packet built against that layout.
func skillTextPacket(
    _ parameters: [(name: String, value: String)],
    for layout: XLParameterLayout
) throws -> XLInvocationBindings<XLSQLiteValue> {
    try XLInvocationBindings<XLSQLiteValue>(
        layout: layout,
        bindings: try parameters.map { parameter in
            guard let slot = layout.slot(for: .named(parameter.name)) else {
                throw SkillQueryError.missingParameter(parameter.name)
            }
            return try XLInvocationBinding(
                slot: slot,
                value: .text(parameter.value)
            )
        }
    ).validatingComplete()
}

func runSkillLifecycle(in database: GRDBDatabase) throws -> [SkillPerson] {
    // `sqlCreate` renders `CREATE TABLE IF NOT EXISTS`. It is not a migration
    // engine and never alters an existing table.
    try database.makeRequest(with: sqlCreate(SkillPerson.self)).execute()

    // Statements that must succeed or fail together share one transaction on
    // one pinned connection. Use `scope`, never the captured `database`.
    try database.withTransaction { scope in
        try scope.makeRequest(
            with: sqlInsert(SkillPerson(id: "ada", name: "Ada Lovelace"))
        ).execute()
        try scope.makeRequest(
            with: sqlInsert(SkillPerson(id: "grace", name: "Grace Hopper"))
        ).execute()
    }

    // The declared query renders once per database and reuses one prepared
    // statement. Each call builds a fresh immutable packet from its arguments.
    _ = try database.skillPeopleByName(name: "Grace Hopper")

    // Writes are not a declared-query shape in v1.5, so they keep their values
    // out of the rendered SQL with named bindings instead.
    let idParameter = XLNamedBindingReference<String>(name: "id")
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let renameRequest = database.makeRequest(
        with: sql { schema in
            let person = schema.into(SkillPerson.self)
            Update(person)
            Setting(person) { row in
                row.name = nameParameter
            }
            Where(person.id == idParameter)
        }
    )
    try renameRequest.execute(
        bindings: try skillTextPacket(
            [
                (name: "id", value: "grace"),
                (name: "name", value: "Grace B. Hopper"),
            ],
            for: renameRequest.parameterLayout
        )
    )

    let deleteRequest = database.makeRequest(
        with: sql { schema in
            let person = schema.into(SkillPerson.self)
            Delete(person)
            Where(person.id == idParameter)
        }
    )
    try deleteRequest.execute(
        bindings: try skillTextPacket(
            [(name: "id", value: "grace")],
            for: deleteRequest.parameterLayout
        )
    )

    return try database.skillPeopleByName(name: "Ada Lovelace")
}
// swiftql-skill-example-end: lifecycle

// swiftql-skill-example-begin: live
func observeSkillPeople(
    named name: String,
    in database: GRDBDatabase
) async throws {
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let request = database.makeRequest(
        with: sql { schema in
            let person = schema.table(SkillPerson.self)
            Select(person)
            From(person)
            Where(person.name == nameParameter)
        }
    )
    let bindings = try skillTextPacket(
        [(name: "name", value: name)],
        for: request.parameterLayout
    )
    // The packet is captured once; every refresh and retry reuses it.
    // Cancelling the consuming task ends iteration and tears the observation
    // down, and never throws `CancellationError`.
    for try await people in request.stream(bindings: bindings) {
        print("\(people.count) matching rows")
    }
}
// swiftql-skill-example-end: live
