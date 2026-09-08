---
title: "What's new in v1.8"
date: 2026-09-08
description: "SwiftQL v1.8 makes the build tell you which index to add. It captures what SQLite plans to do with each declared query, warns about the shapes that cost avoidable work, and proves each index it recommends by creating it on a disposable snapshot copy and re-planning."
---

SwiftQL has validated declared queries at build time since v1.5.2. It opens a
checked-in schema snapshot, prepares every query in a manifest against it, and
fails the build when one no longer matches the schema. That answers one
question: *is this query still valid?*

v1.8 adds a second question to the same run. *What is SQLite actually going to
do with it?*

## What the build now tells you

Turn it on and a build looks like this:

```
…/swiftql-build-validation-manifest.json: warning: plan.full-table-scan in orders.by-customer:
  SQLite reads every row of "Orders" (830 rows, above the 500-row advisory
  threshold) to answer this query. An index covering the columns it filters,
  joins, and orders by would let SQLite seek instead of scan.
…/swiftql-build-validation-manifest.json: warning: plan.verified-index for orders.by-customer:
  The plan for "o" changed from full_table_scan to index_search using
  ix_advisor_orders_customerid_employeeid, constrained by CustomerID, EmployeeID.
  Apply with: CREATE INDEX "ix_advisor_orders_customerid_employeeid"
  ON "Orders" ("CustomerID", "EmployeeID");
```

Two lines, and they are different kinds of thing. The first says what SQLite is
doing that costs avoidable work. The second says what to do about it — and it is
not a guess.

## Why the second line is trustworthy

Anything can pattern-match a query and suggest an index. The hard part is
knowing whether the index would help.

So SwiftQL does not stop at deriving a candidate. It copies your snapshot to a
disposable location, creates the index **on the copy**, re-plans the statement
that motivated it, and compares. A candidate survives only when the index SQLite
names in the new plan is that candidate's own, and either the table access moved
from a full scan to a narrowed seek, or a temporary B-tree the old plan needed
has disappeared.

Everything else is reported as rejected, with the reason. A candidate that
vanishes silently is indistinguishable from one that was never generated, and
the reason it failed is often the more useful half of the answer.

The copy lives in the system temporary directory, never beside your snapshot and
never inside your source tree, and it is removed on every exit path — a normal
return, a thrown error, and `SIGINT` or `SIGTERM`. Afterwards the pinned
snapshot's byte count and SHA-256 must match what they were before, or the run
fails closed.

## It is advice, and it is built that way

None of this can fail a build. That is not a convention the code tries to keep;
it is three separate structural facts:

- Plan records go in their own file. `SQLiteBuildValidationReport` has no plan
  field, so its schema, its verdicts, and its bytes cannot change when plans are
  captured. A test asserts the correctness report is byte-identical with and
  without plan analysis, on a passing run and a failing one.
- `advisory` is its own severity type, not a fourth verdict case. A verdict
  decides the exit status; no arrangement of the advisory type can reach that
  decision.
- The exit code still reads the correctness verdict alone.

It is also free when you do not want it. Without the opt-in file, the plugin's
invocation is unchanged and the build does no extra work.

## Turning it on

One file, in the target that already carries the manifest and snapshot:

```
Sources/MyTarget/
  swiftql-build-validation-manifest.json
  swiftql-build-validation-snapshot.sqlite
  swiftql-plan-analysis.json
```

That third file is also where you record a decision to ignore something:

```json
{
  "format_version": 1,
  "suppressions": [
    {
      "code": "plan.full-table-scan",
      "table": "Categories",
      "reason": "A lookup table of eight rows; a scan is the right plan."
    }
  ]
}
```

Every rule names a code and at least one of a query or a table, and must state a
reason. A rule that silences everything is not expressible, and neither is a
silent one. Silenced findings stay in the report with their reason, and a rule
that silenced nothing is listed too — so a stale instruction to ignore a finding
can be found and deleted rather than quietly outliving the problem it was
written for.

## Reading the advice outside a build log

```
$ swiftql-index-advisor --plan-report plans.json
swiftql-index-advisor: 9 verified recommendation(s), 0 unverified candidate(s).
Improvement rule: swiftql-index-improvement-rule-v2

[1] Orders (CustomerID, EmployeeID)
    DDL:       CREATE INDEX IF NOT EXISTS "ix_advisor_orders_customerid_employeeid" …
    Motivated: orders.by-customer
    Before:    SCAN o
    After:     SEARCH o USING INDEX ix_advisor_orders_customerid_employeeid (CustomerID=? AND EmployeeID=?)
    Why:       The plan changed from full_table_scan to index_search…
    Cost:      This index adds a second B-tree over "Orders" (830 rows…)
```

Report mode is the default and writes nothing. `--apply --output <path>` writes
the statements as a checked-in `.sql` file, and running it again is a no-op — it
compares bytes before writing, so it does not even move the file's timestamp.

It is a command rather than an Xcode fixit because a fixit is unreachable here.
A SwiftPM build-tool plugin emits diagnostics, not fixits, and a Swift fixit
would have to come from a macro — which cannot open a database without breaking
the hermetic, incremental builds the validator exists to protect. So applying
advice stays one explicit invocation whose diff you approve. A build never
rewrites your source.

## What happened when we pointed it at the demo

The to-do demo is the honest test, because its queries were written for
readability rather than for the plan they produce.

It had **no indices at all**. SwiftQL's generated `CREATE TABLE` declares no
primary key, so every lookup by identifier was a full table scan and every
`ORDER BY` built a temporary B-tree. The first run reported eight warnings and
verified nine indices:

| Index | Motivated by | Plan change |
| --- | --- | --- |
| `Todo(id)` | todo-by-id | full scan → index search |
| `TodoList(id)` | todo-list-by-id | full scan → index search |
| `Todo(listID, position)` | checklist-summaries | full scan → index search, sort removed |
| `Todo(listID, id)` | tags-for-list | full scan → covering index search |
| `TodoTag(todoID, tagID)` | tags-for-list, tags-for-todo | automatic index → covering index search |
| `Tag(id, name)` | tags-for-list, tags-for-todo | automatic index → index search |
| `Tag(name)` | tags | temp B-tree removed |
| `Todo(createdAt, position)` | todos | temp B-tree removed |
| `TodoList(position, name)` | todo-lists | temp B-tree removed |

The demo carries all nine now, and every table access in it is an index search.
Three warnings remain, each recorded with its reason: all three are sorts no
index can supply — one over conditional expressions that switch on a bound
parameter, two over the result of a join fan-out — and the advisor correctly
proposes nothing for any of them.

That exercise also found two things wrong with the advisor itself, which is
rather the point of pointing it at real code.

The first: the verification rule rejected **every** sort-serving index. An index
walked in order constrains no column, and the rule demanded at least one
constrained column before it would accept an improvement. That is the entire
remedy for two of the three shapes it diagnoses. Three of the demo's nine
indices removed a temporary B-tree outright and were each rejected for narrowing
nothing. The rule now also accepts a temporary B-tree that the new plan no
longer builds.

The second: a verified recommendation whose statement raised no diagnostic never
reached the build log at all, because the DDL was attached to diagnostic lines.
Six of the demo's nine were invisible. Recommendations now get their own line.

Both are fixed in this release. Neither would have been found without running the
tool against something real.

## Two limits worth knowing

The advisor measures the snapshot it is given. A schema-only snapshot carries no
rows, so a write-cost note reads "0 rows at verification time" and the
full-scan threshold never fires there. Recommendations and their evidence are
unaffected, because they rest on plan shape rather than row counts.

And SwiftQL has no index DDL. `@SQLTable` declares a table and `sqlCreate` builds
one; nothing declares an index. So the statements the advisor verifies are run as
SQL — in the demo, through the one file that reaches past SwiftQL to GRDB. The
advisor can name the index and prove the plan improves, and the library cannot
yet run the statement for you. Typed DDL is v2 work, and this is the clearest
argument for it so far.

## Upgrading

Nothing to do. v1.8 adds build-time tooling and changes no query API, no runtime
behaviour, and no rendered SQL. A target that does not opt in builds exactly as
it did.

```swift
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.8.0")
```

The [changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md) has
the exhaustive detail.
