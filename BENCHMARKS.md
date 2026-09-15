# SwiftQL performance benchmarks

SwiftQL includes a reproducible benchmark harness for measuring where time is
spent between constructing a SwiftQL statement and decoding its result. The
harness is diagnostic evidence, not a cross-machine leaderboard or an absolute
latency gate.

## Run the benchmark

From the package root, one command prints a human-readable summary and writes a
versioned JSON report containing every raw sample:

```sh
swift run -c release swiftql-benchmark \
  --warmups 50 \
  --samples 500 \
  --output .build/benchmarks/swiftql-benchmark.json
```

Run `swift run swiftql-benchmark --help` for the complete command-line reference.
The default output path is `.build/benchmarks/swiftql-benchmark.json`.

Use a release build for recorded baselines. CI deliberately uses an already
built debug executable with zero warmups and one sample. That smoke run checks
the complete report structure, real SQLite metadata, expected row/change
counts, and write rollback behavior without enforcing machine-dependent time.

## Current baseline

This section names the baseline that describes the code that ships. Earlier
baselines stay in the repository as history; they are not deleted or rewritten.

**Current baseline: not recorded yet.** Issue #670 records it on the final
v1.9 code, on an idle host, with [`Benchmarks/record-baselines.sh`](#re-record-the-baselines).
Until then, no row below has a revision or a date, and the figures in the
historical baselines predate the August 2026 decode work.

| Evidence | Files | Revision | Recorded |
| --- | --- | --- | --- |
| Phase harness, format version 2 | `Benchmarks/Baselines/<YYYY-MM-DD>-<machine>-run-{1,2,3}.json` | _not recorded yet_ | _not recorded yet_ |
| Cross-library full fetch | `Benchmarks/Comparison/Recordings/<YYYY-MM-DD>-<machine>/` | _not recorded yet_ | _not recorded yet_ |
| Consumer compile time, `extended` matrix | `Benchmarks/CompileTime/Recordings/<YYYY-MM-DD>-<machine>/` | _not recorded yet_ | _not recorded yet_ |

Historical baselines:

| Evidence | Files | Revision | Recorded |
| --- | --- | --- | --- |
| Phase harness, format version 1 | `Benchmarks/Baselines/2026-07-17-mac16-8-run-{1,2,3}.json` | `6645cc57` | 2026-07-17 |
| Cross-library full fetch | `Benchmarks/Comparison/2026-07-18-mac16-8.json` | `6b417ef9` | 2026-07-18 |
| Consumer compile time, reduced matrix | `Benchmarks/CompileTime/compile-time-results.json` | `8183cb95` | 2026-08-02 |

The 2026-08-02 compile-time report contains three samples whose wall time is
inconsistent with SwiftPM's own build duration in the same log, so
`summarize.py` rejects them. See
[Benchmarks/CompileTime](Benchmarks/CompileTime/README.md#rejected-samples).

## Re-record the baselines

Record on an otherwise idle host, from a clean checkout of the revision:

```sh
git checkout <revision>
Benchmarks/record-baselines.sh --revision <revision>
```

The script builds and runs the phase harness three times in release mode
(50 warmups, 500 samples), runs the cross-library comparison, and runs the
compile-time `extended` matrix. It writes each report to a new dated file,
validates each with its own summarizer, and refuses to overwrite a file that
exists. `--dry-run` prints every command without running any of them, and
`--skip-phase`, `--skip-comparison`, and `--skip-compile-time` record a subset.
After it finishes, fill in the current-baseline table above with the revision
and the date, and commit the new files.

## Cases

The deterministic, integer-seeded fixture is a temporary file-backed SQLite
database with 8 companies, 32 departments, 512 people, and 2 wide decoding
rows. Every run covers the same matrix:

| Case | Contract |
| --- | --- |
| `simple_parameterized_lookup` | Indexed lookup of one person by `:personID`. |
| `simple_lookup_inline_literals` | The same lookup with the person ID rendered inline as a SQL literal. |
| `representative_multi_join_read` | Two joins, columns from all three tables, deterministic order, and 32 rows. |
| `representative_multi_join_read_inline_literals` | The same join with its company ID and minimum score rendered inline. |
| `bounded_write` | Range update of exactly 64 rows, rolled back after every timing. |
| `bounded_write_inline_literals` | The same update with its ID range and score delta rendered inline. |
| `deterministic_row_decode` | Two wide rows covering INTEGER, REAL, TEXT, BLOB, Bool, and nullable values. |
| `deterministic_row_decode_inline_literals` | The same decode with its maximum ID rendered inline. |
| `contextual_value_codec` | One deterministic application value transported as SQLite INTEGER through an immutable contextual codec configuration. |

Each query has a named-binding variant and a plain-value variant next to it.
SwiftQL renders a plain Swift value in a query as an inline SQL literal, which
is its default path, so a plain-value variant has no parameter to bind.

Report format version 2 gives each case twelve phase slots: the six version 1
slots and six SwiftQL production slots. The current nine-case harness therefore
contains 108 slots and 84 measurements:

- A read case measures 11 slots. `swiftql_execute` is not applicable, because
  a SELECT runs through `fetchAll()`.
- A write case measures 8 slots. `row_decoding`, `swiftql_row_materialization`,
  `swiftql_row_decoding`, and `swiftql_fetch_all` are not applicable, because
  the UPDATE has no `RETURNING` clause.
- The contextual-codec case measures only `statement_reset_and_binding` and
  `row_decoding`. SQL DSL construction and statement preparation/cache lookup
  do not exercise the conversion contract it isolates. Its execution slot is
  not applicable because the public request API necessarily decodes the scalar
  result and therefore cannot satisfy the SQLite-only execution boundary. The
  six SwiftQL production slots are not applicable, because the SQL cases
  already measure that path.

The three 2026-07-17 baseline JSON files are format version 1. They predate the
contextual-codec case, the plain-value variants, and the production phases, and
intentionally remain valid four-case, 23-measurement reports rather than being
rewritten. The validator accepts version 1 with its six phases and version 2
with all twelve.

## Phase boundaries

Each raw sample is one case/phase operation timed with
`DispatchTime.now().uptimeNanoseconds`. For read cases, both execution and row
decoding cover that case's complete result set (1, 32, or 2 rows). Setup,
correctness checks, checksum calculation, and result destruction occur after
the end timestamp. The harness does not batch operations, subtract clock
overhead, trim outliers, or combine phases.

| Phase | Included | Excluded |
| --- | --- | --- |
| `swiftql_construction_and_rendering` | Complete schema/meta construction and `XLiteEncoder.makeSQL`. | GRDB and database work. |
| `cold_statement_preparation` | Uncached `Database.makeStatement(sql:)` on one open, schema-warm connection. | Connection acquisition and statement finalization. This is not application cold start. |
| `cached_statement_lookup` | A primed, same-connection `Database.cachedStatement(sql:)` hit. | Initial preparation. Returned object identity is verified. |
| `statement_reset_and_binding` | Public `Statement.setArguments`, including validation, reset, clear, and bind. As an explicit contextual-case exception, `contextual_value_codec` also includes pre-resolved encode, declared-storage validation, immutable invocation-packet construction/completeness validation, and `StatementArguments` construction from the normalized packet value. | SwiftQL request construction and registry/default resolution. Argument-container construction is excluded for the four SQL cases but deliberately included for the contextual-case exception. |
| `execution` | GRDB's required pre-execution reset and SQLite stepping through all result rows, or the bounded UPDATE. The contextual-codec case is not applicable because its public request path also decodes the scalar result. | Preparation, explicit binding, GRDB row materialization, SwiftQL decoding, savepoint entry, and rollback. |
| `row_decoding` | For SQL result cases, the complete captured result set decoded into an output array through the production `GRDBRowAdapter` → `XLColumnValuesRowReader` path shared by a package-private decoder. For `contextual_value_codec`, one captured GRDB INTEGER is normalized to `XLSQLiteValue`, then storage-validated and decoded through a pre-resolved immutable codec slot. | SQL execution, captured GRDB-row creation, semantic verification, checksumming, and decoded-value destruction. |

The version 1 phases above time raw GRDB calls for preparation, binding, and
execution, and decode rows captured before sampling. Format version 2 adds six
phases that run on SwiftQL's own production path, through the same internal
functions that `fetchAll()` and `execute()` call. A package-scoped probe,
`GRDBRequestPhaseProbe`, lends those functions to the harness one phase at a
time; it is not public API. The phases for render, bind, execute, materialize,
and decode are `swiftql_construction_and_rendering` and the first four rows
below.

| Phase | Included | Excluded |
| --- | --- | --- |
| `swiftql_binding` | Building the request's invocation packet from its named bindings (empty for inline literals), packet validation against the parameter layout, the connection's cached statement, binding the validated values, and GRDB argument validation. | Request construction, rendering, and connection access. |
| `swiftql_execution` | For a read, opening GRDB's row cursor on the bound production statement (reset and SQLite argument binding) and stepping every row without reading a column. For a write, one execution of the bound statement. | SwiftQL binding, column materialization, decoding, and, for a write, savepoint entry, rollback, and release. |
| `swiftql_row_materialization` | Opening and stepping the cursor, and normalizing every column of every row to `XLSQLiteValue` through the production cursor loop. | Decoding. |
| `swiftql_row_decoding` | Decoding the complete result, materialized once before sampling, through `GRDBRowDecoder.decode(values:)`, the per-row call inside `fetchAll()`, including the output array. | Execution and materialization. |
| `swiftql_fetch_all` | Public `XLRequest.fetchAll()` on a prepared request with its bindings set: packet validation, one pooled read access, binding, stepping, materialization, and decoding. | Request construction and rendering. |
| `swiftql_execute` | Public `XLWriteRequest.execute()` on a prepared request with its bindings set: packet validation, one pooled write transaction with its commit, binding, and the UPDATE. | Request construction, rendering, and restoring the 64 scores after each sample. |

Phase medians are not additive. In particular, public GRDB execution performs
its own pre-execution reset even though reset is also part of the separately
measured `setArguments` contract, and `swiftql_row_materialization` includes
the stepping that `swiftql_execution` measures on its own.

## Report contents

The JSON report records:

- report format, generation time, monotonic clock, raw integer nanoseconds,
  median, and nearest-rank p95;
- warmups and recorded sample count, with separate consumption checksums;
- repository revision/state, debug/release build configuration, Swift, Xcode,
  SDK, resolved GRDB version and revision, OS, architecture, machine model,
  processor, memory, and CI runner image when available;
- SQLite version, source ID, compile options, journal mode, synchronous mode,
  and page size read from the actual measured connection;
- complete schema SQL, fixture version/counts, rendered SQL, query plans, typed
  parameters, expected result/change counts, and exact phase boundaries.

The human summary is derived from the same in-memory report that is encoded to
JSON. Report validation recalculates every median and p95 from the raw samples.

## Comparing runs

Compare runs only when commit, release configuration, sample count, toolchain,
dependencies, SQLite source ID, fixture version, pragmas, and machine metadata
match. Run at least three independent release processes; use the spread of
their medians to distinguish repeatable changes from process and system noise.

The codec case resolves its parameter and result slots once before sampling.
Its binding measurement then compares resolved encode, storage validation,
immutable invocation-packet construction/completeness validation,
`StatementArguments` construction, and transport binding with the existing
pre-encoded binding baseline; only registry/default resolution, layout
construction, and request construction remain setup. Its decoding measurement
is a one-scalar resolved contextual path, whereas
`deterministic_row_decode` decodes two wide result-macro rows. Compare those
workload medians as integration evidence, not as a per-field ratio.

Issue #188 has a checked-in reproduction recipe and comparison tool in
[Benchmarks/Issue188](Benchmarks/Issue188/README.md). It records new JSON files
outside `Benchmarks/Baselines`, so collecting current evidence cannot overwrite
the historical v1.1 baseline.

The first checked-in measurements and their cross-run variance are documented
in [Benchmarks/Baselines/README.md](Benchmarks/Baselines/README.md). The
[current baseline](#current-baseline) section names the baseline to compare
against. Optimize a
phase only after repeatable measurements and profiling identify a material
cost. CI intentionally has no absolute time threshold.

## Cross-library full-fetch comparison

The independent harness in
[Benchmarks/Comparison](Benchmarks/Comparison/README.md) records a separate
Northwind `Orders` full-fetch baseline against SQLiteData, Lighter, GRDB,
SQLite.swift, and raw SQLite. It uses two isolated dependency graphs, paired
controls, one implementation per fresh process, raw per-iteration samples,
and an exact 16,143-row fixture. The comparison is a before/after reference
for execution-path work, not a general database-library ranking or an absolute
CI performance gate.

## Consumer compile-time scalability

Runtime cost is only half of what a consumer pays. The harness in
[Benchmarks/CompileTime](Benchmarks/CompileTime/README.md) measures the other
half: how long a downstream package takes to build as its table and query
declaration counts grow, compared against hand-written raw SQLite, GRDB,
SQLite.swift, and Lighter consumers in isolated dependency-locked packages. It
records dependency-warm clean builds, no-op rebuilds, and one-query-edit
rebuilds, plus generated-source, object, module, and archive sizes, and it
reports whole-consumer build cost without attributing any part of it to macro
expansion alone.
