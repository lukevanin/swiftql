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

```swift
import SwiftQL

@SQLTable struct Person {
    var id: String
    var occupationId: String?
    var name: String
    var age: Int
} 
```

This defines a table named `Person` with some properties. SwiftQL supports the 
following intrinsic (fundamental) properties which correspond to SQLite counter
parts:

SwiftQL          | SQLite
-----------------|-----------------------
Bool             | INTEGER (0 or 1)
Int              | INTEGER
Double           | REAL
String           | TEXT
Data             | BLOB

SwiftQL also supports optional types, which correspond to a `NULL` column in 
SQLite.

### Creating tables

Before you can use your table you need to create it. In SwiftQL we can use the
`sqlCreate` helper function to create a basic table. SwiftQL also allows you to
to create tables using `Select` statements, which we will look at later.

```swift
let createPersonStatement = sqlCreate(Person.self)
```

This would be equivalent to writing the following SQL:

```sql
CREATE TABLE IF NOT EXISTS Person (
    id TEXT NOT NULL,
    occupationId TEXT NULL,
    name TEXT NOT NULL,
    age INT NOT NULL
);
```

SwiftQL translates to the Swift types to a compatible intrinsic type in SQLite. 
Non-optional fields are been defined as `NOT NULL`, while optional fields are 
defined as `NULL`. 

> Note: The `IF NOT EXISTS` term is added by SwiftQL, and informs SQLite to 
bypass creating the table if it already exists. This allows us to safely execute 
the  create statement when our app starts, without first needing to check if the 
table already exists. 

## Executing statements

SwiftQL provides a default implementation using GRDB for running statements

> Note: Support for alternative database providers is currently under 
development.

First we initialize our database:

```swift
let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let file = directory.appending(path: "my_database.sqlite")
let database = try GRDBDatabase(url: file)
```

Once the database is initialised, we can create and execute the statement:  

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

```
let fredPerson = Person(
    id: "fred",
    occupationId: nil,
    name: "Fred",
    age: "31"
)
```

We can then create and execute the request:

```
try database.makeRequest(with: sqlInsert(fredPerson)).execute()
```

This is equivalent to running the following SQL:

```sql
INSERT INTO Person (id, occupationId, name, age)
VALUES ('fred', NULL, 'Fred', 31)
```

## Running select queries

Now that we have some data, we can run a select query. In the example below we 
prepare the query and execute it:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == 'Fred')
}
let result = try database.makeRequest(with: query).fetchAll()
```

The `result` will contain an array of `Person` objects matching the query. 

We used `fetchAll` to execute a select query instead of calling  `execute`. 
Using `fetchAll` returns an array of all of the matching records for the query. 
We can also use `fetchOne` to fetch only the first result from the query.

```swift
let firstResult = try database.makeRequest(with: query).fetchOne()
```

Select statement syntax is discussed in more detail the <doc:Queries> guide.

### Schema parameter

In the example above we used a `schema` parameter in the `sql` function to 
construct a reference to the table used in the query. A common convention is to
omit the `schema` parameter name entirely and use the default parameter name 
`$0` instead:

```swift
let query = sql { 
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == 'Fred')
}
```

The guide documentation use the explicit `schema` for clarity.  

### Prepared statements

So far we have made the request each time we needed to execute it. Instead we 
can store the request and reuse it later. When the request is created SwiftQL 
will use an SQLite prepared statement. SQLite will parse the SQL string into 
low-level byte code which can be executed efficiently, without needing to parse 
the SQL each time. Re-using requests can potentially improve performance of
complex queries at runtime.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= 21 && person.age < 65)
}
let request = try database.makeRequest(with: query)
```

Once created we can call the prepared statement whenever it is needed.

```swift
let result = try request.fetchAll()
```

## Variables

SwiftQL allows you to use variables in queries in a type-safe manner.

First define a variable binding using the generic `XLNamedBindingReference`, and
specifying the type of the variable, as well as a name. The name is used for 
debugging SQL statements as does not affect the query:

```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")
```

We can include the variable parameter in a query:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
let request = try database.makeRequest(with: query)
```

This is equivalent to the following SQL:

```sql
SELECT *
FROM Person AS person
WHERE person.name == :name
```

The name parameter is not assigned to a value yet. We assign the parameter value
when we execute the query. A best practice when assigning parameters is to 
create a copy of the request then assign the parameter. We can take advantage of
copy-on-write semantics for value types:

```swift
var newRequest = request
newRequest.set(nameParameter, "Fred")
return try request.fetchAll()
```

This binds the value "Fred" to the name parameter in the context of the request
before fetching all of the matching results.

## Update statements

We can modify an existing record using an update statement. In this example we
set the age of the person whose id is `fred` to the value `42`.

```swift
let updateStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting<Person> { row in
        row.age = 42
    }
    Where(
        person.id == 'fred'
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

let updateRequest = try database.makeRequest(with: updateStatement)

...

var newUpdateRequest = updateRequest
newUpdateRequest.set(idParameter, "fred")
newUpdateRequest.set(ageParameter, 42)
try newUpdateRequest.execute()
```

## Delete statements

We can delete records by specifying the table and a where clause for the items
to delete. The example shows a prepared statement with parameters:

```swift
let idParameter = XLNamedBindingReference<String>(name: "id")

let deleteStatement = sql { schema in
    let person = schema.into(Person.self)
    Delete(person)
    Where(person.id == idParameter)
}

let deleteRequest = try database.makeRequest(with: deleteStatement)

...

var newDeleteRequest = deleteRequest
newDeleteRequest.set(idParameter, "fred")
try newDeleteRequest.execute()
```
