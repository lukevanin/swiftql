# Issue #353 — where the per-row typed-decode cost actually is

**Outcome in one line:** the dominant per-row cost is **Swift's runtime
metadata and protocol-conformance machinery**, not value reading, not
allocation, and not GRDB. Roughly **54%** of main-thread samples sit under
three dynamic casts that `XLRowReader.staticColumn(_:alias:)` performs for
every column of every row. The fix is a change to what the `@SQLTable` macro
emits, not a local change to the row reader; one attempt at a local fix is
recorded below as a null result.

This is the first of issue #353's "Done when" items — a sampling profile that
attributes the dominant per-row decode cost to exact code. The second item, a
measured latency reduction in the paired-control harness, is **not** done.

## Method

The SwiftQL half of the issue #250 comparison harness
(`Benchmarks/Comparison/Graphs/SwiftQLGRDB6`, `SwiftQLControl`), release
build, on the exact 16,143-row Northwind `Orders` fixture and its 14 columns.
Three independent processes, 10 warmups and 100 timed full fetches each.
The profile is `sample` over six seconds of the main thread of one such
process, with the timing samples discarded for that run.

Like the #266 evidence, this is deliberately not the full #250 report: no
cross-library graph, no six paired controls, no drift guard. It is enough to
locate a cost, and not enough to accept a latency change.

## Baseline

| Statistic | Value |
| --- | ---: |
| Headline median | 69.94 ms |
| Headline p95 | 71.70 ms |
| Process medians | 70.26, 69.94, 69.78 ms |
| Process spread | 0.69% |

Raw samples: `Runs/baseline-process-{1,2,3}.tsv`.

## Where the time goes

`Runs/self-time-by-symbol.tsv` has the full table. The head of it, as a share
of main-thread samples:

| Share | Symbol |
| ---: | --- |
| 7.5% | `_xlReadLegacyStaticColumn` |
| 7.5% | `swift::MetadataCacheKey::operator==` |
| 6.5% | `swift_getExtendedExistentialTypeMetadata_unique` |
| 6.2% | `_swift_getGenericMetadata` |
| 6.0% | `swift_slowAllocTyped` |
| 5.4% | `_swift_release_dealloc` |
| 5.2% | `getCache` |
| 4.7% | `ExtendedExistentialTypeCacheEntry::Key::Key` |
| 4.3% | `StableAddressConcurrentReadableHashMap<GenericCacheEntry>::getOrInsert` |
| 4.0% | `LockingConcurrentMap<GenericCacheEntry>::getOrInsert` |
| 2.7% | `swift_conformsToProtocolMaybeInstantiateSuperclasses` |
| 2.7% | `ConcurrentReadableHashMap<GenericCacheEntry>::find` |
| 2.4% | `swift_conformsToProtocol` |

Adding the metadata and conformance entries gives **53.9%** of main-thread
samples. Reading a value is nowhere near the top: the whole
`XLSQLiteValueReader.readText` subtree is under 1%.

## Why it happens

`XLRowReader.staticColumn(_:alias:)` is an **unconstrained** protocol
requirement — `T` is not known to be a literal. Its default implementation
therefore finds out at run time, in
`Sources/SwiftQL/SQLRowReading.swift`:

1. `T.self as? any XLLiteral.Type` — a conformance lookup on a metatype.
2. `_xlReadLegacyStaticColumn` reopens that as a generic parameter, then casts
   `expression as? any XLExpression<Literal>`. `any XLExpression<Literal>` is a
   **parameterised** existential, so this instantiates an extended existential
   type — which is `swift_getExtendedExistentialTypeMetadata_unique` and the
   `ExtendedExistentialTypeCacheEntry` work above.
3. `literal as? Value` — a cast back.

Then `Optional<A>.init(reader:)` instantiates `Optional<Column>` metadata,
which is the `_swift_getGenericMetadata` and generic-cache traffic.

The fixture has 16,143 rows and 14 columns, so this runs **226,002 times per
fetch**. None of it reads a value.

The generated code has the information that would avoid all of it: a column's
type is written into the `@SQLTable` expansion, so `T` is concrete at the call
site and its `XLLiteral` conformance is known statically.

## A null result: the constrained-overload fast path

The obvious local fix is to add a constrained overload beside the
unconstrained one:

```swift
extension XLRowReader {
    @inlinable
    public func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral {
        try column(expression, alias: alias)
    }
}
```

It does not work, and the measurement says so rather than the reasoning:

| | Median | p95 |
| --- | ---: | ---: |
| Baseline | 69.94 ms | 71.70 ms |
| With the overload | 71.07 ms | 72.71 ms |
| Change | **+1.61%** | **+1.40%** |

Re-profiling explains it. `_xlReadLegacyStaticColumn` still carries 8.2% self
time afterwards, and the metadata share is unchanged at 53.5%. The overload is
never selected: `staticColumn` is a **protocol requirement**, the generated
code calls it on a protocol-typed reader, and the call therefore dispatches
through the witness table to the unconstrained requirement. An extension
member cannot win a dispatch that has already been resolved to a requirement.

The change was reverted. It would have added public API surface for a measured
regression.

## What would actually work

The call has to stop being a witness call to the unconstrained requirement.
Two routes, both bigger than a row-reader edit:

1. **Emit `column(_:alias:)` directly from the macro** for a column whose type
   is a literal, keeping `staticColumn` for the contextual-codec columns that
   genuinely need it. The macro already knows which is which. This changes
   every pinned expansion in `Tests/SQLMacrosTests/SQLTests.swift`.
2. **Give the reader a non-parameterised column entry point** so no
   `any XLExpression<Literal>` existential is formed. The expression argument
   is unused by `XLColumnValuesRowReader.column`, which reads positionally, so
   the parameterised existential is paid for and then discarded.

Either needs the full #250 paired-control run to accept, which is what the
issue asks for and what this directory does not attempt.

## Constraints this work must keep

From the issue, and unchanged by anything here: no restored `Row.fetchAll` or
`[[XLSQLiteValue]]` matrix, no GRDB types through `SwiftQLCore`, no cursor or
row escaping its database closure, no source-breaking public v1 requirement,
and no weakening of early-stop, mid-stream error identity, statement reset,
pool cleanup, transaction, binding, or live-query snapshot behaviour.
