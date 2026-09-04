# Query-Plan Analysis and Index Advice (v1.8)

Advisory query-plan analysis layered onto the
[#293 standalone build validator](SQLiteBuildValidationValidator.md). It
captures what SQLite plans to do with each statement in the
[#292 manifest](SQLiteBuildValidationManifest.md), and — in later stages of
this milestone — turns the plan shapes that indicate avoidable work into
diagnostics and verified index recommendations.

Everything here is advisory. No plan record, diagnostic, or recommendation
changes a correctness verdict or the validator's exit status.

The design was accepted by the
[#393 go/no-go](SQLiteQueryPlanIndexAdviceGoNoGo.md), backed by the
[EQP variance measurement](SQLiteEQPVariance.md), the
[plan-shape classifier prototype](SQLiteEQPPlanShapeClassifier.md), and the
[index-advisor prototype](SQLiteIndexAdvisor.md).

## Plan capture (#394)

### Where plans live

Plans go in a **sidecar**, never in the canonical correctness report. This is
the spike's decision, and it is what makes "plan capture never changes a
verdict" checkable rather than merely intended: `SQLiteBuildValidationReport`
has no plan field, so its schema, its verdict semantics, and its bytes are
untouched by anything in the plan pass.

```
swiftql-build-validate \
  --database    Northwind.sqlite \
  --manifest    build-validation-manifest.json \
  --output      report.json \
  --plan-output plans.json          # opt-in; omit to skip plan capture
```

`--plan-output` is the whole opt-in. Without it the validator captures no
plans, writes no sidecar, and does no extra work. With it, the run writes a
second canonical JSON file beside the report. The exit code is decided by the
correctness verdict alone.

### What a record contains

One `SQLiteBuildValidationPlanRecord` per manifest entry — never fewer. Each
carries the entry's identity (`query_id`, `definition_identity`,
`descriptor_identity`), the provenance of the SQLite that planned it, and
exactly one of two outcomes:

- `captured` — the normalised plan tree.
- `unsupported` — the reason no plan is available.

There is no third state, and no entry is ever simply absent. A statement whose
plan could not be captured is explicitly unsupported: recording it as an empty
plan would read as "SQLite planned nothing" rather than "this validator
learned nothing".

### Normalisation

A record's tree is built from each row's own `parent` id, not from row order.
SQLite's `id`/`parent` numbers are then discarded: #390 measured them as the
one field that legitimately differs between two SQLite builds planning the
same statement, and the structure they encode is already carried by the tree.
Every node keeps its raw `detail` string alongside its classification, so a
misclassification is auditable rather than silent, and detail text the
classifier does not recognise stays `unclassified` rather than being coerced
into a neighbouring shape.

### Provenance

Each record names the SQLite build that produced it: version, source ID, and
the compile options that can change a plan (statistics, the automatic-index
and LIKE optimizations, virtual-table modules that own their own plan).
Provenance is pinned into the record itself, not only the report header, so a
record lifted out of its report is still provenance-complete. Options that
cannot change a plan tree are left to the correctness report, which records
the connection's full option list.

A record without provenance is necessarily `unsupported`: a captured plan
whose SQLite is unidentified is evidence of nothing.

### Parameters are left unbound

The manifest records a statement's parameter *shape*, not the values an
application binds, so there are no values to bind and every placeholder is
left at its default `NULL`. On a snapshot without `ANALYZE` statistics — which
the pinned snapshot deliberately is — SQLite's plan choice never reads the
bound value, so the captured plan is the plan the statement gets. On a
snapshot that is both built with `SQLITE_ENABLE_STAT4` and analyzed, SQLite
can specialize a plan to a bound value, and the capture would record the
`NULL`-bound plan instead. The record's provenance carries the `ENABLE_STAT4`
option for exactly this reason, and the sidecar names the caveat in its own
`caveats` list.

### Determinism

The sidecar retains no timestamp, host identity, process identity, or path.
Records are ordered by `query_id`, so manifest ordering cannot change the
bytes. Two runs over unchanged inputs produce byte-identical output.

### Build host versus device

A plan captured on the build host is not a promise about the SQLite an
application will run against. #390 measured a materialization strategy
changing between two ordinary SQLite point releases. The sidecar states this
caveat in every report rather than leaving a reader to infer it.
