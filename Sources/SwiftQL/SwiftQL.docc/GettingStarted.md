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

Add the latest published SwiftQL package to your dependencies:

```text
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.3.0")
```

Version 1.3.0 is the published package. This guide's basic request path remains
supported in v1.3, and its static-query and contextual-codec APIs remain
available from version 1.2.0 or later. Pin a source revision only when
intentionally testing later changes from `main`.

SwiftQL v1.3 validates the existing SQLite surface against recorded real-engine,
Northwind, and stress evidence; it does not introduce a new public syntax or
validation API. In particular, issue
[#132](https://github.com/lukevanin/swiftql/issues/132) is a
research-only schema-snapshot preparation prototype. Applications still own
their schema lifecycle and perform physical preparation on the runtime
connection that executes each statement.

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

Requests retain the generated SQL and an immutable `XLParameterLayout`. The
layout is static metadata: it records each logical parameter's deterministic
index, binding key, value type, nullability, coding context, and selected codec
identity. Runtime values are separate. Put them in a fresh
`XLInvocationBindings` packet for each call, then pass that packet to
`fetchAll(bindings:)`, `fetchOne(bindings:)`, `execute(bindings:)`, or a
packet-backed publisher. Creating a request translates the SwiftQL statement
into SQL but does not prepare it immediately. On execution, GRDB obtains a
cached SQLite statement for that SQL on the connection performing the work.

#### Dialect and driver responsibilities

The SQLite dialect defines how SwiftQL renders valid SQLite syntax, including
identifier quoting, placeholder spelling, value storage classes, and required
SQLite capabilities. The database driver has a separate job: it leases a
connection, prepares the rendered SQL, binds SQLite values to its transport,
executes the statement, and reads SQLite values from the result. GRDB is the
current SQLite driver, but it does not define the SQLite syntax or the logical
policy for converting application values.

Adapter packages can depend directly on the `SwiftQLCore` library product. It
exports the dialect, dialect-value, logical-statement, and driver contracts
without linking GRDB; the `SwiftQL` product remains the compatibility facade
that includes the current GRDB-backed SQLite adapter.

#### Logical and physical preparation

Logical requests and prepared handles are database- or pool-bound. They retain
the rendered SQL and request metadata, but they do not own one physical
statement. Physical GRDB statements are connection-bound and must not be shared
between connections or concurrent executions.

With a connection pool, each execution leases a connection and resolves or
caches the physical statement separately on that leased connection. Another
execution may lease a different connection and therefore prepare the same SQL
again. A single-connection database may reuse its own statement cache, but its
physical statements still belong only to that connection.

Preparation is therefore an execution-time operation. Successful preparation
on one connection does not guarantee every later preparation: preparation can
still fail later on a newly leased connection, for example when its schema,
registered functions, or available capabilities differ.

#### Incremental row lifetime

The GRDB adapter steps result rows through a package-internal, driver-neutral
callback while the leased connection is active. It copies each row into
normalized SQLite values before advancing because GRDB reuses cursor-backed row
storage. The synchronous callback may stop without stepping later rows, and a
thrown decoding error releases the cursor and connection before it propagates.
A cursor value is never returned from the database-access closure.

The public v1 behavior remains eager: `fetchAll()` still returns a complete
typed array, while `fetchOne()` returns an optional first row. Those
compatibility APIs are layered over the same incremental primitive.
`fetchAll()` therefore retains its typed output as required but no longer
retains a complete intermediate array of GRDB rows or normalized SQLite-value
rows before typed decoding. Future package adapters should implement the same
callback lifetime rather than exposing their native cursor types.

#### Transactions and bindings

Transaction-scoped work pins one connection for the duration of the
transaction. Code inside that transaction must use the pinned connection and
must not re-enter the root pool, which could lease another connection and break
the transaction boundary or deadlock while waiting for itself.

The synchronous v1 driver commits when the transaction body returns and rolls
back when it throws. `withValidatedTransaction` preserves the exact body error,
so a dedicated caller error can express explicit rollback intent. The v1
contract does not expose nested transactions, savepoints, or task-cancellation
hooks; do not attempt those by re-entering the root pool from a pinned body.
The current GRDB v1 driver is pool-backed and does not expose a separate
single-connection transaction capability.

Each invocation packet carries normalized dialect values in logical-index
order, so every call has fresh bindings. Packet-backed execution does not move
those values into the logical request or connection-wide statement cache.
Packets and layouts are value-semantic and `Sendable` when their dialect values
are. The current `XLRequest` facade itself is not `Sendable` and does not yet
promise that one request can be shared across tasks; use packets to separate
values across repeated calls in the request's supported isolation context.

For cross-task raw-value execution with GRDB, call
`GRDBDatabase.prepareInvocation(with:)`. Its `GRDBPreparedInvocation` result is
`Sendable` and accepts an independent packet in `fetchAllValues`,
`fetchOneValues`, or `execute`. It deliberately returns normalized SQLite
values instead of retaining the legacy typed row-reader graph. For a durable,
database-independent SQL and value-layout contract, create an
`XLStaticQueryDescriptor` and prepare it through the overload described in
<doc:StaticQueries>.

Driver integrations can use the `prepareValidated`, `bindValidated`,
`fetchAllValidated`, `fetchOneValidated`, `executeValidated`, and
`withValidatedTransaction` helpers to normalize transport failures into
`XLDatabaseContractError` categories. The existing GRDB compatibility facade
keeps raw `DatabaseError` and `XLColumnReadError` values where its retry policy
and established decoding API need to inspect them; database and dialect
mismatches are still rejected before physical preparation in both paths.

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

The mutating `set` methods remain as a migration shim for v1 literal bindings.
They immediately normalize each value into a compatibility packet stored in
that request copy. Existing code can continue to copy, set, and execute a
request, but new code should keep the prepared request immutable and pass an
explicit packet for each call. The shim cannot override a contextual
parameter's selected codec. Static descriptors use the same immutable packet
contract while adding stable identity, result metadata, cardinality, and a
cross-task prepared handle; see <doc:StaticQueries>.

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

Continue with <doc:Queries> for select composition, <doc:Expressions> for
conditions and operators, or <doc:LiveQueries> to observe changing results.
