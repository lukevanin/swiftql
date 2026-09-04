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

## Index-candidate generation (#396)

### What motivates a candidate

Two plan shapes. A `full_table_scan` is the obvious one: nothing indexes the
table yet. `automatic_covering_index` belongs beside it because it is SQLite's
own ephemeral workaround for the same situation — it builds and throws away a
covering index on every execution, which is exactly what a persistent index
replaces. The spike's re-plan evidence found the second shape necessary;
without it, the one real improvement it measured would never have been
proposed.

Only **root** plan nodes are considered. Remediating a scan nested inside a
subquery needs that subquery's own `FROM` scope, which the extractor does not
track, so it is out of scope rather than guessed at.

### Column order

The settled rule, in one line:

> equality-and-join-key columns → at most one range column → `ORDER BY` columns

A **join key is an equality constraint too**. SQLite seeds a seek on it once
per outer row exactly as it would from a `WHERE` equality; it just supplies the
bound value at run time instead of from the statement text. So the two share
the leading tier.

At most one range column, because SQLite stops narrowing at the first range
term — a second range column adds width without adding selectivity.

This is measured, not assumed. On `Categories LEFT JOIN Products ON
p.CategoryID = c.CategoryID WHERE p.UnitPrice > 20`, with `Products` on the
looked-up side and no index on either column:

- `Products(CategoryID, UnitPrice)` — join key first — is the index SQLite
  adopts, replacing its own ephemeral automatic index.
- `Products(UnitPrice, CategoryID)` — range first — is **silently ignored**;
  the after-plan comes back byte-for-byte identical to the baseline.

A composite index can only be seeded by an equality prefix.

### Direction and collation

`ORDER BY` terms carry their `ASC`/`DESC` and `COLLATE` into the candidate,
because both decide whether the index can satisfy the sort, and both are
rendered into the DDL.

Ordering is positional: an index satisfies a sort only from the first term
onwards. So a term the extractor cannot read as a plain qualified column — an
expression, a bare unqualified column, a term belonging to another table —
**ends** the tier rather than being skipped. Skipping it would produce a column
list that claims to satisfy an ordering it does not.

### Deduplication and prefix collapse

Candidates with the same table and the same columns merge, recording every
contributing statement so a shared index is visibly shared. A candidate whose
columns are an exact prefix of a wider one on the same table is then dropped —
the wider index already serves every query the prefix would. Before it goes,
its source statements fold into every wider candidate it prefixes, so a
statement that only ever produced the narrow index is still attributed to the
one that now serves it.

### Determinism

Candidates sort by table then columns, source lists are sorted and
deduplicated, and the representative statement is the **lexicographically
first** source rather than whichever was discovered first. Discovery order
follows manifest order; this artifact's bytes must not.

### Bounds, declines, and what is never silent

Three stated bounds, each reported when hit rather than applied quietly: at
most 6 columns per candidate, 4 candidates per statement, and 4 per table. A
truncated set that says nothing about being truncated reads as a complete
answer, which is the one thing it is not.

A remediable node this generator cannot read confidently produces a **decline**
with its reason — an alias the `FROM`/`JOIN` clauses do not resolve, a
statement with nothing to index, an `ORDER BY` whose terms could not be read.
Recording the decline keeps "no candidate" distinguishable from "no problem".

### Proposals, not recommendations

Nothing in this stage opens a database, creates an index, or decides that a
candidate is worth taking. A candidate is a proposal. Verification is #397's,
and only a verified candidate may be reported as recommended.

## Candidate verification (#397)

A candidate is a guess until something tries it. Verification is what turns it
into evidence, and it is opt-in:

```
swiftql-build-validate … --plan-output plans.json --verify-index-candidates
```

### The scratch copy

Verification has to create indices, and the one database it may never create
them in is the snapshot the build is validated against. Each candidate
therefore gets its own disposable copy:

- The copy lives in the **system temporary directory**. A scratch parent
  beside the snapshot, or inside the working directory, is refused explicitly
  — a stray `.sqlite` next to a checked-in snapshot is confusing, and one
  inside a source tree ends up committed.
- The copy is removed on every exit path. `defer` covers a normal return and a
  thrown error; a `SIGINT`/`SIGTERM` handler `unlink`s the registered paths and
  re-raises the signal with its default disposition. The handler reads a
  preallocated C-string table and calls `unlink`, both async-signal-safe;
  `FileManager` would not be. `SIGKILL` cannot be caught by anything, and what
  it leaves behind is in the system temporary directory the OS reclaims, never
  in the source tree.
- Afterwards, the pinned snapshot's byte count and SHA-256 are compared to
  what they were before. A difference is an error, not a warning.
- **One copy per candidate**, so one candidate's index can never change the
  plan another is judged by.

The connection is a `DatabaseQueue` this pass opens and closes. Verification
never runs against an application connection or a long-lived pool.

### The improvement rule

Stated once, applied uniformly, and recorded in the report by version
(`swiftql-index-improvement-rule-v1`) so a recommendation stays readable after
the rule changes.

A candidate is kept only when **all** of the following hold for the plan node
of the candidate's representative alias:

1. the before-plan shape is `full_table_scan` or `automatic_covering_index`;
2. the after-plan shape is `index_search` or `covering_index_scan`;
3. the after-plan node reports at least one constrained column — proving the
   index narrows the scan rather than merely existing;
4. the index SQLite names in the after-plan is **this candidate's own**.

The fourth clause is what stops a candidate being credited for an improvement
some other index produced.

No cost estimate or row-count comparison enters the rule. The pinned snapshot
is deliberately unanalyzed, so a structural shape change is the only signal
available that is not itself a guess.

### What a recommendation carries

A before-plan, the DDL, and an after-plan, bound to the statement's `query_id`
and `descriptor_identity`. A recommendation that only said "add this index"
would ask a developer to take it on trust; the triple is a reviewable artifact
they can judge without re-deriving the reasoning.

Each one also carries a **write-cost note**. An index is not free, and advice
that shows only the read side invites adding one to a table whose writes matter
more than the scan it removes.

### Rejections are reported

A candidate the rule declined appears under `unverified` with its reason, and —
when the plans were captured and the rule simply rejected them — with the
before and after plans that led to the decision. A candidate that vanishes
silently is indistinguishable from one that was never generated, and the reason
it failed is often the more useful half of the answer.

A candidate that could not be verified at all is likewise reported unverified.
It is never recommended.

### Still advisory

`index_recommendations` being absent and being empty are different answers: the
first means verification was not requested, the second that everything was
tried and nothing survived. Neither affects the exit status, which reads the
correctness verdict alone.

## The swiftql-index-advisor codemod (#399)

### The review-then-apply workflow

1. A build with plan analysis opted in prints advisory warnings carrying the
   verified `CREATE INDEX` statement (#398).
2. `swiftql-index-advisor --plan-report <sidecar>` prints every verified
   recommendation with its evidence — before-plan, after-plan, the reason the
   rule accepted it, and the write cost — plus every candidate verification
   rejected, with the reason. This is the default mode and it **changes
   nothing**.
3. When the advice looks right, `--apply --output <path>` writes it as a
   generated SQL artifact, and the developer reviews that diff like any other.

```
swiftql-index-advisor --plan-report plans.json                      # report
swiftql-index-advisor --plan-report plans.json \
                      --apply --output Sources/App/AdvisedIndices.sql
```

`--apply` requires `--output`, so the command can only ever write to a path
the invocation named. No flag, no write.

### Why this is not an Xcode fixit

A fixit would be better, and it is unreachable. A SwiftPM build-tool plugin
emits diagnostics, not fixits. A Swift fixit would have to come from a macro,
and a macro cannot open a database without breaking hermetic, incremental
builds — the very properties the build validator exists to preserve. So the
honest equivalent is one explicit invocation that a developer runs and whose
diff they approve. A build never rewrites source.

### Why SQL rather than a rewritten declaration

The issue asks for a SwiftSyntax rewrite of the declaration site *where a
typed index declaration surface exists*. It does not exist yet — typed DDL is
v2 work (#139) — and there is nothing for SwiftSyntax to edit without
inventing API here. So the command generates a standalone SQL artifact and
says so, in the artifact's own header. When the typed surface lands, the
rewrite replaces the renderer; the command's contract does not change.

The generated statements use `CREATE INDEX IF NOT EXISTS`, because the
artifact is meant to run against a real database repeatedly and the second run
must do nothing. Verification uses the plain form on purpose: an index that
already exists on a scratch copy means the copy was not clean, and that must
fail rather than pass quietly.

### Idempotence

Apply mode is a pure function of the recommendations — no clock, no host, no
path in the output — and it compares bytes before writing. Re-running on
unchanged advice reports "already up to date" and does not touch the file, so
nothing downstream of it rebuilds.

### Refusals

- A sidecar that never ran verification is **refused**. Nothing in it has been
  tried, so nothing in it may be applied, and the message names
  `--verify-index-candidates`.
- Verification that ran and accepted nothing is not a failure — it is an
  answer. The command says so and writes nothing.
- An unreadable sidecar is refused with its path and the reason.

### It consumes the artifact only

No plan analysis, candidate generation, or verification logic lives in this
command. It cannot decide that an index is a good idea; it can only relay a
decision the validator already recorded, with the evidence attached.
