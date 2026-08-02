/*:
 # Update statements

 [Previous: Running select queries](@previous)

 An update statement modifies matching rows. It uses `schema.into(_:)` rather
 than `schema.table(_:)`, because the table is the target of the write rather
 than a source to read from.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

print("before:", try database.fetchPersonByID(id: "fred")?.exampleSummary ?? "no match")
//: Prints `before: Fred (31)`

let updateFred = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.age = 42
    }
    Where(person.id == "fred")
}
try database.makeRequest(with: updateFred).execute()

print("after:", try database.fetchPersonByID(id: "fred")?.exampleSummary ?? "no match")
//: Prints `after: Fred (42)`

/*:
 Passing the same table reference to `Setting(_:_:)` lets Swift infer which row
 type the closure updates, so the type does not have to be repeated as an
 explicit `Setting<Row>` generic argument. Inside the closure, `row.age = 42`
 builds a `SET age = 42` clause rather than assigning to a Swift value.

 - Warning: An update without a `Where` clause modifies every row in the table.
 */

/*:
 ## Updating several columns

 Each assignment in the closure becomes another column in the `SET` clause.
 */
let renameIda = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.name = "Ida B."
        row.age = 69
    }
    Where(person.id == "ida")
}
try database.makeRequest(with: renameIda).execute()

print("ida:", try database.fetchPersonByID(id: "ida")?.exampleSummary ?? "no match")
//: Prints `ida: Ida B. (69)`

/*:
 ## Setting a nullable column

 Both columns above are non-optional. `Person.occupationId` is `String?`, so
 its generated setter type is `Optional<any XLExpression<String?>>`. The outer
 `Optional` means "leave this column out of the `SET` clause" — a different
 thing from the column's own optionality, so assigning a plain `String` or
 `String?` value does not compile. `toNullable()` lifts a non-optional value
 expression into that slot:
 */
let hireFred = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.occupationId = "chef".toNullable()
    }
    Where(person.id == "fred")
}
try database.makeRequest(with: hireFred).execute()

print("fred's occupation:", try database.fetchPersonByID(id: "fred")?.occupationId ?? "none")
//: Prints `fred's occupation: chef`

/*:
 Clearing the column back to `NULL` needs an already-*optional* value, so cast
 it to the existential explicitly instead of relying on `toNullable()`, which
 only accepts a non-optional expression:
 */
let retireFred = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        let clearedOccupationId: String? = nil
        row.occupationId = clearedOccupationId as any XLExpression<String?>
    }
    Where(person.id == "fred")
}
try database.makeRequest(with: retireFred).execute()

print("fred's occupation:", try database.fetchPersonByID(id: "fred")?.occupationId ?? "none")
//: Prints `fred's occupation: none`

/*:
 ## Updating everything that matches

 The `Where` clause is an ordinary typed expression, so one statement can
 update a whole range of rows.
 */
let birthdays = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.age = person.age + 1
    }
    Where(person.age < 40)
}
try database.makeRequest(with: birthdays).execute()

print("after birthdays:", try database.makeRequest(with: sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.id.ascending())
}).fetchAll().map(\.exampleSummary))
//: Prints `after birthdays: ["Fred (42)", "Grace (30)", "Harold (45)", "Ida B. (69)"]`
//: Only Grace was under 40, so only Grace had a birthday.

/*:
 The next page covers deletes, and the named bindings page covers running one
 update repeatedly with different values instead of hard-coding them into the
 statement.

 [Next: Delete statements](@next)
 */
