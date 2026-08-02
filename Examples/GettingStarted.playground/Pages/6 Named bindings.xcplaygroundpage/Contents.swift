/*:
 # Named bindings

 [Previous: Delete statements](@previous)

 Every query so far has had its values written into the statement. A named
 binding puts a typed placeholder there instead, so one request can serve many
 calls with different values.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

/*:
 `XLNamedBindingReference` takes the Swift value type and the placeholder name,
 without a leading colon.
 */
let nameParameter = XLNamedBindingReference<String>(name: "name")

let peopleByNameQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
let peopleByNameRequest = database.makeRequest(with: peopleByNameQuery)

/*:
 That renders to:

 ```sql
 SELECT t0.id AS id, t0.occupationId AS occupationId,
        t0.name AS name, t0.age AS age
 FROM Person AS t0
 WHERE (t0.name == :name)
 ```

 ## Supplying values

 The request's layout describes the placeholder but holds no runtime value.
 Build a packet from that layout and the value for this call.
 */
let nameSlot = peopleByNameRequest.parameterLayout.slot(for: .named("name"))!
let fredBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: peopleByNameRequest.parameterLayout,
    bindings: [
        try XLInvocationBinding(slot: nameSlot, value: .text("Fred"))
    ]
).validatingComplete()

print("Fred:", try peopleByNameRequest.fetchAll(bindings: fredBindings).map(\.exampleSummary))
//: Prints `Fred: ["Fred (31)"]`

//: A second packet against the same request, with a different value.
let graceBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: peopleByNameRequest.parameterLayout,
    bindings: [
        try XLInvocationBinding(slot: nameSlot, value: .text("Grace"))
    ]
).validatingComplete()

print("Grace:", try peopleByNameRequest.fetchAll(bindings: graceBindings).map(\.exampleSummary))
//: Prints `Grace: ["Grace (29)"]`

/*:
 Constructing and validating a packet rejects values for the wrong layout,
 duplicate bindings, and missing parameters before the driver ever runs the
 statement. Missing is not the same as SQL `NULL`: omitting a binding fails
 completeness validation, while `.null` is a present value that only a
 `.nullable` slot accepts. Repeated uses of one named reference share a single
 logical slot and a single value.
 */

/*:
 ## Bindings in an update

 Named bindings matter most for statements that run repeatedly with different
 values.
 */
let personIDParameter = XLNamedBindingReference<String>(name: "id")
let ageParameter = XLNamedBindingReference<Int>(name: "age")

let updateAgeStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.age = ageParameter
    }
    Where(person.id == personIDParameter)
}
let updateAgeRequest = database.makeRequest(with: updateAgeStatement)
let updateLayout = updateAgeRequest.parameterLayout

for (id, age) in [("fred", Int64(42)), ("grace", Int64(30))] {
    let bindings = try XLInvocationBindings<XLSQLiteValue>(
        layout: updateLayout,
        bindings: [
            try XLInvocationBinding(slot: updateLayout.slot(for: .named("id"))!, value: .text(id)),
            try XLInvocationBinding(slot: updateLayout.slot(for: .named("age"))!, value: .integer(age)),
        ]
    ).validatingComplete()
    try updateAgeRequest.execute(bindings: bindings)
}

print("fred:", try database.fetchPersonByID(id: "fred")?.exampleSummary ?? "no match")
print("grace:", try database.fetchPersonByID(id: "grace")?.exampleSummary ?? "no match")
//: Prints `fred: Fred (42)` and `grace: Grace (30)`

/*:
 Watch the types at that boundary. `ageParameter` is an
 `XLNamedBindingReference<Int>`, because `Person.age` is a Swift `Int`, while
 `XLSQLiteValue.integer` carries SQLite's own 64-bit integer and takes an
 `Int64`. The conversion is explicit, which is why the loop above builds its
 ages as `Int64`.
 */

/*:
 ## Declared queries

 Building a packet by hand shows what is going on underneath, and it is more
 ceremony than most call sites want. The `@SQLQuery` and `@SQLQueries` macros
 generate the whole thing from a function signature, so callers pass ordinary
 labelled arguments and never touch a slot or a packet.

 `SwiftQLExamples` declares two of them. `fetchPersonByID(id:)`, used above, and
 `fetchPeopleNamed(name:)`:
 */
print("declared:", try database.fetchPeopleNamed(name: "Harold").map(\.exampleSummary))
//: Prints `declared: ["Harold (45)"]`

/*:
 Their specifications look like this, and live in the compiled module because
 `@SQLQuery` is a macro:

 ```swift
 extension GRDBDatabase {

     @SQLQuery
     public func peopleNamed(name: String) -> [Person] {
         sqlResult { schema in
             let person = schema.table(Person.self)
             Select(person)
             From(person)
             Where(person.name == name)
         }
     }
 }
 ```

 The macro reads the signature and emits a peer executor named `fetch` plus the
 capitalized specification name, so calling `fetchPeopleNamed(name:)` builds a
 fresh packet against one cached request. See the `DeclaredQueries` article for
 the full encoding.

 [Next: Lazy result sets](@next)
 */
