# SQLite `EXPLAIN QUERY PLAN` variance measurement (issue #390)

Milestone 29, "Spike: SQLite query-plan analysis and index advice." This
document is the measurement write-up issue #390 asks for: how much does
`EXPLAIN QUERY PLAN` (EQP) output vary across the SQLite builds SwiftQL
actually encounters, and which properties of that output are stable enough
to build advisory diagnostics on. It is evidence and a recommendation, not a
diagnostic, a report schema, or a public API - see [Non-goals](#non-goals).

## Inputs audited

- [`Conformance/SQLite/COMBINATORIAL_CASES.json`](../../Conformance/SQLite/COMBINATORIAL_CASES.json)
  - issue #191's 208-case pairwise/targeted SELECT corpus, reused unmodified
  via `SQLiteCombinatorialSuite.makeManifest()`.
- [`Tests/SwiftQLNorthwindFixtures/Resources/Northwind/`](../../Tests/SwiftQLNorthwindFixtures/Resources/Northwind)
  - issue #254's pinned, checksum-verified Northwind snapshot.
- [`Tests/SQLTests/NorthwindSemanticCorpusTests.swift`](../../Tests/SQLTests/NorthwindSemanticCorpusTests.swift)
  - the only place in the repo defining Northwind join/CTE/subquery shapes as
  literal SQL; six of those shapes are cribbed verbatim as this corpus's
  Northwind anchor statements (`EQPVarianceCorpus.northwindAnchorStatements()`).
- [`Research/SQLiteBuildValidation/Sources/SwiftQLSQLiteBuildValidationPrototype/SQLiteBuildValidationRuntime.swift`](../../Research/SQLiteBuildValidation/Sources/SwiftQLSQLiteBuildValidationPrototype/SQLiteBuildValidationRuntime.swift)
  - issue #132's capability-audit capture (`sqlite_version()`,
  `sqlite_source_id()`, `PRAGMA compile_options`, `function_list`,
  `collation_list`, `module_list`, a schema fingerprint), reused as-is for
  every capture's runtime provenance.

## Question and non-goals

**Question:** how much does EQP output move across SQLite versions, along
which axes, and which properties can advisory tooling trust?

**Non-goals**, per this issue's hard constraints:

- No diagnostics, candidate generation, report schema, or public API. That is
  #391/#392/the v1.8 issues, contingent on this write-up's recommendation.
- No mutation of the pinned Northwind snapshot. Every capture in this
  pipeline opens a validator-owned copy read-only with `PRAGMA query_only =
  ON`; the pinned file's SHA-256 (`cb6f0071…3381d8`) is asserted unchanged
  after every run (`EQPVarianceCaptureTests.testCaptureNeverMutatesThePinnedNorthwindSnapshot`).
- No conclusion drawn from a single SQLite version or a single host (see
  [Methodology](#methodology)).
- Honest `unsupported` results where a version isn't reachable, not
  interpolation (see [Coverage and limitations](#coverage-and-limitations)).

## Methodology

**Corpus** (`EQPVarianceCorpus.assemble()`, 214 statements, deterministic -
`EQPVarianceCorpusTests.testCorpusAssemblyIsDeterministic`):

- 208 statements from the #191 combinatorial manifest, verbatim
  (`rendered_sql` + resolved `bindings`, unmodified).
- 6 hand-authored Northwind anchor statements the pairwise grid doesn't
  itself exercise against real data: a five-table inner join, a self
  left-join with NULLs, `GROUP BY`/`HAVING`, a scalar subquery, a `UNION`
  compound, and a `WITH` aggregate CTE - each tagged with its
  `SQLiteNorthwindConformanceCaseID` from #254's registry.

**Capture** (`EQPVarianceCapture.capture(from:corpus:label:)`): for every
statement, binds the same resolved values the #191 harness uses
(`arguments(for:)`, mirroring `SQLiteCombinatorialConformanceTests`), runs
`EXPLAIN QUERY PLAN <rendered_sql>`, and records every row's `id`, `parent`,
`notused`, and `detail` verbatim - plus the #132 runtime metadata from the
same connection. Two capture methods feed the same schema
(`EQPCaptureRun`/`EQPStatementCapture`/`EQPRow` in `EQPVarianceModels.swift`):

1. **In-process, GRDB** (`swift run SwiftQLSQLiteEQPVarianceCLI capture`) - whatever SQLite
   the Swift toolchain links (this repo's system libsqlite3, unpinned).
2. **Out-of-process, Python's `sqlite3` module**
   (`Research/SQLiteBuildValidation/Scripts/capture_eqp.py`) - a second,
   genuinely distinct SQLite build reachable without vendoring a custom
   SQLite into the shipping package. The script ports the #132 runtime-
   metadata capture (including the FNV-1a-64 schema fingerprint) into Python
   field-for-field; both captures against a copy of the pinned snapshot
   produced the identical fingerprint `e2c8fadbd38c2313`, cross-validating
   the port and confirming both runs saw byte-identical schemas.

**Classification** (`EQPVarianceClassifier`): compares two capture runs
statement-by-statement. Row `id`/`parent` values are first renumbered to
their position in emission order (EQP always emits a parent before its
children, so this is a valid, order-preserving renumbering) before any other
comparison - see [why](#finding-1-idparent-numbering-is-not-a-stable-identifier).
Remaining differences are bucketed into the classes below by pattern-matching
`detail` text for table/access-method tokens and known materialization
markers (`SEARCH`/`SCAN`, `USING INDEX`, `TEMP B-TREE`, `MERGE (`, etc.).

## Evidence: two real SQLite builds, one pinned corpus

| | Build A | Build B |
|---|---|---|
| Label | `apple-system-3.51.0` | `homebrew-3.53.2` |
| `sqlite_version()` | 3.51.0 | 3.53.2 |
| `sqlite_source_id()` | 2025-06-12 13:14:41 f0ca7bb… | 2026-06-03 19:12:13 d6e03d8… |
| Capture method | in-process, GRDB (Swift toolchain's linked SQLite) | out-of-process, `python3`'s `sqlite3` module (Homebrew's `libsqlite3`) |
| Schema fingerprint | `e2c8fadbd38c2313` | `e2c8fadbd38c2313` (match) |
| Statements captured | 214 | 214 |

Checked-in evidence (`Research/SQLiteBuildValidation/Tests/SwiftQLSQLiteEQPVariancePrototypeTests/Evidence/`):
`corpus.json`, `capture_apple-system-3.51.0.json`, `capture_homebrew-3.53.2.json`,
`comparison_apple-system-3.51.0_vs_homebrew-3.53.2.json`.

### Classification result (214 statements)

| Class | Count | Stable enough for diagnostics? |
|---|---:|---|
| `identical` | 203 | Yes - byte-identical, including `id`/`parent` |
| `id_renumbering_only` | 2 | Structure only - see Finding 1 |
| `materialization_strategy_change` | 9 | No - see Finding 2 |
| `access_path_change` | 0 (not observed) | Not evaluated by this pair |
| `join_order_change` | 0 (not observed) | Not evaluated by this pair |
| `cosmetic_wording_change` | 0 (not observed) | Not evaluated by this pair |
| `unclassified` | 0 | - |

### Finding 1: `id`/`parent` numbering is not a stable identifier

Two statements - the five-table Northwind join
(`c390.northwind.join.customer-order-employee-product`) and the scalar-
subquery Northwind case (`c390.northwind.subquery.products-above-average`) -
produced **identical plan structure and `detail` text** on both builds, but
every `id` and `parent` value was offset by a constant (e.g. `9→12`,
`12→15`, `18→21`, …). The chosen indexes, join order, and access methods were
completely unaffected; only SQLite's internal EQP row-numbering counter
differed. **Any future diagnostic must key on structure (parent shape plus
`detail` text) and never on raw `id`/`parent` values.**

### Finding 2: compound-query execution strategy changed between builds

All 9 `materialization_strategy_change` cases are #191's CTE ×
compound-operator cases (`UNION`/`EXCEPT`/`INTERSECT` over ordinary and
recursive CTEs). 3.51.0 renders the older `COMPOUND QUERY` /
`LEFT-MOST SUBQUERY` / `<OP> USING TEMP B-TREE` shape; 3.53.2 renders a
`MERGE (<OP>)` / `LEFT` / `RIGHT` shape with `USE TEMP B-TREE FOR ORDER BY`
attached differently. Example (`c191.v1.cte.ordinary-nullable.union`):

```
# apple-system-3.51.0
COMPOUND QUERY
├─ LEFT-MOST SUBQUERY
│  ├─ CO-ROUTINE nullable_seed
│  │  └─ SCAN CONSTANT ROW
│  └─ SCAN nullable_rows
└─ UNION USING TEMP B-TREE
   └─ SCAN CONSTANT ROW

# homebrew-3.53.2
MERGE (UNION)
├─ LEFT
│  ├─ CO-ROUTINE nullable_seed
│  │  └─ SCAN CONSTANT ROW
│  ├─ SCAN nullable_rows
│  └─ USE TEMP B-TREE FOR ORDER BY
└─ RIGHT
   └─ SCAN CONSTANT ROW
```

Both are legitimate plans for the same query; SQLite changed how it *executes*
compound queries between these versions. This is real evidence that
materialization/execution-strategy diagnostics are the least stable of the
four axes named in this issue, at least for compound queries. **This is
exactly the class of variance SQLite explicitly does not promise stability
on**, and would show up as false-positive "regression" noise in any
per-plan-shape diagnostic keyed on this wording.

For the other 205 statements (203 identical + 2 renumbered), the chosen
index, join order, and access method were completely stable across this
version pair - including the five-table join, the self left-join, the
`GROUP BY`/`HAVING`, and the `UNION`/CTE Northwind anchors that were not
compound-CTE cases.

## Coverage and limitations

This pass measured two real, distinct SQLite builds reachable from this
delivery's environment directly (no custom SQLite build, no vendored
amalgamation): the system libsqlite3 this repo's Swift toolchain links, and
Homebrew's separately-installed libsqlite3. It did **not** capture the
additional builds this repo's CI matrix (`.github/workflows/swift.yml`)
actually reaches - Linux's custom-built SQLite 3.53.3
(`compatibility` job), or the system SQLite bundled with Xcode 16.2, 16.4,
26.3, and 26.5 (`apple-clean-resolution` job) - because provisioning those
Xcode versions or a from-source SQLite build was out of scope for this pass.
Per this issue's hard constraint, that is recorded as **honestly not
reachable in this delivery**, not interpolated from the two builds that were
measured. `swift run SwiftQLSQLiteEQPVarianceCLI capture` is a small, self-contained CLI
already wired to run inside any of those CI legs unchanged; wiring an actual
CI step to capture and archive that evidence is left as follow-up (recorded
for #393 to schedule against a milestone).

No conclusion here should be read as "SQLite's query planner is stable
across arbitrary versions" - only that it was stable, for this specific
214-statement corpus, across these two specific builds, except for compound
queries.

## Recommendation

1. **Plan records belong in a sidecar, not the canonical report.** EQP output
   is not a stability contract (SQLite's own documentation says so), and
   Finding 2 demonstrates real, version-driven variance for at least one
   query shape family even between two builds ~a year apart. Folding raw EQP
   into the canonical validation report (`SQLiteBuildValidationReport`) would
   make report diffs noisy across environments for reasons unrelated to
   SwiftQL. A sidecar (opt-in, clearly advisory) keeps that noise out of the
   pass/fail contract.
2. **`id`/`parent` must never be used as a diagnostic key.** Any classifier
   or diagnostic built in #391 must normalize on structure (Finding 1) before
   comparing captures, exactly as `EQPVarianceClassifier.normalize` does here.
3. **Materialization-strategy diagnostics need the widest safety margin.**
   Of the four axes, this pass found real variance only in materialization
   strategy (compound-query execution), and only for compound-CTE queries.
   Access-path and join-order diagnostics were not observed to vary in this
   pair; #391/#392 should not assume this generalizes to a wider version
   matrix, and should re-check against whatever additional builds a future
   CI-wired capture reaches.
4. **Proceed to #391** (normalised plan capture and shape classification)
   using this corpus, capture pipeline, and the renumbering-first comparison
   discipline established here.

## Reproducing this evidence

```bash
# In-process capture (whatever SQLite this Swift toolchain links)
swift run SwiftQLSQLiteEQPVarianceCLI export-corpus --output corpus.json
swift run SwiftQLSQLiteEQPVarianceCLI capture \
  --database path/to/northwind-copy.db --label <label> --output capture.json

# Out-of-process capture against a different installed SQLite build
python3 Research/SQLiteBuildValidation/Scripts/capture_eqp.py \
  --corpus corpus.json --database path/to/northwind-copy.db \
  --label <label> --output capture.json

# Classify the difference between two captures
swift run SwiftQLSQLiteEQPVarianceCLI compare \
  --baseline capture_a.json --comparison capture_b.json --output comparison.json
```

`EQPVarianceCaptureTests.testCheckedInAppleSystemEvidenceMatchesWhenRuntimeIsIdentical`
re-runs the in-process capture on every `swift test` invocation and asserts
byte-identity with the checked-in `apple-system` evidence - but only when the
host's linked SQLite version and source ID match the pinned evidence exactly;
otherwise it skips with an explicit message naming both versions, rather than
failing CI legs that (correctly, per this issue) link a different SQLite.
