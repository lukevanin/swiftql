# `@SQLQuery` peer-macro encoding — spike findings and go/no-go

**Milestone:** [Spike: @SQLQuery peer-macro encoding](https://github.com/lukevanin/swiftql/milestone/28)
**Feeds:** [#26](https://github.com/lukevanin/swiftql/issues/26) (declaration-macro packaging)
**Toolchain floor under test:** swift-tools-version 5.9, swift-syntax 509.1.1, Swift 5 language mode
**Local verification toolchain:** Apple Swift 6.3.2 (building the pinned 5.9 package, Swift 5 mode)
**Status:** experiment complete — **GO** for a v1.5.1 implementation, with the packaging change recorded below.

---

## 1. Verdict

**GO.** The `@SQLQuery` declaration macro can be implemented on the **stable Swift 5.9 attached-macro roles** — no experimental function-body macro, no Swift-6-era toolchain floor. All four go criteria are met. #26's assumption that the encoding "may require a function-body macro and therefore a Swift-6-era toolchain, shipping as a gated preview or defer to v2" is **void for the encoding itself**; body macros remain relevant only to *one specific ergonomic improvement* (deleting the vestigial specification function), which stays a v2 item.

### Go criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Signature-driven body rewrite implementable against swift-syntax 509.x on the 5.9 floor, Swift 5 mode | **Met** (#359 PR #364; #369 PR #370) |
| 2 | Frozen-literal guard enforceable with clear declaration-site diagnostics; every undetectable hazard eliminated by design or explicitly judged acceptable; **no silent wrong results** | **Met** (#360 PR #372) — this encoding has *no silent-freeze path*; see §4 |
| 3 | Render-once caching yields byte-stable SQL and reuses physical prepared statements, with allocation-anchored evidence | **Met** (#361 PR #373) |
| 4 | No blocking Swift 5 language-mode or macro-toolchain issues | **Met** — none encountered across all four PRs; full suite 800 tests green |

---

## 2. What was proven, by issue

### #359 — signature-driven body rewrite (PR #364, merged)

An **attached peer macro** (`@attached(peer)`, the stable role `@SQLTable` uses) reads the attached function's signature *and* body, rewrites every parameter reference to a typed `XLNamedBindingReference<T>` placeholder (type taken from the signature), and generates a value-free statement builder plus an executor. One- and two-parameter and optional-parameter cases compile and execute against GRDB; the rendered SQL is `:name` placeholders with the correct `XLParameterLayout`, no inline value literals. **The Swift-6 body-macro gate #359's encoding was designed to avoid is genuinely avoided.**

Return-type spelling caveat: the attached function must be written `-> any XLQueryStatement<Row>` (not `some`), because the existing `sql {}` entry point erases to an existential — a `some` return fails to compile on the user's own function, independent of the macro.

### #369 — direct-result signatures + container encoding (PR #370, merged)

Eliminated the `-> any XLQueryStatement<Row>` boilerplate. The spec can declare its **result directly** (`-> [Person]` / `-> Person?`) and the macro derives cardinality from the annotation. Two encodings were proven on the floor:

- **Direct-result peer** (`@SQLQuery`, per function): the spec calls a trapping `sqlResult {}` entry point so it type-checks with the direct result type; the macro swaps `sqlResult` back to `sql` when it emits the value-free builder. Return-shape dispatch: `[Row]` → `fetchAll`, `Row?` → `fetchOne`, legacy `any/some XLQueryStatement<Row>` → `fetchAll`.
- **Container + member macro** (`@SQLQueries`, **recommended packaging**): specifications live in a nested `private struct Query`; a member macro on the extension sees them all in one expansion and generates executors as members of the database, carrying the spec's own name (`personByName`, not `fetchPersonByName`) because they land in a different scope. Call sites: `try database.personByName(name:)` (one-shot) and `try database.execute { try $0.personByName(name:) }` (scoped).

Type-system facts established with standalone `swiftc -swift-version 5` snippets: SE-0415 body macros are Swift 6.0 + `-enable-experimental-feature BodyMacros` (out per #26's floor); a peer cannot overload the attached function's own name with the executing signature (return-type/`throws`-only overloads are invalid redeclarations); overloading on return type alone *is* legal but the executor always lands in the illegal `throws`-only shape.

### #360 — frozen-literal guard (PR #372)

See §4. Strict declaration-site diagnostics for every reference shape the rewrite cannot reach, and a soundness argument that this encoding has **no silent-wrong-results path**.

### #361 — render-once executor (PR #373)

See §5. The executor renders once per declaration and reuses the request; per-call work is packet construction + execution; the SQL is byte-identical across calls, so GRDB reuses the physical prepared statement. Allocation-anchored on a deterministic render count (1 render for N calls).

---

## 3. The vestigial specification function (Wart B)

A peer macro cannot replace or annotate the attached declaration, so the written specification function remains compiled and callable. Its severity depends on the encoding, and it was progressively downgraded across the spike:

| Encoding | Direct call of the spec returns | Correctness if misused | Severity |
|---|---|---|---|
| #359 statement-returning spec | a valid-but-**inline-literal** statement (silently defeats statement reuse) | harmless (wrong SQL text, right rows) | moderate, **silent** |
| #369 direct-result peer | **traps** via `sqlResult`'s `fatalError` | crash — loud, caught in any test run | low, **loud** |
| #369 container (`@SQLQueries`) | spec lives in a `private`/`fileprivate` `Query` container, **never referenced by generated code** | hidden from the visible API by the developer's own access control | **negligible** |

**Mitigation for v1.5.1:** the container encoding. Declaring the `Query` container `private` removes the trapping specs from the visible API surface entirely — the strongest mitigation available without body macros.

**Literal elimination is a v2 / gated-preview item.** [SE-0415 Function Body Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0415-function-body-macros.md) is the *only* way to also delete the second symbol (the macro replaces the body in place, making the spec's own function the executor — #26's stable-v2 target shape). It is Implemented in Swift 6.0 but ships behind `-enable-experimental-feature BodyMacros`, which (a) raises the compiler floor from 5.9 and (b) would force every downstream consumer to pass the experimental flag. Both are disqualifying for a stable v1.x library. **Cost of raising the floor, quantified:** it buys *only* Wart-B elimination — bindings, rewrite, dispatch, effects, and caching all already work on 5.9 — at the cost of a Swift-6 CI/toolchain floor, an experimental-flag requirement propagated to every downstream package, and loss of Swift-5-language-mode consumers. Not worth it for v1.x; revisit if/when `BodyMacros` graduates out of experimental.

**Framing change for #26:** from "body macros *might be needed* for the encoding" (they are not — #359 disproved that) to "body macros are the *only* way to also delete the vestigial specification function, and that specific improvement is what defers to v2."

---

## 4. Frozen-literal guard — soundness (go criterion 2)

The generated executor renders SQL once and reuses it, so any parameter value that escapes the rewrite would freeze into the cached SQL on the first call — a silent wrong-results bug, the design's central hazard.

**Key result: this encoding has no silent-freeze path.** The rewriter replaces *every* matching `DeclReferenceExpr` (except member names), and `XLNamedBindingReference<T>` *only ever renders as a placeholder*, never as a literal. So a parameter reference is either rewritten to a placeholder (safe) or produces a **loud compile error** on the generated code. The diagnostics therefore (a) convert confusing generated-code errors into clear declaration-site errors, and (b) conservatively reject a few fragile-but-workable shapes to keep the invariant simple.

Diagnostics added (each with an `assertMacroExpansion` test):

- collection-typed parameter (`[T]`/`Set`/`Dictionary`) — variable-length `IN` breaks stable SQL;
- parameter in a string interpolation;
- parameter captured in a nested closure;
- parameter passed as a function-call argument;
- parameter used to initialize a local binding;
- hand-constructed `XLNamedBindingReference` / `contextualBinding`;
- parameter never referenced (unused).

**Hazard cases that cannot be detected lexically — documented explicitly, none silent:**

1. **Helper-call vs. SQL-function-call indistinguishability.** The call-argument diagnostic flags *any* parameter used as a direct call argument, because a Swift helper `nameFilter(name)` is lexically identical to a legitimate SQL scalar function `length(name)` that accepts an expression. In the spike's single-`SELECT`, comparison-operand scope this conservative rejection is safe — an **over**-approximation (may reject valid DSL, never silently wrong). A fuller implementation that admits SQL-function calls needs a type-directed or allowlist approach.
2. **Callee-is-a-parameter** (`predicate(x)`) and **paren-wrapped bases** (`(name).lowercased()`) are not caught by the guard; both fall to the compiler as loud type errors on the generated code (residual noted in #359 findings).

Neither is a silent-wrong-results gap, so criterion 2 is satisfied.

---

## 5. Render-once executor — evidence (go criterion 3)

`XLRenderOnceCache<Row>` (thread-safe, lazily populated) holds one rendered request per key; the macro emits one as a `static` peer per query. Proven:

- **Render-once:** a counting build closure renders the statement **exactly once across 1,000 calls**; a 128-thread first-use race also renders exactly once (the cache renders under its lock).
- **Byte-stable, value-free SQL:** one rendered request serves different argument values and returns the right rows; the rendered SQL is byte-identical, contains `:id`, and has no inline literal.
- **Allocation-anchored benchmark:** anchored on the deterministic render count (not noisy wall-clock). 50,000 iterations: render-once **1 render** vs per-call **50,000 renders** (wall-clock ~90×, corroborating only). Rendering dominated the construction+rendering allocation profile in #166, so one render for N calls amortizes that cost to zero per call.
- **Physical-statement reuse:** because the SQL text is identical across calls, GRDB's per-connection `cachedStatement(sql:)` reuses the physical prepared statement — lazy render-once is observationally equivalent to compile-time SQL text (which is infeasible for macros due to declaration-locality: table/column names live on other declarations).

**Cache-keying decision:** key on **`(databaseIdentifier, dialectIdentifier)`**. The dialect identifier is the render-relevant component — rendered SQL depends only on the dialect, so a second dialect renders into its own entry (single dialect today; the decision does not preclude more). The database identifier keeps a per-declaration `static` cache from binding one pool's request to another database. **Multi-dialect implication:** a database targeting a different dialect gets a separate rendered entry automatically; no cross-dialect collision. **Trade-off:** the `static` cache retains one entry per distinct database pool for the process lifetime — fine for long-lived databases; a per-instance store or eviction is the production refinement. No correctness issue (the database-identity key prevents cross-database reuse).

---

## 6. Return-shape dispatch (feasibility only; implementation is v1.5.1)

With a direct-result signature the return annotation is the only source of cardinality (macros are declaration-local). Established mapping:

| Return annotation | Fetch | Executor result |
|---|---|---|
| `[Row]` / `Array<Row>` | `fetchAll` | `[Row]` |
| `Row?` / `Optional<Row>` | `fetchOne` | `Row?` |
| `any`/`some XLQueryStatement<Row>` (legacy #359) | `fetchAll` | `[Row]` |

Scalar results and write statements (INSERT/UPDATE/DELETE, RETURNING) are **out of scope for the spike** — feasibility only: a scalar shape (`Row` non-optional non-array) and a write shape would each need their own dispatch and request path (`XLWriteRequest.execute`), which are additive. Collection-typed parameters are rejected (variable-length `IN` breaks stable SQL) — a fixed-arity `IN` or an array-binding runtime is a separate design.

**Effects:** execution throws. In the peer encoding the executor is a separate symbol, so the spec need not be `throws`; recommend allowing (and documenting as preferred) spelling the spec `throws` so a future body-macro form — where the spec's own signature becomes the executor — is a source-compatible migration to #26's `async throws -> Person?` target. `async` stays out of scope (v1.5.0) and is not precluded: an `async` executor is additive.

---

## 7. Proposed generated-symbol naming (provisional per #26 — not frozen)

| Symbol | Peer encoding (#359/#369) | Container encoding (#369, recommended) |
|---|---|---|
| Value-free statement builder | `personByNameStatement()` | inlined into the executor |
| Executor | `fetchPersonByName(…)` | `personByName(…)` (the spec's own name, legal via scope separation) |
| Spec entry point | `sqlResult { … }` (trapping) | `sqlResult { … }` inside a `private struct Query` |
| Render-once cache | `__xl<Name>Cache` (static) | one static per generated executor |
| Scope/execution | — | `Context`, `execute(_:)` |
| Runtime support | `_xlQueryParameterBinding(_:named:in:)`, `XLRenderOnceCache`, `XLPreparedQueryCacheKey`, `XLDatabase.preparedQueryCacheKey` | same |

`sqlQuery` is already the labeled-closure statement builder in `SQLFunctionalSyntax.swift`, so the trapping direct-result anchor needs a different name (`sqlResult` is the provisional pick). All names above are open for #26 to settle at representative call sites.

---

## 8. Recommended v1.5.1 implementation shape

**Adopt the container + member-macro encoding (`@SQLQueries`) on the stable Swift 5.9 floor**, with the direct-result peer encoding retained as evidence of the encoding layer and of why scope separation is required.

Suggested issue breakdown for v1.5.1 (each a self-contained task):

1. **`@SQLQueries` container macro, promoted from spike to product** — the member macro, `Context`, `execute(_:)`, database-level sugar, and the specification container. Freeze the generated-symbol names here (§7).
2. **Frozen-literal guard, productionized** — the §4 diagnostics, plus a decision on the helper-call over-approximation (keep conservative, or add a type-directed allowlist for SQL-function calls).
3. **Render-once cache, productionized** — decide `static`-per-declaration vs a per-database store; settle `preparedQueryCacheKey` as public runtime surface or hide it behind an internal seam.
4. **Return-shape dispatch beyond `fetchAll`/`fetchOne`** — scalar results and write statements, if wanted in v1.5.1 (otherwise defer).
5. **`execute` / `Context` runtime design** — connection checkout, pooling, transaction scoping. The spike stub binds the database directly; this is runtime design, and the `async` variant (`try await database.execute { … }`, v1.5.0) lands here additively.

**What of #26's original framing changes:** #26 should drop the "requires a function-body macro / Swift-6-era toolchain / gated preview or defer to v2" premise for the *encoding*. Body macros are reclassified as the v2-only path to deleting the vestigial specification function (Wart B, §3), not a prerequisite for shipping `@SQLQuery` on v1.x.

---

## 9. Out of scope (with pointers)

- **Async execution** — v1.5.0 (#22). Not precluded; an `async` executor is additive.
- **Value codecs, incl. `Date` parameters** — v1.5.3; full codec ergonomics are tied to v2 database-scoped builders.
- **Catalog integration** — #212 / #214.
- **Write statements, scalar results, collection/`IN` parameters** — feasibility noted (§6); implementation deferred.
- **Multiple `@SQLQueries` extensions per database type** — a second extension would redeclare `Context`; a naming or single-extension convention is runtime design.

---

## 10. Provenance

| Issue | PR | Findings comment |
|---|---|---|
| #359 signature-driven body rewrite | #364 (merged) | issue #359 |
| #369 direct-result + container | #370 (merged) | issue #369 |
| #360 frozen-literal guard | #372 | issue #360 |
| #361 render-once executor | #373 | issue #361 |
| #362 this write-up | — | — |

All names and runtime surface introduced by the spike remain provisional per #26. Release decisions beyond the experiment branch are **not** part of the spike (milestone workflow).
