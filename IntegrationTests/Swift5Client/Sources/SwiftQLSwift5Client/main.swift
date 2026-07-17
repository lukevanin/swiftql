import Foundation
import SwiftQL

#if compiler(<6.0)
#error("The downstream compatibility fixture must use the supported Swift 6 compiler.")
#endif

#if swift(>=6.0)
#error("The downstream compatibility fixture must remain in Swift 5 language mode.")
#endif

@SQLTable(name: "DownstreamPerson")
struct Person: Equatable {
    let id: String
    let name: String
    let age: Int
}

@SQLResult
struct PersonSummary: Equatable {
    let name: String
    let age: Int
}

enum FixtureError: Error {
    case unexpectedResult(PersonSummary?)
}

private func executeFixture(databaseURL: URL) throws -> PersonSummary? {
    let database = try GRDBDatabase(url: databaseURL, logger: nil)
    try database.makeRequest(with: sqlCreate(Person.self)).execute()
    try database.makeRequest(
        with: sqlInsert(Person(id: "ada", name: "Ada Lovelace", age: 36))
    ).execute()
    try database.makeRequest(
        with: sqlInsert(Person(id: "grace", name: "Grace Hopper", age: 85))
    ).execute()

    let id = XLNamedBindingReference<String>(name: "id")
    let statement = sql { schema in
        let person = schema.table(Person.self)
        Select(
            PersonSummary.columns(
                name: person.name,
                age: person.age
            )
        )
        From(person)
        Where(person.id == id)
    }
    var request = database.makeRequest(with: statement)
    request.set(id, "grace")
    return try request.fetchOne()
}

private func runFixture() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-swift5-client-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let result = try executeFixture(
        databaseURL: directory.appendingPathComponent("fixture.sqlite")
    )
    guard result == PersonSummary(name: "Grace Hopper", age: 85) else {
        throw FixtureError.unexpectedResult(result)
    }
}

try runFixture()
print("SWIFTQL_DOWNSTREAM_SWIFT5_CLIENT ok")
