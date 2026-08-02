/*:
 # Inserting data

 [Previous: Defining tables](@previous)

 Inserting a row means creating an instance of the table type and handing it to
 `sqlInsert`.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

//: An empty database with the example schema already created.
let database = try ExampleDatabase.makeEmpty()

let fred = Person(
    id: "fred",
    occupationId: nil,
    name: "Fred",
    age: 31
)

try database.makeRequest(with: sqlInsert(fred)).execute()

/*:
 That is equivalent to:

 ```sql
 INSERT INTO Person (id, occupationId, name, age)
 VALUES ('fred', NULL, 'Fred', 31)
 ```

 `occupationId` is optional, so passing `nil` writes SQL `NULL`. The other three
 properties are non-optional and were emitted with a `NOT NULL` constraint when
 the table was created, so there is no way to leave them out.

 Insert statements use `execute()` rather than `fetchAll()`, because they return
 no rows.
 */

//: Inserting several rows means executing several statements.
let colleagues = [
    Person(id: "grace", occupationId: "eng", name: "Grace", age: 29),
    Person(id: "harold", occupationId: "chef", name: "Harold", age: 45),
    Person(id: "ida", occupationId: nil, name: "Ida", age: 68),
]
for colleague in colleagues {
    try database.makeRequest(with: sqlInsert(colleague)).execute()
}

/*:
 Each of those is its own implicit transaction. When a group of writes has to
 succeed or fail together, run them inside `withTransaction(_:)` instead, which
 the transactions page covers.
 */

let everyoneQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
}
let everyone = try database.makeRequest(with: everyoneQuery).fetchAll()
print("rows in Person:", everyone.count)
print("names:", everyone.map(\.name).sorted())
//: Prints `rows in Person: 4` and `names: ["Fred", "Grace", "Harold", "Ida"]`

/*:
 Those four rows are the same cast `ExampleDatabase.makeSeeded()` inserts, which
 is what the remaining pages start from.

 [Next: Running select queries](@next)
 */
