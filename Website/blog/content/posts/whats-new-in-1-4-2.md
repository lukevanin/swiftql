---
title: "What's new in v1.4.2"
date: 2026-07-22
description: "LIKE ESCAPE, NOT IN, nullable subqueries, custom collations, and REGEXP land, closing out the operator conformance matrix."
---

SwiftQL v1.4.2 adds five expression-level features and completes the generated real-SQLite conformance matrix for every public operator overload. `XLCollation` also changes from an enumeration to a struct, which needs a one-line migration if code switches over it exhaustively.

## `LIKE ... ESCAPE`

`like(_:escape:)` joins the existing `like(_:)` across the same four optionality shapes:

```swift
name.like(pattern, escape: "\\")
```

`ESCAPE` renders inside its own `LIKE` production rather than as a separate binary expression, so a second `LIKE` in the same predicate cannot absorb the escape clause it does not own. SQLite requires the escape value to resolve to exactly one character; a longer or empty value still prepares, then fails when the statement is stepped with `ESCAPE expression must be a single character`, because no Swift type can express that constraint ahead of time.

## `notIn`

`notIn` mirrors every `in` shape already in the library: value lists, subqueries, common table expressions, and the optional-operand and NULL-candidate variants.

```swift
Where(person.name.notIn(["Alice", "Bob"]))
```

The negation lives on the `IN` node itself rather than on a wrapping `NOT`, so composing a predicate cannot move it outwards to somewhere it would change what the SQL means. `NOT IN` follows SQLite's own semantics: an unmatched value compared against a candidate set that contains NULL comes back NULL rather than true, except for an empty candidate set, where `NOT IN` is true even for a NULL operand.

## Subqueries on the nullable side of a join

`nullableSubquery(alias:_:)` and `nullableSubqueryExpression(alias:_:)` join `schema.nullableTable` as ways to mark the joined side of a `LEFT JOIN` as optional, this time for a subquery rather than a table:

```swift
let latestOrder = nullableSubquery(alias: "latestOrder") { schema in
    let order = schema.table(Order.self)
    Select(order)
    From(order)
    OrderBy(order.placedAt.descending())
    Limit(1)
}
```

Scalar subquery results also stop double-wrapping. A scalar subquery is already nullable, because it yields NULL when it selects no row; when the inner statement is itself optional, the two sources of NULL now collapse into one `Optional` instead of nesting `Optional<Optional<Wrapped>>`.

## Custom collating sequences

`GRDBDatabaseBuilder.addCollation(_:compare:)` registers a collating sequence on every connection the builder creates, the same way `addFunction` already does:

```swift
var builder = try GRDBDatabaseBuilder(url: fileURL, configuration: Configuration(), logger: nil)
builder.addCollation("byLength") { lhs, rhs in
    if lhs.count == rhs.count { return .orderedSame }
    return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
}
```

Naming it from a query goes through `XLCollation`, which is why the type changes shape this release: it moves from an enumeration to a `RawRepresentable` struct. `.binary`, `.nocase`, and `.rtrim` stay available as static members and still render as bare grammar tokens, and `init(rawValue:)` is new, for naming a sequence registered on the connection:

```swift
OrderBy(word.text.collate(XLCollation(rawValue: "byLength")).ascending())
```

A custom name renders as a quoted identifier, `COLLATE "byLength"`, which SQLite resolves to the same registered sequence, so `collate(_:)` still cannot be used as a raw-SQL escape hatch. Equality and hashing fold ASCII case, matching how SQLite itself resolves collation names.

Because `XLCollation` is no longer an enumeration, code that switches over a collation value exhaustively needs a `default` case:

```swift
switch collation {
case .binary, .nocase, .rtrim:
    …
default:
    …
}
```

Existing `collate(_:)` call sites that only use the three built-ins keep compiling unchanged.

## `REGEXP`

`regexp(_:)` adds the `REGEXP` operator across the same four optionality shapes as `glob`:

```swift
Where(phrase.text.regexp("[0-9]+$"))
```

SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and ships no implementation of that function, so the pattern syntax is whatever function the application registers. Without a registered `regexp` function, the statement fails to prepare with `no such function: regexp`.

## Operator conformance matrix completed

The changelog's largest item is not a new API: it is closing out the real-SQLite conformance evidence for the operators that already existed. Every public operator overload now carries both a prepare and a semantic execution record, and the corresponding inventory entries move from partial to supported.

| | v1.4.1 | v1.4.2 |
| --- | ---: | ---: |
| Feature records | 101 | 105 |
| Supported | 88 | 96 |
| Partial | 3 | 1 |
| Unimplemented | 7 | 5 |
| Evidence records | 104 | 139 |
| Real-SQLite evidence | 68 | 88 |

Alongside that, `IN`-subquery cases were added for both query-backed entry points, and a same-table `IN`-subquery execution test was revived so that distinct aliases across two nesting levels stay pinned by an executing test rather than by inspection alone.

## Deprecated

The `subquery(alias:)` overload constrained to `XLMetaNullable` is deprecated. It could never actually be selected, because no `select` function in the library produces a statement over a nullable row type. `nullableSubquery(alias:_:)`, above, is the replacement.

## Migration

`in`, `like`, `collate(_:)`, and `subquery(alias:)` call sites remain source-compatible. The two changes that need action are the `XLCollation` `switch` case described above, and registering the `regexp` function before a query uses the `REGEXP` operator.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.2 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.2)
