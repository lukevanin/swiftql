# Getting started

Learn how to define a table and perform basic SQLite operations with SwiftQL.

## Overview

This guide introduces SwiftQL's essential database operations: creating a
table, inserting rows, selecting data, binding values, updating rows, and
deleting rows. Read it start to finish once, then come back to it as a quick
reference.

It stays on the everyday path on purpose. Connection ownership, statement
preparation, row lifetime, and the exact transaction rules are covered
separately in <doc:AdvancedUsage>; you do not need them to write your first
query.

The guide assumes a basic understanding of SQLite SQL. For a more comprehensive
introduction to SQL, see the
[SQLite SQL Language Documentation](https://www.sqlite.org/lang.html).

## Add SwiftQL to your project

Add the latest published SwiftQL package to your dependencies:

```text
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.5.2")
```

Version 1.5.2 is the published package. This guide's basic request path remains
supported in v1.3, and its static-query and contextual-codec APIs remain
available from version 1.2.0 or later. Pin a source revision only when
intentionally testing later changes from `main`.

Then add `SwiftQL` to the dependencies of your target and import the module in
files that use it. The package requires Swift tools 5.9 and targets iOS 16 or
later and macOS 13 or later. The supported compiler configurations are listed
in the
[compatibility matrix](https://github.com/lukevanin/swiftql/blob/main/COMPATIBILITY.md).

## Defining tables

Before querying a database, define the structure of its tables. A table is a
Swift `struct` annotated with `@SQLTable`:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
import SwiftQL

@SQLTable struct Person {
    var id: String
    var occupationId: String?
    var name: String
    var age: Int
}
```

This defines a table named `Person`. SwiftQL uses the following intrinsic Swift
types when binding values to SQLite and reading values from SQLite:

| SwiftQL | SQLite storage class |
| --- | --- |
| Bool | INTEGER (0 or 1) |
| Int | INTEGER |
| Double | REAL |
| String | TEXT |
| Data | BLOB |

These mappings provide type safety for Swift expressions, bindings, and decoded
results. Optional properties can store `NULL`; non-optional properties are
emitted with a `NOT NULL` constraint.

### Creating tables

Use `sqlCreate` to create a basic table:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let createPersonStatement = sqlCreate(Person.self)
```

This is equivalent to the following SQL:

```sql
CREATE TABLE IF NOT EXISTS Person (
    id NOT NULL,
    occupationId,
    name NOT NULL,
    age NOT NULL
)
```

The current `sqlCreate` implementation omits declared SQLite type names, so
SQLite assigns the generated columns BLOB affinity. It also does not infer
primary keys, uniqueness constraints, foreign keys, indexes, or migrations.
Manage those schema details explicitly when your application needs them.

The `IF NOT EXISTS` clause makes this statement safe to run when the table
already exists. It does not migrate an existing table when the Swift type
changes. For `CREATE TABLE ... AS SELECT`, see <doc:FunctionalSyntax>.

## Executing statements

SwiftQL ships with a GRDB-backed database adapter. Create a `GRDBDatabase` for
the SQLite file your application uses:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
import Foundation

let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let file = directory.appending(path: "my_database.sqlite")
let database = try GRDBDatabase(url: file, logger: nil)
```

Create the table by turning the statement into a request and executing it:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
try database.makeRequest(with: createPersonStatement).execute()
```

Create the database adapter once for a database path and reuse it. Running the
basic `sqlCreate` statement at launch is safe because it includes
`IF NOT EXISTS`, but schema changes still need an explicit migration strategy.

SwiftQL defines the `XLDatabase` protocol and provides `GRDBDatabase` as its
first-party implementation. Applications can provide another adapter by
conforming to `XLDatabase`.

## Inserting data

Create an instance of the table type:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let fredPerson = Person(
    id: "fred",
    occupationId: nil,
    name: "Fred",
    age: 31
)
```

Then create and execute an insert request:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
try database.makeRequest(with: sqlInsert(fredPerson)).execute()
```

This is equivalent to the following SQL:

```sql
INSERT INTO Person (id, occupationId, name, age)
VALUES ('fred', NULL, 'Fred', 31)
```

## Running select queries

Construct and execute a select query:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let peopleNamedFredQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
let peopleNamedFred = try database.makeRequest(with: peopleNamedFredQuery).fetchAll()
```

`peopleNamedFred` is an array of `Person` values matching the query. Select
requests use `fetchAll()` instead of `execute()` when all matching rows are
needed. Use `fetchOne()` when zero or one matching row is enough:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let firstPersonNamedFred = try database.makeRequest(with: peopleNamedFredQuery).fetchOne()
```

`fetchOne()` returns `Person?`. Without an `OrderBy` clause, SQLite does not
guarantee which matching row is returned. Select syntax is discussed in more
detail in the <doc:Queries> guide.

### Schema parameter

The previous query uses the `schema` parameter to construct a table reference.
You can instead use the closure's default `$0` parameter:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let peopleNamedFredShorthandQuery = sql {
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

This guide uses the explicit `schema` name for clarity.

### Reusing requests

Creating a request translates a SwiftQL statement into SQL once. Keep the
request and execute it as many times as you need:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let workingAgeQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= 21 && person.age < 65)
}
let workingAgeRequest = database.makeRequest(with: workingAgeQuery)
```

Execute the request whenever it is needed:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let workingAgePeople = try workingAgeRequest.fetchAll()
```

A request holds the rendered SQL and an immutable description of its
parameters. It does not hold the values for a particular call — those go in a
separate bindings packet, described in the next section. That separation is
what lets one request serve many calls with different values.

<doc:AdvancedUsage> covers when SQLite actually prepares the statement, how
that interacts with a connection pool, and which of these types are safe to
share between tasks.

## Named bindings

Use `XLNamedBindingReference` to add a type-safe named placeholder to a query.
Provide the Swift value type and the placeholder name without a leading colon:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")
```

Include the binding in a query:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let peopleByNameQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
let peopleByNameRequest = database.makeRequest(with: peopleByNameQuery)
```

This is equivalent to the following SQL:

```sql
SELECT t0.id AS id, t0.occupationId AS occupationId,
       t0.name AS name, t0.age AS age
FROM Person AS t0
WHERE (t0.name == :name)
```

The request's layout describes the placeholder, but it does not contain a
runtime value. Build a SQLite packet from that layout and the normalized value
for this call:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let nameSlot = peopleByNameRequest.parameterLayout
    .slot(for: .named("name"))!
let fredBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: peopleByNameRequest.parameterLayout,
    bindings: [
        try XLInvocationBinding(slot: nameSlot, value: .text("Fred"))
    ]
).validatingComplete()
let fredResults = try peopleByNameRequest.fetchAll(bindings: fredBindings)
```

Constructing and validating a packet rejects values for the wrong layout,
duplicate bindings, and missing parameters before driver execution. Missing is
not the same as SQL `NULL`: omitting a binding fails completeness validation,
while `.null` is a present value accepted only by a `.nullable` slot. Repeated
uses of the same named reference share one logical slot and one value.

## Update statements

Use an update statement to modify matching rows. This example sets Fred's age
to `42`:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let updateFredStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting<Person> { row in
        row.age = 42
    }
    Where(person.id == "fred")
}

try database.makeRequest(with: updateFredStatement).execute()
```

Use `schema.into()` for the table modified by a result-builder update or delete
statement.

> Warning: An update without a `Where` clause modifies every row in the table.

Named bindings are useful for updates that run with different values:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let personIDParameter = XLNamedBindingReference<String>(name: "id")
let ageParameter = XLNamedBindingReference<Int>(name: "age")

let updateAgeStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting<Person> { row in
        row.age = ageParameter
    }
    Where(person.id == personIDParameter)
}

let updateAgeRequest = database.makeRequest(with: updateAgeStatement)

// Later, when the update is needed:
let updateBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: updateAgeRequest.parameterLayout,
    bindings: [
        try XLInvocationBinding(
            slot: updateAgeRequest.parameterLayout.slot(for: .named("id"))!,
            value: .text("fred")
        ),
        try XLInvocationBinding(
            slot: updateAgeRequest.parameterLayout.slot(for: .named("age"))!,
            value: .integer(42)
        )
    ]
).validatingComplete()
try updateAgeRequest.execute(bindings: updateBindings)
```

## Delete statements

Use a delete statement with a `Where` clause to remove matching rows:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let deleteIDParameter = XLNamedBindingReference<String>(name: "id")

let deletePersonStatement = sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.id == deleteIDParameter)
}

let deletePersonRequest = database.makeRequest(with: deletePersonStatement)

// Later, when the deletion is needed:
let deleteBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: deletePersonRequest.parameterLayout,
    bindings: [
        try XLInvocationBinding(
            slot: deletePersonRequest.parameterLayout
                .slot(for: .named("id"))!,
            value: .text("fred")
        )
    ]
).validatingComplete()
try deletePersonRequest.execute(bindings: deleteBindings)
```

> Warning: A delete without a `Where` clause removes every row in the table.

## Grouping work in a transaction

When several statements must succeed or fail together, run them inside
`withTransaction(_:)`. The closure receives a scope that works exactly like the
database you already have — call `makeRequest(with:)` on it as usual:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let (workingAgeCount, insertedID) = try database.withTransaction { scope in
    let newHire = Person(id: "txn-scope-a", occupationId: nil, name: "Grace", age: 29)
    try scope.makeRequest(with: sqlInsert(newHire)).execute()
    let promoted = Person(id: "txn-scope-b", occupationId: nil, name: "Harold", age: 45)
    try scope.makeRequest(with: sqlInsert(promoted)).execute()
    let matches = try scope.makeRequest(with: workingAgeQuery).fetchAll()
    return (matches.count, newHire.id)
}
```

The three rules worth knowing on day one:

- Statements run in the order you write them, on one connection.
- The transaction commits when the closure returns and rolls back every write
  if the closure throws — including errors you throw yourself.
- A read inside the closure sees the writes the closure already made.

Values computed inside the closure come back out as its return value, as
`workingAgeCount` and `insertedID` do above.

Transactions have boundaries the compiler cannot enforce: nesting them, using
the scope after the closure returns, and observing live queries inside one are
all rejected at runtime. <doc:AdvancedUsage> lists each rejection and the
reason for it.

## Where to go next

- <doc:Queries> — joins, grouping, ordering, subqueries, and CTEs.
- <doc:Expressions> — conditions, operators, and typed expression composition.
- <doc:DeclaredQueries> — declare queries as functions with the `@SQLQuery` and
  `@SQLQueries` macros.
- <doc:LiveQueries> — observe results that change as the database changes.
- <doc:AdvancedUsage> — connections, statement preparation, row lifetime, and
  the full transaction contract.
