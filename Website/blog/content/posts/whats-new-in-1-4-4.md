---
title: "What's new in v1.4.4"
date: 2026-07-24
description: "INSERT gains conflict-resolution clauses and upsert, RETURNING lands on INSERT, UPDATE, and DELETE, and UPDATE can now be scoped by a WITH clause."
---

v1.4.4 rounds out SwiftQL's write surface. Conflict resolution, upsert, `RETURNING`, and CTE-scoped updates were the remaining gaps between what SwiftQL's `INSERT`, `UPDATE`, and `DELETE` could express and what SQLite's grammar allows. All six additions are covered below, and every change is additive: existing insert, update, and delete code keeps compiling unchanged.

## INSERT OR conflict resolution

SQLite's conflict algorithm is part of the `INSERT` keyword itself, applying to every uniqueness constraint the statement violates. `Insert(_:or:)` and the functional `insert(_:or:)` now take that algorithm as a parameter:

```sql
INSERT OR IGNORE INTO Person (id, name) VALUES ('a', 'Fred')
```

```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    Insert(person, or: .ignore)
    Values(Person.MetaInsert(newPerson))
}
```

`.rollback`, `.abort`, `.fail`, `.ignore`, and `.replace` are all covered.

## REPLACE INTO

`REPLACE INTO` is SQLite's shorthand for `INSERT OR REPLACE INTO`, and it's now available as its own statement through `Replace` and the functional `replace(_:)`:

```swift
let statement = sql { schema in
    let person = schema.table(Person.self)
    Replace(person)
    Values(Person.MetaInsert(newPerson))
}
```

## Upsert with ON CONFLICT

`OnConflict`, the functional `onConflict`/`onConflictDoNothing` methods, and a new `XLSchema.excluded` reference cover both the `DO NOTHING` and `DO UPDATE SET ...` forms of `INSERT ... ON CONFLICT`, including an optional `WHERE` filter on the update:

```swift
let schema = XLSchema()
let person = schema.table(Person.self)
let excluded = schema.excluded(Person.self)

let statement = insert(person)
    .values(Person.MetaInsert(newPerson))
    .onConflict("id", doUpdate: { row in row.name = excluded.name })
```

`excluded` refers to the row that triggered the conflict, the same way `excluded.name` does inside a raw SQLite upsert. It renders as the bare `excluded` keyword rather than an aliased table, matching what SQLite's own conflict target expects.

## RETURNING on INSERT, UPDATE, and DELETE

`INSERT`, `UPDATE`, and `DELETE` can now all carry a `returning(_:)` clause, including on `ON CONFLICT` upserts. A statement with `RETURNING` becomes fetchable:

```swift
let inserted: [Person] = try database.makeRequest(
    with: insert(person)
        .values(Person.MetaInsert(newPerson))
        .returning(person)
).fetchAll()
```

SQLite rejects statement-aliased names inside a `RETURNING` list, so the returned columns render unqualified (`RETURNING id, name`) rather than `RETURNING t0.id`. `RETURNING` requires SQLite 3.35.0, and a returning statement runs once on a write connection: publishing it as a live query fails rather than silently re-executing the write on every database change.

## UPDATE scoped by a common table expression

`XLWithStatement.update` lets a factored common table expression drive an update, the same way `with(cte).select(...)` already drove a read:

```swift
let source = schema.commonTable { schema in
    let p = schema.table(Person.self)
    return select(p).from(p)
}
let target = schema.into(Person.self)
let s = schema.table(source)

let statement = with(source)
    .update(target)
    .set { row in row.age = s.age + 1 }
    .from(s)
    .where(target.id == s.id)
```

## SELECT-driven inserts and updates, confirmed

`INSERT ... SELECT` and the `UPDATE ... SET ... FROM (SELECT ...)` form, built with `fromExpression`, now carry real-SQLite execution evidence in the conformance inventory alongside everything else in this release.

## Conformance inventory

The new conflict-resolution, replace, upsert, CTE-scoped update, `RETURNING`, and SELECT-driven surfaces are recorded in the project's SQLite conformance inventory. It now tracks 111 public-surface feature records: 107 supported, 2 capability-gated, 1 intentionally unsupported, and 1 unimplemented, with 105 of 171 evidence records exercising a real SQLite engine.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.4 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.4)
