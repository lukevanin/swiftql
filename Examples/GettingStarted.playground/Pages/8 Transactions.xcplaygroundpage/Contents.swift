/*:
 # Transactions

 [Previous: Lazy result sets](@previous)

 When several statements have to succeed or fail together, run them inside
 `withTransaction(_:)`. The closure receives a scope that works exactly like the
 database you already have, so `makeRequest(with:)` is called on it as usual.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

let workingAgeQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= 21 && person.age < 65)
}

let (workingAgeCount, insertedID) = try database.withTransaction { scope in
    let newHire = Person(id: "txn-a", occupationId: "eng", name: "Kit", age: 27)
    try scope.makeRequest(with: sqlInsert(newHire)).execute()
    let promoted = Person(id: "txn-b", occupationId: "chef", name: "Lena", age: 45)
    try scope.makeRequest(with: sqlInsert(promoted)).execute()
    let matches = try scope.makeRequest(with: workingAgeQuery).fetchAll()
    return (matches.count, newHire.id)
}
print("counted inside:", workingAgeCount, "inserted:", insertedID)
//: Prints `counted inside: 5 inserted: txn-a`

/*:
 Three rules cover most of what you need on day one:

 - Statements run in the order you write them, on one connection.
 - The transaction commits when the closure returns, and rolls back every write
   if the closure throws, including errors you throw yourself.
 - A read inside the closure sees the writes the closure already made, which is
   why the count above is 5 rather than 3.

 Values computed inside the closure come back out as its return value, as
 `workingAgeCount` and `insertedID` do.
 */

/*:
 ## Rolling back

 Throwing out of the closure discards everything it wrote. Nothing special is
 needed to trigger a rollback; an ordinary Swift error is enough.
 */
struct RejectedError: Error {}

let before = try database.makeRequest(with: workingAgeQuery).fetchAll().count

do {
    try database.withTransaction { scope in
        try scope.makeRequest(with: sqlInsert(
            Person(id: "txn-c", occupationId: nil, name: "Mo", age: 33)
        )).execute()
        throw RejectedError()
    }
}
catch is RejectedError {
    print("rolled back")
}

let after = try database.makeRequest(with: workingAgeQuery).fetchAll().count
print("before:", before, "after:", after)
print("mo:", try database.fetchPersonByID(id: "txn-c")?.exampleSummary ?? "no match")
//: Prints `rolled back`, `before: 5 after: 5`, and `mo: no match`

/*:
 The insert ran and then went away, so the row is not in the database and the
 count is unchanged.

 Transactions have boundaries the compiler cannot enforce. Nesting them, using
 the scope after the closure returns, and observing live queries inside one are
 all rejected at runtime. The `AdvancedUsage` article lists each rejection and
 the reason for it.

 [Next: Live queries](@next)
 */
