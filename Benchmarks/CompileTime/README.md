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

Macro expansion size is recorded as unavailable with a reason. The pinned
toolchain exposes no flag that writes macro expansion buffers to a stable,
machine-readable location during a SwiftPM build, and guessing a number from
whole-build timing would be exactly the fabrication this harness is meant to
avoid.

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

<!-- RESULTS -->

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
