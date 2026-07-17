# Getting started

Learn how to define a table and perform basic SQLite operations with SwiftQL.

## Overview

This guide introduces SwiftQL's essential database operations: creating a
table, inserting rows, selecting data, binding values, updating rows, and
deleting rows.

The guide assumes a basic understanding of SQLite SQL. For a more comprehensive
introduction to SQL, see the
[SQLite SQL Language Documentation](https://www.sqlite.org/lang.html).

## Add SwiftQL to your project

Add SwiftQL v1.1 or later to your package dependencies:

```text
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.1.0")
```

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

Requests are value types that contain the generated SQL and its bound values,
so you can store and reuse them. Creating a request translates the SwiftQL
statement into SQL but does not prepare it immediately. On execution, GRDB
obtains a cached SQLite statement for that SQL on the connection performing the
work.

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

The binding has no value until you set one on the request. Copy a reusable
request before setting its values so each execution can be configured
independently:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
var fredRequest = peopleByNameRequest
fredRequest.set(nameParameter, "Fred")
let fredResults = try fredRequest.fetchAll()
```

Set every binding referenced by a statement before executing its request.

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
var fredAgeRequest = updateAgeRequest
fredAgeRequest.set(personIDParameter, "fred")
fredAgeRequest.set(ageParameter, 42)
try fredAgeRequest.execute()
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
var deleteFredRequest = deletePersonRequest
deleteFredRequest.set(deleteIDParameter, "fred")
try deleteFredRequest.execute()
```

> Warning: A delete without a `Where` clause removes every row in the table.

Continue with <doc:Queries> for select composition, <doc:Expressions> for
conditions and operators, or <doc:LiveQueries> to observe changing results.
