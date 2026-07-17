# Getting started

Introduces the basic concepts and usage of SwiftQL. 

## Overview

This guide covers the fundamental functionality provided by SwiftQL. After 
completing this you will be able to perform essential database operations 
using SwiftQL. 

This guide assumes cursory understanding of SQL as used in SQLite. This guide 
will not attempt to teach SQL, but aims to provide sufficient detail to be 
useful to non-experts and newcomers to SQL. 

Please refer to the 
[SQLite SQL Language Documentation](https://www.sqlite.org/lang.html) for a more
comprehensive discussion about using SQL.  

## Defining tables

Before we can query our database we need to define the structure of our tables.
A table is defined using a `struct`, annotated with `@SQLTable`:

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

This defines a table named `Person` with some properties. SwiftQL uses the
following intrinsic (fundamental) Swift types when binding values to SQLite and
reading values from SQLite:

SwiftQL          | SQLite storage class
-----------------|-----------------------
Bool             | INTEGER (0 or 1)
Int              | INTEGER
Double           | REAL
String           | TEXT
Data             | BLOB

These mappings provide type safety for Swift expressions, bindings, and decoded
results. The current `sqlCreate` implementation does not emit SQLite declared
type names, so SQLite assigns the generated columns BLOB affinity. Optional
properties can store `NULL`; non-optional properties are emitted with a
`NOT NULL` constraint.

### Creating tables

Before you can use your table you need to create it. In SwiftQL we can use the
`sqlCreate` helper function to create a basic table. SwiftQL also allows you to
to create tables using `Select` statements, which we will look at later.

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let createPersonStatement = sqlCreate(Person.self)
```

This would be equivalent to writing the following SQL:

```sql
CREATE TABLE IF NOT EXISTS Person (
    id NOT NULL,
    occupationId,
    name NOT NULL,
    age NOT NULL
)
```

The generated statement omits declared SQLite types. Non-optional properties are
defined as `NOT NULL`, while optional properties omit that constraint.

> Note: The `IF NOT EXISTS` term is added by SwiftQL, and informs SQLite to 
bypass creating the table if it already exists. This allows us to safely execute 
the  create statement when our app starts, without first needing to check if the 
table already exists. 

## Executing statements

SwiftQL provides a default implementation using GRDB for running statements

> Note: Support for alternative database providers is currently under 
development.

First we initialize our database:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
import Foundation

let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let file = directory.appending(path: "my_database.sqlite")
let database = try GRDBDatabase(url: file, logger: nil)
```

Once the database is initialised, we can create and execute the statement:  

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
try database.makeRequest(with: createPersonStatement).execute()
```

The database initialization and table creation only needs to happen once in the 
application life cycle. 

We will follow this pattern of creating and executing statements throughout this
tutorial.

## Inserting data

Our database has been created but it is currently empty. Let's add some data.
First we create an instance of our table struct:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let fredPerson = Person(
    id: "fred",
    occupationId: nil,
    name: "Fred",
    age: 31
)
```

We can then create and execute the request:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
try database.makeRequest(with: sqlInsert(fredPerson)).execute()
```

This is equivalent to running the following SQL:

```sql
INSERT INTO Person (id, occupationId, name, age)
VALUES ('fred', NULL, 'Fred', 31)
```

## Running select queries

Now that we have some data, we can construct and execute a select query:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
let result = try database.makeRequest(with: query).fetchAll()
```

The `result` will contain an array of `Person` objects matching the query. 

We used `fetchAll` to execute a select query instead of calling  `execute`. 
Using `fetchAll` returns an array of all of the matching records for the query. 
We can also use `fetchOne` to fetch only the first result from the query.

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let firstResult = try database.makeRequest(with: query).fetchOne()
```

Select statement syntax is discussed in more detail the <doc:Queries> guide.

### Schema parameter

In the example above we used a `schema` parameter in the `sql` function to 
construct a reference to the table used in the query. A common convention is to
omit the `schema` parameter name entirely and use the default parameter name 
`$0` instead:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let query = sql { 
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

The guide documentation use the explicit `schema` for clarity.  

### Prepared statements

So far we have made the request each time we needed to execute it. Instead we
can store the request and reuse it later. Creating a request translates the
SwiftQL statement into SQL, but does not prepare it immediately. When a request
is fetched or executed, GRDB obtains a cached SQLite statement for that SQL. The
first execution prepares the statement, and later executions on the same
database connection can reuse the cached statement.

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= 21 && person.age < 65)
}
let request = database.makeRequest(with: query)
```

Once created we can execute the request whenever it is needed.

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let result = try request.fetchAll()
```

## Variables

SwiftQL allows you to use variables in queries in a type-safe manner.

First define a variable binding using the generic `XLNamedBindingReference`, and
specifying the type of the variable as well as a name. The name appears in the
rendered SQL placeholder and is used when binding the request:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")
```

We can include the variable parameter in a query:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
let request = database.makeRequest(with: query)
```

This is equivalent to the following SQL:

```sql
SELECT t0.id AS id, t0.occupationId AS occupationId,
       t0.name AS name, t0.age AS age
FROM Person AS t0
WHERE (t0.name == :name)
```

The name parameter is not assigned to a value yet. We assign the parameter value
when we execute the query. A best practice when assigning parameters is to 
create a copy of the request then assign the parameter. We can take advantage of
copy-on-write semantics for value types:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
var newRequest = request
newRequest.set(nameParameter, "Fred")
let results = try newRequest.fetchAll()
```

This binds the value "Fred" to the name parameter in the context of the request
before fetching all of the matching results.

## Update statements

We can modify an existing record using an update statement. In this example we
set the age of the person whose id is `fred` to the value `42`.

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let updateStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting<Person> { row in
        row.age = 42
    }
    Where(
        person.id == "fred"
    )
}

try database.makeRequest(with: updateStatement).execute()
```

> Note: Use `schema.into()` when defining a table that is modified in the query.

> Warning: Omitting the where clause will update all of the records in the 
table. A  best practice when using update statements is to always specify a 
where clause to limit the scope of changes. 

We can also a prepared statement with named parameters for common update 
operations:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let idParameter = XLNamedBindingReference<String>(name: "id")
let ageParameter = XLNamedBindingReference<Int>(name: "age")

let updateStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting<Person> { row in
        row.age = ageParameter
    }
    Where(
        person.id == idParameter
    )
}

let updateRequest = database.makeRequest(with: updateStatement)

// Later, when the update is needed:

var newUpdateRequest = updateRequest
newUpdateRequest.set(idParameter, "fred")
newUpdateRequest.set(ageParameter, 42)
try newUpdateRequest.execute()
```

## Delete statements

We can delete records by specifying the table and a where clause for the items
to delete. The example shows a prepared statement with parameters:

<!-- test: XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings -->
```swift
let idParameter = XLNamedBindingReference<String>(name: "id")

let deleteStatement = sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.id == idParameter)
}

let deleteRequest = database.makeRequest(with: deleteStatement)

// Later, when the deletion is needed:

var newDeleteRequest = deleteRequest
newDeleteRequest.set(idParameter, "fred")
try newDeleteRequest.execute()
```
