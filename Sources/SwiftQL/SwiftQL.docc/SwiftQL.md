# ``SwiftQL``

Write SQL using familiar type-safe Swift syntax.

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

This would be equivalent to writing the following SQL:

```sql
SELECT *
FROM Person AS person
WHERE person.name == 'Fred'
```

SwiftQL is designed to look like the SQL you are accustomed to, while adhering 
to the style and conventions of the Swift language. 

SwiftQL uses SQL used by SQLite. If you have used SQL in SQLite you already know 
SwiftQL.

## Why SQLite?

SQLite is a commonly used database used by many iOS and MacOS applications. It 
has been around forever, runs just about everywhere, and its charactaristics are 
generally well understood. 

SwiftQL provides the best the best of both SQLite and Swift: a stable and well 
defined interface and set of capabilities, accessed through a modern type safe 
language.

Where Swift and SQLite diverge in philosophy, Swift is given preference so that
the SQL code you write continues to feel like first class Swift. An example is 
where SQLite uses flexible typing, SwiftQL adheres to Swift's strict typing and
provides assurances that SQL statements will not implicitly convert types. 
However SwiftQL does not intentionally remove any functionality from SQLite, and 
provides utilities for safely casting types when needed.  

## When to use SwiftQL

SwiftQL provides a safer way to write SQL to interact with an SQLite database, 
or if you need a portable self-hosted relational database. SwiftQL lets you:
- Create tables using `Create` statements,
- Modify the database using `Update`, `Insert`, and `Delete` statements, and 
- Query the database using `Select` statements.

SwiftQL provides a way to write SQL statements uing regular Swift syntax which
is checked at compile time. 

By using SwiftQL you gain code completion in your IDE for table and
column names, and assurances that the SQL code you write is syntactically 
correct.

When making changes to existing tables, the compiler can provide errors and 
warnings to indicate where references need to be changed in your code.

SwiftQL ensures that types are handled consistently avoiding errors caused by
implicit type conversion.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Queries>
- <doc:LiveQueries>
- <doc:Expressions>
- <doc:BuiltinFunctions>
- <doc:FunctionalSyntax>

### Advanced topics
- <doc:CustomFunctions>
- <doc:CustomTypes>
- <doc:GenericTableParameters>


