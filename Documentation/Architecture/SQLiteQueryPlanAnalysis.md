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
  [--plan-suppressions plan-suppressions.json]
  [--plan-scan-row-threshold 500]
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


## Advisory shape diagnostics (#395)

### What is diagnosed

Four plan shapes, each one the #390 measurement found identical across two
real SQLite builds for every statement that exercised it:

| Code | Fires on | What it means |
| --- | --- | --- |
| `plan.full-table-scan` | `full_table_scan` above the row threshold | SQLite reads every row of the table to answer the query. |
| `plan.temp-b-tree-order-by` | `temp_b_tree_for_order_by` | SQLite materializes a temporary B-tree because no index returns the rows in `ORDER BY` order. |
| `plan.temp-b-tree-group-by` | `temp_b_tree_for_group_by` | The same, for `GROUP BY` order. |
| `plan.correlated-scalar-subquery` | `correlated_scalar_subquery` | A scalar subquery is re-evaluated once per outer row. |

A diagnostic is keyed on the classified **shape**, never on the raw
`EXPLAIN QUERY PLAN` wording that produced it — wording is the classifier's
input, not the diagnostic's. A shape the classifier did not recognise carries
no advice, and the diagnostic type refuses to be constructed with one.

### Severity

`advisory` is its own type, `SQLiteBuildValidationPlanDiagnosticSeverity`,
rather than a fourth case on `SQLiteBuildValidationVerdict`. A verdict decides
the validator's exit status; no arrangement of the advisory type can reach
that decision. Making `advisory` a verdict case would have put "never affects
exit status" behind a convention every future `switch` has to keep. This way
it is behind the type system.

### The row threshold

A full scan is diagnosed only above `--plan-scan-row-threshold` rows, default
500. Below a few hundred rows a scan is typically a handful of page reads, and
advice about it is noise that trains a reader to ignore the findings that
matter. The row count is taken from the snapshot and recorded in the
diagnostic, so the finding can be read without re-deriving it.

The rule needs a real table, so it needs the plan node's spelling resolved.
EQP prints whichever spelling the statement used, and SwiftQL renders
`FROM "Orders" AS "t0"`, so `SCAN t0` has to become `Orders` before either a
reader or `CREATE INDEX` can use it. `SQLiteBuildValidationPlanTableResolver`
does that from the statement's own `FROM`/`JOIN` clauses, and resolves nothing
it is not confident about: a CTE name is excluded, and an alias rebound to a
different table in a nested scope resolves to neither. An unresolved alias
produces no scan diagnostic rather than one resting on an assumed table size.

### The correlated-subquery fixture, and what it changed

#395 required a **real** correlated-scalar-subquery fixture before that
diagnostic could ship, because the spike's 214-statement corpus contained
none and only a synthetic case exercised the classifier's heuristic. The
fixture this repository now carries —

```sql
SELECT p.ProductName,
       (SELECT c.CategoryName FROM Categories c WHERE c.CategoryID = p.CategoryID)
FROM Products p
```

— found that the heuristic was wrong. The spike classified a subquery as
correlated when it was *nested under a row-looping node*. On the SQLite this
repository tests against, that real correlated subquery is emitted as a
**top-level sibling** (`parent == 0`) of `SCAN p`, carrying SQLite's own
explicit `CORRELATED SCALAR SUBQUERY` detail. The heuristic alone would have
called it uncorrelated.

The classifier now reads SQLite's own word first and keeps the structural test
only as a fallback for a build that does not print it. This is exactly the
outcome the issue's extra Done-When bullet was written to force.

### Suppression

Suppression is an explicit, checked-in file, never an inference:

```json
{
  "format_version": 1,
  "suppressions": [
    {
      "code": "plan.full-table-scan",
      "table": "Categories",
      "reason": "A lookup table of eight rows; a scan is the right plan."
    },
    {
      "code": "plan.temp-b-tree-order-by",
      "query_id": "reports.monthly-export",
      "reason": "Sorted once, offline, for a report nobody waits on."
    }
  ]
}
```

Every rule names a code and at least one of a query or a table, and must state
a reason. A rule that silences every occurrence of a code is not expressible,
and neither is a silent one. A rule naming both a query and a table is
narrower than either alone, never broader.

Silenced findings are **kept** in the sidecar, under `suppressed_diagnostics`,
with the reason the repository gave. Silencing a finding is a decision, and a
decision that leaves no trace is indistinguishable from a finding that never
happened. Rules that silenced nothing are listed under `unused_suppressions`,
so a stale instruction to ignore something can be found and deleted.

### Advice is not a verdict

Advisory diagnostics are in the sidecar, and the exit code reads the
correctness verdict alone. A run with findings on every statement still exits
zero if the manifest validated. The CLI prints the advice to stderr beside the
correctness summary, and printing it changes nothing about the exit status.
