# Generic Table Parameters

Use generic parameters on table definitions.

## Overview

SwiftQL lets you create `@SQLTable` definitions which use generic type
parameters. Generic parameters can use the intrinsic types, including `Bool`,
`Int`, `Double`, `String`, and `Data`, as well as any custom type defined as an
`XLCustomType`.

A table with generic parameters can be useful when its structure is reused in
an application but the type of one or more fields differs.

## Using generic tables

This example defines a table with one generic parameter. Each generic column
must satisfy the same `XLLiteral` and `XLExpression` requirements as a concrete
column type.

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
import SwiftQL

@SQLTable(name: "Generic")
struct GenericTable<Value: XLLiteral & XLExpression> {
    var id: String
    var type: String
    var value: Value
}
```

We can now create, insert into, and query the table using a `String` generic
parameter.

First we create the table. All specializations use the same SQL table name, so
the table is created once. The specialization used in each insert or query
controls how SwiftQL encodes and decodes the generic column.

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let createStatement = sqlCreate(GenericTable<String>.self)
try database.makeRequest(with: createStatement).execute()
```

Next we can insert some data into the table. Here the generic type is inferred
to be `String` from the value assigned to the `value` attribute.

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let insertStatement = sqlInsert(GenericTable(id: "foo-name", type: "name", value: "Foo"))
try database.makeRequest(with: insertStatement).execute()
```

We can now use the generic table in a `Select` query. We need to provide the 
generic parameter in the query when specifying the table. 

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
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

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let insertStatement = sqlInsert(GenericTable(id: "foo-age", type: "age", value: 42))
try database.makeRequest(with: insertStatement).execute()
```

We can select our integer records from the database:

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
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
example using the custom UUID shown in <doc:CustomTypes/UUID-wrapper>. Our custom
type is used just like an intrinsic type:

We can create a table using our custom type:

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let createStatement = sqlCreate(GenericTable<MyUUID>.self)
try database.makeRequest(with: createStatement).execute()
```

We can insert records using those values:

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
import Foundation

let uuid = MyUUID(UUID(uuidString: "72472fdd-a897-4b35-9bd9-0f23688f45f7")!)
let insertStatement = sqlInsert(GenericTable(id: "foo-id", type: "id", value: uuid))
try database.makeRequest(with: insertStatement).execute()
```

We can query our generic table using our custom type:

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
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

Generic tables take advantage of SQLite's dynamic type system and type
affinity: the type of a table column is not always strictly enforced. This
comes with the caveat that a column can potentially contain different storage
classes.

Consider the use case described above where a generic table contains both `Int`
and `String` data:

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let fooName = GenericTable(id: "foo-name", type: "name", value: "Foo")
try database.makeRequest(with: sqlInsert(fooName)).execute()

let fooAge = GenericTable(id: "foo-age", type: "age", value: 42)
try database.makeRequest(with: sqlInsert(fooAge)).execute()
```

Our table now contains two records. One record contains a `String` `"Foo"`, and
the other record contains an `Int` `42`. Selecting every row through the
`GenericTable<Int>` specialization asks SwiftQL to decode both storage classes
as `Int`, which is not a reliable representation of the stored data. Filter to
rows written with the matching specialization or use a schema that models the
possible value types explicitly.

<!-- test: XLDocumentationTests.testDocumentationGenericTableParameters -->
```swift
let selectStatement = sql { schema in
    let table = schema.table(GenericTable<Int>.self)
    Select(table)
    From(table)
}
```

> Warning: It is the programmer's responsibility to ensure that generic tables 
are read and written in a consistent manner.
