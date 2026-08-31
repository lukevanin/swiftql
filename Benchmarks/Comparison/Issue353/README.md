# Issue #353 — where the per-row typed-decode cost actually is

**Outcome in one line:** the dominant per-row cost was **Swift's runtime
metadata and protocol-conformance machinery**, not value reading, not
allocation, and not GRDB. Roughly **54%** of main-thread samples sat under
three dynamic casts that `XLRowReader.staticColumn(_:alias:)` performed for
every column of every row. Adding a second, `XLLiteral`-constrained
`staticColumn` **requirement** removes all three casts for a literal column
and makes the full fetch **39.4% faster**.

Both of issue #353's "Done when" items are done: the sampling profile that
attributes the cost to exact code, and a latency reduction measured in a
paired-control run. Two earlier attempts are kept below, because each one
explains why the accepted change is shaped the way it is.

## Method

The SwiftQL half of the issue #250 comparison harness
(`Benchmarks/Comparison/Graphs/SwiftQLGRDB6`, `SwiftQLControl`), release
build, on the exact 16,143-row Northwind `Orders` fixture and its 14 columns.
Three independent processes, 10 warmups and 100 timed full fetches each.
The profile is `sample` over six seconds of the main thread of one such
process, with the timing samples discarded for that run.

Like the #266 evidence, this is deliberately not the full #250 report: no
cross-library graph, no six paired controls, no drift guard. It is enough to
locate a cost, and not enough to accept a latency change. The paired run under
"Measured result" is what accepts the change; this section describes only the
profile that found the cost.

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

## A null result: the constrained overload in an extension

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

## What worked: a constrained requirement

The extension failed because the call had already resolved to a requirement.
The accepted change therefore adds a **second requirement** to `XLRowReader`,
constrained to a `T` that conforms to `XLLiteral`:

```swift
func staticColumn<T>(
    _ expression: any XLExpression<T>,
    alias: XLName
) throws -> T where T: XLLiteral
```

Generated row readers name one concrete Swift type per column. Overload
resolution at the generated call site therefore selects this requirement for
every literal column, and the unconstrained requirement only for a contextual
one. The witness reads the value directly, so none of the three casts happen.

Nothing in the macro changes. That is the useful property of this shape: the
compiler decides which requirement each column uses, so no pinned macro
expansion in `Tests/SQLMacrosTests/SQLTests.swift` moves, and a `@SQLTable`
or `@SQLResult` written before this change gets the faster path with no edit.

The default implementation of the new requirement forwards to `column`, so
every existing `XLRowReader` conformance outside this package keeps compiling.
One conformance shape changes behaviour: a reader that overrides the
unconstrained `staticColumn` to treat literal columns specially no longer sees
them there, because they now select the constrained requirement. Such a reader
implements the constrained requirement too. A reader that implements only
`column`, which is the documented shape, is unaffected.

`Tests/SQLTests/StaticColumnDispatchTests.swift` pins the selection. It reads
a generated three-column row through a reader that implements both
requirements and records which one each column arrived through. A correctness
test cannot catch a regression here, because both requirements return the same
value; only the dispatch differs.

## Measured result

Method: the same SwiftQL half of the #250 harness, release build, same
16,143-row fixture and same 14 columns. Two source trees that differ only in
`Sources/SwiftQL/SQLRowReading.swift`, each built into its own graph. Six
pairs. Both arms of a pair run back to back, and the arm that runs first
alternates by pair, so a monotonic thermal drift cannot favour one arm. 10
warmups and 100 timed fetches per process, as usual.

| | Median | p95 | Process spread |
| --- | ---: | ---: | ---: |
| Baseline | 72.38 ms | 74.67 ms | 3.49% |
| Constrained requirement | 43.88 ms | 45.32 ms | 3.78% |
| Change | **-39.37%** | **-39.30%** | |

Every pair agrees, which is what makes the result safe to accept at this
sample size:

| Pair | Baseline | Candidate | Change |
| ---: | ---: | ---: | ---: |
| 1 | 71.25 ms | 43.15 ms | -39.43% |
| 2 | 72.03 ms | 43.91 ms | -39.04% |
| 3 | 73.74 ms | 44.26 ms | -39.98% |
| 4 | 71.22 ms | 43.65 ms | -38.71% |
| 5 | 72.79 ms | 44.81 ms | -38.44% |
| 6 | 72.72 ms | 43.85 ms | -39.70% |

The smallest per-pair change is 38.4%. The harness rejects a cross-graph
control difference above 5% and treats anything below it as noise, so a
uniform 38–40% is far outside what this harness can produce by accident.

Raw samples: `Runs/paired-samples.tsv`. Per-pair medians:
`Runs/paired-summary.tsv`.

Note that the baseline here reads 72.38 ms against the 69.94 ms recorded
above. The two numbers come from different sessions and toolchains, so they
are not comparable to each other. Only the two arms of this paired run are
comparable, and they were built and timed together.

## The profile after the change

Re-profiling confirms the change removed the cost it was aimed at, rather than
moving time somewhere unmeasured. Both profiles below were captured with one
tool in one session: `Runs/verification-self-time-baseline.tsv` and
`Runs/verification-self-time-candidate.tsv`.

| Symbol self time | Baseline | Candidate |
| --- | ---: | ---: |
| `_xlReadLegacyStaticColumn` | 1.12% | **0.00%** |
| `swift_getExtendedExistentialTypeMetadata_unique` | 3.44% | **0.00%** |
| `ExtendedExistentialTypeCacheEntry::Key::Key` | 1.84% | **0.00%** |
| `swift_conformsToProtocol` | 2.20% | **0.00%** |
| `swift::MetadataCacheKey::operator==` | 4.88% | 1.91% |
| `_swift_getGenericMetadata` | 1.24% | 0.64% |
| `sqlite3VdbeExec` | 1.68% | 2.98% |

Metadata and conformance work falls from **23.4%** to **10.2%** of main-thread
samples. The three casts are gone: the two existential entries and the
conformance lookup are at zero, not merely reduced. `sqlite3VdbeExec` rises as
a share because the total shrank — SQLite now gets a larger part of a smaller
whole, which is the intended direction.

These shares are lower than the 53.9% quoted earlier because this profile ran
for three seconds under a newer toolchain, not six seconds under the original
one. Compare the two columns of this table with each other, not with the
original profile.

## Reproduce the paired run

`paired.py` builds one comparison graph per source tree and interleaves the
timed processes. It reuses `Benchmarks/Comparison/run.py` for fixture
verification, graph preparation, building, and sample parsing, so the measured
path is the same one the #250 harness measures.

```sh
python3 Benchmarks/Comparison/Issue353/paired.py \
  --comparison-dir Benchmarks/Comparison \
  --workspace /private/tmp/swiftql-issue353 \
  --baseline /path/to/tree/without/the/change \
  --candidate /path/to/tree/with/the/change \
  --pairs 6 \
  --cooldown-seconds 180 \
  --output /private/tmp/swiftql-issue353/paired-result.json
```

Run it on an otherwise idle machine. `test_paired.py` covers the schedule, the
process-id cycling, and the percentage arithmetic.

## A harness repair this work needed first

`run.py` could not build the SwiftQL graph at all. The graph's pinned
`Package.resolved` was captured on 2026-07-18; SwiftQL added its OpenCombine
dependency on 2026-07-20. SwiftPM therefore added an OpenCombine pin during
every build, and `build_graph` correctly refused to continue, because a
rewritten resolution means the measured dependency versions are not the pinned
ones.

The repair adds the missing pin, at the exact version and revision SwiftPM
resolves, to
`Benchmarks/Comparison/Graphs/SwiftQLGRDB6/Package.resolved`. No other pin
changes. This is not a performance change; without it, no #250-based latency
result could be produced at all.

## Constraints this work must keep

From the issue, and unchanged by anything here: no restored `Row.fetchAll` or
`[[XLSQLiteValue]]` matrix, no GRDB types through `SwiftQLCore`, no cursor or
row escaping its database closure, no source-breaking public v1 requirement,
and no weakening of early-stop, mid-stream error identity, statement reset,
pool cleanup, transaction, binding, or live-query snapshot behaviour.
