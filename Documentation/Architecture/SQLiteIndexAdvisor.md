# Scratch-copy index-candidate generation and re-plan verification (issue #392)

Milestone 29, "Spike: SQLite query-plan analysis and index advice." This
document is the prototype write-up issue #392 asks for: deriving index
candidates from a statement's predicates, joins, and sort order, then
verifying each one by creating it on a scratch copy of the pinned Northwind
snapshot and re-planning. It builds on [#390's capture pipeline](SQLiteEQPVariance.md)
and [#391's shape classifier](SQLiteEQPPlanShapeClassifier.md) rather than
duplicating either.

## Non-goals

Research target only (`SwiftQLSQLiteIndexAdvisorPrototype`), per this
issue's hard constraints: no public SwiftQL API, no report schema change, no
build-plugin work, no typed index DDL. Candidate creation runs only against
a scratch copy of the pinned snapshot, opened by
`NorthwindFixture.withTemporaryCopy` — never the canonical file and never a
long-lived application connection. No `sqlite3expert.c`, no custom SQLite
build. Partial and expression indices are **not implemented** — noted below
as future candidate-space extensions, not attempted here.

## Methodology

### Deriving candidate columns

`IndexCandidateExtraction` (a narrow, pattern-based extractor, not a SQL
parser — see its doc comment for exactly what it recognises and what it
deliberately refuses to guess at) reads, for one table alias in one
statement's rendered SQL:

- `WHERE`-clause equality and range comparisons (conjuncts joined only by
  top-level `AND`; a top-level `OR`, or a conjunct that isn't a plain
  column/operator comparison, yields nothing for that clause rather than a
  guess).
- `JOIN … ON` equality (or `IS`, for a nullable left join) key columns.
- `ORDER BY` columns, ignoring `COLLATE`/`ASC`/`DESC`.
- The alias→real-table-name map (`tableAliasMap`), which explicitly excludes
  two situations rather than resolving them wrong: a CTE name masquerading
  as a table (`WITH "cte0" AS (…) … FROM "cte0" AS "t0"` — `"cte0"` isn't a
  real table `CREATE INDEX` could target), and an alias reused for a
  different table in a nested scope (`FROM "Orders" AS "t0" WHERE … IN
  (SELECT … FROM "Employees" AS "t0" …)` — resolving this correctly needs
  real scope tracking this extractor doesn't do, so a conflicting rebinding
  drops the alias entirely).

`IndexCandidateGenerator.candidateColumns(for:in:)` orders the derived
columns by precedence, per SQLite's own left-to-right composite-index rule:
**equality columns, then at most one range column** (a second range column
after the first cannot narrow a B-tree seek any further — SQLite stops
using the index to narrow at the first range term), **then join-key
columns, then `ORDER BY` columns** (so the index can also satisfy sort order
without a temp B-tree). Each column appears once, at its highest-precedence
position.

### Finding remediable statements

`IndexCandidateGenerator.remediableCandidates(for:plan:)` walks a #391
classified plan's root nodes for `full_table_scan` shapes, and — where the
statement's SQL yields a non-empty candidate column list for that node's
alias, and the alias resolves to a real table — produces a
`RemediableCandidate`. No signal, no resolvable table, no candidate.

### Deduplication

`IndexCandidateGenerator.deduplicate(_:)` merges candidates with the exact
same `(table, columns)` (recording every contributing statement id, and
keeping the first occurrence as the concrete statement to verify against),
then drops any candidate whose column list is an **exact prefix** of
another surviving candidate on the same table — a wider index already
serves every query the narrower prefix would have.

### Scratch-copy verification

`IndexCandidateVerifier.verify(candidate:statement:)` opens one temporary
copy of the pinned snapshot via `NorthwindFixture.withTemporaryCopy`
(already used by #390/#391's own tests), captures and classifies the
**before** plan, executes the candidate's `CREATE INDEX` DDL, captures and
classifies the **after** plan, and returns both plans plus the candidate's
DDL and a verdict as a single `IndexCandidateEvidence` value —
`withTemporaryCopy` removes the scratch copy on every exit path (success, a
thrown error, or a failure creating the copy itself), which is exactly the
"discard on every path including failure" this issue requires, reused
rather than reimplemented.

### The improvement rule

Stated once, applied uniformly to every candidate — no per-case judgment:

> A candidate is kept only when the plan node for the target alias changes
> from `full_table_scan` to `index_search` or `covering_index_scan`, **and**
> the after-plan node reports at least one constrained column.

No cost estimate or row-count comparison is used. The pinned snapshot is
deliberately unanalyzed (no `sqlite_stat1` — see [#390](SQLiteEQPVariance.md)),
so a cost-based comparison would not be trustworthy evidence; a structural
shape change, backed by #391's classifier, is the only signal here that
isn't itself an unfounded guess.

## Evidence

Generating candidates from #390's checked-in `apple-system-3.51.0` capture
(214 real statements, 114 `full_table_scan` nodes) and deduplicating
produced exactly **6 candidates**. Verifying all 6 against the pinned
Northwind snapshot:

| Table | Columns | Source statement | Verdict |
|---|---|---|---|
| `Orders` | `CustomerID`, `EmployeeID` | `c191.v1.select.j-left.w-injection-binding` | **✅ improvement** |
| `Orders` | `OrderID` | `c191.v1.select.g-customer-id.h-count-greater-than-one.o-ascending` | ❌ false positive |
| `Orders` | `CustomerID`, `OrderID` | `c191.v1.select.j-inner.o-ascending` | ❌ false positive |
| `Orders` | `EmployeeID`, `CustomerID` | `c191.v1.select.p-nullable-region…` | ❌ false positive |
| `Orders` | `EmployeeID`, `OrderID` | `c191.v1.select.j-left.o-ascending` | ❌ false positive |
| `Employees` | `ReportsTo`, `EmployeeID` | `c390.northwind.join.left-null-manager` | ❌ false positive |

Checked-in evidence (`Research/SQLiteBuildValidation/Tests/SwiftQLSQLiteIndexAdvisorPrototypeTests/Evidence/`):
`candidates.json`, `verification.json`.

### The one real improvement

`c191.v1.select.j-left.w-injection-binding` is
`SELECT t0.orderID FROM Orders AS t0 LEFT JOIN Employees AS employees_join ON (t0.employeeID IS employees_join.employeeID) WHERE (t0.customerID == :customer_input)`
— a genuine `WHERE` equality filter on `Orders`, the driving table of a
`LEFT JOIN`. `CREATE INDEX ON Orders (CustomerID, EmployeeID)` changes the
plan from `full_table_scan` to `index_search`, constrained by `["CustomerID"]`
— `EmployeeID` rides along in the index (derived from the `LEFT JOIN`'s
join key, per the precedence rule) but doesn't narrow the seek itself, which
the evidence records honestly rather than overclaiming.

### The five false positives, and why they're honest, not bugs

All five share one root cause the write-up states plainly: **a join-key
column is only useful to index when the table being indexed is the
*looked-up* side of the join, not the driving/outer side being scanned to
feed it.** Four of the five candidates (`Orders(CustomerID, OrderID)`,
`Orders(EmployeeID, CustomerID)`, `Orders(EmployeeID, OrderID)`,
`Employees(ReportsTo, EmployeeID)`) were derived from a join key on a table
with **no `WHERE` filter of its own** — the table must be scanned in full
regardless of any index, because the join doesn't reduce how many of its own
rows need visiting. The candidate generator does not currently distinguish
a join's driving side from its looked-up side; this is a real, documented
limitation, not silently patched over.

The sixth pattern is distinct: `Orders(OrderID)`, derived purely from an
`ORDER BY orderID` term with no `WHERE` clause at all. `OrderID` is already
the table's `INTEGER PRIMARY KEY` (rowid alias — see #390's evidence), so a
plain table scan already visits rows in that order for free; the redundant
secondary index is never chosen; `beforePlan == afterPlan` exactly.

**In every case, the false positive was caught by scratch-copy verification
itself** — the improvement rule rejected all five without needing a
special case for "driving side of a join" or "already the primary key." That
is the point of verifying rather than asserting.

## Coverage and limitations

- **Missing statistics cap advice at shape-derived, not distribution-
  derived**, exactly as #390 anticipated: this prototype cannot tell a
  highly-selective equality predicate from a nearly-useless one — it can
  only observe *whether* SQLite's planner chose to narrow with an index,
  not *how much* that narrowing helps. The one real improvement found here
  happens to be a case where narrowing is obviously worthwhile (`CustomerID`
  equality); a stats-driven advisor might reject candidates this prototype
  accepts, or vice versa, on a differently-shaped dataset.
- **Only the driving table's `full_table_scan` roots are considered** —
  extending detection to remediate a `temp_b_tree_for_order_by`/
  `temp_b_tree_for_group_by` node (eliminating a sort, not just avoiding a
  scan), or to inner-joined tables specifically, is straightforward future
  work using the same #391 shapes, not attempted in this pass.
- **Partial and expression indices are not implemented.** A partial index
  (`CREATE INDEX … WHERE …`) could serve some of the false-positive cases
  above if the filtered subset were small — e.g. an index on `Employees`
  filtered to `ReportsTo IS NOT NULL` doesn't apply here (the join key issue
  is structural, not selectivity), but could plausibly help other,
  differently-shaped statements. An expression index could serve a
  predicate on a computed value. Both extend the candidate space this
  prototype's precedence rule already establishes, but adding either is
  deferred.
- **No vendored `sqlite3expert`, no custom SQLite build** — every candidate
  is verified using only public SQLite API (`CREATE INDEX` DDL plus
  `EXPLAIN QUERY PLAN`), reusing #390/#391's existing capture and
  classification pipeline unchanged.

## Reproducing this evidence

```bash
swift run SwiftQLSQLiteIndexAdvisorCLI generate \
  --capture path/to/capture.json --output candidates.json

swift run SwiftQLSQLiteIndexAdvisorCLI verify \
  --candidates candidates.json --output verification.json
```

`IndexCandidateGeneratorTests.testRealCorpusCandidatesMatchCheckedInEvidence`
and `IndexCandidateVerifierTests.testCheckedInVerificationEvidenceMatchesFreshRun`
re-run this exact pipeline on every `swift test` invocation and assert
byte-identity with the checked-in evidence — with no version-skew caveat,
since neither `IndexCandidate` nor `IndexCandidateEvidence` embeds an SQLite
version field.
