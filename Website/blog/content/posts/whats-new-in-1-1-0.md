---
title: "What's new in v1.1.0"
date: 2026-07-17
description: "SwiftQL 1.1.0 adds NULL-aware aggregate APIs, an opt-in live-query retry policy for SQLITE_BUSY, and a verified, provenance-checked release pipeline."
---

SwiftQL 1.1.0 changes how aggregate results model SQL NULL, adds an opt-in retry policy for live queries under SQLite contention, and replaces the manual release process with a verified, provenance-checked pipeline. It also tightens several places where the type checker was more permissive than SQLite itself.

## Aggregates can return NULL, and now say so

`SUM`, `AVG`, `MIN`, `MAX`, and `GROUP_CONCAT` all return NULL in SQLite when there's no matching row, or when every row is NULL. SwiftQL 1.0's `sum()`, `average()`, `min()`, `max()`, and `groupConcat()` didn't model that: they returned a nonoptional type, so an empty aggregate produced a decode failure at the SQLite boundary instead of a value.

1.1.0 adds `OrNull` counterparts whose expression types are optional:

```swift
let total = invoice.amount.sumOrNull()
```

`total` is `Int?` here, and decodes to `nil` exactly when SQLite returns NULL. The same pattern applies to `minOrNull(distinct:)`, `maxOrNull(distinct:)`, `averageOrNull(distinct:)`, `groupConcatOrNull(distinct:)`, and `groupConcatOrNull(separator:)`.

The old nonoptional APIs are deprecated, not removed. They keep their 1.0 signatures and behavior throughout SwiftQL 1.x, so nothing breaks on upgrade. Projects that treat warnings as errors will need to migrate before the deprecation warnings become build failures. Where a fallback value makes more sense than `nil`, `coalesce` supplies it:

```swift
let total = invoice.amount.sumOrNull().coalesce(0)
```

The optionality also composes correctly inside subqueries. A scalar subquery is already optional, because it may return no row at all. Selecting an already-optional `OrNull` aggregate inside `subquery` or `subqueryExpression` produces a single `Int?`, not `Int??`:

```swift
let total = subquery {
    select(invoice.amount.sumOrNull()).from(invoice)
}
```

That collapsing happens in the type system, not as a runtime unwrap, so there's no separate `Int??` case to handle by hand.

## An opt-in retry policy for live queries

Live queries built on GRDB now take a `GRDBLiveQueryRetryPolicy`. The default, `.terminal`, is unchanged from 1.0: an observation that fails ends with its original error. The new `.retryBusy` option retries only `SQLITE_BUSY` failures, three times, after fixed delays of 0.1, 0.2, and 0.4 seconds, and resets the retry count once a value is delivered. Every other error, including `SQLITE_LOCKED`, stays terminal.

```swift
let database = try GRDBDatabase(
    url: databaseURL,
    logger: nil,
    liveQueryRetryPolicy: .retryBusy
)
```

This is aimed at transient write contention on a shared connection pool, where a live query observer can otherwise fail permanently on a lock that clears a moment later.

## Two type-checker gaps closed

Prefix bitwise NOT (`~`) is now constrained to integer SQL expressions. In 1.0 it also accepted `Double` and other real-valued expressions, which SQLite doesn't support for that operator; the Swift type checker now rejects those at compile time instead of failing at execution.

String concatenation now renders as an explicitly grouped binary expression, so `COLLATE` and neighboring operators apply with unambiguous SQLite precedence instead of relying on SQLite's own default grouping.

## A verified release pipeline

The rest of 1.1.0 is release engineering, and it accounts for most of the changed files. Tagging a release now runs the same Swift compiler matrix and DocC build used in CI, publishes checksummed provenance assets through an idempotent, draft-first GitHub Release, and supports read-only test tags with documented recovery from a partial release. Documentation deploys through a matching least-privilege Pages workflow that builds on every pull request but only deploys authorized `main` commits, with both the build artifact and the deployed site tied to the exact commit SHA.

Alongside that, a warnings-as-errors gate now runs on every supported compiler lane, distinguishing SwiftQL's own warnings and unclassified ones (both of which fail the build) from warnings in dependencies or the toolchain (which are reported but don't). Getting there meant cleaning up the warnings the gate would otherwise have caught: generated `.columns(...)` helpers no longer call a deprecated internal helper, immutable table macros no longer trigger never-mutated-local warnings, and all first-party product and test targets now build clean under complete strict-concurrency checking with the supported Swift 6 compiler, without turning on Swift 6 language mode.

DocC generation is stricter too. The site generator is non-mutating and treats DocC warnings as errors, validating the landing page and all ten source articles, and every Swift example across the documentation now has a compile-checked scenario mapping backed by a catalog test that rejects untyped code fences, stale API spellings, and unknown test markers. A new `XLEnum` guide covers integer- and string-backed enums with SQLite coverage for both valid and unknown stored raw values.

Two smaller additions round out the release: a `swiftql-benchmark` executable that reports raw samples, median, and p95 timings for query construction, rendering, SQLite preparation, statement-cache hits, binding, execution, and row decoding, and an external Swift package fixture that exercises SwiftQL's macros, typed queries, binding, and SQLite execution from Swift 5 language mode under the Swift 6 compiler, run in CI with both pinned and clean dependency resolution.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.1.0 release](https://github.com/lukevanin/swiftql/releases/tag/v1.1.0)
