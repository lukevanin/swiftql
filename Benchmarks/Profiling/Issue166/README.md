# Issue #166 — construction/rendering profile and reduction

This directory records the profiling evidence and the before/after measurements
for issue #166, "Profile and reduce SwiftQL query construction and rendering
overhead." It is diagnostic evidence, not an absolute CI latency gate.

The [#128 baseline](../../Baselines/README.md) established that the combined
`swiftql_construction_and_rendering` phase is a material SwiftQL-owned cost for
every workload. #166 owns attributing that cost to exact code and reducing it
without changing rendered SQL, entity metadata, query semantics, or the public
1.x API.

## Method

Two complementary instruments were used, because the #128 harness records only
wall-clock samples and this machine has real background load (other test suites
run concurrently), which adds process-to-process DVFS/core-placement noise to a
sub-50-microsecond phase.

1. **Deterministic allocation profile** — `swiftql-construction-profile` (a new
   diagnostic executable in this package, `Benchmarks/Sources/SwiftQLConstructionProfile`)
   installs the in-process Darwin `malloc_logger` hook and counts every heap
   allocation issued while it (a) constructs only, (b) renders a prebuilt
   statement only, and (c) does the combined construct+render the #128 harness
   measures. Allocation counts are immune to scheduler noise, so they attribute
   cost to the exact sub-phase. It rebuilds the exact two read queries the #128
   harness measures (`simple_parameterized_lookup` and
   `representative_multi_join_read`) against the public API.
2. **Timing** — the checked-in `swiftql-benchmark` (#128) harness, 50 warmups
   and 500 samples, run as eight independent release processes per condition,
   before and after, back to back under the same machine load. Reported values
   are the median of the eight process medians; spread is
   `(max − min) / mean` of the process medians.

## Environment

- Machine: Mac16,8, Apple M4 Pro, arm64, macOS 26.5.1
- Toolchain: release, Xcode 26.5 (17F42), Swift 6.3.2, macOS SDK 26.5
- GRDB 6.29.3 (`2cf6c756`), SQLite 3.51.0 (`f0ca7bba…apl`), WAL, `synchronous = 1`

This matches the #128 baseline machine and toolchain. The machine was **not**
idle during timing (concurrent unrelated Swift test suites), so process spread
is genuine and is reported rather than hidden.

## What the profile attributed

Rendering, not construction, dominates the phase. Per-operation heap
allocations (deterministic, `iterations = 20000`):

| Case | Construction allocs | Render allocs | Combined allocs | Render share |
| --- | ---: | ---: | ---: | ---: |
| Simple lookup | 73 | 249 | 322 | 77% |
| Multi-join read | 128 | 434 | 562 | 77% |

Rendering issued roughly three-quarters of all allocations. Attributing the
render allocations to exact code (`Sources/SwiftQL/SQLiteEncoding.swift`):

- **`XLiteBuilder.append(_ tokens: String...)`** was variadic and filtered, so
  every builder node allocated a variadic `[String]` box *and* a `filter` copy
  even though every one of its 29 call sites passes a single already-rendered
  token.
- **`build()`** always re-joined its token array, allocating a fresh joined
  `String` even for the single-token leaf and wrapper builders that dominate the
  tree.
- **`XLiteFormatter.scopedName(_:)`** rendered every qualified reference through
  `values.map(name).joined(".")`, allocating an intermediate `map` array for the
  one- and two-component names that make up essentially all references.

## The reduction

Three output-preserving changes in `SQLiteEncoding.swift`:

1. `append` takes a single token and appends it directly (keeping the
   empty-token filter), removing the variadic box and `filter` copy per node.
2. `build()` returns the sole token directly when there is exactly one, skipping
   the join allocation; multi-token builders still join with their separator.
3. `scopedName` special-cases zero/one/two components and only falls back to
   `map`/`joined` for three or more, so the common reference allocates no
   intermediate array.

No rendered SQL, entity set, parameter layout, query semantics, or public API
changed. Swift 5.9 support is unaffected (no new language features are used).

### Allocation result (deterministic)

| Case | Render allocs before → after | Combined allocs before → after |
| --- | ---: | ---: |
| Simple lookup | 249 → 212 (**−14.9%**) | 322 → 285 (**−11.5%**) |
| Multi-join read | 434 → 365 (**−15.9%**) | 562 → 493 (**−12.3%**) |

Raw: [`before-allocation-profile.json`](before-allocation-profile.json),
[`after-allocation-profile.json`](after-allocation-profile.json).

### Timing result (#128 harness, eight processes each)

Median of process medians for the `swiftql_construction_and_rendering` phase,
microseconds:

| Case | Before | After | Median delta | Spread before → after |
| --- | ---: | ---: | ---: | ---: |
| Simple lookup | 29.10 | 24.96 | **−14.2%** | 7.6% → 16.1% |
| Multi-join read | 47.35 | 40.04 | **−15.4%** | 11.2% → 12.6% |
| Bounded write | 20.04 | 16.56 | **−17.4%** | 9.5% → 7.7% |
| Deterministic decode | 32.03 | 27.83 | **−13.1%** | 10.0% → 7.5% |

The median improvement (13–17%) is consistent across all four independent cases
and tracks the deterministic allocation reduction, so it is a repeatable change
rather than process noise — even though the absolute spread on this loaded
machine is several percent. All four cases improve, including `bounded_write`,
which shares the same builder even though only the two read queries were
profiled. Per-process medians and p95 are in
[`timing-summary.json`](timing-summary.json).

## Reproduce

```sh
# Deterministic allocation profile (before vs after your working tree)
swift run -c release swiftql-construction-profile \
  --iterations 20000 --warmups 200 --samples 4000 \
  --json /tmp/profile.json

# Timing: run several independent release processes per condition and compare
# the process medians and spread (see BENCHMARKS.md for the harness contract).
swift run -c release swiftql-benchmark --warmups 50 --samples 500 \
  --output /tmp/run-1.json
```

## Limits

This is one machine, one toolchain, and the two representative read queries plus
the two write/decode #128 cases. The allocation counts are deterministic; the
timing values are not portable and are not a CI gate. Construction-side
allocations (component-array copies in `XLQueryStatementComponents.appending`,
namespace/alias churn) were profiled and left unchanged: they are the smaller
share and could not be reduced without touching query-value semantics, which is
out of scope for this SQL-output-preserving change.
