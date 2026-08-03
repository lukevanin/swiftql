---
title: "What's new in v1.4.6"
date: 2026-07-25
description: "SwiftQL v1.4.6 cuts query construction-and-rendering allocations by around 15% through three internal fast paths, with no change to the public API or rendered SQL."
---

v1.4.6 is an internal performance release. Every change is allocation-only: the public API, entity metadata, and rendered SQL are unchanged, and no migration is required.

## Fewer allocations in query construction and rendering

Issue #128 established that constructing and rendering a query costs real allocations on every workload. For issue #166, a new deterministic allocation profiler attributed about three-quarters of that cost to rendering rather than construction, then pointed at three specific call sites in `SQLiteEncoding.swift`.

The builder's token-append method took a variadic `String...` and filtered it, so every builder node allocated both a variadic array box and a filter copy, even though all 29 call sites pass exactly one already-rendered token:

```swift
// Before
private mutating func append(_ tokens: String...) {
    _tokens.append(contentsOf: tokens.filter({ !$0.isEmpty }))
}

// After
private mutating func append(_ token: String) {
    if !token.isEmpty {
        _tokens.append(token)
    }
}
```

`build()` always re-joined the token array, even for the single-token leaf and wrapper builders that make up most of the tree:

```swift
// Before
public func build() -> String {
    _tokens.joined(separator: XLSeparator.tuple.rawValue)
}

// After
public func build() -> String {
    if _tokens.count == 1 {
        return _tokens[0]
    }
    return _tokens.joined(separator: XLSeparator.tuple.rawValue)
}
```

And `scopedName(_:)` ran every qualified reference, including the `table.column` shape that covers almost all of them, through `values.map(name).joined(".")`:

```swift
// Before
public func scopedName(_ values: [String]) -> String {
    values.map(name).joined(separator: ".")
}

// After
public func scopedName(_ values: [String]) -> String {
    switch values.count {
    case 0:
        return ""
    case 1:
        return name(values[0])
    case 2:
        var scoped = name(values[0])
        scoped += "."
        scoped += name(values[1])
        return scoped
    default:
        return values.map(name).joined(separator: ".")
    }
}
```

None of this changes what a query renders to. The deterministic profiler recorded the effect on the two representative read cases from the #128 harness:

| Case | Render allocations, before to after | Combined allocations, before to after |
| --- | ---: | ---: |
| Simple parameterized lookup | 249 to 212 (-14.9%) | 322 to 285 (-11.5%) |
| Multi-join read | 434 to 365 (-15.9%) | 562 to 493 (-12.3%) |

The same profiling run measured the #128 harness's wall-clock median dropping roughly 13-17% across its four read, write, and decode cases, with byte-identical SQL output before and after. No absolute CI latency gate was added; the allocation counts are the primary, deterministic evidence, and the timing figures are directional, taken on a machine that had other test suites running concurrently.

## One buffer, reused, on the incremental decode path

`GRDBDatabaseDriverConnection.forEachRow` used to allocate a fresh `[XLSQLiteValue]` array for every row, then wrap it again in `Array(...)`:

```swift
// Before
let values = Array(row.databaseValues.map(\.sqliteDialectValue))
```

It now normalizes into one buffer that's reused across the whole fetch, clearing and refilling it row to row instead of allocating a new array each time:

```swift
// After
var values: [XLSQLiteValue] = []
while let row = try cursor.next() {
    values.removeAll(keepingCapacity: true)
    values.reserveCapacity(row.count)
    for databaseValue in row.databaseValues {
        values.append(databaseValue.sqliteDialectValue)
    }
    // ... pass `values` to the row callback
}
```

Copy-on-write keeps this safe for callers that retain a row, such as the eager `collectAllRows`/`collectFirstRow` compatibility shims: retaining a row gives it its own storage the next time the buffer refills. The typed decode path itself still materializes no intermediate matrix, which preserves the bounded-memory guarantee from issue #248.

This removes a real per-row allocation, but it doesn't close the issue #266 latency regression. Measured against the #250 harness, the regression turned out to be bound by per-row typed-decode compute, not by the allocation that was just removed, so this change is latency-neutral on that workload. The remaining latency work continues in issue #353.

## A new diagnostic executable

`swiftql-construction-profile` is a new executable target added to the package (`Benchmarks/Sources/SwiftQLConstructionProfile`). It installs Darwin's `malloc_logger` hook in-process and counts heap allocations issued during construction, rendering, and the combined construct-and-render phase, for the same two read queries the #128 harness measures:

```sh
swift run -c release swiftql-construction-profile \
  --iterations 20000 --warmups 200 --samples 4000 \
  --json /tmp/profile.json
```

It produced the allocation counts in the table above. It's diagnostic evidence for issue #166, not part of SwiftQL's runtime or a CI gate.

## Migration

None. Every change in v1.4.6 is internal: the public API, entity metadata, and rendered SQL are all unchanged.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.6 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.6)
