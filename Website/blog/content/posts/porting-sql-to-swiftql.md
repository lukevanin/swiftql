---
title: "Moving a SQL query into SwiftQL, one clause at a time"
date: 2026-07-31
description: "How to port an existing SQLite query to SwiftQL: clause by clause, in SQL's own order, with worked examples including a left join, grouped aggregates, and a full recursive CTE."
---

I designed SwiftQL so that porting a query is mechanical: rewrite it clause by clause, top to bottom, in the same order the SQL already has. If a query does not port this way, that is a bug in SwiftQL, not something to work around.

## The shape of a port

Take an ordinary query:

```sql
SELECT * FROM Person WHERE name = 'Fred'
```

The port keeps every clause, in order, and swaps table and column names for typed references:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

Three lines of SQL, three statements of Swift, same order. The only additions are the `sql { schema in ... }` entry point and the `let person =` binding, which gives you a typed handle to the table. That handle is where the type checking comes from: `person.name` is a typed column reference, so a typo does not compile, and a rename sends the compiler to every query that touches it.

## Filtering, ordering, and paging

Clauses stack the same way SQL stacks them. Ordering, limits, and offsets are separate statements, in the order SQL already puts them:

```sql
SELECT * FROM Person
ORDER BY age ASC
LIMIT 5 OFFSET 10
```

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.age.ascending())
    Limit(5)
    Offset(10)
}
```

## A left join

A left join shows the one place SQL and SwiftQL differ:

```sql
SELECT Person.id, Person.name, Occupation.id, Occupation.name
FROM Person
LEFT JOIN Occupation ON Occupation.id = Person.occupationId
```

A projection that is not a whole table needs a result type, so the decoded rows have somewhere to land:

```swift
@SQLResult struct PersonOccupation {
    let personId: String
    let personName: String
    let occupationId: String?
    let occupationName: String?
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    Select(
        PersonOccupation.columns(
            personId: person.id,
            personName: person.name,
            occupationId: occupation.id,
            occupationName: occupation.name
        )
    )
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

`schema.nullableTable` marks the joined side as optional, because a left join can produce no matching row. That case only shows up in SQL the first time a join comes back empty. SwiftQL marks `occupationId` and `occupationName` as `String?` before the query ever runs, so the compiler is the one catching it, not a crash report.

## Grouping and aggregates

`GROUP BY` and `HAVING` port the same way, and the aggregate gets a name you can refer to from `Having`:

```sql
SELECT occupationId, COUNT(id) AS numberOfPeople
FROM Person
GROUP BY occupationId
HAVING numberOfPeople >= 2
```

```swift
@SQLResult struct OccupationAggregate {
    var occupationId: String?
    var numberOfPeople: Int
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let row = OccupationAggregate.columns(
        occupationId: person.occupationId,
        numberOfPeople: person.id.count()
    )
    Select(row)
    From(person)
    GroupBy(person.occupationId)
    Having(row.numberOfPeople >= 2)
}
```

Binding the projection to `row` first lets `Having` refer to `numberOfPeople` by name, the same way SQL refers to the alias.

## The recursive CTE

This is the showpiece, and the showpiece is easier shown than described. Walking an org chart upward from a starting employee:

```sql
WITH RECURSIVE cte(value) AS (
    SELECT 'Alice'
    UNION
    SELECT Org.name FROM Org CROSS JOIN cte WHERE Org.boss = cte.value
)
SELECT Org.name FROM Org WHERE Org.name IN cte
```

```swift
@SQLResult struct ScalarString {
    var value: String?
}

let query = sql { schema in

    let cte = schema.recursiveCommonTableExpression(ScalarString.self) { schema, cte in
        let org = schema.table(Org.self)
        // Define the initial value for the starting condition.
        let initialResult = ScalarString.columns(value: "Alice".toNullable())
        Select(initialResult)
        // Union the initial value with successive values.
        Union()
        // Select members from the org whose boss matches the current member.
        Select(ScalarString.columns(value: org.name))
        From(org)
        Join.Cross(cte)
        Where(org.boss == cte.value)
    }

    let org = schema.table(Org.self)
    With(cte)
    Select(org.name)
    From(org)
    Where(org.name.in(cte))
}
```

The recursive self-reference is the `cte` parameter of the closure. It is a typed table reference like any other, so `cte.value` is checked the same way `org.name` is, and the compiler catches a typo in either one.

## Porting raw SQL strings

If your current code interpolates values straight into the SQL text, the port removes the interpolation along with the string:

```swift
let sqlText = "SELECT id, name FROM Person WHERE name = '\(name)'"
var statement: OpaquePointer?
sqlite3_prepare_v2(db, sqlText, -1, &statement, nil)
```

```swift
let nameParameter = XLNamedBindingReference<String>(name: "name")

let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
```

`nameParameter` is bound at invocation, not spliced into the statement, so there is no closing quote to get wrong and no value that needs escaping.

The same replacement works on GRDB's own raw-SQL API. An update built from a format string:

```swift
try db.execute(
    sql: "UPDATE Person SET age = ? WHERE id = ?",
    arguments: [newAge, personID]
)
```

ports to a statement built once and reused, with the same named bindings:

```swift
let ageParameter = XLNamedBindingReference<Int>(name: "age")
let personIDParameter = XLNamedBindingReference<String>(name: "id")

let updateAgeStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.age = ageParameter
    }
    Where(person.id == personIDParameter)
}
```

Execution, pooling, and observation stay with GRDB underneath, so an existing setup keeps working. SwiftQL replaces the part where a query was a string.

## Where it doesn't map one to one

A handful of gaps are documented rather than papered over, and each has a working answer.

Schema migrations are not something SwiftQL touches at all: keep using GRDB's own migrator alongside it.

```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("v2") { db in
    try db.alter(table: "Person") { $0.add(column: "occupationId", .text) }
}
try migrator.migrate(dbQueue)
```

Of 114 tracked SQLite features, 110 are supported today with evidence from a real SQLite engine.

### Supported today

| Area | Features | What it covers |
| --- | ---: | --- |
| Expressions, functions, and value codecs | 43 | Aggregates (`COUNT`, `SUM`, `AVG`, `GROUP_CONCAT`), `CASE`/`COALESCE`/`IIF`, date and time, JSON, `CAST`, `LIKE`/`IN`/`BETWEEN`, and `INTEGER`/`REAL`/`TEXT`/`BLOB` type-boundary conformance |
| Inserts, updates, and deletes | 26 | `INSERT`/`UPDATE`/`DELETE`, upsert (`ON CONFLICT`), `RETURNING`, conflict-resolution clauses, `WITH`-scoped updates, transaction and rollback behavior |
| Reads | 10 | `SELECT`, `FROM`, `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET` over real data |
| Live queries | 12 | `stream()`/`streamOne()`, cancellation, retry, backpressure, and isolation across a connection pool |
| Joins | 6 | `INNER`, `LEFT`, `RIGHT`, `FULL OUTER`, `CROSS`, `NATURAL`, and `USING` |
| Compound queries | 4 | `UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT`, including direct scalar rows |
| Subqueries | 4 | Scalar, correlated, and `IN`-subquery forms |
| Common table expressions | 4 | Ordinary and recursive CTEs, `MATERIALIZED`/`NOT MATERIALIZED` hints, and direct scalar rows |
| Schema | 1 | `CREATE TABLE` and `CREATE TABLE AS SELECT` |

### Planned

| Feature | Planned for |
| --- | --- |
| Typed `CREATE INDEX`, `ALTER TABLE`, and `DROP TABLE` (a full typed DDL model) | v2 |
| Nested transactions and savepoints | v2 |
| Single-connection visibility guarantees | v2 |

### Not planned

- **Fluent-style soft-delete, restore, force-delete, and default-filter lifecycle.** This is an ORM lifecycle convention, not a SQLite language feature, and adopting it would mean hiding the relational model the same way an ORM does. Model it directly instead: an ordinary `deletedAt: Date?` column and a plain `Where` clause do the same job without needing special library support.

Full guide: [PortingFromSQL.md](https://github.com/lukevanin/swiftql/blob/main/Documentation/PortingFromSQL.md)
The project: [github.com/lukevanin/swiftql](https://github.com/lukevanin/swiftql)
