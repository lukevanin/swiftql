---
title: "What's new in v1.7"
date: 2026-09-03
description: "SwiftQL v1.7 makes the REGEXP operator work. SQLite ships no regexp function, so the operator used to fail before it ran; SwiftQL now supplies one backed by Swift Regex, compiles each pattern once per statement instead of once per row, and lets you match a RegexBuilder pattern directly."
---

SwiftQL has had a `REGEXP` operator since v1.4.2. Until v1.7 you could not use it.

That sounds like a bug, and it was not. SQLite parses `X REGEXP Y` as a call to a function named `regexp`, and then ships no implementation of that function. Every database engine that supports the operator supplies its own. SQLite leaves it to you:

```swift
Where(person.name.regexp("^A.*n$"))
```

Before v1.7 that statement rendered correct SQL and then failed the moment SQLite tried to prepare it:

```
no such function: regexp
```

The fix was to register a two-argument `regexp` function on every connection yourself, before any query used the operator. Documented, but not something a library should ask for.

## SwiftQL supplies the function

In v1.7 the same line of code just works. The operator records SwiftQL's own implementation while the statement renders, and the driver registers it on whichever pooled connection executes that statement.

The rendered SQL did not change. It is still `(t0.name REGEXP '^A.*n$')`, byte for byte.

## What a pattern means

SQLite defines no regular-expression dialect. It only says the operator calls a function; the function decides everything else. So shipping an implementation means deciding what a pattern means, and writing it down:

| Case | Result |
| --- | --- |
| Pattern syntax | Swift's, as accepted by `Regex.init(_:)` |
| Match rule | The pattern is searched for **anywhere** in the subject |
| `NULL` on either side | `NULL` |
| Invalid pattern | An error naming the pattern |
| An argument that is neither TEXT nor a UTF-8 BLOB | An error |

Searching rather than matching the whole subject is the interesting one. `"alpha-123" REGEXP '[0-9]+$'` is true, because the pattern is looked for inside the subject rather than matched against all of it. That is what the widely used `regexp` extensions for SQLite do, and what PostgreSQL's `~` operator does. Anchor with `^` and `$` when you want the whole subject to match.

An invalid pattern raising an error rather than returning false matters more than it looks. A mistyped pattern that quietly returns false is indistinguishable from a pattern that legitimately matched nothing — you get an empty result set and no reason for it.

## Your own `regexp` still wins

If you already register a `regexp` of your own, upgrading changes nothing. SwiftQL never registers its bundled function on a connection that already provides one of that signature — the same name and either the same argument count or the `-1` SQLite reports for a variadic function, which can serve a fixed-arity call — whether yours arrived through `GRDBDatabaseBuilder.addFunction(_:)` or through `Configuration.prepareDatabase(_:)`.

That check costs one `PRAGMA function_list` per database — not one per query.

## Compiled once, not once per row

SQLite calls a scalar function once for every candidate row, and passes the pattern again on each of those calls. A naive implementation compiles the same pattern thousands of times for one statement, and compiling a regular expression costs far more than matching with an already compiled one.

So the pattern is compiled once per statement execution and then only matched. On a measured 2000-row scan against one pattern, that is one compile instead of 2000, and about 46× less wall-clock time in the recorded run.

The cache belongs to one registered function on one connection, and is never shared between them. Swift's `Regex` is not `Sendable`, and sharing one compiled value between the pooled connections matching with it concurrently is exactly the sharing the standard library does not promise is safe.

## Patterns you can build

A pattern string is a string. There is no compile-time check, no composition, and no way to build one from named pieces. `RegexBuilder` has all three:

`Anchor`, `ZeroOrMore` and the rest come from `RegexBuilder`, so a file using
them needs `import RegexBuilder` alongside `import SwiftQL`:

```swift
import RegexBuilder
import SwiftQL

enum PersonPatterns {
    static let leadingA = XLRegexPattern {
        Anchor.startOfSubject
        "A"
        ZeroOrMore(.any)
        "n"
        Anchor.endOfSubject
    }
}

let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.regexp(PersonPatterns.leadingA))
}
```

A `static let`, not a local — for the reason in the next paragraph.

A compiled `Regex` cannot be sent to SQLite, which carries only text, integers, reals, blobs, and nulls. So `XLRegexPattern` registers the `Regex` and the statement carries an opaque key instead; SwiftQL resolves the key back when SQLite calls the function.

Two rules come with that. The registry does not keep your pattern alive — hold the `XLRegexPattern` in a `static let` or a property for as long as statements using it can execute, and a released one reports itself rather than silently matching nothing. And a key names a registration in one process, so a statement matching an `XLRegexPattern` cannot become a static query descriptor; use a pattern string when a statement has to be validated at build time.

## It works everywhere a query runs

A query is not only executed. It is also prepared as a static descriptor, and checked by the SwiftPM build validator against a pinned SQLite snapshot before your app ever runs.

Both of those paths used to fail for `REGEXP`, for the same underlying reason: neither carries the live registration the request paths carry. A descriptor keeps deterministic metadata only, and the validator opens its own connection.

In v1.7 a descriptor records the *signature* of the function it needs — deterministic, unlike a closure — and SwiftQL rebuilds its own implementation from it. The validator registers the same implementations on its snapshot connection. A query using `REGEXP` now passes the build and runs on every path.

Your own custom functions still need an upfront `addFunction(_:)` call on the static path. SwiftQL can rebuild a function it wrote; it cannot rebuild one it did not.

## Getting it

```swift
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.7.0")
```

The full list of changes, with every API name and constraint, is in the [changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md).
