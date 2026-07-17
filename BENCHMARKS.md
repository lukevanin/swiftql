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

## Cases

The deterministic, integer-seeded fixture is a temporary file-backed SQLite
database with 8 companies, 32 departments, 512 people, and 2 wide decoding
rows. Every run covers the same matrix:

| Case | Contract |
| --- | --- |
| `simple_parameterized_lookup` | Indexed lookup of one person by `:personID`. |
| `representative_multi_join_read` | Two joins, columns from all three tables, deterministic order, and 32 rows. |
| `bounded_write` | Range update of exactly 64 rows, rolled back after every timing. |
| `deterministic_row_decode` | Two wide rows covering INTEGER, REAL, TEXT, BLOB, Bool, and nullable values. |
| `contextual_value_codec` | One deterministic application value transported as SQLite INTEGER through an immutable contextual codec configuration. |

Each case contains all six phase slots. The current five-case harness therefore
contains 30 slots and 25 measurements. `bounded_write × row_decoding` is not
applicable because the UPDATE has no `RETURNING` clause. The contextual-codec
case measures only `statement_reset_and_binding` and `row_decoding`; SQL DSL
construction, statement preparation/cache lookup, and execution do not exercise
the conversion contract it isolates. The three historical baseline JSON files
predate that case and intentionally remain valid four-case, 23-measurement
reports rather than being rewritten.

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
| `statement_reset_and_binding` | Public `Statement.setArguments`, including validation, reset, clear, and bind. The contextual-codec case additionally includes pre-resolved encode and storage validation. | SwiftQL request construction, registry/default resolution, and argument creation. |
| `execution` | GRDB's required pre-execution reset and SQLite stepping through all result rows, or the bounded UPDATE. | Preparation, explicit binding, GRDB row materialization, SwiftQL decoding, savepoint entry, and rollback. |
| `row_decoding` | For SQL result cases, the complete captured result set decoded into an output array through the production `GRDBRowAdapter` → `XLColumnValuesRowReader` path shared by a package-private decoder. For `contextual_value_codec`, one captured GRDB INTEGER is normalized to `XLSQLiteValue`, then storage-validated and decoded through a pre-resolved immutable codec slot. | SQL execution, captured GRDB-row creation, semantic verification, checksumming, and decoded-value destruction. |

Phase medians are not additive. In particular, public GRDB execution performs
its own pre-execution reset even though reset is also part of the separately
measured `setArguments` contract.

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
Its binding measurement then compares resolved encode, storage validation, and
transport binding with the existing pre-encoded binding baseline; registry
lookup and argument-container construction remain setup. Its decoding
measurement is a one-scalar resolved contextual path, whereas
`deterministic_row_decode` decodes two wide result-macro rows. Compare those
workload medians as integration evidence, not as a per-field ratio.

Issue #188 has a checked-in reproduction recipe and comparison tool in
[Benchmarks/Issue188](Benchmarks/Issue188/README.md). It records new JSON files
outside `Benchmarks/Baselines`, so collecting current evidence cannot overwrite
the historical v1.1 baseline.

The first checked-in measurements and their cross-run variance are documented
in [Benchmarks/Baselines/README.md](Benchmarks/Baselines/README.md). Optimize a
phase only after repeatable measurements and profiling identify a material
cost. CI intentionally has no absolute time threshold.
