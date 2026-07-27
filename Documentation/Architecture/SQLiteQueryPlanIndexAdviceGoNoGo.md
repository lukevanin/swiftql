# Query-plan analysis and index advice: spike go/no-go (issue #393)

Milestone 29, "Spike: SQLite query-plan analysis and index advice." This is
the closing write-up: a go/no-go on advisory query-plan analysis and index
advice, backed by the measured evidence from the spike's three prototypes,
and the confirmed (or revised) split of the provisional v1.8 issues. Per
this milestone's own charter, **this document — not the v1.8 scaffold — is
authoritative** on how that work is divided.

Research only: no product code, public API, or build-plugin change ships
from this issue. The three prototype PRs it synthesizes are
[#412](https://github.com/lukevanin/swiftql/pull/412) (issue #390),
[#422](https://github.com/lukevanin/swiftql/pull/422) (issue #391), and
[#427](https://github.com/lukevanin/swiftql/pull/427) (issue #392).

## Verdict: **GO**, with three scoped corrections to the v1.8 issues

Advisory query-plan analysis and index advice are worth building in v1.8.
All three legs of the spike produced real, reproducible evidence on the
pinned Northwind snapshot, not merely a plausible design:

- EQP capture is deterministic and, for the shapes that matter, stable
  across two real SQLite builds (#390).
- Plan-shape classification handles 100% of a 214-statement real corpus
  with zero unclassified nodes, and is provably robust to the one
  cross-build instability #390 found (`id`/`parent` renumbering) (#391).
- Index-candidate generation and scratch-copy verification produced one
  genuine, evidenced improvement and caught its own five false positives
  structurally — without a single special case (#392).

The GO is **scoped**, not unconditional: §"Confirmed and revised v1.8
issues" below corrects one real discrepancy the spike surfaced (issue #396's
assumed candidate-column precedence) and adds an evidence-backed caveat to
two others (issues #394, #395). Nothing in the milestone is closed — see
[Hard constraint check](#hard-constraint-check).

**Build-host plans are not device plans.** Every measurement in this spike
ran on this delivery's build host and one additional local SQLite install.
Apple ships a different SQLite per OS release (#390), so nothing here
predicts what a specific customer device's query planner will choose. v1.8
must carry this caveat to every place it surfaces plan-derived advice —
issues #395 and #398 already say so; that language is confirmed, not new.

## Evidence behind the verdict

### EQP variance by class (#390)

214 real statements (208 from the #191 combinatorial manifest, 6 hand-authored
Northwind joins/CTEs), captured against two real, distinct SQLite builds
(Apple system 3.51.0, Homebrew 3.53.2) on the pinned, checksum-verified
Northwind snapshot:

| Class | Count | Stable across the two builds? |
|---|---:|---|
| Byte-identical | 203 | Yes |
| `id`/`parent` renumbered, structure identical | 2 | Structurally yes, raw ids no |
| Materialization strategy changed (compound-query CTEs) | 9 | No |

Full detail: [`SQLiteEQPVariance.md`](SQLiteEQPVariance.md).

### Classifier stability (#391)

The same 214 statements, on both builds, classified through `EQPPlanShapeClassifier`:
**zero** nodes fell back to `unclassified` on either build. The two
`id`/`parent`-renumbered statements produced byte-identical *normalised*
plans on both builds (proving the classifier's `id`/`parent`-blind design
actually delivers on #390's recommendation, not just states it). The nine
materialization-strategy statements classified fully and differently on each
build — the classifier *named* the variance #390 measured, which is its job,
not a failure.

Full detail: [`SQLiteEQPPlanShapeClassifier.md`](SQLiteEQPPlanShapeClassifier.md).

### Index-advice quality on Northwind (#392)

Generating and verifying candidates from the same 214-statement capture
produced exactly 6 deduplicated candidates:

- **1 confirmed improvement**: a real `WHERE`-equality filter, verified to
  change the plan from `full_table_scan` to `index_search`.
- **5 false positives**, all caught by scratch-copy verification itself:
  4 from indexing a join key on the *driving* side of a join (which must be
  scanned in full regardless), 1 from indexing a column that was already the
  table's `INTEGER PRIMARY KEY`.

That is a 1-in-6 yield on a snapshot deliberately picked for correctness
coverage, not for having many indexable hot paths — the meaningful result is
not the yield, it's that **every rejection was structural, not asserted**.
No case required a hand-written exception.

Full detail: [`SQLiteIndexAdvisor.md`](SQLiteIndexAdvisor.md).

## Decided design questions

Per this issue's Required Approach, each open question the milestone
scaffold left open is settled here:

1. **Do plan records live in the canonical build-validation report, or a
   sidecar?** **Sidecar.** #390's Finding 2 (real materialization-strategy
   variance between two ordinary point releases) means folding raw EQP into
   the pass/fail report would make report diffs noisy for reasons unrelated
   to SwiftQL correctness. A sidecar keeps that noise out of the
   correctness contract #293/#294 own. (#394's body is updated to state
   this directly rather than "where the spike decides.")
2. **What is the improvement rule for keeping a candidate?** The rule
   #392 stated and applied uniformly: kept only when the target alias's
   plan node changes from `full_table_scan` to `index_search` or
   `covering_index_scan` *and* the after-plan reports at least one
   constrained column. No cost estimate — the pinned snapshot is
   deliberately unanalyzed (see decision 4). This is the "rule version" #397
   asks to record in its report.
3. **How are unclassified shapes surfaced?** Never coerced into a named
   shape. `EQPPlanShapeKind.unclassified`, with the raw `detail` string
   always retained, so a misclassification is auditable rather than silent.
   #395's diagnostics must key only on named shapes, per its own hard
   constraint, and #391 proved a 0%-unclassified rate is achievable on a
   real corpus without ever needing to fall back to that case.
4. **Should the pinned snapshot's no-statistics policy change?** **No.**
   #392's structural improvement rule needed no `sqlite_stat1` to find a
   real improvement and reject five plausible false positives. Adding
   statistics now would only serve the deferred `sqlite3_stmt_scanstatus`
   exploration (see below), which is a separate future prototype, not a
   reason to change today's pinned-snapshot policy.

## Confirmed and revised v1.8 issues

Milestone 30 ("v1.8", #394–#399). Every issue is **confirmed** as scoped
except the one correction below; two more carry a new evidence-backed
caveat. None are closed — the GO verdict means proceed, not "some of this
was wrong."

| Issue | Disposition | Why |
|---|---|---|
| #394 — Capture normalised plans in build validation | **Confirmed**, body updated | Directly matches #390/#391's proven pipeline. Updated to state the sidecar decision explicitly (design question 1) instead of leaving it open. Still blocked on #292/#293 (v1.5.2 build validator), independent of this spike. |
| #395 — Emit advisory shape diagnostics | **Confirmed**, caveat added | Full table scan, temp B-tree (`ORDER BY`/`GROUP BY`) are backed by real, cross-build-stable evidence (#390/#391). **Correlated scalar subquery is not** — the real corpus contains zero correlated scalar subqueries; #391's classifier distinguishes it from a plain scalar subquery by a parent-shape heuristic validated only against one synthetic fixture. Issue body updated to require a real correlated-subquery fixture (extending the Northwind anchor corpus) as part of this issue's own Done-When, not assumed proven. |
| #396 — Generate index candidates from static descriptors | **Revised**: precedence question reopened | The issue's provisional body assumed equality → **join** → range → order-by. #392's validated implementation used equality → **range** → join → order-by, and matches the one real improvement found. Neither ordering was validated against a real inner-joined table with *both* a range predicate and a join key competing for the second index column — #392's corpus didn't contain that shape. Issue body updated to require settling this empirically (build both orderings, re-plan, keep the one SQLite actually prefers) rather than assuming either. Every other requirement (dedup, prefix-collapse, decline-on-unclassified, deterministic ordering) is confirmed by #392's implementation and tests. |
| #397 — Verify candidates by re-planning on a scratch copy | **Confirmed as-is** | This is, almost line for line, what #392 built and evidenced: scratch-copy-per-run, same classifier, explicit improvement rule with a recorded version, reject-with-reason, digest-verified cleanup on every path. The one requirement #392 did not address — "note the interaction between a candidate and the write cost it implies" — remains open for #397's implementation; the spike was read-plan-only. |
| #398 — Surface advice through the SwiftPM build plugin | **Confirmed as-is** | Out of scope for all three spike PRs by design (no build-plugin changes). A downstream consumer of #394/#395/#397's artifacts; nothing in the spike bears on its own requirements. |
| #399 — `swiftql-index-advisor` codemod | **Confirmed as-is** | Same as #398: downstream consumer, untouched by spike evidence. The fixit-unreachability rationale in its body stands (SwiftPM build-tool plugins cannot emit fixits; a macro cannot open a database). |

### Hard constraint check

Per this issue's own hard constraints: no product code, public API, or
build-plugin change ships here (confirmed — this delivery is documentation
and issue-body edits only); no claim that a build-host plan predicts a
device plan (confirmed — stated explicitly above and already present in
#395/#398); and since the verdict is **GO**, not no-go, the "close v1.8
honestly instead of downgrading to vague follow-ups" constraint doesn't
apply — nothing is closed.

## Deferred, with a named future owner

| Item | Why deferred | Future owner |
|---|---|---|
| Partial indices (`CREATE INDEX … WHERE …`) | Would extend #392's candidate space but no real corpus statement in this pass needed one to resolve a false positive (the join-key false positives are structural, not selectivity-driven) | #396 (index-candidate generation), as a scoped enhancement once the base precedence question above is settled |
| Expression indices | Same — extends the candidate space, unexercised by this pass's corpus | #396, same as above |
| Vendored `sqlite3expert.c` | Rejected at scaffolding time (needs a custom SQLite build; the scratch-copy approach #392 validated needs only public API) and re-confirmed here: #392 never needed it | Not planned. A deliberate rejection, not a deferred task. |
| `sqlite3_stmt_scanstatus` measured costs | Named in this issue's own Required Approach as something to record; **not actually evaluated** by any of #390/#391/#392 — this write-up states that gap honestly rather than retroactively claiming coverage | A new, unscheduled research issue (not yet filed): prototype `sqlite3_stmt_scanstatus` as a way to get *measured* per-operation cost without `ANALYZE`, which could sharpen #392's purely structural improvement rule into a graded one |

## Milestone closure

Milestone 29 ("Spike: SQLite query-plan analysis and index advice") closes
with this issue. Its three prototype issues (#390, #391, #392) each have a
merged-when-approved PR and a written architecture doc; this document is
the fourth and closing piece. Milestone 30 ("v1.8") remains open with its
six issues as confirmed/revised above, still gated on v1.5.2's build
validator (#292, #293) landing first.
