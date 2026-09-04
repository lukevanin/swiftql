/*:
 # Lazy result sets

 [Previous: Named bindings](@previous)

 `fetchAll()` decodes every matching row up front into a complete array and
 `fetchOne()` decodes at most one. When a query may match many rows and the
 caller does not need all of them retained at once, or wants to stop as soon as
 it finds what it is looking for, `withResultSet(_:)` decodes one row at a time
 instead.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

let everyoneQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.id.ascending())
}

try database.makeRequest(with: everyoneQuery).withResultSet { results in
    while let person = try results.next() {
        print("row:", person.exampleSummary)
    }
}
//: Prints one `row:` line per person, ordered by id.

/*:
 `withResultSet(_:)` hands the closure an `XLResultSet<Row>`: a reference type
 whose `next()` performs at most one additional row step and typed decode, and
 returns `nil` once the query is exhausted. For the ordinary, non-`RETURNING`
 case no row is fetched or decoded before the closure asks for it, so stopping
 early means the later rows are never stepped or decoded at all.
 */

//: Stopping as soon as a match is found, without decoding the rest.
let firstChef = try database.makeRequest(with: everyoneQuery).withResultSet { results -> Person? in
    while let person = try results.next() {
        if person.occupationId == "chef" {
            return person
        }
    }
    return nil
}
print("first chef:", firstChef?.exampleSummary ?? "none")
//: Prints `first chef: Harold (45)`

/*:
 ## The rules worth knowing

 `XLResultSet` is not a `Sequence` or a `Collection`. It has no replayable value
 semantics, cannot be iterated with `for row in results`, and is not `Sendable`.
 It is valid only for the duration of the `withResultSet(_:)` callback, and that
 callback owns the underlying read connection or snapshot for its whole
 duration, so avoid slow unrelated work between `next()` calls.

 Never let the result set escape the callback. A reference retained past the
 callback's return throws `XLResultSetError.closed` from every later `next()`
 call, and so does a reference explicitly closed with `close()`. That differs
 from natural exhaustion: once a query legitimately runs out of rows, `next()`
 keeps returning `nil` rather than throwing.
 */
var escaped: XLResultSet<Person>?
try database.makeRequest(with: everyoneQuery).withResultSet { results in
    escaped = results
    _ = try results.next()
}
do {
    _ = try escaped?.next()
    print("escaped: unexpectedly succeeded")
}
catch {
    print("escaped:", error)
}
//: Prints `escaped: closed`

/*:
 Error handling differs from `fetchAll()` too. A decode or SQLite error only
 ends iteration from that point forward, and rows already returned by earlier
 `next()` calls remain valid independent values; `fetchAll()` instead fails
 atomically and returns nothing.

 Prefer `fetchAll()` when every row is needed as a complete retained array, or
 when the array conveniences (`map`, `filter`, `count`, sorting) matter more
 than incremental decoding. Prefer `withResultSet(_:)` when the result may be
 large, the caller may stop before consuming every row, or the cost of decoding
 rows nobody uses should scale with rows actually requested rather than with the
 query's total cardinality.

 [Next: Transactions](@next)
 */
