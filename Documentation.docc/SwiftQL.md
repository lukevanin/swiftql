# SwiftQL

SwiftQL lets you write SQL using familiar type-safe Swift.

## Overview

SwiftQL lets you write type-safe SQLite statements using familiar Swift syntax.

Here is a quick example:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == 'Fred')
}
```

This would be equivalent to writing the SQL:

```sql
SELECT *
FROM Person AS person
WHERE person.name == 'Fred'
```

SwiftQL is designed to look like SQLite SQL syntax, while keeping to the style 
and conventions of the Swift language. 

## When to use SwiftQL

SwiftQL provides a safer way to write SQL to interact with an SQLite database, 
or if you need a portable self-hosted relational database. SwiftQL lets you:
- Create tables using `Create` statements,
- Modify the database using `Update`, `Insert`, and `Delete` statements, and 
- Query the database using `Select` statements.

## Why SQLite?

SQLite is a commonly used database used by many iOS and MacOS applications. It 
has been around forever, runs just about everywhere, and its charactaristics are 
generally well understood. 

## How is SwiftQL different to SwiftData?

SwiftData is an object-relational mapping (ORM) framework that allows 
applications to persist an object graph. SwiftQL provides an interface to query 
and modify a relational database.

With an ORM such as SwiftData the application primarly interacts with objects. 
Relationships between objects are defined by member properties.

With a relational database the application interacts with rows within tables.
Relationships are defined by joining tables using primary and foreign keys.

Call us biased but believe that relational databases are the Correct Way™️ to
handle large and/or complicated data sets efficiently.

## Getting started

We briefly saw SwiftQL's syntax in the overview. This section goes into more 
detail on composing and executing queries, including how to pass parameters.

### Defining tables

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

### Executing statements

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

### Inserting data

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

### Running select queries

Now that we have some data, we can run the select query we enountered 
previously. First we prepare the query, then execute it:

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

### Variables

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




