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

```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person).from(person)
}
``` 

This would be equivalent to writing the statement using result builder syntax:

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

```swift
let schema = XLSchema()
let people = schema.table(Person.self, as: "people")
let statement = select(people).from(people)
```

The statement is executed in the same manner as the result builder syntax seen
in other examples:

```swift
let database = GRDBDatabase(url: <url to SQLite database file>)
let request = database.makeRequest(with: statement)
let rows = request.fetchAll()
```

Below are additional examples using functional syntax.

### Example: Variable parameter

```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person).from(person).where(person.name == nameParameter)
}
```

### Example: Where

```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .where((person.name == "John Doe") || (person.age == 25))
}
```

### Example: Order-by

```swift
let statement = sqlQuery { schema in 
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .orderBy(person.name.ascending(), person.age.descending())
}
``` 

### Example: Limit

```swift
let _ = sqlQuery { schema in 
    let person = schema.table(Person.self)
    return select(person)
        .from(person)
        .limit(10) 
}
```

### Example: Inner join

```swift
let statement = sqlQuery { swift 
    let person = $0.table(Person.self)
    let occupation = $0.table(Occupation.self)
    return select(person)
        .from(person)
        .innerJoin(occupation, on: occupation.id == person.occupationId)
}
```

### Example: Group-by 

``` swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)

    let result = OccupationCount.columns(
        occupation: occupation.name,
        numberOfPeople: person.id.count()
    )

    return select(result)
        .from(person))
        .leftJoin(Occupation.self, on: person.occupationId == occupation.id }
        .groupBy(occupation.id)
}
```

### Example: Left join

```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let result = PersonOccupation.columns(
        person: person.name,
        occupation: occupation.name.coalesce("No occupation") 
    )
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

### Example: Update

```swift
let idParameter = XLNamedBindingReference<String>(name: "id")
let valueParameter = XLNamedBindingReference<Int>(name: "value")

let statement: any XLUpdateStatement<TestTable> = sqlUpdate { schema in
    let table = schema.into(TestTable.self)
    return update(table, set: TestTable.MetaUpdate(
        value: valueParameter
    ))
    .where(table.id == idParameter)
}

var request = database.makeRequest(with: statement)
request.set(Self.idParameter, id)
request.set(Self.valueParameter, value)
try request.execute()
```

### Example: Create

```swift
let createStatement = sqlCreate { schema in
    let t = schema.create(Temp.self)
    return create(t).as { schema in
        let employee = schema.table(EmployeeTable.self)
        let row = result {
            Temp.SQLReader(
                id: employee.id,
                value: employee.name
            )
        }
        return select(row).from(employee)
    }
}
try database.makeRequest(with: createStatement).execute()
```
