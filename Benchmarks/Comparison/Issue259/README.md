# Fair cross-library SQLite workload families beyond full fetch

Issue [#250](https://github.com/lukevanin/swiftql/issues/250) recorded one
workload: fetch all 16,143 `Orders` rows and all 14 columns. That baseline
stays exactly as it is. This directory answers the next question, which is
[#259](https://github.com/lukevanin/swiftql/issues/259): which *other* workload
families can be compared across Swift SQLite libraries without pretending the
libraries expose the same API, and what would each of those comparisons have to
pin down to be falsifiable?

The answer has two parts. The first is a set of workload contracts and an
applicability matrix, below. The second is a working prototype that runs three
of those contracts through SwiftQL, GRDB, and SQLite.swift against the real
committed Northwind fixture in release builds, which is what turns the contracts
from a proposal into something that has actually been falsified once.

## What a workload contract has to pin down

Every contract in this document specifies all of the following, because leaving
any one of them implicit is how two libraries end up being compared on different
work:

1. **Schema and data.** Which tables, which rows, which committed fixture.
2. **Semantics.** The exact predicate, join, grouping, ordering, or mutation.
3. **Selected columns.** Both how many and which ones.
4. **Bindings.** Which values are bound parameters and which are literals.
5. **Transaction boundary.** Where a transaction opens and where it commits.
6. **Connection and statement lifecycle.** Whether the connection is opened
   once, and whether a prepared statement is reused between iterations.
7. **Value representation.** The Swift type each column decodes into, including
   nullability and any cast.
8. **Correctness oracle.** A state check and a value checksum, both computed
   outside the timed interval, and both compared against an expectation derived
   independently of the library being measured.
9. **Warmup and sampling.** Warmups, timed samples, and independent processes.
10. **Applicable APIs.** Which tier of each library's surface is being used, and
    which libraries have no equivalent at all.

## Timing boundaries: what turned out to be comparable

#259 asked for construction/rendering, cold preparation, cached lookup, binding,
execution, decoding, observation delivery, and end-to-end timing to be separated
"where APIs expose comparable seams". Working through the three libraries'
public surfaces, they do not.

SwiftQL can separate all of those seams, and
[BENCHMARKS.md](../../../BENCHMARKS.md) already does exactly that for SwiftQL
alone through its own six-phase harness. GRDB exposes `makeStatement`,
`cachedStatement`, `setArguments`, and row iteration, so a three-way split is
reachable there. SQLite.swift's typed query path builds SQL, prepares, binds,
steps, and decodes inside `prepare`/`pluck`/`run`, and exposes no public seam
between them. Lighter's generated accessors expose none either.

So a cross-library phase breakdown would have to compare SwiftQL's measured
phases against numbers reconstructed by subtraction for the other libraries,
and subtraction across different implementations is exactly the "fabricated
attribution" this project already refuses elsewhere. The prototype therefore
times end to end only, and the report records `timedBoundary: end_to_end_only`
along with the reason. Per-phase work stays inside each library's own harness.

## Workload families

### Prototyped

These three have running implementations in `Prototype/` and recorded samples.

#### `point_lookup`

Fetch all 14 `Orders` columns for one `OrderID`, decoded into the shared row
shape. Keys rotate through a fixed set of 256 identifiers (`10248 + 63n`), all
of which exist because `Orders.OrderID` is a contiguous `INTEGER PRIMARY KEY
AUTOINCREMENT` range in the fixture. Exactly one row comes back, and every
iteration verifies that the returned `OrderID` is the key that was bound.

The value oracle is an FNV-1a fold over all 14 decoded fields, computed on the
first and final iteration only and compared against the same fold applied to a
row read independently through the SQLite C API. Comparing against an
independent expectation rather than against the first iteration is what allows
the bound key to change on every iteration; the #250 harness could avoid that
problem only because it binds nothing.

Representation: `Int` for `OrderID`, `String?` for the three `DATETIME` columns,
`Double?` for `Freight`. SQLite.swift's typed decoder rejects an INTEGER for a
`Double?` expression and `Orders.Freight` is a NUMERIC column with 4,130 INTEGER
and 12,013 REAL values, so its typed query casts `Freight` to REAL. That is the
same disclosed difference the #250 harness carries.

Lifecycle: one connection, opened before warmup. Statement reuse differs by
library and is not equalised; see the applicability matrix.

#### `join_aggregate`

Inner-join `Orders` to `Customers` on `CustomerID`, group by
`Customers.Country`, and return `COUNT(Orders.OrderID)` and
`TOTAL(Orders.Freight)` per group, ordered by country ascending. Exactly 22
groups come back, including the group for the two customers whose `Country` is
NULL, which is deliberate: a workload that quietly drops NULL groups would hide
a real semantic difference between libraries.

`TOTAL()` rather than `SUM()`, because `TOTAL()` always returns REAL and never
NULL, so no library has to express a coalesce the others do not. The checksum
rounds the total to cents before folding, so the oracle does not depend on the
last ulp of a floating-point accumulation order that SQLite is free to change.

#### `transactional_write`

Insert the same deterministic 100-row batch into a dedicated scratch table
inside one explicit transaction, and commit. The scratch table is created
outside timing in a per-process copy of the fixture, and the batch is deleted
between iterations, also outside timing, so committed state is identical before
every measured transaction. Timing covers begin, 100 parameterised inserts, and
commit.

The oracle reads the committed rows back through the SQLite C API and compares
them against a checksum of the batch that the harness knows it asked for, so a
library that silently coerced a value would fail rather than produce a fast
number.

Each write process gets its own copy of the database. The read workloads share
one copy, and the runner re-verifies that copy's SHA-256 after every process has
finished, which is what proves no read workload mutated the data underneath a
later sample.

### Researched, not prototyped

#### `observation`

GRDB has `ValueObservation`, SwiftQL has `publish()`/`publishOne()` over
OpenCombine, SQLite.swift 0.16 has no observation API at all, and Lighter's
generated accessors have none. Two of four libraries can be compared, and even
those two do not agree on what an observation delivers: GRDB's
`ValueObservation` coalesces and re-fetches on its own scheduler, and SwiftQL's
publisher has its own delivery contract and refuses to run inside a transaction
scope.

A fair observation workload therefore cannot measure "time to deliver an
update" as one number. It has to measure a *pipeline* with an explicit
definition of the start event (the committing write), the end event (the
subscriber receiving a value whose checksum matches the post-write state), and
the scheduler both libraries are pinned to. It also has to state a coalescing
policy, because a library that coalesces two writes into one delivery is doing
less work by design and not by accident.

This is comparable, but only for GRDB and SwiftQL, and only with a
delivery-latency contract rather than a throughput one. It is the workload with
the highest design cost per unit of information, so it should follow the
cheaper ones.

#### `concurrency`

The libraries do not share a concurrency model. GRDB's `DatabasePool` gives
WAL-mode concurrent readers with one writer; `DatabaseQueue` serialises
everything. SwiftQL's v1 driver pins one connection for a transaction scope and
documents that re-entering the pool from inside an open transaction is
rejected. SQLite.swift's `Connection` is a single serialised connection.

A concurrency comparison is only meaningful once the *journal mode*, the
*connection topology*, and the *reader count* are pinned identically, and even
then it compares configurations more than libraries. It is worth doing, but as
a scaling curve (N concurrent readers against one writer, WAL mode, same pool
size) rather than as a single number, and the report has to say that a library
whose topology cannot be configured to match is absent from the curve rather
than plotted at its default.

#### `decoding`

Decoding cost is already partly visible: #250's `grdb_manual` versus
`grdb_codable` pair isolates GRDB's `Codable` overhead on one workload, and
SwiftQL's own phase harness measures its `row_decoding` phase directly.

What is not comparable is decoding *in isolation* across libraries, because
none of them exposes a public seam that hands you a materialised row and lets
you decode it separately. The reachable version is a *representation matrix*:
run the same point lookup with column sets chosen to isolate one representation
at a time (all-INTEGER, all-TEXT, all-nullable, wide 14-column) and read the
differences between those cells within one library, then compare the *shapes*
of the curves across libraries rather than their absolute values. That is a
genuine finding and it needs no new seam.

#### `cold_startup`

Cold start is the one family where the #250 method actively cannot be reused,
because that method's whole design is to warm up first. A cold-start workload
measures process launch through first decoded row, once per process, with an
evicted page cache, which means one sample per process and therefore tens of
processes to get a usable distribution.

It is comparable across all four libraries, and it is the workload where
SwiftQL's macro-generated static descriptors and Lighter's generated accessors
would be expected to differ most from a runtime query builder. It needs its own
runner rather than an extension of the existing one: a single-sample-per-process
harness with explicit cache-state control has almost nothing in common with a
100-sample warm loop.

## Applicability and fairness matrix

`typed` means the library's own type-checked query surface. `raw SQL` means
hand-written SQL through the library's row API. `absent` means the library has
no such API at any tier.

| Workload | SwiftQL | GRDB | SQLite.swift | Lighter | Comparable? |
| --- | --- | --- | --- | --- | --- |
| `point_lookup` | typed declared query | typed record request | typed query builder | typed generated accessor | Yes, with the `Freight` cast disclosed |
| `join_aggregate` | typed builder | raw SQL | typed builder | absent | Yes, with GRDB's tier disclosed |
| `transactional_write` | typed transaction scope | typed persistable record | typed query builder | absent (read-only generation) | Yes |
| `observation` | publisher | `ValueObservation` | absent | absent | Only SwiftQL and GRDB, and only as delivery latency |
| `concurrency` | pinned-connection scope | pool or queue | single connection | single connection | Only as a curve over a pinned topology |
| `decoding` | measurable in isolation | partly (manual vs Codable) | not in isolation | not in isolation | Only as a representation matrix, not as a phase |
| `cold_startup` | typed | typed | typed | generated | Yes, but needs a one-sample-per-process runner |

Three entries deserve their reasons stated rather than just a cell:

- **GRDB at `raw SQL` for `join_aggregate`.** GRDB's typed association path
  needs `belongsTo` associations declared on the record types. That changes the
  declaration surface rather than the query surface, so it is a different tier
  from SwiftQL's inline typed join. Running GRDB at the raw-SQL tier is the
  honest choice, and it flatters GRDB rather than SwiftQL, which is why it is
  safe to leave until the typed-association tier is added. See the follow-up.
- **Lighter absent from `join_aggregate` and `transactional_write`.** Lighter
  generates accessors from a schema; it has no user-written join, aggregate, or
  insert expression to measure, and the #250 harness already runs it in
  read-only generation mode.
- **SQLite.swift absent from `observation`.** Version 0.16.0 ships no
  observation API. Timing a hand-rolled polling loop against
  `ValueObservation` would compare a workaround to a feature.

## Run the prototype

```sh
python3 Benchmarks/Comparison/Issue259/run.py \
  --workspace /private/tmp/swiftql-issue259 \
  --swiftql-checkout "$PWD" \
  --output Benchmarks/Comparison/Issue259/prototype-results.json \
  --cooldown-seconds 60
```

The workspace must be new or empty. The runner verifies the committed fixture
through #250's own verification code rather than a second copy of it, builds
the release prototype, waits out the cooldown, and then runs each workload and
implementation in its own process with the implementation order rotated per
process. `--prepare-only` stops after preparing the graph.

Validate and render:

```sh
python3 Benchmarks/Comparison/Issue259/summarize.py \
  Benchmarks/Comparison/Issue259/prototype-results.json
```

Validation reparses every raw sample log, checks its hash, recomputes every
median, p95, throughput, and spread, and rejects a report that omits its API
tiers, its timing boundary and reason, or its relationship to #250.

Run the harness tests with:

```sh
python3 -m unittest discover -s Benchmarks/Comparison/Issue259 -p 'test_*.py'
```

## Recorded prototype results

[`2026-08-02-mac16-8.json`](2026-08-02-mac16-8.json) was recorded at
`2026-08-01T22:46:33Z` from clean SwiftQL revision
`106ad457bd3f0531e402157028364bee09380005`, after the release build and a
60-second cooldown. It links 27 raw sample TSVs and 27 `/usr/bin/time -l`
resource logs under [`Runs/`](Runs/), preserving all 2,700 timed samples and
their verified SHA-256 values. The graph pins GRDB 6.29.3, SQLite.swift 0.16.0,
SwiftSyntax 509.1.1, and OpenCombine 0.14.0.

The run used a Mac16,8 with Apple M4 Pro, 14 cores, 24 GiB memory, arm64
macOS 26.5.1 (25F80), Xcode 26.5, Swift 6.3.2, and system SQLite 3.51.0.

### `point_lookup`

| Implementation | API tier | Median | p95 | Lookups/s | Process spread | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| GRDB | typed record request | 51.92 us | 58.04 us | 19,262 | 3.0% | 9.9 MiB |
| SQLite.swift | typed query builder | 35.29 us | 39.83 us | 28,335 | 3.7% | 9.0 MiB |
| SwiftQL | typed declared query | 44.33 us | 53.58 us | 22,557 | 6.3% | 10.8 MiB |

### `join_aggregate`

| Implementation | API tier | Median | p95 | Queries/s | Process spread | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| GRDB | raw SQL row mapping | 9.86 ms | 10.12 ms | 101 | 2.0% | 16.9 MiB |
| SQLite.swift | typed query builder | 9.71 ms | 9.94 ms | 103 | 1.1% | 16.0 MiB |
| SwiftQL | typed query builder | 10.23 ms | 10.49 ms | 98 | 0.4% | 18.5 MiB |

### `transactional_write`

| Implementation | API tier | Median | p95 | Rows/s | Process spread | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| GRDB | typed persistable record | 620.35 us | 730.46 us | 161,198 | 2.0% | 9.3 MiB |
| SQLite.swift | typed query builder | 1.04 ms | 1.16 ms | 96,119 | 5.2% | 8.5 MiB |
| SwiftQL | typed transaction scope | 1.50 ms | 1.67 ms | 66,880 | 1.2% | 10.3 MiB |

### What these three prototypes showed

The point lookup separates the three libraries by 20-45%, against process
spreads of 3-6%, so the ordering is outside noise on this host. That is the
result which most justifies building the family, because the full-fetch baseline
amortises every per-call cost over 16,143 rows and cannot see it at all. The
point lookup also exercises binding, which the baseline never does.

The join/aggregate separates them by 5% against spreads of 0.4-2%. The work is
dominated by SQLite scanning 16,143 rows and grouping them, so which API the
caller used barely registers. That is itself worth recording: a workload whose
cost is dominated by the engine discriminates poorly between libraries, and this
family is worth implementing for its semantic coverage (joins, grouping, NULL
groups, aggregate representation) rather than as a speed comparison.

The transactional write separates SwiftQL from GRDB by 2.4x, far outside the
1-5% spreads. SwiftQL's `sqlInsert(_:)` builds a fresh insert statement per row
inside the transaction scope, where GRDB's `PersistableRecord.insert` reuses a
cached statement. That is a reproducible cost on the write path and exactly the
kind of thing the full-fetch baseline was never going to surface. It is
reported here as a workload-design finding rather than a regression, since no
earlier measurement of this path exists to regress against.

Peak RSS is the whole process, including the executable, its dependency graph,
the connection, and retained results, so it is not an allocation attributable to
any one API. The three libraries stay within a few MiB of each other on every
workload.

## Recommendation

Build the shared harness first, then the three prototyped families, each as its
own shippable piece rather than as one bundle. Every item below has its own
issue under the
[Cross-library workload benchmark suite](https://github.com/lukevanin/swiftql/milestone/31)
milestone, with the ordering recorded as GitHub dependencies.

1. **[#508](https://github.com/lukevanin/swiftql/issues/508) shared workload
   harness.** The prototype had to add a per-iteration bound parameter, an
   independent value oracle per parameter, per-process writable database copies,
   and an API-tier record. Every family below needs those, so they belong in one
   place.
2. **[#509](https://github.com/lukevanin/swiftql/issues/509) `point_lookup`.**
   Cheapest to make fair, the only family that exercises binding, and the one
   with the clearest separation between libraries.
3. **[#510](https://github.com/lukevanin/swiftql/issues/510)
   `transactional_write`.** The existing baseline has no write path at all, and
   transaction boundaries are the part of a database API most likely to differ
   semantically rather than only in speed.
4. **[#511](https://github.com/lukevanin/swiftql/issues/511)
   `join_aggregate`.** Worth building for semantic coverage of joins, grouping,
   and NULL groups, and it is the family where GRDB needs a second tier.
5. **[#512](https://github.com/lukevanin/swiftql/issues/512) `decoding` as a
   representation matrix.** Nearly free once `point_lookup` exists, since it
   reuses that contract with different column sets.
6. **[#513](https://github.com/lukevanin/swiftql/issues/513) `cold_startup`.**
   Needs its own one-sample-per-process runner with explicit cache-state
   control.
7. **[#514](https://github.com/lukevanin/swiftql/issues/514) `concurrency`.** A
   reader-scaling curve over a pinned topology, not a single number.
8. **[#515](https://github.com/lukevanin/swiftql/issues/515) `observation`.**
   Last: the highest design cost and the fewest covered libraries.

Do not build a single aggregate score across these families. Each one answers a
different question, and a library that wins the point lookup can lose the write
without either result being wrong.

## Limits

The prototype records three independent release processes per cell on one
machine, with 10 warmups and 100 timed samples each, and retains every raw
sample. That is enough to establish that the contracts are implementable and
that their oracles hold; it is not enough to declare a winner. Read the process
spread column before reading any difference: a gap smaller than the larger of
the two spreads being compared is noise on this host, and this project's
benchmark machine is documented as noisy.

Nothing in this directory is a baseline, a threshold, or a CI gate. The #250
report remains the only recorded cross-library baseline.
