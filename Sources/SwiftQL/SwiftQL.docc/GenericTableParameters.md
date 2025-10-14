# Generic Table Parameters

Use generic parameters on table definitions.

## Overview

SwiftQL lets you create `@SQLTable` and `SQLResult` definitions which use 
generic type parameters. Generic parameters can use the intrinsic types 
including `Bool`, `Int`, `Double`, `String` and `Data`, as well any custom type 
defined as an `SQLCustomType`.

A table or result with generic parameters might be used where the structure of 
the table or result is commonly used in an application, but where the type of 
some or all of the fields differs. 

## Using generic tables

We define a table with a generic parameter conforming to `XLLiteral` and
`XLExpression`. SwiftQL does impose a limit on the number or type of generic 
parameters.

```swift
@SQLTable struct GenericTable<Value: XLLiteral & XLExpression> {
    var id: String
    var type: String
    var value: Value
}
```

We can now use our generic table like any other table create, insert, and query 
our table using a `String` generic parameter.

First we create the table. The generic parameter used in the create statement
is not important as it can be overridden in queries.

```swift
let createStatement = sqlCreate(GenericTable<String>.self)
try database.makeRequest(with: createStatement).execute()
```

Next we can insert some data into the table. Here the generic type is inferred
to be `String` from the value assigned to the `value` attribute.

```swift
let insertStatement = sqlInsert(GenericTable(id: "foo-name", type: "name", value: "Foo"))
try database.makeRequest(with: insertStatement).execute()
```

We can now use the generic table in a `Select` query. We need to provide the 
generic parameter in the query when specifying the table. 

```swift
let selectStatement = sql { schema in
    let table = schema.table(GenericTable<String>.self)
    Select(table)
    From(table)
    Where(table.type == "name")
}
let names = try database.makeRequest(with: selectStatement).fetchAll()
```

We can use the same table with an `Int` parameter. We can insert another record
into the table with an integer value:

```swift
let insertStatement = sqlInsert(GenericTable(id: "foo-age", type: "age", value: 42))
try database.makeRequest(with: insertStatement).execute()
```

We can select our integer records from the database:

```swift
let selectStatement = sql { schema in
    let table = schema.table(GenericTable<Int>.self)
    Select(table)
    From(table)
    Where(table.type == "age")
}
let ages = try database.makeRequest(with: selectStatement).fetchAll()
```

## Custom types

Generic tables can also use custom types which we define. Let's look at an 
example using the custom UUID shown in <doc:CustomTypes/Custom-UUID>. Our custom
type is used just like an intrinsic type:

We can create a table using out custom type:

```swift
let createStatement = sqlCreate(GenericTable<MyUUID>.self)
try database.makeRequest(with: createStatement).execute()
```

We can insert records using those values:

```swift
let uuid = MyUUID(UUID(uuidString: "72472fdd-a897-4b35-9bd9-0f23688f45f7")!)
let insertStatement = sqlInsert(GenericTable(id: "foo-id", type: "id", value: uuid))
try database.makeRequest(with: insertStatement).execute()
```

We can query our generic table using our custom type:

```swift
let selectStatement = sql { schema in
    let table = schema.table(GenericTable<MyUUID>.self)
    Select(table)
    From(table)
    Where(table.type == "id")
}
let uuids = try database.makeRequest(with: selectStatement).fetchAll()
```

## Data consistency

Generic tables take advantage of SQLite's loose typing or type affinity: that is 
the type of a table column is not strictly enforced. This comes with the caveat 
that a column in a table can potentially contain different types of data. 

Consider the use case described above where a generic table contains both `Int` 
and  `String` data:

```swift
let fooName = GenericTable(id: "foo-name", type: "name", value: "Foo")
try database.makeRequest(with: sqlInsert(fooName).execute()

let fooAge = GenericTable(id: "foo-age", type: "age", value: 42)
try database.makeRequest(with: sqlInsert(fooAge)).execute()
```

Our table now contains two records. One record contains a `String` `"foo"`, and
the other record contains an `Int` `42`. If we now select from the table using 
an `Int` for the generic table, without an appropriate `Where` clause, the
query will select rows containing `String` and `Int` values, resulting in an
exception at runtime.

```swift
let selectStatement = sql { schema in
    let table = schema.table(GenericTable<Int>.self)
    Select(table)
    From(table)
}
```

> Warning: It is the programmer's responsibility to ensure that generic tables 
are read and written in a consistent manner.
