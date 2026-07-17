# Functional Syntax

Use functional syntax with SwiftQL.

## Overview

This guide will show you how to use SwiftQL's built in functional syntax. 

SwiftQL provides functional syntax as an alternative to the result builder 
syntax discussed in the <doc:GettingStarted> guide. 

> Note: While the intended goal of SwiftQL is to provide feature parity for both
functional and result builder syntax, some features may not be available while
SwiftQL is under development. If your favorite feature is missing, please file
an issue on GitHub.

## Essentials

SwiftQL provides the convenience function `sqlQuery` that lets you compose a 
query using functional syntax.  

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person).from(person)
}
```

This would be equivalent to writing the statement using result builder syntax:

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
}
```

The main differences are:

Functional syntax                                | Result builder syntax                   
-------------------------------------------------|-------------------------------------
Uses a return statement.                         | No return statement.
Lower case names for statements. e.g. `select`   | Statements start with an uppercase letter. e.g. `Select`.
Statements are joined with a dot.                | Statements are written on separate lines.

Functional syntax can also be written without the wrapper function. In this case
an `XLSchema` needs to be instantiated explicitly:

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let schema = XLSchema()
let people = schema.table(Person.self, as: "people")
let statement = select(people).from(people)
```

The statement is executed in the same manner as the result builder syntax seen
in other examples:

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
import Foundation

let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let databaseURL = directory.appending(path: "my_database.sqlite")
let database = try GRDBDatabase(url: databaseURL, logger: nil)
let request = database.makeRequest(with: statement)
let rows = try request.fetchAll()
```

Below are additional examples using functional syntax.

### Example: Variable parameter

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person).from(person).where(person.name == nameParameter)
}

let request = database.makeRequest(with: statement)
let bindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: request.parameterLayout,
    bindings: [
        try XLInvocationBinding(
            slot: request.parameterLayout.slot(for: .named("name"))!,
            value: .text("John Doe")
        )
    ]
).validatingComplete()
let peopleNamedJohn = try request.fetchAll(bindings: bindings)
```

Functional and result-builder statements produce the same immutable static
parameter layout. Values are supplied separately in a per-call packet; the
syntax used to construct the statement does not change binding semantics.

### Example: Where

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .where((person.name == "John Doe") || (person.age == 25))
}
```

### Example: Order-by

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let statement = sqlQuery { schema in 
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .orderBy(person.name.ascending(), person.age.descending())
}
```

### Example: Limit

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let _ = sqlQuery { schema in 
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .limit(10) 
}
```

### Example: Inner join

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)
    return select(person)
        .from(person)
        .innerJoin(occupation, on: occupation.id == person.occupationId)
}
```

### Example: Group-by 

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
@SQLResult struct OccupationPopulation {
    let occupation: String
    let numberOfPeople: Int
}

let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)

    let result = OccupationPopulation.columns(
        occupation: occupation.name.coalesce("No occupation"),
        numberOfPeople: person.id.count()
    )

    return select(result)
        .from(person)
        .leftJoin(occupation, on: occupation.id == person.occupationId)
        .groupBy(occupation.id)
}
```

### Example: Left join

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
@SQLResult struct PersonOccupationName {
    let person: String
    let occupation: String
}

let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let result = PersonOccupationName.columns(
        person: person.name,
        occupation: occupation.name.coalesce("No occupation") 
    )
    return select(result)
        .from(person)
        .leftJoin(occupation, on: occupation.id == person.occupationId)
}
```

### Example: Update

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
@SQLTable struct ExampleValue {
    let id: String
    let value: Int
}

try database.makeRequest(with: sqlCreate(ExampleValue.self)).execute()
try database.makeRequest(
    with: sqlInsert(ExampleValue(id: "example-id", value: 0))
).execute()

let idParameter = XLNamedBindingReference<String>(name: "id")
let valueParameter = XLNamedBindingReference<Int>(name: "value")
let id = "example-id"
let value = 42

let statement: any XLUpdateStatement<ExampleValue> = sqlUpdate { schema in
    let table = schema.into(ExampleValue.self)
    return update(table, set: ExampleValue.MetaUpdate(
        value: valueParameter
    ))
    .where(table.id == idParameter)
}

let request = database.makeRequest(with: statement)
let bindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: request.parameterLayout,
    bindings: [
        try XLInvocationBinding(
            slot: request.parameterLayout.slot(for: .named("id"))!,
            value: .text(id)
        ),
        try XLInvocationBinding(
            slot: request.parameterLayout.slot(for: .named("value"))!,
            value: .integer(Int64(value))
        )
    ]
).validatingComplete()
try request.execute(bindings: bindings)
```

`validatingComplete()` distinguishes an omitted parameter from a present SQL
`NULL` value. Use `.null` only for a slot declared nullable; leaving a slot out
is always a missing binding. The mutating `set` API remains available as a
source-compatible migration shim for older literal-based code.

### Example: Create

<!-- test: XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations -->
```swift
@SQLTable struct EmployeeSource {
    let id: String
    let name: String
}

@SQLTable struct EmployeeName {
    let id: String
    let value: String
}

try database.makeRequest(with: sqlCreate(EmployeeSource.self)).execute()
try database.makeRequest(
    with: sqlInsert(EmployeeSource(id: "employee-1", name: "Ada"))
).execute()

let createStatement = sqlCreate { schema in
    let t = schema.create(EmployeeName.self)
    return create(t).as { schema in
        let employee = schema.table(EmployeeSource.self)
        let row = EmployeeName.columns(
            id: employee.id,
            value: employee.name
        )
        return select(row).from(employee)
    }
}
try database.makeRequest(with: createStatement).execute()
```
