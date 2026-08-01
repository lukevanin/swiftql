/*:
 # Running select queries

 [Previous: Inserting data](@previous)

 A query is written clause by clause, in SQL's own order, inside `sql { }`.
 `sql` is an ordinary function taking a result builder, so a playground page can
 write one directly.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

let peopleNamedFredQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
let peopleNamedFred = try database.makeRequest(with: peopleNamedFredQuery).fetchAll()
print("fetchAll:", peopleNamedFred.map(\.exampleSummary))
//: Prints `fetchAll: ["Fred (31)"]`

/*:
 `peopleNamedFred` is an array of `Person` values. `fetchAll()` is the right
 call when every matching row is needed; `fetchOne()` is enough when zero or one
 row will do.
 */
let firstPersonNamedFred = try database.makeRequest(with: peopleNamedFredQuery).fetchOne()
print("fetchOne:", firstPersonNamedFred?.exampleSummary ?? "no match")
//: Prints `fetchOne: Fred (31)`

/*:
 `fetchOne()` returns `Person?`. Without an `OrderBy` clause SQLite does not
 guarantee which matching row comes back, so use `fetchOne()` for queries that
 identify at most one row rather than as a shortcut for "the first result".

 ## The schema parameter

 The query above names the closure's parameter `schema` for clarity. The
 closure's default `$0` works just as well:
 */
let shorthandQuery = sql {
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
print("shorthand:", try database.makeRequest(with: shorthandQuery).fetchAll().map(\.exampleSummary))
//: Prints `shorthand: ["Fred (31)"]`

/*:
 ## Reusing requests

 Creating a request translates a SwiftQL statement into SQL once, so keep the
 request around and execute it as many times as you need.
 */
let workingAgeQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= 21 && person.age < 65)
}
let workingAgeRequest = database.makeRequest(with: workingAgeQuery)

print("first run:", try workingAgeRequest.fetchAll().map(\.exampleSummary).sorted())
//: Prints `first run: ["Fred (31)", "Grace (29)", "Harold (45)"]`

try database.makeRequest(with: sqlInsert(
    Person(id: "jo", occupationId: "eng", name: "Jo", age: 24)
)).execute()

print("second run:", try workingAgeRequest.fetchAll().map(\.exampleSummary).sorted())
//: Prints `second run: ["Fred (31)", "Grace (29)", "Harold (45)", "Jo (24)"]`

/*:
 The same request saw the new row, because a request holds the rendered SQL and
 an immutable description of its parameters rather than a snapshot of the data.
 It does not hold the values for a particular call either; those live in a
 separate bindings packet, which the named bindings page covers. That separation
 is what lets one request serve many calls with different values.

 `AdvancedUsage` covers when SQLite actually prepares the statement, how that
 interacts with a connection pool, and which of these types are safe to share
 between tasks.

 [Next: Update statements](@next)
 */
