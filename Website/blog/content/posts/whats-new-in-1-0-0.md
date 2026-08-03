---
title: "What's new in 1.0.0"
date: 2025-09-30
description: "SwiftQL's first tagged release: macro-generated table types, a SQL-shaped query API backed by GRDB, joins, CTEs, and custom types and functions."
---

SwiftQL 1.0.0 is the project's first tagged release. It ships the pieces that everything since builds on: a `@SQLTable` macro that turns a Swift struct into a typed table, a query API that can be written either as chained functions or as a SQL-shaped result builder, and a GRDB-backed layer that executes the generated SQL against SQLite.

## Defining a table

A table is a Swift struct annotated with `@SQLTable`. The macro reads the struct's stored properties and generates the column references, encoding, and decoding needed to use it in a query:

```swift
@SQLTable struct Person: Equatable {
    var id: String
    var occupationId: String?
    var name: String
    var age: Int
}
```

`Bool`, `Int`, `Double`, `String`, and `Data` are supported out of the box, along with enums backed by those types. A table gets a reference from a schema, and that reference is what queries are built from:

```swift
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    return select(person).from(person)
}
```

This is a real test from 1.0.0's suite, checked against both the SQL it renders and the rows it returns:

```swift
let sql = encoder.makeSQL(statement).sql
let rows = try database.makeRequest(with: statement).fetchAll()
// sql == "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0"
// rows == [johnDoe, janeDoe, yogiBear]
```

## Two ways to write the same query

The functional syntax above chains methods the way a query builder normally does. 1.0.0 also ships a result builder syntax, entered through the `sql { }` closure, where each SQL clause is its own statement in SQL's own order:

```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
}
```

Both forms produce the same statement and the same generated SQL. Which one to use is a matter of preference: the functional form reads like a fluent builder, the result builder form reads closer to the SQL text it produces.

## Joins, grouping, and subqueries

Inner and left joins are supported, driven by `Join.Inner` and `Join.Left` on the result-builder side:

```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)
    Select(person)
    From(person)
    Join.Inner(occupation, on: occupation.id == person.occupationId)
}
```

A left join can produce a row where the joined side has no match, and SwiftQL models that with `schema.nullableTable`, which makes every column from that table optional in the result. `GROUP BY`, `HAVING`, and aggregate functions (`count`, `min`, `max`, `average`) are also there, along with scalar and correlated subqueries usable anywhere a column can appear.

Right joins are the one join type 1.0.0 does not support.

## Common table expressions

Ordinary and recursive CTEs are both present from the start. A recursive CTE is built with `schema.recursiveCommonTableExpression`, which hands the closure a second parameter for the self-reference:

```swift
let expression = sql { schema in
    let cte = schema.recursiveCommonTableExpression(ScalarString.self) { schema, cte in
        let org = schema.table(Org.self)
        Select(result { ScalarString.SQLReader(scalarValue: "Alice".toNullable()) })
        Union()
        Select(result { ScalarString.SQLReader(scalarValue: org.name) })
        From(org)
        Join.Cross(cte)
        Where(org.boss == cte.scalarValue)
    }
    let org = schema.table(Org.self)
    With(cte)
    Select(org.name)
    From(org)
    Where(org.name.in(cte))
}
```

`cte.scalarValue` in the `Where` clause refers back to the recursive term, and it's type-checked the same as any other column reference.

## Inserts, updates, deletes, and CREATE TABLE AS SELECT

`sqlInsert`, `sqlUpdate`, `sqlCreate`, and the result builder's `Delete` clause cover writes:

```swift
let expression = sql { schema in
    let t = schema.into(TestTable.self)
    Delete(t)
    Where(t.value == 42)
}
// DELETE FROM Test AS t0 WHERE (t0.value == 42)
```

A statement built with a parameterized closure and `SQLNamedBindingReference` can be constructed once and reused, with new values bound per call:

```swift
private static let statement: any SQLUpdateStatement<TestTable> = sqlUpdate {
    let table = $0.into(TestTable.self)
    return update(table, set: TestTable.MetaUpdate(value: valueParameter))
        .where(table.id == idParameter)
}
```

`sqlCreate` also supports `CREATE TABLE AS SELECT`, populating a new table from the result of a query rather than a literal row.

## Custom types and custom functions

Types beyond the built-in five can participate in SQL by conforming to `SQLCustomType`, which defines how a value is read from a row, bound as a parameter, and rendered into SQL text. The README's example extends `UUID` and `Date` this way, storing a `Date` as text and wrapping every SQL use of it in SQLite's `unixepoch` function so comparisons work on the numeric timestamp rather than the string.

Custom SQLite functions work the same way, through `SQLCustomFunction`. A function conforming to that protocol is installed on the database once and then called from any expression of the matching type, with its Swift implementation running at query time and its result flowing back into SQL.

## Built on GRDB

1.0.0 targets iOS 16 and macOS 13, needs the Swift 5.9 toolchain for macro support, and depends on swift-syntax 509.0.0 for the macro implementation and GRDB 6.29.3 for SQLite access and execution. Connection pooling, migrations, and observation stay with GRDB; SwiftQL's job is the statement that gets handed to it.

## What's not there yet

A handful of gaps are called out directly in the 1.0.0 README rather than left implicit:

- Right joins aren't supported.
- There's no `UPSERT` (`INSERT ... ON CONFLICT`) support.
- `INSERT ... SELECT` and `UPDATE ... SELECT` aren't supported; only literal values can be inserted or updated.
- There's no general `.cast(to:)` for converting an expression's type; conversions are handled case by case, like `.toNullable()` and `.toDouble()`.
- `GROUP BY` correctness (which columns are legal in the `SELECT` list) isn't enforced by the type system, so a statement that SQLite would reject can still compile.
- SwiftQL executes through GRDB rather than talking to SQLite directly.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[1.0.0 release](https://github.com/lukevanin/swiftql/releases/tag/1.0.0)
