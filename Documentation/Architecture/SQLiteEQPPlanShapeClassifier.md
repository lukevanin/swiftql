# Normalised query-plan capture and shape classification (issue #391)

Milestone 29, "Spike: SQLite query-plan analysis and index advice." This
document is the prototype write-up issue #391 asks for: a normalised plan
tree built from raw EQP rows, plus a classifier that turns each node into a
named shape. It builds directly on [#390's EQP variance evidence and
capture pipeline](SQLiteEQPVariance.md) rather than duplicating it.

## Non-goals

Research target only (`SwiftQLSQLitePlanShapePrototype`), per this issue's
hard constraints: no public SwiftQL API, no shipping report schema, no
build-plugin work, no index creation or snapshot mutation. Classification is
a pure function of captured rows plus recorded SQLite provenance — nothing
here opens a database connection.

## Model

- **`EQPPlanNode`** (`EQPPlanShapeModels.swift`): `detail` (raw, always
  preserved), `shape` (`EQPPlanShapeKind`), `attributes`
  (`EQPPlanShapeAttributes`), `children`.
- **`EQPPlan`**: a statement's normalised plan is a *forest* of `EQPPlanNode`
  roots, not a single tree — most statements have more than one top-level
  node (e.g. a table scan alongside a sibling `USE TEMP B-TREE FOR ORDER BY`).
  No timestamp, host, or SQLite-version field: the same rows always
  normalise to the same plan, a requirement this issue states explicitly.
- **`EQPPlanShapeAttributes`**: `table`, `indexName`, `constrainedColumns`,
  `isCovering`, `isAutomatic` — populated only where the shape carries them.

### Why more than the seven required shapes

The issue requires classifying "at least" seven shapes. The real #390
corpus's captures also contain compound-query, CTE-coroutine, and recursive-
CTE structural nodes that are none of those seven — forcing them into one
would be exactly the coercion this issue forbids ("never coerce an unknown
shape into a known one"). `EQPPlanShapeKind` therefore has 17 cases: the
seven required shapes, plus ten more precisely-named patterns actually
observed in the real corpus (`covering_index_scan`, `list_subquery`,
`co_routine_subquery_or_cte`, `compound_query_strategy`,
`recursive_cte_step`, `constant_row_scan`, `bloom_filter`,
`temp_b_tree_for_distinct_aggregate`, `temp_b_tree_for_compound_operation`),
plus `unclassified` as the honest fallback for genuinely unrecognised text.

## Classification

`EQPPlanShapeClassifier.classify(rows:statementID:)` first indexes rows by
`parent` id, then recursively builds the tree top-down from the roots
(`parent == 0`) through that index. Parent-child adjacency comes entirely
from each row's own `parent` field, not from its position in the row list.
Sibling order is not independent of input order, though: children of the
same parent (and the top-level roots) keep the relative order they had in
the input rows, so this is deterministic for a given capture but not
permutation-invariant against an arbitrary reordering of the same rows.
Building top-down means a node's children are classified after — and with
knowledge of — their parent's already-known shape. That parent-awareness is
needed for exactly one distinction:

### Correlated vs. uncorrelated scalar subquery

SQLite's raw EQP text does not literally say "correlated" — both cases print
identically as `SCALAR SUBQUERY N`. The only signal available from the
captured rows is structural: a scalar subquery SQLite can evaluate once
(uncorrelated) is hoisted as a sibling of the driving row source, with
`parent == 0`; one it must re-evaluate per outer row (correlated) is nested
as a child of whatever row-producing node supplies the correlation — a table
scan, index search, or another per-row-loop shape. `isRowLoopingShape`
implements this rule. It is a heuristic on tree structure, not a guarantee:
the real corpus contains no correlated scalar subquery to validate it
against (every `SCALAR SUBQUERY` node in both checked-in plan evidence files
classifies as plain `scalar_subquery`, 1 occurrence, 0
`correlated_scalar_subquery`), so this distinction is exercised only by a
clearly-labelled synthetic fixture (`testSyntheticCorrelatedScalarSubqueryUsesParentShapeHeuristic`).

### Structured attribute extraction

`SEARCH`/`SCAN` detail text is parsed into table, access method, and
constraint clause, then further classified:

| Raw pattern | Shape | Notes |
|---|---|---|
| `SCAN <table>` | `full_table_scan` | |
| `SCAN <table> USING COVERING INDEX <name>` | `covering_index_scan` | full scan optimized via a covering index; still visits every row |
| `SEARCH <table> USING INDEX <name> (<constraint>)` | `index_search` | `constrainedColumns` parsed from `<constraint>` |
| `SEARCH <table> USING INTEGER PRIMARY KEY (<constraint>)` | `index_search` | `indexName = "INTEGER PRIMARY KEY"` |
| `SEARCH <table> USING COVERING INDEX <name> (<constraint>)` | `index_search` | `isCovering = true` |
| `SEARCH <table> USING AUTOMATIC [PARTIAL] COVERING INDEX (<constraint>)` | `automatic_covering_index` | SQLite's on-the-fly ephemeral index — distinct from a real named index, including a named `sqlite_autoindex_*`; requires the literal `AUTOMATIC` marker |
| any other `SEARCH`/`SCAN … USING …` | `unclassified` | table still captured for audit; access method not guessed |

## Evidence

Classified both checked-in #390 captures
(`capture_apple-system-3.51.0.json`, `capture_homebrew-3.53.2.json`) end to
end; results checked in as `plans_apple-system-3.51.0.json` and
`plans_homebrew-3.53.2.json`.

| Shape | apple-system-3.51.0 | homebrew-3.53.2 |
|---|---:|---:|
| `full_table_scan` | 114 | 114 |
| `index_search` | 64 | 64 |
| `covering_index_scan` | 17 | 17 |
| `constant_row_scan` | 93 | 93 |
| `co_routine_subquery_or_cte` | 14 | 14 |
| `recursive_cte_step` | 8 | 8 |
| `bloom_filter` | 5 | 5 |
| `list_subquery` | 5 | 5 |
| `scalar_subquery` | 1 | 1 |
| `temp_b_tree_for_group_by` | 10 | 10 |
| `temp_b_tree_for_distinct_aggregate` | 6 | 6 |
| `compound_query_strategy` | 33 | 42 |
| `temp_b_tree_for_order_by` | 20 | 29 |
| `temp_b_tree_for_compound_operation` | 9 | 0 |
| `automatic_covering_index` | 0 | 0 |
| `correlated_scalar_subquery` | 0 | 0 |
| `unclassified` | **0** | **0** |

**Zero unclassified nodes on either build, across all 214 real statements.**
The three rows that differ between builds are exactly #390's Finding 2 (the
9 CTE × compound-operator cases): 3.51.0's `<OP> USING TEMP B-TREE` node
becomes 3.53.2's `USE TEMP B-TREE FOR ORDER BY` (accounting for the +9/+9
shift), while `compound_query_strategy`'s count rises from 33 to 42 because
the newer `MERGE (<OP>)`/`LEFT`/`RIGHT` shape has more nodes than the older
`COMPOUND QUERY`/`LEFT-MOST SUBQUERY` shape for the same 9 statements. This
is the classifier correctly *naming* the variance #390 measured, not
disagreeing with it.

### Determinism and id-renumbering robustness

- `testClassificationIsDeterministicAcrossRepeatedRuns`: classifying the same
  captured rows twice produces byte-identical `EQPPlan` values.
- `testIDRenumberedJoinStatementNormalisesIdenticallyAcrossBuilds`: the
  five-table Northwind join (#390 Finding 1 — its raw `id`/`parent` values
  differ between builds) produces a **byte-identical** normalised plan on
  both builds, because `EQPPlanNode` never encodes `id`/`parent`. This is the
  concrete proof that #390's recommendation ("never use `id`/`parent` as a
  diagnostic key") is followed here, not just stated.

## Reproducing this evidence

```bash
swift run SwiftQLSQLitePlanShapeCLI classify \
  --capture path/to/capture.json --output plans.json
```

Prints a shape-count summary to stdout and writes the full classified forest,
per statement, as canonical JSON.
