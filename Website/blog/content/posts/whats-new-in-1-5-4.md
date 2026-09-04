---
title: "What's new in v1.5.4"
date: 2026-07-29
description: "SwiftQL v1.5.4 moves scalar functions to method style, adds SwiftUI observers for live queries, restores the #row macro, and infers Setting's row type from the table."
---

SwiftQL v1.5.4 is an ergonomics release. Nothing about the query language
changes; four call sites get shorter or more consistent, live queries gain a
direct SwiftUI adapter, and the `#row` macro returns after a compiler crash
took it out of a previous release.

## Scalar functions move to method style

Most of SwiftQL's scalar functions were already methods on `XLExpression`:
`.isNull()`, `.collate()`, `.round()`. Four holdouts were still free
functions: `count(_:)`, `min(_:)`/`max(_:)`, `iif(_:then:else:)`, and
`printf(format:_:)`. v1.5.4 adds a method-style form for each and deprecates
the free function.

```swift
// Before
let smallest = min(x, 0, 10)
let largest = max(x, 0, 10)
let formatted = printf(format: "%s is %d years old", name, age)
let status = iif(occupation.name.isNull(), then: "Unemployed", else: "Employed")
let total = count(all())

// After
let smallest = x.min(0, 10)
let largest = x.max(0, 10)
let formatted = "%s is %d years old".printf(name, age)
let status = occupation.name.isNull().iif(then: "Unemployed", else: "Employed")
let total = all().count()
```

`min`/`max` still require at least two arguments in the new form.
SQLite's scalar `MIN`/`MAX` is meaningless with one, and a single-argument
call is already spoken for: it's the aggregate `MIN(expr)`/`MAX(expr)`, kept
working (and now deprecated toward `minOrNull()`/`maxOrNull()`) rather than
changed, since changing what it renders would be a silent behavior break
rather than a straightforward deprecation.

The old free functions still compile. They're marked `@available(*,
deprecated)` with a message pointing at the replacement, following the same
deprecation pattern already used for `sum()`/`average()` in favor of
`sumOrNull()`/`averageOrNull()`.

## `Setting` infers its row type from the table

`Update`/`Setting` pairs needed the row type spelled out explicitly on
`Setting`, because a result builder can't carry a generic parameter across
statement boundaries:

```swift
// Before
Update(person)
Setting<Person>(person) { row in
    row.age = 42
}

// After
Update(person)
Setting(person) { row in
    row.age = 42
}
```

The new `Setting(_:_:)` initializer takes the same table reference already
passed to `Update`, and uses it purely as a type witness to infer `Row`. It
isn't checked against the enclosing `Update`, so passing a different table
reference here won't be caught, but callers pass the same one either way. The
existing `Setting { ... }` and `Setting(metaInstance)` initializers are
unchanged for cases that don't have a table reference handy.

## `#row` is back

The `#row` ad hoc projection macro shipped once before, then got reverted
after it triggered a Swift 5.9.2 IRGen compiler crash. v1.5.4 restores it,
with the crash boundary now fenced off per compiler version instead of
worked around.

For a projection that's used once and doesn't deserve a named
`@SQLResult` type, `#row(...)` builds the column set inline:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let row = #row(person.name, occupation.name)
    Select(row)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
    Where(row._0 != "Fred")
}
```

`#row` takes one to six column expressions. One column decodes into
`SQLScalarResult`; two to six decode into `SQLRow2` through `SQLRow6`, with
positional field names (`_0`, `_1`, ...) since there's no caller-chosen name
to use.

The two-to-six column shapes need Swift 6.1 or later. On the pinned Swift
5.9.2 and Swift 6.0 compatibility cells, decoding a result type with two or
more generic parameters through `fetchAll()`, `publish()`, or `publishOne()`
crashes `swift-frontend` during IR generation: a confirmed compiler bug,
reproduced independently on both cells, that restructuring the call site
does not work around. The single-column shape doesn't hit this and works
everywhere. This is SwiftQL's first source-level API difference across
compiler versions, and it's documented in
[COMPATIBILITY.md](https://github.com/lukevanin/swiftql/blob/main/COMPATIBILITY.md#swift-59-and-swift-60-api-surface-gaps).

As a side effect of fencing off that crash, `GRDBRequest.decodeRows(packet:)`
now accumulates into an outer array and returns `Void` from its
`withReadConnection`/`withTransaction` closures instead of returning `[Row]`
directly. This protects every multi-generic-parameter `Row` type from the
same IRGen crash, at no cost to any other row type, and isn't limited to
`#row`'s new shapes.

## Live queries in SwiftUI without a hand-written Combine sink

`XLQueryObserver` and `XLQueryRowObserver` wrap `publish()`/`publishOne()`
as `ObservableObject`s, so a view model can adopt a live query directly:

```swift
final class PeopleViewModel: ObservableObject {
    let people: XLQueryObserver<Person>

    init(database: some XLDatabase) {
        people = XLQueryObserver(database.makeRequest(with: peopleQuery))
    }
}
```

`XLQueryObserver` exposes `@Published var rows: [Row]` and `@Published var
error: Error?`; `XLQueryRowObserver` mirrors it for `publishOne()`, with a
`row: Row?` in place of `rows`. Observation starts on initialization and
stops when the observer is deallocated, and every delivered value arrives on
the main queue. This adds no new package dependency: SwiftQL already
conforms to `Combine.ObservableObject` (or `OpenCombine`'s equivalent on
Linux) without importing SwiftUI itself, so the wrapper works the same way
on Linux and on Apple platforms.

## Two investigations closed, no code changed

v1.5.4 also closes out two issues that turned out not to be bugs:

- Chaining multiple optional fallbacks through `coalesce`/`??` already
  composed correctly into SQLite's variadic `COALESCE`. The one real
  footgun is that `??` applied to a plain Swift `Optional` silently falls
  back to the standard library's operator instead of rendering `COALESCE`;
  that case is now called out as a warning in the `Expressions.md`
  documentation.
- A scalar subquery whose result is already optional already flattened to a
  single `T?` rather than `T??`. The three observable `NULL` states now have
  direct test coverage against a real SQLite engine.

## Upgrade impact

No migration is required. Every change is additive or a source-compatible
deprecation. The one thing to be aware of: `#row`'s two-to-six column shapes
are unavailable on Swift 5.9 and the pinned Swift 6.0 cell, so a project
pinned to one of those compilers can only use `#row`'s single-column form.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.5.4 release](https://github.com/lukevanin/swiftql/releases/tag/v1.5.4)
