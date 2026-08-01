/*:
 # Import check

 This page proves the plumbing rather than teaching anything.

 SwiftQL's API is built on macros, and expanding a macro needs a compiler
 plugin that SwiftPM builds and hands to the compiler. A classic Xcode
 playground has no `Package.swift` of its own and no reliable way to load that
 plugin, so a page that writes `@SQLTable` cannot be counted on to compile.

 The example tables and queries are therefore declared in `SwiftQLExamples`, a
 target of the SwiftQL package that this workspace also contains, and their
 macros expand during the ordinary package build. By the time this page runs,
 `Person`, `Occupation`, and the generated `fetch…` executors are ordinary
 compiled API, and nothing below expands a macro.

 If the import fails with "no such module", select the **SwiftQLExamples**
 scheme with **My Mac** as the destination and build (⌘B). `Examples/README.md`
 has the full setup.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

//: A database with the example schema created and a few rows already in it.
let database = try ExampleDatabase.makeSeeded()

/*:
 A query written in the playground itself. `sql { }` is an ordinary function
 taking a result builder, so writing one here is fine. Only the `@SQLTable`
 declaration of `Person` had to happen in the compiled module.
 */
let engineersQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.occupationId == "eng")
}
let engineers = try database.makeRequest(with: engineersQuery).fetchAll()
print("engineers:", engineers.map(\.exampleSummary))
//: Prints `engineers: ["Fred (31)", "Grace (29)"]`

//: And a generated executor, called across the module boundary.
let freds = try database.fetchPeopleNamed(name: "Fred")
print("named Fred:", freds.map(\.exampleSummary))
//: Prints `named Fred: ["Fred (31)"]`

let harold = try database.fetchPersonByID(id: "harold")
print("by id:", harold?.exampleSummary ?? "no match")
//: Prints `by id: Harold (45)`
