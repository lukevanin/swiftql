# ``SwiftQL``

Write SQL using familiar type-safe Swift syntax.

## Overview

SwiftQL lets you write type-safe SQLite statements using familiar Swift syntax.

Here is a quick example:

<!-- test: XLDocumentationTests.testDocumentationQuickStart -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

This would be equivalent to writing the following SQL:

```sql
SELECT t0.id AS id, t0.occupationId AS occupationId,
       t0.name AS name, t0.age AS age
FROM Person AS t0
WHERE (t0.name == 'Fred')
```

SwiftQL is designed to look like the SQL you are accustomed to, while adhering 
to the style and conventions of the Swift language. 

SwiftQL targets SQLite's SQL dialect. If you already know SQLite syntax, the
corresponding SwiftQL statements should feel familiar.

## Why SQLite?

SQLite is a commonly used database in many iOS and macOS applications. It has
been around for decades, runs just about everywhere, and its characteristics
are generally well understood.

SwiftQL combines SQLite and Swift: a stable and well
defined interface and set of capabilities, accessed through a modern type safe 
language.

Where Swift and SQLite diverge in philosophy, Swift is given preference so that
the SQL code you write continues to feel like first-class Swift. SwiftQL uses
Swift's generic constraints to catch many mismatched expression types while a
statement is constructed. SQLite retains its dynamic typing, affinity, and
runtime coercion rules when the generated statement is executed.
SwiftQL aims to preserve SQLite's native semantics while exposing them through a
typed API. The current API covers a practical subset of SQLite, with unsupported
syntax called out in the relevant guides. SwiftQL also provides utilities for
safely casting types when needed.

## v1.2 boundaries

SwiftQL v1.2 separates database-independent query definitions from database
execution. An `XLStaticQueryDescriptor` retains rendered SQL, dialect
requirements, immutable parameter and result metadata, stable identity, and
cardinality without retaining a database, physical statement, or invocation
value. Prepare it against a `GRDBDatabase`, then give every call a fresh
`XLInvocationBindings` packet. See <doc:StaticQueries> for construction,
identity, preparation, and cardinality rules.

`SwiftQLCore` contains the GRDB-free dialect, value, logical-statement, binding,
and driver contracts needed by adapter packages. The `SwiftQL` product is the
application-facing compatibility facade: it adds the macros, typed SQL DSL,
contextual codecs, and the current GRDB-backed SQLite implementation. Dialects
own SQL spelling and value storage rules; drivers own connections, physical
preparation, binding transport, execution, and row transport. See
<doc:GettingStarted> for connection, transaction, and prepared-statement
ownership.

Existing v1 requests, named bindings, `XLCustomType` wrappers, and explicit
raw-value APIs remain source-compatible. The current `XLRequest` facade is
database-bound and not `Sendable`; prepared raw static-query handles are
`Sendable`, while closure-backed typed row-layout wrappers remain task-local.
Use <doc:CustomTypes> when one Swift type needs contextual or multiple SQLite
representations.

## v1.3 conformance evidence

The v1.3 source-tree milestone validates SwiftQL's existing public SQLite
surface rather than adding another syntax layer. Its versioned inventory,
generated report, bounded combinatorial cases, pinned Northwind corpus, and
observation stress contracts exercise rendering, real SQLite preparation, and
behavior. Evidence is tied to the recorded SQLite version, source ID, compile
options, and available capabilities; it is not a claim of complete SQLite
grammar coverage. See the repository's
[compatibility matrix](https://github.com/lukevanin/swiftql/blob/main/COMPATIBILITY.md)
and
[conformance report](https://github.com/lukevanin/swiftql/blob/main/Conformance/SQLite/REPORT.md)
for the canonical scope and current evidence.

Issue [#132](https://github.com/lukevanin/swiftql/issues/132) is research only.
Its internal prototype prepares static SQL against a pinned, read-only schema
snapshot and emits deterministic diagnostics, but v1.3 does not ship a public
validator, build plugin, query macro, schema system, or new query-declaration
API. It neither persists prepared statements nor removes runtime preparation
on each physical connection. Version 1.3.0 is the latest published package.

## When to use SwiftQL

SwiftQL provides a safer way to write SQL to interact with an SQLite database, 
or if you need a portable self-hosted relational database. SwiftQL lets you:

- Create tables using `Create` statements,
- Modify the database using `Update`, `Insert`, and `Delete` statements, and 
- Query the database using `Select` statements.

SwiftQL provides a way to write SQL statements using regular Swift syntax which
is checked at compile time. 

By using SwiftQL you gain code completion in your IDE for table and column
names, plus compile-time checks for the types and SwiftQL APIs used to construct
a statement. SQLite remains the final authority for database-specific syntax
and runtime constraints.

When making changes to existing tables, the compiler can provide errors and 
warnings to indicate where references need to be changed in your code.

This type information reduces construction and result-decoding mistakes without
replacing SQLite's runtime type rules.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Queries>
- <doc:StaticQueries>
- <doc:LiveQueries>
- <doc:Expressions>
- <doc:RealValues>
- <doc:BuiltinFunctions>
- <doc:FunctionalSyntax>

### Advanced topics
- <doc:Enums>
- <doc:CustomFunctions>
- <doc:CustomTypes>
- <doc:GenericTableParameters>
