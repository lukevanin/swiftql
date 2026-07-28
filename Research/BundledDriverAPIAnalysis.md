# Should SwiftQL's driver contract adopt a bundled, sqlite-nio-shaped API?

**Verdict: REJECT as a replacement. ADOPT a narrow hybrid** — keep the
multi-step contract as the protocol requirement, and add a *bundled convenience
extension* (`executeBundled`/`forEachBundledRow`) that is derived from the
existing primitives rather than replacing them. The bundled shape's real
benefits are almost entirely obtainable without bundling; its central cost —
forfeiting prepared-statement reuse — is measurable in the repo's own baselines
at **+11% to +120% per call**, and it is not recoverable behind the seam for
every backend SwiftQL has committed to.

Analysis performed against the worktree at `5eb28fcf`, comparing
`XLDatabaseDriverConnection`
([SQLDatabaseDriver.swift](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)) with
the shape documented in
[SQLiteNIOFeasibility.md](SQLiteNIOFeasibility.md) §1. Performance claims are
computed from the three committed runs in
[`Benchmarks/Baselines/`](../Benchmarks/Baselines/), not from new measurements.

This is **not** the question of whether to depend on `sqlite-nio` — that was
assessed and answered NO-GO. It is whether its one-method API shape is a better
contract for SwiftQL's own drivers.

> **Note:** references to `SQLiteNIOFeasibility.md` point at the companion
> analysis, which is currently uncommitted on branch
> `claude/sqlite-nio-feasibility-cbbc40`. Those links resolve once both documents
> land in `Research/`.

---

## 0. The shapes, stated precisely

Today, per execution (`XLDatabaseDriverConnection`,
[SQLDatabaseDriver.swift:66-95](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L66)):

```swift
mutating func preparePhysical(_: XLValidatedLogicalPreparedStatement) throws -> PhysicalStatement
mutating func bind(_: Dialect.Value, to: XLBindingKey, in: PhysicalStatement) throws -> PhysicalStatement
mutating func fetchAll(_: PhysicalStatement) throws -> [[Dialect.Value]]
mutating func fetchOne(_: PhysicalStatement) throws -> [Dialect.Value]?
mutating func execute(_: PhysicalStatement) throws
```

plus the package-internal refinement
([SQLDatabaseDriver.swift:115-122](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L115)):

```swift
mutating func forEachRow(_: PhysicalStatement, _ body: ([Dialect.Value]) throws -> XLRowStreamControl) throws
```

The bundled counterpart would be a single requirement, roughly:

```swift
mutating func run(
    _ statement: XLValidatedLogicalPreparedStatement,
    _ bindings: XLInvocationBindings<Dialect.Value>,
    _ onRow: ([Dialect.Value]) throws -> XLRowStreamControl
) throws
```

## 1. What the bundled shape genuinely buys — assessed against the real code

### 1.1 "No escaping statement handle, so no cursor-confinement problem" — *already solved, and not by the contract*

This is the headline argument, and against this codebase it is the weakest.
`GRDBPhysicalStatement`
([GRDBDatabaseDriver.swift:771-780](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L771))
is a struct of four stored properties, and **it is not a cursor**. It holds the
logical statement, a `connectionIdentifier: UUID`, GRDB's `Statement` (a
prepared handle, not an open cursor), and `bindings: [XLBindingKey: XLSQLiteValue]`.

The actual cursor is created and destroyed entirely inside one call
([GRDBDatabaseDriver.swift:627-659](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L627)):
`Row.fetchCursor` is called at line 632 and the cursor never outlives
`forEachRow`. So the "cursor cannot escape" property that the doc comment
attributes to non-`Sendable` `PhysicalStatement` is in fact enforced by
`forEachRow`'s scoped body, which is *already* bundled in the only sense that
matters. Bundling `prepare` into that call adds nothing to confinement.

The confinement that `PhysicalStatement` *does* provide is cross-connection
ownership, enforced dynamically by `validateOwnership`
([GRDBDatabaseDriver.swift:683-690](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L683)),
and it is exercised by tests
([SQLDriverContractTests.swift:119](../Tests/SwiftQLCoreTests/SQLDriverContractTests.swift#L119)).
Bundling would make that check unnecessary — a genuine but small win, worth one
UUID field and one guard.

**Verdict: overstated.** Real benefit ≈ deleting `validateOwnership` and one
stored property.

### 1.2 "No partially-bound or half-finalized intermediate states" — *the premise is already false here*

`bind` does not touch SQLite. It is a pure value operation: copy the struct, set
a dictionary entry, return
([GRDBDatabaseDriver.swift:576-603](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L576),
especially lines 600-602). The physical bind happens once, atomically, at
execution, when `statementArguments` materialises the whole positional table and
hands it to GRDB
([GRDBDatabaseDriver.swift:692-739](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L692)).

So SwiftQL's multi-step contract is already *value-accumulating*, not
*incremental-mutation*. There is no half-bound `sqlite3_stmt` to observe, and
`validateBindings`
([GRDBDatabaseDriver.swift:608-613](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L608))
rejects an incomplete packet before any execution. The "intermediate states"
hazard is a hazard of a *different* multi-step design than the one SwiftQL has.

**Verdict: not a real benefit against this code.**

### 1.3 "Drastically smaller contract for adapter authors" — *real, but ~3→1, not 5→1, and mostly obtainable for free*

Counting substantive work for a new adapter today: `preparePhysical`, `bind`,
`forEachRow`. `fetchAll`, `fetchOne`, and `execute` are already one-line
forwards to the streaming extension's `collectAllRows`/`collectFirstRow`
([GRDBDatabaseDriver.swift:615-625](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L615);
same pattern in the test double at
[SQLDriverContractTests.swift:680-686](../Tests/SwiftQLCoreTests/SQLDriverContractTests.swift#L680)).
`execute` is the only one with genuinely separate behaviour.

That 3→1 reduction is real. But **most of it is available without bundling**:
promoting `fetchAll`/`fetchOne` to defaulted requirements for streaming
conformers is a pure-win cleanup that removes the boilerplate every adapter
currently duplicates, and it changes no shape. Bundling buys the remaining
step — merging `preparePhysical` and `bind` into the call — which is the
step that costs caching (§2).

**Verdict: real but modest, and largely severable from the bundling decision.**

### 1.4 "The natural protocol wire for v2.2–v2.4 *is* one round trip" — *this is backwards*

This is the load-bearing claim for the adapter-authoring argument, and it does
not survive contact with the wire protocols. ROADMAP explicitly specifies
"database-bound prepared handles" for all three
([ROADMAP.md:711, 719, 726](../ROADMAP.md#L707)) — the multi-step shape is a
stated v2.2–v2.4 requirement, not an accident of the SQLite adapter.

| Backend | Parameterised execution on the wire | Fits bundled? |
|---|---|---|
| **PostgreSQL** | Extended query only: `Parse`/`Bind`/`Describe`/`Execute`/`Sync`. The *simple* `Q` protocol carries **no parameters at all** — bundling onto it would mean interpolating literals. | Pipelining Parse+Bind+Execute+Sync is one round trip, but only with the **unnamed** statement, which is destroyed by the next `Parse`. Bundled ⇒ no server-side plan reuse, by construction. |
| **MySQL** | `COM_STMT_PREPARE` → (read statement id) → `COM_STMT_EXECUTE` → `COM_STMT_CLOSE`. The id is only known from the prepare response. | **Cannot** be one round trip. A bundled call costs *two* round trips where a cached prepared handle costs one. Bundling is strictly worse. |
| **SQL Server** | `sp_prepare`/`sp_execute`/`sp_unprepare`, or `sp_executesql` (bundled, ad-hoc). | Bundled form exists, but leans on plan-cache text matching instead of an owned handle. |
| **SQLite** | `prepare_v3`/`bind`/`step`/`finalize`. | Natural fit, at the cost of re-preparing. |

The protocols that actually motivated this question are the ones that fit the
bundled shape *worst*. For MySQL it is a round-trip regression; for PostgreSQL
it forecloses named prepared statements. The one backend where bundling is
natural is SQLite — the backend that already has a working multi-step adapter.

**Verdict: the argument inverts. Multi-step is the better wire match for
v2.2–v2.4.**

### 1.5 "Trivially async-compatible" — *true, and the strongest genuine point*

This one holds. A bundled `run(...)` has exactly one suspension point and no
value that must survive across an `await`, so `async` promotion is mechanical.
The multi-step form makes the connection-owned, non-`Sendable`
`PhysicalStatement` live across `await` boundaries in the caller — the precise
difficulty flagged in [SQLiteNIOFeasibility.md](SQLiteNIOFeasibility.md) §3.1.

Two qualifications:

- `forEachRow`'s callback is **synchronous by design**
  ([SQLDatabaseDriver.swift:98-105](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L98)),
  so a bundled call is only async at its boundary, not throughout. That is fine,
  and it is what you want.
- The property comes from *scoping*, not from *bundling*. A multi-step contract
  whose statement is only reachable inside a `withPrepared { … }` scope has the
  same property. Bundling is one way to get scoping; it is not the only way.

**Verdict: genuine, and it is the one argument that should carry weight — but it
argues for scoped statement access, not specifically for bundling.**

## 2. What it costs

### 2.1 Statement caching — it *can* live behind a bundled call, but only for SQLite

The mechanism works: key a per-connection `[String: Statement]` cache by SQL
text inside the bundled call, and `reset`+`clear_bindings`+rebind on reuse. That
is exactly what GRDB's `cachedStatement(sql:)`
([GRDBDatabaseDriver.swift:571](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L571))
already does, and nothing in the bundled signature prevents an adapter from
calling it. So **bundling does not mechanically foreclose caching for SQLite.**

It forecloses three things that ROADMAP v2.1 asks for by name:

1. **Caller-controlled cache lifetime.** With the handle hidden, "prepare this
   once and reuse it across N calls" is no longer expressible in the contract;
   it becomes an adapter-private heuristic. ROADMAP v2.1 requires "per-connection
   statement preparation and caching" and "preparation **warm-up** and metrics"
   ([ROADMAP.md:697, 704](../ROADMAP.md#L692)). Warm-up is precisely
   *prepare without executing* — unrepresentable in a bundled-only contract (§2.3).
2. **Schema-version invalidation and safe reprepare** ([ROADMAP.md:701](../ROADMAP.md#L701))
   becomes unobservable from the core. The core can no longer tell whether a
   given execution hit or missed the cache, so the metrics requirement has no
   seam to attach to.
3. **Cross-backend caching.** For MySQL the cache must hold a server-side
   statement id whose lifetime is explicitly managed by `COM_STMT_CLOSE`; for
   PostgreSQL a named statement. A bundled call can hide that, but the *only*
   correctness-preserving policy it can implement without caller input is
   LRU-with-eviction, and eviction on a server-side handle is a network
   operation with failure modes the core cannot see.

**Verdict: caching survives bundling for SQLite; the *contractual* caching,
warm-up, and metrics requirements of v2.1 do not.**

### 2.2 Prepare-once/execute-many for batch inserts

Today `boundStatement`
([GRDBDatabaseDriver.swift:442-476](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L442))
calls `connection.prepare` per invocation, so SwiftQL does **not currently
exploit** prepare-once/execute-many — the win is deferred to the GRDB cache. So
bundling costs nothing *today*, but it removes the seam where the optimisation
would naturally land. Given the measured per-prepare surcharge for
`bounded_write` is ~3.7 µs (§4), a 10 000-row batch insert leaves ~37 ms on the
table. That is the single clearest future cost.

### 2.3 Prepare-without-execute — the stated dependency is *not* real today, but the forward-looking one is

The task premise is that `Sources/SwiftQLSQLiteBuildValidationValidator/`
(#292/#293) depends on a prepare-without-execute step in the driver contract. It
does not. The validator drives `sqlite3_prepare_v3` directly
([SQLitePrepareV3Probe.swift:158](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift#L158))
and finalises without stepping; it imports `SwiftQLCore` only for
`XLSQLiteDialect` identity and capability checks
([SQLiteBuildValidator.swift:280, 312](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidator.swift#L280))
and never touches `XLDatabaseDriverConnection`. **Bundling the driver contract
would not break build validation.**

The forward-looking cost is real, though. Extending build validation to
v2.2–v2.4 means validating SQL against a live server without side effects, and
the only safe primitives for that are PostgreSQL `Parse`+`Describe` (no
`Execute`) and MySQL `COM_STMT_PREPARE` (no `COM_STMT_EXECUTE`). A bundled-only
contract cannot express either, so cross-dialect build validation would need its
own out-of-contract probe per backend — replicating for three servers the
duplication SQLite already lives with.

### 2.4 The static-query path

Minimal impact, and this is the part that argues *for* bundling. `GRDBStaticQuery`
never touches `PhysicalStatement`: it builds an `XLInvocationBindings` packet
([GRDBStaticQuery.swift:326](../Sources/SwiftQL/GRDBStaticQuery.swift#L326)) and
hands it to `GRDBPreparedInvocation.fetchAllValues` / `forEachValueRow` /
`execute`
([GRDBDatabaseDriver.swift:501-529](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L501)).
Those methods already take *SQL-plus-a-binding-packet and deliver rows* —
`GRDBPreparedInvocation` **is** a bundled API, one layer above the driver seam.
The bundled shape is therefore already SwiftQL's public execution surface; the
open question is only whether it should also be the *driver* seam.

## 3. Row delivery and early termination

sqlite-nio's `Void`-returning `onRow` is not a property of bundling — it is a
defect of that particular signature, and one SwiftQL must not inherit.

A bundled call keeps early stop iff its callback returns `XLRowStreamControl`
and the driver honours `.stop` by abandoning the cursor
([GRDBDatabaseDriver.swift:655-657](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L655)).
With that signature, bundling is neutral on streaming.

Early stop is load-bearing beyond `fetchOne`:

- `collectFirstRow` returns `.stop` after row 1
  ([SQLDatabaseDriver.swift:139-149](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L139));
- `fetchAtMost(limit)` stops at the limit *while decoding*
  ([GRDBSQLDatabase.swift:311-345](../Sources/SwiftQL/GRDBSQLDatabase.swift#L311)) —
  a `LIMIT`-less early stop that a `Void` callback would turn into a full scan;
- the reusable normalisation buffer at
  [GRDBDatabaseDriver.swift:648-651](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L648)
  makes the typed decode path materialise no intermediate matrix. sqlite-nio's
  eagerly-materialised `SQLiteRow` forfeits exactly this.

**Required signature:** `([Dialect.Value]) throws -> XLRowStreamControl`,
synchronous, non-escaping, with values valid only until the callback returns.
Any bundled proposal that weakens this is a regression, not a refactor.

## 4. Binding model — bundling is *easy* here, because the work is already done

`XLInvocationBindings<Value>`
([SQLInvocationBindings.swift:450-458](../Sources/SwiftQLCore/SQLInvocationBindings.swift#L450))
already carries `layout: XLParameterLayout` plus an ordered
`[XLInvocationBinding<Value>]`, each binding pairing an `XLParameterSlot` (which
owns the `XLBindingKey`, type identifier, nullability, and codec identity) with
its value. It is `Sendable`, immutable, and validated by `validatingComplete()`.
**This is already the bundled binding packet**; a bundled call would take it
verbatim.

Named binds survive without difficulty. Normalisation from `XLBindingKey` to
SQLite's positional table already exists at
[GRDBDatabaseDriver.swift:703-738](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L703),
and it is derived *entirely* from `parameterLayout` — core-owned data — plus two
SQLite rules (named placeholders take the next free index; `.indexed(n)` maps to
`n+1`, gaps preserved as NULL).

Should that move up into the core? **No, and this is the one place where the
current split is exactly right.** The rules are dialect-specific: SQLite's
"named takes the next free slot" is a SQLite rule, PostgreSQL is `$1`-positional
with no named form on the wire, MySQL is `?`-only. Hoisting normalisation into
core would bake SQLite's numbering into every dialect. Bundling neither forces
nor forbids the move — the packet is already the right currency either way.

**Verdict: neutral. The binding model is bundling-ready today and needs no
change under either design.**

## 5. Hybrid designs

| Design | Shape | Assessment |
|---|---|---|
| **A. Bundled-only** | One requirement replaces five. | Rejected. Forecloses v2.1 warm-up/metrics (§2.1), regresses MySQL to two round trips (§1.4), and removes the only seam for cross-dialect build validation (§2.3). |
| **B. Bundled requirement + multi-step optional refinement** (mirroring `XLStreamingDatabaseDriverConnection`) | Every adapter implements `run`; cache-capable adapters additionally conform to a refinement exposing `prepare`/`bind`. | **The trap.** The refinement pattern works for streaming because the *general* form (`fetchAll`) is derivable from the *specific* one (`forEachRow`) — see `collectAllRows`, [SQLDatabaseDriver.swift:128](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L128). Here the derivation runs the wrong way: you cannot synthesise a bundled `run` from nothing, so every adapter writes `run` *and* the cache-capable ones write the multi-step form too — strictly more work than today, with two paths to keep behaviourally identical. |
| **C. Multi-step requirement + bundled convenience extension** | Keep today's requirements; add `executeBundled`/`forEachBundledRow` as a protocol *extension* composing `prepare` → bind-loop → `forEachRow`. | **Recommended.** Derivation runs the right way (bundled is a strict composition of the primitives), so it costs adapter authors nothing and can never diverge. It is, almost exactly, `boundStatement` + `forEachRow` promoted from `GRDBInvocationExecutor` into the contract. |
| **D. Scoped multi-step** | Replace the returned handle with `withPreparedStatement(_:) { stmt in … }`. | Worth doing **later, with the async decision**, not now. Captures the §1.5 async benefit (no handle across `await`) and the §1.1 confinement benefit without losing caching. Source-breaking for direct driver clients, so it belongs in the same change as the async break, not before it. |

**Composition with the async question.** This is the decisive tiebreaker.
[SQLiteNIOFeasibility.md](SQLiteNIOFeasibility.md) §7.4 says to treat sync→async
as its own deliberate decision. Option C is the only one that stays neutral: the
bundled extension is trivially async-promotable *and* the multi-step primitives
remain available, so the async decision can still choose between D (scoped) and
a fully bundled async form when it is actually made. Option A pre-commits the
contract to a shape chosen for a backend SwiftQL rejected, and does so *before*
the decision that should drive it.

## 6. Benchmark implications

**The instrument already exists and no new benchmark is needed to bound the
cost.** `BenchmarkPhase`
([BenchmarkTypes.swift:3-10](../Benchmarks/Sources/SwiftQLBenchmarks/BenchmarkTypes.swift#L3))
separates `coldStatementPreparation` from `cachedStatementLookup`, measured
independently at
[SwiftQLBenchmarkRunner.swift:586-623](../Benchmarks/Sources/SwiftQLBenchmarks/SwiftQLBenchmarkRunner.swift#L586).
A bundled-without-caching design pays `cold_statement_preparation` where the
current design pays `cached_statement_lookup`, so the surcharge is a subtraction
over data already committed.

From the three runs in [`Benchmarks/Baselines/`](../Benchmarks/Baselines/)
(2026-07-17, mac16-8), median nanoseconds:

| Case | cold prep | cached lookup | surcharge | sum of other phases | **relative cost** |
|---|---|---|---|---|---|
| `simple_parameterized_lookup` | 14 062 | 250 | +13 812 | 11 459 | **+120%** |
| `deterministic_row_decode` | 10 375 | 208 | +10 167 | 13 249 | **+77%** |
| `bounded_write` | 3 792 | 83 | +3 709 | 22 625 | **+16%** |
| `representative_multi_join_read` | 20 000 | 291 | +19 709 | 182 854 | **+11%** |

The memory note that this machine is noisy and sub-10% deltas are unreliable is
respected and does not blunt the finding — these are **11%–120%**, and the
underlying `cold_statement_preparation` medians reproduce across the three runs
to within 2% (14 062 / 14 209 / 14 167 ns for `simple_parameterized_lookup`).
The signal is far above the noise floor because it is a large, structural cost,
not a micro-delta. The cost is worst precisely for small, frequent queries — the
shape an embedded app runs in a scroll loop.

**On allocation counts.** The preferred anchor is only half-available. A
deterministic `malloc_logger`-based allocation probe exists
([ConstructionProfile.swift](../Benchmarks/Sources/SwiftQLConstructionProfile/ConstructionProfile.swift),
issue #166), but it is scoped to construction and rendering, and
`BenchmarkMeasurement`
([BenchmarkTypes.swift:73-78](../Benchmarks/Sources/SwiftQLBenchmarks/BenchmarkTypes.swift#L73))
records nanoseconds only — there is no allocation field in the report schema. If
this question is ever re-opened, the correct first move is to extend that probe
across the driver phases; `sqlite3_prepare_v3` allocates the VDBE program, so
the allocation delta would be large, deterministic, and immune to machine noise.
Until then the wall-clock numbers above stand on reproducibility across runs
rather than on a single run's precision.

## 7. Recommendation

**Reject the bundled shape as a replacement for the driver contract. Adopt
hybrid C — multi-step requirements, bundled convenience extension.**

Concretely:

1. **Keep** `preparePhysical`/`bind`/`forEachRow` as the requirements.
2. **Add** a protocol extension on `XLStreamingDatabaseDriverConnection`
   providing `forEachBundledRow(_ statement:_ bindings:_ body:)` and
   `executeBundled(_:_:)`, composing the primitives. This is `boundStatement`
   ([GRDBDatabaseDriver.swift:442](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L442))
   generalised out of the GRDB executor. Adapter authors get the small surface
   for free; the two paths cannot diverge because one is defined by the other.
3. **Separately** (a pure win, independent of this decision) default
   `fetchAll`/`fetchOne` for streaming conformers, deleting the identical
   forwards at
   [GRDBDatabaseDriver.swift:615-625](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L615)
   and [SQLDriverContractTests.swift:680-686](../Tests/SwiftQLCoreTests/SQLDriverContractTests.swift#L680).
   This captures most of the §1.3 ergonomics win with none of the cost.
4. **Defer** option D (scoped `withPreparedStatement`) to the async-contract
   decision, where it belongs.
5. **Do not** adopt a `Void`-returning row callback under any design (§3).

### The strongest counterargument to this position

*"You are optimising for a caching win SwiftQL doesn't currently take. Since
`boundStatement` re-`prepare`s on every invocation
([GRDBDatabaseDriver.swift:448](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L448)),
the multi-step contract is already paying bundling's per-call cost. And the
+120% figure assumes bundling without caching — but §2.1 concedes a SQL-keyed
cache fits behind a bundled call, which is precisely what GRDB does internally.
So the honest comparison is bundled-with-cache versus multi-step-with-cache,
where the surcharge is ~zero and the smaller contract wins outright."*

This is the right objection and it is half correct. The performance comparison
does collapse for SQLite: a bundled call that internally calls
`cachedStatement(sql:)` costs the same 250 ns lookup, and the §6 table then
measures only the naive implementation. If SQLite were the only backend, the
argument would carry.

It fails on three counts:

- **It doesn't generalise.** For MySQL the bundled call is two round trips
  unless the adapter caches a server-side statement id — but a hidden cache
  cannot be told when to `COM_STMT_CLOSE`, and getting that wrong leaks
  server-side statements. The contract would be pushing a lifetime problem into
  a place with no interface to solve it (§1.4, §2.1).
- **It concedes v2.1's stated requirements.** "Preparation warm-up and metrics"
  ([ROADMAP.md:704](../ROADMAP.md#L704)) is prepare-without-execute plus
  cache-hit observability. Both are expressible only if the prepare step has
  contractual existence. A cache that works but that the core cannot observe or
  warm satisfies the letter of "caching" and none of the requirement.
- **The ergonomics win is available without the trade.** Hybrid C delivers the
  same one-call surface to adapter authors. Since the small surface can be had
  as a derived extension, paying for it by deleting the primitives is buying
  something already free.

The counterargument's real force is against option A being *catastrophic* — it
is not, for SQLite. It is against A being *worth it*, and there the answer is
that hybrid C dominates: same ergonomics, no forfeited capability, and it leaves
the async decision genuinely open.

### When to revisit

Revisit if SwiftQL commits to an async driver contract *and* PostgreSQL/MySQL
adapter prototypes show that per-connection prepared-handle caching is not worth
its complexity on those wires. At that point the choice is between bundled-async
and scoped-async (option D), and the evidence base will be adapter prototypes
rather than SQLite baselines.
