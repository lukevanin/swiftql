---
title: "Why I taught the Swift compiler to read SQL"
date: 2026-07-31
description: "The design story behind SwiftQL: why Core Data and raw SQLite strings both fail, and why the library reads SQL in SQL's own order."
---

Every iOS app I've built that stored real data forced the same choice, and both options were bad.

Core Data is an object-graph manager. Apple says it isn't an ORM, but it offers the same bargain: you work with objects, and the store becomes someone else's problem.

Queries are hard to reason about, ordinary inserts and updates are slow, and the threading model is unpredictable. Managed objects are heap-allocated and bound to their context, so moving data across threads means passing IDs and re-faulting rather than passing values directly.

There are batch APIs that are faster, but they work by bypassing the object graph entirely. The abstraction meant to save work ends up generating its own, and its fastest path is the one that steps around it.

SQLite is the other option: stable, efficient, predictable, simple. But in Swift its queries are strings, with no compile-time checking at all. Every query is a shot in the dark that breaks the moment anything changes.

This came to a head when I worked at EventCloud, where I built the mobile app: a white-label app for events, offline-first, with a large data set and sync. It started on Core Data, and a disproportionate share of development time and runtime went into the database layer.

Moving to SQLite fixed the performance and predictability problems. It replaced them with a new one: hand-rolled query strings with zero compiler help.

I'd used LINQ before, and the idea followed from there: Swift should express SQL natively, so a query is type-checked like any other line of code.

## Native had to mean something specific

The goal was for the actual SQL language to work as first-class Swift syntax, using its own grammar rather than inventing a lookalike.

Most persistence libraries invent a proprietary API, and with it a switching cost: what you learn only applies inside that library. My constraint from the start was that the same statement should read the same way in SQL and in SwiftQL, so a query translates in either direction without a mental compiler in between.

That's why the library is SQL-shaped rather than ORM-shaped, and why clause names and clause order match SQL exactly:

```swift
sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

Each clause appears once, under its SQL name, in SQL's own order. There's no separate rule to learn about where `WHERE` attaches: the answer is the one SQL already gave you. The source is the statement.

I believe relational databases are the right way to handle data, and ORMs add an unnecessary layer of indirection that misrepresents what's happening underneath.

Object graphs model containment and reference well. They don't model a left join, a grouped aggregate, or a projection across three tables, because none of those produce an object: they produce a row shape that exists only for that query.

Every ORM answers this with workarounds like prefetch hints and fault batching, which are configuration knobs for a problem the relational model doesn't have, since a join is one query. When the abstraction leaks, and it always leaks, you end up needing to understand both the database and the layer built to hide it from you.

Swift had no way to check the SQL it already had.

## Getting there took some trial and error

The idea was viable long before Swift could express it well.

The first version used a third-party code generator, which put a separate tool and a generated-file lifecycle between me and my code. The second required annotating structs by hand: rudimentary, but it proved the core idea, that if the compiler knows the shape of the table, it can check the query. The third tried `Codable`, property wrappers, and `Mirror` to remove that boilerplate, but those mechanisms describe a type at runtime, and the whole point was to check it at compile time.

Swift macros, which arrived in version 5.9 in 2023, were the missing piece: compile-time code generation in the language, without a separate tool. SwiftQL moved onto them immediately.

The other piece was `buildPartialBlock`, which arrived in Swift 5.7. It let every combination of SQL clauses share one result builder instead of needing its own overload, and that's what made the syntax above possible: something that reads as both proper SQL and idiomatic modern Swift, the same shape SwiftUI had already established.

## The hardest part

The hardest part was arriving at a translation from Swift to SQL that's checked by the compiler and still produces a cacheable prepared statement.

Those two goals pull against each other. Compile-time checking wants everything expressed statically in the type system, while prepared-statement caching wants a stable SQL string where the actual values aren't part of it. Satisfying both meant the type-level structure has to describe a statement's shape while its values travel separately: code whose entire purpose is generating other code.

Recursive common table expressions, expressed inside a typed result builder, are the extreme case of this.

## Who this is for

Any Swift project using SQLite. Type-safe queries that still look like SQL are, I think, the lowest-friction way to work with a database from Swift.

Several libraries offer compile-time-checked queries without becoming an ORM. What differs is whether the source corresponds to the statement it produces. Chained builders assemble a query by attaching clauses to a table in whatever order the API accepts, using method names that approximate SQL keywords without being them. SwiftQL writes each clause under its own SQL name, in the order SQL already defines.

Most SQLite code in Swift apps today is still a string handed to a C API, checked by nothing until it runs. That's what this library replaces.

More on the design: [DESIGN.md](https://github.com/lukevanin/swiftql/blob/main/Documentation/DESIGN.md)
The project: [github.com/lukevanin/swiftql](https://github.com/lukevanin/swiftql)
