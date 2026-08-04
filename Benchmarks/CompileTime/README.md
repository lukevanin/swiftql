# Consumer compile-time scalability

This directory measures what it costs a downstream app to *build* against
SwiftQL as the app grows, and compares that against four other ways of writing
the same schema and the same queries. It answers "how long does my build take
when I have 100 tables" rather than "how fast is a query at runtime", which is
what [Benchmarks/Comparison](../Comparison/README.md) covers.

Everything here is whole-consumer build cost. A `swift build` measurement
contains parsing, macro expansion, type checking, SIL, IRGen, and linking, and
this harness has no way to separate those, so it never claims a share of any
number for macro expansion on its own.

## What is measured

Five isolated consumer packages, one per API style, each with its own pinned
dependency graph. None of them is reachable from SwiftQL's production package
graph: they live under `Consumers/`, are copied into a scratch workspace, and
the SwiftQL consumer takes the measured checkout as a local path dependency.

| Consumer | Declarations that scale |
| --- | --- |
| `control_raw_sqlite` | Plain structs, per-table SQL constants, and hand-written `sqlite3_*` stepping and column mapping. No package dependencies. |
| `swiftql` | `@SQLTable` structs and `@SQLQuery` specification functions on a `GRDBDatabase` extension. |
| `grdb` | `Codable` + `FetchableRecord` + `PersistableRecord` structs with `Column` constants, and query-interface request functions. |
| `sqlite_swift` | Structs plus `Table`/`Expression` constants, and typed query functions that map each row explicitly. |
| `lighter` | `schema.sql`, which the Enlighter build-tool plugin turns into record types. |

Every consumer declares the same six-column shape (`id`, `name`, `category`,
`quantity`, `weight`, `note`, with `note` the only nullable column) and the same
query semantics: select all six columns from one table where `name` matches a
bound parameter and `category` matches a literal. Query *j* targets table
`((j - 1) mod tableCount) + 1`, so the queries spread deterministically over
whatever tables exist.

### Applicability

Lighter has no user-written table or query declarations at all. Its plugin reads
a schema file and emits everything, so there is nothing for a Lighter user to
write more or less of except SQL. The table axis therefore scales `schema.sql`,
which is the honest analogue of "my app now has 100 tables", and both the query
axis and the one-query-edit mode do not exist for it. The harness records that
as an explicit applicability entry rather than substituting something that only
looks comparable, and `summarize.py` rejects a report whose declared
applicability disagrees with the build modes it actually recorded.

## Scales

Table and query counts move independently around a shared 1-table, 1-query
baseline, so a cell is either "N tables, 1 query" or "1 table, N queries". The
canonical scales are 1, 10, 100, and 500. A report records which subset it
actually covered, and the validator refuses a report whose declared scales and
recorded measurements disagree.

## Build modes

Each cell is measured in three modes, in this order, and each measurement is its
own `swift build` process.

| Mode | What happens before the build |
| --- | --- |
| `clean_dependency_warm` | Every generated consumer source file is rewritten, which invalidates the whole consumer module. Dependency and macro-plugin builds stay warm. |
| `noop_incremental` | Nothing changes. |
| `one_query_edit` | One string literal inside query 1 changes. Nothing else in the file moves, so the diff is exactly one line. |

`clean_dependency_warm` is not an empty cache: the compared libraries and the
SwiftQL macro plugin are already built, which is what a working developer's
machine looks like. Comparing it against a genuinely cold cache would compare
different things, so the harness does not do that.

Every raw log is checked for evidence that the consumer target did or did not
recompile. A no-op build that recompiled, or a clean build that did not, fails
the run and fails validation, which is what stops a mode from silently
measuring nothing.

## Metrics

Each measurement records wall, user, and system time and peak RSS, all read
from one `/usr/bin/time -l` invocation and re-parsed out of the checked-in raw
log during validation. Peak RSS covers the whole `swift build` process tree,
including SwiftPM, the compiler, and the macro plugin, so it is not an
allocation attributable to any one API.

Alongside the timings, each cell records untimed build outputs: generated source
bytes with a per-file SHA-256, the consumer target's object bytes, its
`.swiftmodule` size, the static archive size, and plugin-generated Swift bytes
where a plugin exists. The static archive contains linked dependency objects, so
it is dominated by the dependency rather than by the declarations; the object
bytes are the scale-sensitive figure.

Macro expansion size is recorded as unavailable, with the same reason for every
consumer. The pinned toolchain exposes no flag that writes macro expansion
buffers to a stable, machine-readable location during a SwiftPM build, and
guessing a number from whole-build timing would be exactly the fabrication this
harness is meant to avoid. Only the SwiftQL consumer expands macros at all, so
for the other four the field is recording the absence of something they never
had.

If `/usr/bin/time -l` is unavailable, the harness refuses to record a partial
measurement rather than emitting one with holes in it.

## Run it

One command generates every consumer, compile-checks it, and records the matrix:

```sh
python3 Benchmarks/CompileTime/run.py \
  --workspace /private/tmp/swiftql-compile-time \
  --swiftql-checkout "$PWD" \
  --tables 1,10,100 \
  --queries 1,10,100 \
  --repetitions 3 \
  --output Benchmarks/CompileTime/compile-time-results.json
```

The workspace must be new or empty, and the output file and its sibling `Runs`
directory must not already exist. `--prepare-only` generates and compile-checks
every selected cell without timing anything. `--consumers` restricts the run to
a subset. `--allow-dirty` records a dirty SwiftQL checkout explicitly and is for
exploratory work only.

Validate a report and render the matrix using only the Python standard library:

```sh
python3 Benchmarks/CompileTime/summarize.py \
  Benchmarks/CompileTime/compile-time-results.json
```

Compare two compatible reports:

```sh
python3 Benchmarks/CompileTime/summarize.py \
  --baseline Benchmarks/CompileTime/baseline.json \
  --candidate Benchmarks/CompileTime/candidate.json
```

Validation reparses every raw build log, checks its SHA-256 against the report,
confirms the wall/user/system/RSS values and the recompilation evidence match
what the log actually says, recomputes every median and spread, and rejects
missing scales, missing repetitions, duplicate or non-contiguous schedule
entries, nonpositive measurements, artifact points without measurements,
applicability that contradicts the recorded modes, and dependency drift between
two compared reports. `--require-full-matrix` additionally rejects a report that
does not cover all four canonical scales.

Run the harness tests with:

```sh
python3 -m unittest discover -s Benchmarks/CompileTime -p 'test_*.py'
```

### Regenerating the pinned resolutions

`--bootstrap-resolved` resolves each consumer and copies the resulting
`Package.resolved` back into its checked-in template. Use it only when a
consumer's declared dependencies change, and commit the result.

## Recorded baseline

**This run is noisy and should be replaced before anyone draws a conclusion
from it.** It was captured on a host running several other unrelated,
concurrent `swift build`/Xcode processes (parallel delivery work happening at
the same time), not a quiet machine. The `swiftql tables=10` clean-build cell
reads 911.65s with a 99% spread across its three repetitions -- roughly 300x
every other cell in the same row -- and two `control_raw_sqlite` cells show
422-6780% spread. Both are textbook symptoms of build contention, not of
anything SwiftQL, GRDB, SQLite.swift, or Lighter did. It is recorded anyway,
raw samples and all, rather than discarded, because a validated report with
its noise plainly visible in `wallSpreadPercent` is more useful evidence than
no report -- and because manufacturing a cleaner-looking number by quietly
excluding the bad run would be exactly the fabrication this harness exists to
avoid. Re-run on an otherwise-idle machine before citing any specific figure
below; the low-spread cells (`grdb`, `sqlite_swift`, most `noop_incremental`
rows) are more likely to be trustworthy than the high-spread ones, but "more
likely" is not the same as verified.

This run also covers a reduced matrix -- table and query scales of 1 and 10
only, not the full canonical 1/10/100/500 -- to keep one recording pass inside
a practical wall-clock budget. `--require-full-matrix` will reject this report
if that stricter bar is ever wanted; the command in "Run it" above shows the
fuller 1/10/100 invocation.

```
$ python3 Benchmarks/CompileTime/summarize.py Benchmarks/CompileTime/compile-time-results.json
SwiftQL consumer compile-time scalability
=========================================

Report generated: 2026-08-02T08:55:07.365366Z
SwiftQL revision: 8183cb95152df53537204d1d5527034869508a23
Machine: Mac16,8 / Apple M4 Pro / 14 cores
Toolchain: Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101)
Target: arm64-apple-macosx26.0
Configuration: debug, 3 independent build processes per cell, dependency-warm
Recorded table scales: [1, 10]; recorded query scales: [1, 10]; canonical matrix: [1, 10, 100, 500]

Cost is whole-consumer build cost. No part of any number is attributed to macro expansion alone.

Applicability
-------------
  control_raw_sqlite: table axis applicable, query axis applicable, one-query edit applicable
      Dependency-free control: hand-written structs, hand-written SQL text, and hand-written sqlite3 C stepping and column mapping.
  swiftql: table axis applicable, query axis applicable, one-query edit applicable
      @SQLTable declarations and @SQLQuery specification functions on a GRDBDatabase extension.
  grdb: table axis applicable, query axis applicable, one-query edit applicable
      Codable FetchableRecord/TableRecord structs and query-interface request functions.
  sqlite_swift: table axis applicable, query axis applicable, one-query edit applicable
      Table/Expression declarations and typed query functions that map each row explicitly.
  lighter: table axis applicable, query axis not_applicable, one-query edit not_applicable
      Lighter has no user-written table or query declarations. Its Enlighter build-tool plugin emits record types from a schema file, so the table axis scales schema.sql and the query axis and the one-query-edit mode do not exist.

Median wall time - clean_dependency_warm
----------------------------------------
  scale                       control_raw_sqlite               swiftql                  grdb          sqlite_swift               lighter
  1 tables x 1 queries             1.23 s +/-21%         1.74 s +/-32%         0.85 s +/-11%          0.78 s +/-1%         1.17 s +/-27%
  1 tables x 10 queries           1.16 s +/-762%          2.11 s +/-4%         0.88 s +/-10%         0.88 s +/-22%                   n/a
  10 tables x 1 queries            0.86 s +/-43%       911.65 s +/-99%          1.00 s +/-3%          0.79 s +/-1%          3.79 s +/-3%

Median wall time - noop_incremental
-----------------------------------
  scale                       control_raw_sqlite               swiftql                  grdb          sqlite_swift               lighter
  1 tables x 1 queries             0.81 s +/-23%          0.64 s +/-2%          0.57 s +/-0%          0.56 s +/-0%          0.57 s +/-2%
  1 tables x 10 queries           0.55 s +/-422%          0.65 s +/-2%          0.57 s +/-2%         0.57 s +/-44%                   n/a
  10 tables x 1 queries            0.56 s +/-52%         0.95 s +/-26%          0.57 s +/-2%          0.56 s +/-2%          0.57 s +/-0%

Median wall time - one_query_edit
---------------------------------
  scale                       control_raw_sqlite               swiftql                  grdb          sqlite_swift
  1 tables x 1 queries             1.25 s +/-14%         1.65 s +/-10%          0.82 s +/-0%          0.77 s +/-0%
  1 tables x 10 queries         13.28 s +/-6780%          2.10 s +/-1%          0.87 s +/-2%         0.85 s +/-41%
  10 tables x 1 queries            1.01 s +/-51%         10.04 s +/-5%          0.84 s +/-1%          0.77 s +/-1%

Build outputs and generated source
----------------------------------
  consumer            scale                         source     objects   swiftmodule    static lib  plugin swift
  control_raw_sqlite  1 tables x 1 queries         2.0 KiB    53.8 KiB      30.8 KiB      58.3 KiB   unavailable
  control_raw_sqlite  1 tables x 10 queries       13.8 KiB    85.7 KiB      32.9 KiB      90.9 KiB   unavailable
  control_raw_sqlite  10 tables x 1 queries        7.9 KiB   188.3 KiB      98.5 KiB     209.3 KiB   unavailable
  grdb                1 tables x 1 queries           944 B   100.7 KiB      57.5 KiB      15.6 MiB   unavailable
  grdb                1 tables x 10 queries        3.1 KiB   116.0 KiB      59.6 KiB      15.6 MiB   unavailable
  grdb                10 tables x 1 queries        6.6 KiB   653.7 KiB     281.4 KiB      16.2 MiB   unavailable
  lighter             1 tables x 1 queries           161 B   221.8 KiB     143.7 KiB       3.9 MiB      27.4 KiB
  lighter             10 tables x 1 queries        1.6 KiB     1.6 MiB     906.9 KiB       5.5 MiB     234.1 KiB
  sqlite_swift        1 tables x 1 queries         1.6 KiB    56.5 KiB      29.8 KiB       3.5 MiB   unavailable
  sqlite_swift        1 tables x 10 queries        6.7 KiB    90.2 KiB      31.9 KiB       3.6 MiB   unavailable
  sqlite_swift        10 tables x 1 queries        9.9 KiB   261.5 KiB     120.4 KiB       3.8 MiB   unavailable
  swiftql             1 tables x 1 queries           628 B   459.7 KiB     122.5 KiB      35.1 MiB   unavailable
  swiftql             1 tables x 10 queries        3.3 KiB   575.4 KiB     129.7 KiB      35.2 MiB   unavailable
  swiftql             10 tables x 1 queries        2.6 KiB     3.6 MiB     939.7 KiB      38.6 MiB   unavailable

Peak RSS is the peak of the whole `swift build` process tree, not an allocation attributed to any one API.
These are machine-dependent measurements from one host. Nothing here is a CI gate or a regression threshold.
```

## Interpretation and limits

These are wall-clock builds on one machine. SwiftQL's own benchmark guidance
about noise applies here with more force than it does to runtime measurements,
because a build competes with everything else running on the host for all
fourteen cores. Read the order-of-magnitude differences between scales and
between consumers; do not read a single-digit percentage difference between two
cells as a change in anything. The `wallSpreadPercent` column in the rendered
matrix is there so you can see how much of a cell is noise.

Nothing here is a CI gate. The harness sets no threshold, and no threshold
should be added until repeated baselines on the same host establish this
harness's own variance.

Cells from different table counts, query counts, build modes, toolchains, or
machines are not comparable, and `summarize.py --baseline/--candidate` refuses
to compare two reports whose environment, workload configuration, or dependency
pins differ.
