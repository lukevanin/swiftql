/*:
 # Defining tables

 A table is a Swift `struct` annotated with `@SQLTable`. The example schema is
 declared in the `SwiftQLExamples` module this playground imports, and it looks
 like this:

 ```swift
 import SwiftQL

 @SQLTable
 public struct Person {
     public var id: String
     public var occupationId: String?
     public var name: String
     public var age: Int
 }
 ```

 That declaration is not repeated on this page, because `@SQLTable` is a macro
 and expanding a macro needs a compiler plugin that a classic playground cannot
 load. `Examples/README.md` explains the arrangement. In your own project you
 write the declaration exactly as above, in an ordinary Swift file.

 SwiftQL uses these intrinsic Swift types when binding values to SQLite and
 reading values back:

 | SwiftQL | SQLite storage class |
 | --- | --- |
 | Bool | INTEGER (0 or 1) |
 | Int | INTEGER |
 | Double | REAL |
 | String | TEXT |
 | Data | BLOB |

 Optional properties can store `NULL`. Non-optional properties are emitted with
 a `NOT NULL` constraint, which is why `occupationId` above is the only column
 allowed to be missing.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

/*:
 ## Opening a database

 SwiftQL ships with a GRDB-backed adapter. Create a `GRDBDatabase` for the
 SQLite file your application uses. This page writes to a throwaway file in the
 temporary directory so it starts from the same state every run; an application
 would use its durable database URL and reuse one `GRDBDatabase` for that path.
 */
let file = FileManager.default.temporaryDirectory
    .appending(path: "getting-started-\(UUID().uuidString).sqlite")
let database = try GRDBDatabase(url: file, logger: nil)

/*:
 ## Creating the table

 `sqlCreate` turns a table type into a create statement, and
 `makeRequest(with:)` turns a statement into something you can execute.
 */
let createPerson = sqlCreate(Person.self)
try database.makeRequest(with: createPerson).execute()

/*:
 That is equivalent to:

 ```sql
 CREATE TABLE IF NOT EXISTS Person (
     id NOT NULL,
     occupationId,
     name NOT NULL,
     age NOT NULL
 )
 ```

 The `IF NOT EXISTS` clause makes the statement safe to run at every launch. It
 does not migrate an existing table when the Swift type changes, so schema
 changes still need an explicit migration strategy of your own.

 The current `sqlCreate` implementation omits declared SQLite type names, so
 SQLite assigns the generated columns BLOB affinity, and it infers no primary
 keys, uniqueness constraints, foreign keys, or indexes. Manage those
 explicitly when your application needs them.

 `SwiftQLExamples` has a second table, `Occupation`, declared the same way.
 */
try database.makeRequest(with: sqlCreate(Occupation.self)).execute()

//: The table exists and is empty, which is all this page set out to do.
let everyone = try database.makeRequest(with: sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
}).fetchAll()
print("rows in Person:", everyone.count)
//: Prints `rows in Person: 0`

/*:
 `ExampleDatabase.makeEmpty()` in the imported module does exactly what this
 page just did, and `ExampleDatabase.makeSeeded()` adds a fixed set of rows on
 top. Later pages use those helpers rather than repeating the setup.

 SwiftQL defines the `XLDatabase` protocol and provides `GRDBDatabase` as its
 first-party implementation, so an application can supply another adapter by
 conforming to `XLDatabase`.

 [Next: Inserting data](@next)
 */
