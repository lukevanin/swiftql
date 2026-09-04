/*:
 # Delete statements

 [Previous: Update statements](@previous)

 A delete statement removes matching rows. Like an update, it takes its table
 from `schema.into(_:)`.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

let countEveryone = database.makeRequest(with: sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
})
print("before:", try countEveryone.fetchAll().count)
//: Prints `before: 4`

let deleteHarold = sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.id == "harold")
}
try database.makeRequest(with: deleteHarold).execute()

print("after:", try countEveryone.fetchAll().count)
print("harold:", try database.fetchPersonByID(id: "harold")?.exampleSummary ?? "no match")
//: Prints `after: 3` and `harold: no match`

/*:
 - Warning: A delete without a `Where` clause removes every row in the table.

 A `Where` clause that matches nothing is not an error. The statement executes
 and removes no rows.
 */
try database.makeRequest(with: sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.id == "nobody")
}).execute()
print("still:", try countEveryone.fetchAll().count)
//: Prints `still: 3`

/*:
 ## Deleting a range

 The `Where` clause is an ordinary typed expression, so a delete can match on
 anything a select could.
 */
try database.makeRequest(with: sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.age >= 65)
}).execute()
print("under 65:", try countEveryone.fetchAll().map(\.exampleSummary).sorted())
//: Prints `under 65: ["Fred (31)", "Grace (29)"]`

/*:
 [Next: Named bindings](@next)
 */
