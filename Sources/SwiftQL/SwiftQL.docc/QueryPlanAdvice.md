# Query plan advice

Capture what SQLite plans to do with each declared query, read the advice it
produces, and apply the index recommendations that were verified.

## Overview

The `SwiftQLSQLiteBuildValidationPlugin` build-tool plugin, described in
<doc:StaticQueries>, prepares every statement in a build-validation manifest
against a checked-in schema snapshot. Query plan analysis is a second,
separate opt-in on top of that. With it turned on, a build also:

1. Captures each statement's `EXPLAIN QUERY PLAN` on the snapshot.
2. Diagnoses the plan shapes that cost avoidable work.
3. Proposes index candidates for those shapes.
4. Verifies each candidate by creating it on a disposable copy of the snapshot
   and planning the statement again.

The findings arrive as build warnings and in a JSON sidecar file. The
`swiftql-index-advisor` command turns the verified recommendations into a
checked-in SQL file.

The findings are advice. A plan finding never changes a correctness verdict or
the validator's exit status, so no finding can fail a build. Plan analysis can
still fail the run in these cases, the same as any other invalid input:

- A plan option is used without `--plan-output`, or the row threshold is not a
  nonnegative integer.
- The suppression file cannot be read or is not valid.
- `--plan-output` conflicts with another path.
- The validator cannot write the sidecar.
- The pinned snapshot changes while candidates are verified.

## Turn on plan analysis

A target that already uses the plugin has two files in its own directory:
`swiftql-build-validation-manifest.json` and
`swiftql-build-validation-snapshot.sqlite`. To turn on plan analysis, add a
third file beside them, named `swiftql-plan-analysis.json`. The presence of
that file is the whole switch.

The file is a plan-suppression document. To opt in with no suppressions, use
this content:

```text
{"format_version": 1, "suppressions": []}
```

When the file is present, the plugin adds three arguments to its
`swiftql-build-validate` invocation:

- `--plan-output`, with a path to `swiftql-plan-analysis-report.json` in the
  plugin's work directory for the target.
- `--plan-suppressions`, with the path to `swiftql-plan-analysis.json`.
- `--verify-index-candidates`.

The plugin declares the opt-in file as a command input and the sidecar as a
second command output, so a change to the opt-in file runs the command again.
Without the file, the invocation does not change and the build does no plan
work.

The plugin does not pass `--plan-scan-row-threshold`, so a plugin build uses
the default threshold of 500 rows.

## Run the validator by hand

The same options are available when you run `swiftql-build-validate`
directly:

```text
swiftql-build-validate \
  --database swiftql-build-validation-snapshot.sqlite \
  --manifest swiftql-build-validation-manifest.json \
  --output swiftql-build-validation-report.json \
  --plan-output swiftql-plan-analysis-report.json \
  --plan-suppressions swiftql-plan-analysis.json \
  --plan-scan-row-threshold 500 \
  --verify-index-candidates
```

- `--plan-output <path>`: Where to write the plan sidecar. This option
  turns plan analysis on. Omit it and the validator captures no plans.
- `--plan-suppressions <path>`: A checked-in suppression file. The
  "Suppress a finding" section below describes its grammar.
- `--plan-scan-row-threshold <rows>`: Diagnose a full table scan only when
  the table has more rows than this value. The value must be a nonnegative
  integer. The default is 500.
- `--verify-index-candidates`: Verify each index candidate on a disposable
  copy of the snapshot. Without this option, the sidecar has candidates but no
  recommendations.

The last three options only tune plan analysis. The validator refuses each of
them when `--plan-output` is missing, so a run cannot look configured and do
nothing. Each of `--plan-output`, `--plan-suppressions`, and
`--plan-scan-row-threshold` may appear once.

`--plan-output` must not name the same file as `--output`, `--database`,
`--manifest`, or `--plan-suppressions`, and must not use a SQLite sidecar path
next to `--database`. `--output` must not name the same file as
`--plan-suppressions` either. The validator compares the paths after it
resolves symbolic links, and it compares existing files by device and inode,
so a symbolic link or a hard link to an input is refused too.

## Read the build warnings

The validator writes its advice to standard error in the
`<path>: warning: <message>` form that SwiftPM and Xcode already parse. The
path is the manifest, because the manifest is where the statement is recorded.
There are two kinds of line.

A **diagnostic** line says what SQLite does that costs avoidable work:

```text
<manifest>: warning: <code> in <query id>: <message>
```

A **recommendation** line says what to do about it, and carries the statement
to apply:

```text
<manifest>: warning: plan.verified-index for <query ids>: <reason> <write cost> Apply with: CREATE INDEX ...;
```

The two kinds do not pair up. A statement can have a diagnostic and no verified
remedy. A verified recommendation can come from a statement that no diagnostic
fired on.

A third line appears only when verification could not set up a scratch copy
for a candidate. It names the full cause, paths included, which the sidecar
does not:

```text
<manifest>: warning: plan.scratch-setup-failed for <query ids>: <index name> is unverified because its scratch copy could not be set up: <cause>
```

The validator diagnoses four plan shapes:

- `plan.full-table-scan`: SQLite reads every row of a table. This fires
  only when the table is resolved and its row count is above the scan row
  threshold. Below a few hundred rows, a full scan costs a handful of page
  reads.
- `plan.temp-b-tree-order-by`: SQLite builds a temporary B-tree to sort
  rows for `ORDER BY`, because no index returns them in that order.
- `plan.temp-b-tree-group-by`: SQLite builds a temporary B-tree to group
  rows for `GROUP BY`.
- `plan.correlated-scalar-subquery`: SQLite evaluates a scalar subquery
  once for each outer row, because the subquery reads a column of the outer
  row.

## Suppress a finding

Some findings are correct and still need no change, for example a sort that no
index can supply. Record those in `swiftql-plan-analysis.json` instead of
ignoring the warning.

```text
{
  "format_version": 1,
  "suppressions": [
    {
      "code": "plan.temp-b-tree-order-by",
      "query_id": "TodoQueries.search",
      "reason": "The ORDER BY switches on a bound parameter, so no index can supply the order."
    }
  ]
}
```

The file has this grammar:

- `format_version`: Required. Must be `1`. The validator refuses any
  other version.
- `suppressions`: Required. An array of rules.
- `code`: Required in each rule. One of the four diagnostic codes above.
- `query_id`: Optional. The manifest query identifier the rule applies to.
- `table`: Optional. The table the rule applies to. This is the real table
  name, not the alias the statement used. Only `plan.full-table-scan` findings
  have a table. A rule for any other code must name a `query_id`, or it never
  matches.
- `reason`: Required in each rule. It must not be empty or only white
  space.

Each rule must name a `query_id`, a `table`, or both. A rule that silences every
occurrence of a code cannot be written. A rule matches a finding only when
every field the rule states matches, so a rule with both a query and a table is
narrower than a rule with either one.

When more than one rule matches a finding, only one rule silences it and
supplies the reason. The validator sorts the rules by `code`, then `query_id`,
then `table`, then `reason`, and uses the first match. A rule with no
`query_id` sorts before a rule with one, so for `plan.full-table-scan` a
table-only rule wins over a query-specific rule. Avoid overlapping rules, so that each
finding has one clear reason.

Suppression leaves a trace. The sidecar keeps each silenced finding in
`suppressed_diagnostics` with the reason of the rule that silenced it. It lists
each rule that matches no finding in `unused_suppressions`, so you can find and
delete a stale rule. A rule that matches a finding counts as used even when an
earlier rule silenced that finding, so an overlapping rule does not appear in
`unused_suppressions`.

## How a candidate becomes a recommendation

The validator proposes candidates from the captured plans, within fixed limits:
at most 6 columns in one index, 4 candidates for one statement, and 4
candidates for one table. When a limit cuts the list, the sidecar records it in
`truncations`. When the validator cannot read a statement with confidence, it
declines to propose a candidate and records the reason in `declines`.

To verify a candidate, the validator copies the snapshot to a fresh scratch
file, creates the index on the copy, plans the statement that motivated it
again, and applies the improvement rule. The pinned snapshot is never written.
The validator compares the byte count and SHA-256 of the original file after
each candidate whose scratch copy was made, even when that candidate's
evaluation throws an error. It compares them once more at the end of the pass,
against a baseline taken before the first candidate, so any change during the
pass is caught, including a change between two candidates. If the
snapshot changed, nothing read from it can be trusted, and the run fails with a
snapshot-changed error.

Other failures do not fail the run. They put the candidate in `unverified`, and
it is never recommended:

- If the scratch copy cannot be set up, for example because the scratch
  location is refused or the copy cannot be opened, the reason starts "The
  scratch copy could not be set up". The reason in the sidecar never names a
  path. The validator also prints a `plan.scratch-setup-failed` warning with
  the full cause, so the build log says why no advice was produced.
- If planning the statement or creating the index fails on the copy, the
  reason starts "Verification could not be completed".

The scratch connection registers the same bundled function as the validator's
own connection, `regexp`, which SQLite calls for `REGEXP`. A statement that uses
`REGEXP` can therefore be planned and verified on the copy.

The current rule is `swiftql-index-improvement-rule-v2`. A candidate is
accepted only when both of these are true:

1. In the new plan, the index SQLite uses for the candidate's table is the
   candidate's own index. An improvement that some other index produced does
   not count.
2. The plan shows one of two kinds of evidence:
   - **A narrowed scan.** The table's plan node changes from a full table scan
     or an automatic covering index to an index search or a covering index
     scan, and the new node constrains at least one column.
   - **A removed sort.** A temporary B-tree for `ORDER BY` or `GROUP BY` that
     the old plan had is gone from the new plan.

No cost estimate or row count enters the rule. The snapshot is deliberately
not analyzed, so a change in plan structure is the only signal that is not
itself a guess.

Each recommendation also carries a write-cost note. An index adds a second
B-tree over its table. Every `INSERT` and `DELETE` on that table, and every
`UPDATE` of an indexed column, must maintain it. The note quotes the table's
row count at verification time, so a schema-only snapshot reports 0 rows.

## Read the sidecar

The sidecar is a JSON file with sorted keys. It holds no timestamp, host name,
process identity, or path. The records, findings, rules, and candidates are in
a fixed order, and each plan tree keeps the order SQLite reported, so two runs
over the same inputs on the same SQLite write identical bytes. Its top-level
keys are:

- `records`: One entry for each manifest statement, with `query_id`,
  `definition_identity`, `descriptor_identity`, the SQLite `provenance`
  (`sqlite_version`, `sqlite_source_id`, and the plan-relevant
  `compile_options`), and an `outcome`. The outcome `status` is `captured`,
  with the plan tree in `roots`, or `unsupported`, with a `reason`. A statement
  is never left out.
- `diagnostics`: The findings that no suppression silenced.
- `suppressed_diagnostics`: The silenced findings, each with its reason.
- `unused_suppressions`: The rules that match no finding.
- `settings`: The `full_table_scan_row_threshold`, the `suppressions`, and
  the `candidate_limits` the run used.
- `index_candidates`: The `limits`, `candidates`, `truncations`, and
  `declines` from candidate generation. A candidate is a proposal that nothing
  has tried yet.
- `index_recommendations`: The verification result, with the
  `improvement_rule_version`, the accepted `recommendations`, and the rejected
  `unverified` candidates with their reasons. Each recommendation has the
  `before_plan`, the `after_plan`, the `improvement_reason`, and the
  `write_cost_note`.
- `caveats`: What a reader must not conclude from these plans.
- `schema_snapshot`, `observed_database_byte_count`, `observed_database_sha256`:
  The snapshot identity the plans were captured on.
- `format_version`, `manifest_format_version`, `conformance_inventory_version`, `combinatorial_manifest_version`:
  The versions of the sidecar and its inputs.

A missing `index_recommendations` key and an empty `recommendations` list are
different answers. A missing key means that verification did not run. An empty
list means that verification tried every candidate and accepted none.

Each plan node has the raw `detail` text from SQLite, a classified `shape`, the
`attributes` extracted from the detail (`table`, `index_name`,
`constrained_columns`, `is_covering`, and `is_automatic`), and its `children`.
The raw text is always kept, so a wrong classification can be audited.

## Apply the recommendations

`swiftql-index-advisor` reads the sidecar. It does no plan analysis of its own,
and no build runs it.

Report mode is the default. It prints each verified recommendation with its
DDL, the queries that motivated it, the plans before and after, the reason,
and the write cost, followed by each unverified candidate and its reason. It
writes nothing.

```text
swiftql-index-advisor --plan-report swiftql-plan-analysis-report.json
```

To write the recommendations as a SQL file, add `--apply` and `--output`:

```text
swiftql-index-advisor \
  --plan-report swiftql-plan-analysis-report.json \
  --apply \
  --output Database/RecommendedIndices.sql
```

- `--plan-report <path>`: Required. A sidecar that
  `swiftql-build-validate` wrote with `--plan-output` and
  `--verify-index-candidates`.
- `--output <path>`: Where to write the SQL file.
- `--apply`: Write the file. The command refuses `--apply` without
  `--output`, so it only writes to a path that the invocation names.
- `--force`: With `--apply`, replace an existing output file that does not
  start with the generated header. Use it once, for example to replace a
  hand-written file with the generated one. The command refuses `--force`
  without `--apply`.

Two refusals protect the files around the output:

- `--output` must not name the same file as `--plan-report`. The command
  compares the paths after it resolves symbolic links, and it compares
  existing files by device and inode, so a symbolic link or a hard link to the
  sidecar is refused too. `--force` does not change this.
- If the output file exists and its first line does not carry the
  `Generated by swiftql-index-advisor.` header, the command did not write it.
  The command refuses to replace it, and the message names `--force`. A file
  that the command generated is replaced without `--force` when the advice
  changes.

The generated file starts with a `-- Generated by swiftql-index-advisor. Do
not edit by hand.` header that names the source sidecar and the improvement
rule. Each statement follows a comment with its table and columns, the queries
that motivated it, the plans before and after, the reason, and the write cost.
Each statement is `CREATE INDEX IF NOT EXISTS`, so the file can run against a
real database on every launch or migration.

The command gives a definite answer in each case:

- If the sidecar has no verification results, the command refuses and tells
  you to run `swiftql-build-validate` again with `--verify-index-candidates`.
- If verification accepted no candidates, there is nothing to apply, and the
  command does not write the output file.
- If the output file already has the same bytes, the command does not write
  it, so its modification time does not change.

SwiftQL has no typed index declarations yet, so the command writes a separate
SQL file and does not edit Swift source. Run that file against your database
yourself, for example from a migration. <doc:TodoDemo> shows one application
that runs the verified statements through GRDB.

## Limits of the advice

- A plan captured on the build host is not a promise about the SQLite that the
  application runs. A materialization strategy can change between two ordinary
  SQLite point releases.
- Parameters are not bound during capture. On a snapshot built with
  `SQLITE_ENABLE_STAT4` and analyzed, a plan specialized to a bound value is
  not represented.
- Treat each recommendation as a guide to look at, not a guarantee.
