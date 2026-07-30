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
`NorthwindFixture.withTemporaryCopy` - never the canonical file and never a
long-lived application connection. No `sqlite3expert.c`, no custom SQLite
build. Partial and expression indices are **not implemented** - noted below
as future candidate-space extensions, not attempted here.

## Methodology

### Deriving candidate columns

`IndexCandidateExtraction` (a narrow, pattern-based extractor, not a SQL
parser - see its doc comment for exactly what it recognises and what it
deliberately refuses to guess at) reads, for one table alias in one
statement's rendered SQL:

- `WHERE`-clause equality and range comparisons (conjuncts joined only by
  top-level `AND`; an `OR` anywhere in the clause - a blunt substring check,
  deliberately more conservative than "does this `OR` actually change
  precedence" - or a conjunct that isn't a plain column/operator
  comparison, yields nothing for that clause rather than a guess).
- `JOIN … ON` equality (or `IS`, for a nullable left join) key columns.
- `ORDER BY` columns, ignoring `COLLATE`/`ASC`/`DESC`.
- The alias→real-table-name map (`tableAliasMap`), which explicitly excludes
  two situations rather than resolving them wrong: a CTE name masquerading
  as a table (`WITH "cte0" AS (…) … FROM "cte0" AS "t0"` - `"cte0"` isn't a
  real table `CREATE INDEX` could target), and an alias reused for a
  different table in a nested scope (`FROM "Orders" AS "t0" WHERE … IN
  (SELECT … FROM "Employees" AS "t0" …)` - resolving this correctly needs
  real scope tracking this extractor doesn't do, so a conflicting rebinding
  drops the alias entirely).

`IndexCandidateGenerator.candidateColumns(for:in:)` orders the derived
columns by precedence, per SQLite's own left-to-right composite-index rule:
**every equality-constrained column first - a join key is an equality
constraint too** (SQLite seeks on it per outer row exactly like a `WHERE`
equality; it just supplies the bound value at run time instead of from the
statement text) - **then at most one range column** (a second range column
after the first cannot narrow a B-tree seek any further - SQLite stops
using the index to narrow at the first range term), **then `ORDER BY`
columns** (so the index can also satisfy sort order without a temp
B-tree). Each column appears once, at its highest-precedence position.

This ordering is confirmed by a real scratch-copy re-plan, not assumed: see
[Finding: join keys must precede range columns](#finding-join-keys-must-precede-range-columns)
below.

### Finding remediable statements

`IndexCandidateGenerator.remediableCandidates(for:plan:)` walks a #391
classified plan's root nodes for `full_table_scan` **or
`automatic_covering_index`** shapes, and - where the statement's SQL yields
a non-empty candidate column list for that node's alias, and the alias
resolves to a real table - produces a `RemediableCandidate`. No signal, no
resolvable table, no candidate. (`automatic_covering_index` was added here
for the same reason it was added to the improvement rule below: the
join-key/range-column finding's fixture has its remediable root classified
as `automatic_covering_index`, not `full_table_scan`, so the improvement
rule accepting that shape was unreachable end to end until this scan also
looked for it - caught by Copilot review, confirmed by
`IndexCandidateGeneratorTests.testRemediableCandidatesIncludesAutomaticCoveringIndexRoots`.)

### Deduplication

`IndexCandidateGenerator.deduplicate(_:)` merges candidates with the exact
same `(table, columns)` (recording every contributing statement id, and
keeping the first occurrence as the concrete statement to verify against),
then drops any candidate whose column list is an **exact prefix** of
another surviving candidate on the same table - a wider index already
serves every query the narrower prefix would have. A dropped prefix
candidate's source statement ids are folded into every wider candidate it
prefixes before being discarded, so a statement that only ever produced the
narrower prefix is still attributed to the index that now serves it,
instead of silently disappearing from the evidence (caught by Copilot
review; confirmed by
`IndexCandidateGeneratorTests.testDeduplicatePreservesPrefixCandidateSourceStatementIDs`).

### Scratch-copy verification

`IndexCandidateVerifier.verify(candidate:statement:)` opens one temporary
copy of the pinned snapshot via `NorthwindFixture.withTemporaryCopy`
(already used by #390/#391's own tests), captures and classifies the
**before** plan, executes the candidate's `CREATE INDEX` DDL, captures and
classifies the **after** plan, and returns both plans plus the candidate's
DDL and a verdict as a single `IndexCandidateEvidence` value -
`withTemporaryCopy` removes the scratch copy on every exit path (success, a
thrown error, or a failure creating the copy itself), which is exactly the
"discard on every path including failure" this issue requires, reused
rather than reimplemented.

### The improvement rule

Stated once, applied uniformly to every candidate - no per-case judgment:

> A candidate is kept only when the plan node for the target alias changes
> from `full_table_scan` **or `automatic_covering_index`** to `index_search`
> or `covering_index_scan`, **and** the after-plan node reports at least one
> constrained column.

(`automatic_covering_index` was added to the "before" shapes after the join-key/range-column finding below surfaced a real case where SQLite's own ephemeral index, not a full table scan, was the baseline being improved on.)

No cost estimate or row-count comparison is used. The pinned snapshot is
deliberately unanalyzed (no `sqlite_stat1` - see [#390](SQLiteEQPVariance.md)),
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
- a genuine `WHERE` equality filter on `Orders`, the driving table of a
`LEFT JOIN`. `CREATE INDEX ON Orders (CustomerID, EmployeeID)` changes the
plan from `full_table_scan` to `index_search`, constrained by `["CustomerID"]`
- `EmployeeID` rides along in the index (derived from the `LEFT JOIN`'s
join key, per the precedence rule) but doesn't narrow the seek itself, which
the evidence records honestly rather than overclaiming.

### The five false positives, and why they're honest, not bugs

All five share one root cause the write-up states plainly: **a join-key
column is only useful to index when the table being indexed is the
*looked-up* side of the join, not the driving/outer side being scanned to
feed it.** Four of the five candidates (`Orders(CustomerID, OrderID)`,
`Orders(EmployeeID, CustomerID)`, `Orders(EmployeeID, OrderID)`,
`Employees(ReportsTo, EmployeeID)`) were derived from a join key on a table
with **no `WHERE` filter of its own** - the table must be scanned in full
regardless of any index, because the join doesn't reduce how many of its own
rows need visiting. The candidate generator does not currently distinguish
a join's driving side from its looked-up side; this is a real, documented
limitation, not silently patched over.

The sixth pattern is distinct: `Orders(OrderID)`, derived purely from an
`ORDER BY orderID` term with no `WHERE` clause at all. `OrderID` is already
the table's `INTEGER PRIMARY KEY` (rowid alias - see #390's evidence), so a
plain table scan already visits rows in that order for free; the redundant
secondary index is never chosen; `beforePlan == afterPlan` exactly.

**In every case, the false positive was caught by scratch-copy verification
itself** - the improvement rule rejected all five without needing a
special case for "driving side of a join" or "already the primary key." That
is the point of verifying rather than asserting.

### Finding: join keys must precede range columns

The real 214-statement corpus never produced a statement where a table on
the *looked-up* side of a join carried both a join key and a range
predicate - so the corpus alone couldn't settle whether a candidate's join
key should come before or after a range column. Rather than assume either
ordering (an earlier draft of this prototype used equality → range → join
→ order-by, which is what the corpus's one real improvement happened to
produce, coincidentally without ever exercising this exact tiebreak),
constructing and re-planning a real case settles it:

```sql
SELECT p.ProductID FROM Categories AS c
LEFT JOIN Products AS p ON p.CategoryID = c.CategoryID
WHERE p.UnitPrice > 20 OR p.ProductID IS NULL
```

`Products` has no existing index beyond its own primary key, and is forced
onto the looked-up side of the `LEFT JOIN` (the `OR … IS NULL` keeps SQLite
from converting this into an inner join and reordering the tables).
SQLite's own baseline plan is its `automatic_covering_index` shape - an
ephemeral, per-query index on `CategoryID` alone, rebuilt every execution:

```
SCAN c
BLOOM FILTER ON p (CategoryID=?)
SEARCH p USING AUTOMATIC COVERING INDEX (CategoryID=?) LEFT-JOIN
```

`CREATE INDEX ON Products(CategoryID, UnitPrice)` - join key first - is the
index SQLite actually adopts, replacing the ephemeral one and dropping the
bloom-filter step entirely:

```
SCAN c
SEARCH p USING COVERING INDEX ix_a (CategoryID=?) LEFT-JOIN
```

`CREATE INDEX ON Products(UnitPrice, CategoryID)` - range first - is
**silently ignored**. The after-plan is byte-for-byte identical to the
baseline, as if the candidate didn't exist:

```
SCAN c
BLOOM FILTER ON p (CategoryID=?)
SEARCH p USING AUTOMATIC COVERING INDEX (CategoryID=?) LEFT-JOIN
```

This is real, unambiguous confirmation of the general SQLite rule
`candidateColumns` now implements: **equality-style columns - `WHERE`
equality and join keys alike - must precede any range column**, because a
composite index can only be seeded by an equality prefix; nothing after the
first range column narrows a seek at all. It also surfaced a second,
directly related gap: the improvement rule's original precondition only
recognised `full_table_scan` as a remediable "before" shape. Replacing
SQLite's own ephemeral `automatic_covering_index` with a real, persistent
one is exactly the same category of improvement, so the rule now accepts
either shape as the starting point. Both fixes are proven end to end by
`IndexCandidateVerifierTests.testJoinKeyPrecedesRangeColumnConfirmedByRealScratchCopyReplan`.

## Coverage and limitations

- **Missing statistics cap advice at shape-derived, not distribution-
  derived**, exactly as #390 anticipated: this prototype cannot tell a
  highly-selective equality predicate from a nearly-useless one - it can
  only observe *whether* SQLite's planner chose to narrow with an index,
  not *how much* that narrowing helps. The one real improvement found here
  happens to be a case where narrowing is obviously worthwhile (`CustomerID`
  equality); a stats-driven advisor might reject candidates this prototype
  accepts, or vice versa, on a differently-shaped dataset.
- **Only root-level `full_table_scan`/`automatic_covering_index` nodes are
  considered - never a nested node inside a subquery or CTE.** A plan's
  roots are a generic forest of top-level nodes (any of the tables involved,
  plus non-table nodes like a temp B-tree), not just one "driving" table;
  extending detection to remediate a `temp_b_tree_for_order_by`/
  `temp_b_tree_for_group_by` node (eliminating a sort, not just avoiding a
  scan), or to a remediable node nested inside a subquery, is straightforward
  future work using the same #391 shapes, not attempted in this pass.
- **Partial and expression indices are not implemented.** A partial index
  (`CREATE INDEX … WHERE …`) could serve some of the false-positive cases
  above if the filtered subset were small - e.g. an index on `Employees`
  filtered to `ReportsTo IS NOT NULL` doesn't apply here (the join key issue
  is structural, not selectivity), but could plausibly help other,
  differently-shaped statements. An expression index could serve a
  predicate on a computed value. Both extend the candidate space this
  prototype's precedence rule already establishes, but adding either is
  deferred.
- **No vendored `sqlite3expert`, no custom SQLite build** - every candidate
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
byte-identity with the checked-in evidence. Neither `IndexCandidate` nor
`IndexCandidateEvidence` embeds an SQLite version field, so unlike #390's
equivalent check this assertion is unconditional rather than runtime-gated
- but that reflects what #390 actually measured (these particular
index-search/full-scan decisions were stable between the two real builds
tested there), not a guarantee that every SQLite build plans them
identically forever. EQP choices remain SQLite-version-dependent in
principle; if this test ever fails on a different host, its failure message
prints that host's `sqlite_version()`/`sqlite_source_id()` so the
difference is diagnosable rather than a bare JSON diff.
