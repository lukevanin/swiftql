# Issue #266 — incremental decode allocation reduction and latency finding

This directory records the before/after evidence for issue #266, "Recover
incremental GRDB decoding latency without restoring eager matrices."

**Outcome in one line:** the safe, SwiftQL-owned change here removes the per-row
intermediate allocation from the incremental cursor path and preserves the
bounded-memory win, but the #248 latency regression is **not** allocation-bound,
so this change is **latency-neutral** on the measured workload. The dominant
per-row cost is the typed-decode compute, which a follow-up issue owns. This is
partial progress on #266, not its resolution; the latency goal stays open.

## The change

`GRDBDatabaseDriverConnection.forEachRow` previously allocated a fresh
`[XLSQLiteValue]` per row and then wrapped it again in `Array(...)`:

```swift
let values = Array(row.databaseValues.map(\.sqliteDialectValue))
```

It now reuses one normalization buffer across the whole fetch. Copy-on-write
keeps the eager `collectAllRows`/`collectFirstRow` compatibility shims correct
(a retained row gets its own storage when the buffer is refilled), so no
`[[XLSQLiteValue]]` matrix is materialized and the bounded-memory guarantee from
#248 is preserved. Instrumented stop/failure and buffer-aliasing tests stay
green (`GRDBDriverContractTests`, full `swift test`: 743 tests, 0 failures).

## Method

Measured with the comparison harness's SwiftQL GRDB 6 graph
(`Benchmarks/Comparison/Graphs/SwiftQLGRDB6`, `SwiftQLControl`) run directly on
the exact 16,143-row Northwind `Orders` fixture and 14 columns, release builds,
10 warmups and 100 timed full fetches per process, three independent processes,
peak RSS via `/usr/bin/time -l`. Before builds the base decode path; after
builds this change; only the SwiftQL source revision differs.

This is the SwiftQL half of the #250 harness. It deliberately omits the
cross-library graph, the six paired controls, the paired-control drift guard,
and the 180-second cooldown, because those establish cross-library
comparability, not a within-SwiftQL before/after. The authoritative
paired-control run is reproduced with the command below.

## Environment

- Machine: Mac16,8, Apple M4 Pro, arm64, macOS 26.5.1, Swift 6.3.2, GRDB 6.29.3.
- The machine was **not** idle (concurrent unrelated Swift test suites), so
  per-process latency carries real contention; the median-of-process-medians is
  robust to a single contended process and the base run's spread was 0.3%.

## Result

Median of three process medians, and peak RSS across the three processes:

| Metric | Before (base) | After (this change) | Delta |
| --- | ---: | ---: | ---: |
| Median latency | 76.08 ms | 76.22 ms | **+0.2%** |
| p95 (median of process p95) | 88.04 ms | 88.12 ms | +0.1% |
| Peak RSS | 37.1 MiB | 37.4 MiB | bounded, preserved |
| Base process spread | 0.3% | — | — |

Raw per-process samples and RSS are in [`Runs/`](Runs/).

The +0.2% delta sits far inside the run-to-run spread, and the base run was
stable at 0.3% spread, so this is a genuine null result rather than noise hiding
an effect: **removing the per-row allocation does not move latency.**

## Finding: the regression is decode-compute-bound, not allocation-bound

The #248 candidate regressed 43.72 ms → 67.23 ms. This change proves that the
extra time is not the per-row `[XLSQLiteValue]` allocation. For context, the
harness's own `grdb_manual` control fetches and maps the same 16,143 rows in
~6.9 ms, and SwiftQL's *eager* baseline was already 43.72 ms — so SwiftQL's
typed-decode compute, not GRDB cursor stepping, is the cost center. The
incremental restructuring (per-row normalization plus the scoped sequential row
reader) added compute on top of that path.

Recovering the remaining latency requires reducing the per-row typed-decode
compute — profiling `XLColumnValuesRowReader` / the scoped row reader (#268),
the per-column `XLFieldReader`, and value normalization — or decoding closer to
the borrowed cursor. That is a larger change that must be measured on a quiet
machine with a sampling profiler, and is tracked as an atomic follow-up rather
than rushed here. This change deliberately does not restore eager buffering or
couple the decoder into the driver to chase latency.

## Reproduce the authoritative paired-control before/after

```sh
# after (current checkout) and before (base revision), each from a clean tree:
python3 Benchmarks/Comparison/run.py \
  --workspace /private/tmp/swiftql-comparison \
  --swiftql-checkout "$PWD" \
  --output Benchmarks/Comparison/Issue266/candidate.json \
  --cooldown-seconds 180
python3 Benchmarks/Comparison/summarize.py \
  --baseline Benchmarks/Comparison/2026-07-18-mac16-8.json \
  --candidate Benchmarks/Comparison/Issue266/candidate.json
```
