---
title: "What's new in v1.2.0"
date: 2026-07-19
description: "SwiftQL 1.2.0 adds a GRDB-free SwiftQLCore product, contextual value codecs, and durable static query descriptors underneath the unchanged v1 API, and fixes how COLLATE names and non-finite Double values render."
---

SwiftQL 1.2.0 is a foundation release. It adds a second, GRDB-free library product, a contextual value-codec system for types with more than one database representation, and a durable static-query layer with stable identities that can be built and validated before a database connection exists. Underneath all of it, the v1 `sql { }` request API that every earlier release used keeps working exactly as it did.

## A GRDB-free core

SwiftQL has shipped as one library backed by GRDB since 1.0. 1.2.0 splits out `SwiftQLCore`, a second product carrying the orthogonal SQL-dialect, dialect-value, logical-statement, database-driver, and transaction contracts, with no GRDB dependency at all:

```swift
.library(name: "SwiftQLCore", targets: ["SwiftQLCore"]),
.library(name: "SwiftQL", targets: ["SwiftQL"]),
```

The application-facing `SwiftQL` product re-exports it, so nothing about importing `SwiftQL` changes:

```swift
@_exported import SwiftQLCore
```

This exists so the rendering and validation logic that decides what counts as a well-formed SwiftQL statement doesn't have to depend on any one database driver. GRDB remains the only shipped implementation of those contracts, but it's no longer baked into the core.

## One Swift type, multiple SQLite representations

`XLCustomType`, the v1 way to give a Swift type its own SQLite encoding, is still there and still works. 1.2.0 adds contextual value codecs alongside it, for the case where the same Swift type needs more than one stored representation, or where a type shouldn't need a retroactive `XLLiteral` conformance at all.

A codec pairs throwing encode and decode closures with stable type, dialect, storage, and version metadata:

```swift
let dateType = XLValueTypeIdentifier(rawValue: "com.example.foundation-date")
let decimalDateCodecKey = XLValueCodecKey(
    id: "com.example.date.decimal-seconds",
    version: 1
)

let decimalDateCodec = XLValueCodec<Date, XLSQLiteDialect>(
    key: decimalDateCodecKey,
    valueTypeIdentifier: dateType,
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(
        rawValue: XLSQLiteStorageClass.text.rawValue
    ),
    encode: { date, _, _ in
        .text(String(date.timeIntervalSince1970))
    },
    decode: { value, _, _ in
        guard case .text(let text) = value else {
            throw DateCodecError.unexpectedValue(value)
        }
        guard let seconds = Double(text) else {
            throw DateCodecError.invalidText(text)
        }
        return Date(timeIntervalSince1970: seconds)
    }
)

let dateRegistry = try XLValueCodecRegistry().registering(decimalDateCodec)
let dateCoding = try XLValueCodingConfiguration(
    registry: dateRegistry,
    defaultCodecKeys: [decimalDateCodecKey]
)
```

A second codec, say one that stores whole seconds as `INTEGER` instead of decimal seconds as `TEXT`, can register against the same `Date` type without touching `Date` itself or replacing the first codec. Nothing is a database default until its key is listed in `defaultCodecKeys`, and an individual property, parameter, or result slot can select a non-default codec explicitly. Codec selection is a fixed, deterministic order: an explicit key first, then a query-level key, then the database default, then a legacy `XLCustomType` adapter, and a structured error if none of those apply. Changing a codec's key, version, or storage identifier is a schema change, the same as renaming a column.

## Durable, database-independent query definitions

The other new piece is `XLStaticQueryDescriptor`: an immutable, complete description of one rendered statement, its dialect requirements, its parameter and result slots, and its cardinality, with no connection, physical statement, or codec registry attached. Because it holds no database reference, it can be constructed and registered once, ahead of time, and prepared against any compatible database later.

The Swift-side counterpart is `XLQueryCapture`, a value-free declaration that a static query will receive a runtime value from its caller. It never stores the caller's value, so building a descriptor never touches application data. A capture is bound to an argument only when the query actually runs, well after the descriptor and its identity are fixed:

```swift
let preparedCutoff = try staticDatabase.prepareInvocation(
    with: cutoffDescriptor
)
let cutoffBindings = try preparedCutoff.makeInvocationBindings(
    cutoffParameter.argument(Date(timeIntervalSince1970: 86_400))
)
let cutoffRow = try preparedCutoff.fetchExactlyOneValues(
    bindings: cutoffBindings
)
```

`cutoffDescriptor` and `cutoffParameter` come from building the descriptor once, up front; the full walkthrough is in the new `StaticQueries.md` guide. What that setup buys back: a capture's value is always bound, never spliced into rendered SQL. One test round-trips a string containing `'); DROP TABLE injection_guard; --` straight through a capture as an ordinary bound value, and the table is still there afterward.

`@SQLTable` and `@SQLResult` gained a matching `staticRowLayout(using:...)` factory alongside their existing `columns(...)` factory, so a static query's result rows can decode without running a model initializer or requiring `sqlDefault()`. `Select` no longer requires its result type to conform to `XLResult` for this to work; existing `XLResult`-based selects keep compiling unchanged.

This is deliberately a lower-level layer. Nothing in an existing v1 request has to move onto it, and the migration notes say so directly: keep using `makeRequest(with:)`, `XLNamedBindingReference`, and `XLResult` for anything that isn't asking for a durable cross-task identity or a codec-backed result layout.

## COLLATE names render as grammar tokens, not string literals

`.collate(_:)` previously rendered its collation name the same way any other operand renders, as a SQL string literal. `lhs.collate(.nocase)` produced `COLLATE 'NOCASE'`. SQLite is lenient enough to accept that, but it isn't the actual grammar: `COLLATE` takes a bare collation-name token, not a string.

1.2.0 renders `.binary`, `.nocase`, and `.rtrim` as the literal tokens `COLLATE BINARY`, `COLLATE NOCASE`, and `COLLATE RTRIM`, and it's now backed by execution tests against real SQLite:

```swift
let lhs = XLNamedBindingReference<String>(name: "lhs")
let rhs = XLNamedBindingReference<String>(name: "rhs")
let statement = sql { _ in
    Select(lhs.collate(.nocase) == rhs)
}
```

Bound to `"alpha"` and `"ALPHA"`, that now correctly evaluates to `true`.

A handful of other renderer gaps closed the same way, each with new coverage against a real SQLite engine rather than a fixture:

- `BETWEEN` now goes through the same generic list-composition path as other operators, instead of its own specialized builder.
- Fluent `INSERT ... SELECT` clause chains execute against real SQLite.
- The query builder's documented missing-`FROM` failure is now covered by a test that triggers it.
- Table and common-table `FROM` dependencies, including recursive common table definitions, share one dependency model.
- First-party renderers use semantic `XLSeparator.list` and `.tuple` names internally; the older `.comma`, `.space`, and raw-string separator APIs are unaffected.

## Non-finite Double values fail loudly instead of quietly

SQLite has no bare literal syntax for `NaN` or `+/-infinity`. Before 1.2.0, rendering one of those as an inline `Double` literal could emit a token SQLite doesn't accept, or change the value's meaning. Validated rendering now rejects all three up front:

```swift
do {
    _ = try XLiteEncoder(dialect: XLSQLiteDialect())
        .makeValidatedSQL(Double.infinity)
}
catch let error as XLSQLValueEncodingError {
    // The error identifies the rejected value and expression type.
    print(error.localizedDescription)
}
```

Bound parameters get a narrower version of the same check. SQLite's C binding API does preserve `+infinity` and `-infinity` through a bound `REAL`, so those two remain valid there. A bound `NaN`, though, is silently converted to SQL `NULL` by SQLite itself; SwiftQL now rejects that case rather than let a value quietly become `NULL`. Finite values, including the largest and smallest finite magnitudes and signed zero, are unaffected.

## Migration

Existing `makeRequest(with:)`, `XLNamedBindingReference`, `XLCustomType`, `XLLiteral`, `XLResult`, and raw-separator code keeps working without changes. Nothing here requires touching the v1.2 contracts just to keep an existing query running.

Reach for `XLStaticQueryDescriptor` when a query needs a durable identity, cross-task raw-value execution, or a codec-backed result layout, and build a fresh `XLInvocationBindings` packet per call rather than sharing a request across tasks. Reach for `XLValueCodec` and `XLValueCodingConfiguration` when one application type needs more than one persisted representation; keep a legacy `XLCustomType` only where its existing storage bytes and introspection behavior need to be preserved exactly.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.2.0 release](https://github.com/lukevanin/swiftql/releases/tag/v1.2.0)
