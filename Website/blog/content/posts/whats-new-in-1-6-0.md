---
title: "What's new in v1.6"
date: 2026-09-02
description: "SwiftQL v1.6 makes SQLite's JSON surface typed Swift: the -> and ->> operators, json_extract, the constructor, inspection, mutation, and aggregate functions, JSONB variants, and a typed path builder. Decoding a large result set also got about 56% faster."
---

SwiftQL v1.6 is about JSON. SQLite has had a JSON function set since 3.9.0, and it is the part of SQLite that string-built queries hurt most: a path is a string, a mutation is a nested function call, and nothing tells you when the two disagree. This release makes all of it typed Swift expressions.

A second, unrelated change ships in the same release: decoding a large result set is about 56% faster than in v1.5.7, and existing code gets that without changing a line.

## A JSON column is just a column

SQLite has no JSON storage class. A JSON document is ordinary `TEXT`, or a `BLOB` in SQLite's binary form. So a SwiftQL model declares it as a `String`, and nothing marks it as special:

```swift
@SQLTable
struct Note: Identifiable {

    let id: String

    let title: String

    /// A JSON object, for example:
    /// `{"tags":["home","urgent"],"priority":2,"due":null}`
    let metadata: String
}
```

What changes in v1.6 is what you can write about that column.

## Paths are built, not spelled

Every JSON function takes a path. Before v1.6 the only way to name one was a string literal, which is exactly the failure mode SwiftQL exists to remove. `XLJSONPath` builds a path from segments:

```swift
let priority = XLJSONPath.root.key("priority")        // $.priority
let firstTag = XLJSONPath.root.key("tags").index(0)   // $.tags[0]
let lastTag = XLJSONPath.root.key("tags").last        // $.tags[#-1]
```

The segments do the quoting. `key("a.b")` names the single key `a.b` rather than reading as "b inside a", because the path grammar needs quotes there and gets them. Writing that by hand is a mistake that produces a working query returning the wrong answer, which is the worst kind.

A path renders through the same text formatter as any other operand, so it cannot smuggle raw SQL into a statement. And because SQLite has no negative array index, `index(-1)` stops with a diagnostic naming `last` and `index(fromEnd:)` as the remedy, rather than rendering something SQLite will reject at run time.

## Three ways to read, and they differ

SQLite gives you `->`, `->>`, and `json_extract`. They are not interchangeable, and v1.6 keeps them distinct rather than picking one:

```swift
let statement = sql { schema in
    let note = schema.table(Note.self)
    Select(
        note.metadata.jsonValue(
            at: XLJSONPath.root.key("priority"),
            as: Int.self
        )
    )
    From(note)
}
```

`jsonValue(at:as:)` is `->>`: it returns a SQL value in the type you name, so a selected string arrives without its JSON quotes. `jsonElement(at:)` is `->`: it returns JSON text, so a selected string keeps its quotes. `jsonExtract(at:as:)` is the function form of `->>`, and it also takes more than one path, in which case SQLite collects the results into an array.

Every read is optional, because a path that matches nothing gives SQL `NULL`. Where they part is a JSON `null`:

| Read | A path that matches nothing | A JSON `null` |
| --- | --- | --- |
| `jsonValue(at:as:)` | SQL `NULL` | SQL `NULL` |
| `jsonExtract(at:as:)` | SQL `NULL` | SQL `NULL` |
| `jsonElement(at:)` | SQL `NULL` | the text `null` |

Neither operator is spelled as a Swift operator. The compiler reserves `->` and refuses to declare it, so both are methods — which at least keeps the two spellings alike.

## Changing a document in place

The five mutation functions return a new document rather than writing to the table, so you put one in an `Update`:

```swift
let promote = sql { schema in
    let note = schema.into(Note.self)
    Update(note)
    Setting(note) { row in
        row.metadata = note.metadata
            .jsonSetting((XLJSONPath.root.key("priority"), 1))
            .coalesce(note.metadata)
    }
    Where(note.id == "note-1")
}
```

`jsonInserting` writes only where nothing is, `jsonReplacing` only where something already is, `jsonSetting` either way, `jsonRemoving` deletes, and `jsonPatched` applies an RFC 7396 merge patch. Each takes its path and value as a pair, and requires at least one, so an incomplete or empty argument list cannot be written at all.

Every mutation result is optional, because SQLite returns `NULL` for a `NULL` document. `metadata` is non-optional above, so `coalesce` supplies the original for that case and the types line up.

## Building and collecting

`jsonArray` and `jsonObject` construct documents. `jsonObject` takes its members as name/value pairs, which means SQLite's "requires an even number of arguments" error cannot be reached from Swift — there is no way to write half a member.

The two aggregates collect rows into a document:

```swift
let tagsPerNote = sql { schema in
    let note = schema.table(Note.self)
    Select(note.title.jsonGroupArray())
    From(note)
}
```

Neither aggregate result is optional. An empty group gives `[]` and `{}`, not SQL `NULL`. `jsonGroupObject` takes no `distinct` parameter, because SQLite allows `DISTINCT` only on an aggregate with exactly one argument, and it has two.

## JSONB, where it pays

Eleven SQLite functions return the binary representation instead of JSON text, reached through twelve Swift entry points. They are worth using when a document is read repeatedly without being handed back to the caller: SQLite parses text on every call and does not parse JSONB at all.

The functions whose result is a SQL value rather than JSON have no JSONB twin, because SQLite defines none. There is no `jsonb_type`, `jsonb_valid`, `jsonb_array_length`, `jsonb_quote`, `jsonb_error_position`, or `jsonb_pretty` — confirmed against `pragma function_list` on 3.51.0. Those functions read a JSONB input directly and keep their own result types.

## What needs which SQLite

Not all of this is available on every engine SwiftQL supports. SwiftQL renders the SQL either way; it is the engine that refuses:

| Surface | Needs SQLite |
| --- | ---: |
| JSON functions, `json_extract`, paths, aggregates | 3.9.0 |
| `->` and `->>` | 3.38.0 |
| `json_error_position` | 3.42.0 |
| JSONB, and `json_valid(X, F)` with flags | 3.45.0 |
| `json_pretty` | 3.46.0 |

The macOS cells in SwiftQL's supported matrix run SQLite 3.43.2, so the surfaces above that line are covered by execution tests that ask the connection what it defines and skip with a message naming the runtime, rather than by combinatorial cases, where a missing capability is a failure rather than a skip.

## The conformance inventory

SwiftQL records what it supports as evidence rather than as a claim. The v1.6 inventory:

| Support status | Features |
| --- | ---: |
| Supported | 113 |
| Partial | 0 |
| Capability-gated | 2 |
| Intentionally unsupported | 1 |
| Unimplemented | 1 |

Three feature records are new in v1.6 — `syntax.expression.json-path`, `syntax.expression.json-operators`, and `syntax.expression.jsonb-functions` — and the existing `syntax.expression.json-functions` record grew from two functions to the whole set. Thirteen new evidence records cite the test suites behind them. The [conformance report](https://github.com/lukevanin/swiftql/blob/main/Conformance/SQLite/REPORT.md) is the generated view of it.

## Decoding got much faster

This has nothing to do with JSON, and it is probably the change most existing code will notice.

Profiling a 16,143-row, 14-column fetch showed about 54% of main-thread samples in one place: the generated row reader's unconstrained `staticColumn(_:alias:)` finding a literal conformance at run time and reopening the expression as a parameterised existential, 226,002 times for that one fetch. Adding a second requirement constrained to `XLLiteral` lets the compiler select it statically for every literal column.

A second pass found the generated row closure building each column's expression inside itself, once per row — 226,002 `XLColumnResult` values where 14 would do, each boxed into an existential too large for the inline buffer, so each box was a heap allocation. The generated factory now binds every column expression once, before it builds its metadata value.

Each change was measured on its own against the state before it, over six interleaved pairs on one machine:

| Change | Median | p95 | Range across pairs |
| --- | ---: | ---: | ---: |
| Constrained literal read | 72.38 ms → 43.88 ms | 74.67 ms → 45.32 ms | -38.4% to -40.0% |
| Hoisted column expressions | 42.74 ms → 30.63 ms | 44.08 ms → 31.32 ms | -26.9% to -30.1% |

The two compose to about 56%. No source change is needed to get it: nothing in the macros' public output changes, so every existing `@SQLTable` and `@SQLResult` reaches the faster path as it is.

## `sql { }` as a subquery, on Swift 6.1

The last item is one that has been reverted once before. `sql { ... }` can now be used directly where a subquery is expected, inferring a table row, a nullable table row, or a scalar from the surrounding expression, instead of requiring `subqueryExpression { ... }`.

The six overloads are behind `#if compiler(>=6.1)`. Compiled together with the rest of the package they crash the Swift 5.9 and 6.0 frontends — the reason the first attempt was pulled before v1.5.4 shipped. On those toolchains nothing changes: `subqueryExpression { ... }` remains the spelling, and it is what the gated overloads forward to.

## Upgrading

The JSON surface is additive. Two narrow things change.

`validJSON()` is deprecated in favour of `validJSONOrNull()`. `json_valid(NULL)` returns SQL `NULL`, not false, and a non-optional `Bool` result cannot represent that. The old spelling still compiles and renders identical SQL; it will return an optional expression in SwiftQL 2.

An `XLRowReader` conformance outside the package that overrides the unconstrained `staticColumn(_:alias:)` to give literal columns behaviour `column(_:alias:)` does not give will no longer see literal columns arrive there. Implement the new constrained requirement as well to keep it. A reader that implements only `column(_:alias:)`, which is the documented shape, is unaffected.

The [JSON documentation page](https://lukevanin.github.io/swiftql/documentation/swiftql/json/) covers the whole surface, and every snippet on it is built and executed by the test suite. The [changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md) is the exhaustive record.
