# Feasibility: an asynchronous database driver contract for SwiftQL

**Verdict: GO, in a reduced form — "async scope, synchronous cursor."** Make the
three *scope* methods on `XLDatabaseDriver` (`withReadConnection`,
`withWriteConnection`, `withTransaction`) async. Leave
`XLDatabaseDriverConnection` — `preparePhysical`, `bind`, `fetchAll`,
`fetchOne`, `execute`, and `forEachRow` — entirely synchronous, preserving the
non-`Sendable` `PhysicalStatement` invariant exactly as it stands today. Land it
in **v2**, after the GRDB adapter boundary ([#113]) and Swift 6 mode ([#133]),
before the native SQLite adapter ([#136]).

A fully asynchronous connection contract is **NO-GO**: it buys nothing an
embedded SQLite library can spend, and it costs the one invariant
([SQLDatabaseDriver.swift:62-70](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L62))
that currently makes cursor escape unrepresentable.

Analysis performed against the working tree at `5eb28fc`, GRDB **6.29.3**
(`.build/checkouts/GRDB.swift`, the pinned resolution), and the milestone
definitions in [ROADMAP.md](../ROADMAP.md). Evidence standard and framing follow
[SQLiteNIOFeasibility.md](SQLiteNIOFeasibility.md) §3.1, which deferred exactly
this decision.

---

## 1. Motivation, honestly assessed

Start from the baseline, because it is stark: **SwiftQL contains zero `async`
and zero `await` today.** Not one occurrence across all six targets in
`Sources/` (17,756 lines in `SwiftQL`, 3,586 in `SwiftQLCore`). There are no
actors, no `AsyncSequence`, no `AsyncStream`, no `CheckedContinuation`, and one
single `Task.isCancelled`
([GRDBSQLDatabase.swift:1291](../Sources/SwiftQL/GRDBSQLDatabase.swift#L1291)).
The library is synchronous end to end, and the 182 `Sendable` annotations exist
to make *values* safe to move, not to make execution concurrent.

### What async does not buy

- **Speed.** SQLite reads are synchronous filesystem work — `sqlite3_step` on a
  page that is in the OS cache or is not. Wrapping that in a continuation adds
  a hop and a heap allocation. On the hot path (`forEachRow`, which
  deliberately reuses one normalization buffer across rows,
  [GRDBDatabaseDriver.swift:640-655](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L640))
  async is a pure regression.
- **Concurrency.** WAL multi-reader concurrency already comes from
  `DatabasePool`, and the writer is serialized by SQLite regardless. Async
  changes *how you wait*, not *how many can proceed*.
- **Cancellation, by itself.** This is worth stating plainly because it is the
  most commonly overstated benefit. GRDB 6.29.3 contains **no**
  `withTaskCancellationHandler`, **no** `Task.isCancelled`, and **no**
  `CancellationError` anywhere in its sources — its async `read` is a bare
  `withUnsafeThrowingContinuation` over `asyncRead`
  (`GRDB/Core/DatabaseReader.swift` line 462).
  Making SwiftQL async over GRDB 6 therefore propagates cancellation *not at
  all* unless SwiftQL builds it. See §4.

### What async genuinely buys

1. **Not blocking a cooperative-pool thread — the strongest argument, and it
   is a live hazard today.** A caller who writes `Task { try db.personByID(...) }`
   blocks a cooperative thread pool thread for the whole duration of the read.
   The pool is sized to the core count; on a 2-core device, two concurrent
   SwiftQL reads can starve the pool, and under Swift 6's forward-progress
   model that is a bug, not a slowdown — the runtime assumes pool threads make
   progress. This hazard exists *now*, and the ROADMAP already advertises the
   fix: its target developer experience is spelled
   `func personByID(id: UUID) async throws -> Person?`
   ([ROADMAP.md:215](../ROADMAP.md#L215)). SwiftQL is currently unable to honour
   its own published target API — the `@SQLQuery` macro **rejects** an `async`
   declaration with a diagnostic today
   ([SQLQueryMacro.swift:190-198](../Sources/SQLMacros/SQLQueryMacro.swift#L190)).
2. **Network-backed dialects in v2.2–v2.4.** PostgreSQL, MySQL, and T-SQL are
   genuinely I/O-bound over a socket. There is no defensible synchronous
   design for them. If the driver contract is still synchronous when [#137]
   (PostgreSQL vertical slice) starts, the contract breaks then instead — with
   a second adapter already written against it.
3. **Structured cancellation, once built.** Real, but it is work (§4), not a
   free consequence of the `async` keyword.
4. **Backpressure — the weakest of the four, and it argues *against* async row
   iteration.** Backpressure over a SQLite cursor requires holding the cursor
   while the consumer is slow, which means holding a connection out of the
   pool for an unbounded period. That is worse than materializing. The repo has
   already reached this conclusion independently: [#249] mandates a
   *synchronous* scoped `XLResultSet` and explicitly defers async row iteration
   because "it needs an explicit backpressure, cancellation, and
   connection-lifetime contract" ([ROADMAP.md:282](../ROADMAP.md#L282)).

**Net:** (1) and (2) are sufficient on their own and are about the *scope*
boundary. (4) is a reason not to go further. That asymmetry is the whole
recommendation.

## 2. Blast radius

### 2a. Full async contract (both protocols) — rejected

| Layer | File | Lines | Character |
|---|---|---|---|
| Contract | [SQLDatabaseDriver.swift](../Sources/SwiftQLCore/SQLDatabaseDriver.swift) | 327 | **Redesign.** 9 protocol requirements + 9 extension helpers; the `PhysicalStatement` non-`Sendable` invariant is invalidated (§3) |
| Driver adapter | [GRDBDatabaseDriver.swift](../Sources/SwiftQL/GRDBDatabaseDriver.swift) | 900 | Mixed. Scope methods redesigned; `GRDBInvocationExecutor` mechanical; reentrancy tracker **redesign** (§4) |
| Request layer | [GRDBSQLDatabase.swift](../Sources/SwiftQL/GRDBSQLDatabase.swift) | 1,313 | Mostly mechanical, except `publisher(fetch:)` which **cannot** go async (§2c) |
| Static queries | [GRDBStaticQuery.swift](../Sources/SwiftQL/GRDBStaticQuery.swift) | 748 | Mechanical — 8 public entry points |
| Public protocols | [SQLDatabase.swift](../Sources/SwiftQL/SQLDatabase.swift) | — | **Source break.** `XLRequest` (5 fetch methods), `XLWriteRequest` (2) |
| Transaction scope | [SQLTransactionScope.swift](../Sources/SwiftQL/SQLTransactionScope.swift) | — | `XLTransactionalDatabase.withTransaction` + its 3-case error enum |
| Publishers | [GRDBOpenCombineValuePublisher.swift](../Sources/SwiftQL/GRDBOpenCombineValuePublisher.swift), [GRDBLiveQueryRetryPolicy.swift](../Sources/SwiftQL/GRDBLiveQueryRetryPolicy.swift) | 343 | **Blocked** (§2c) |
| Macros | [SQLQueryMacro.swift](../Sources/SQLMacros/SQLQueryMacro.swift), [SQLQueriesMacro.swift](../Sources/SQLMacros/SQLQueriesMacro.swift) | 3,477 | Small and localized: 1 diagnostic + 4 signature-emission sites + 4 `try`-emission sites |

**Public entry points that change signature: 16.** `XLRequest` ×5,
`XLWriteRequest` ×2, `GRDBStaticQuery` ×8 (`execute`,
`fetchExactlyOneValues`, `fetchZeroOrOneValues`, `fetchAllValues`,
`forEachValueRow`, `fetchExactlyOne`, `fetchZeroOrOne`, `fetchAll`),
`XLTransactionalDatabase.withTransaction` ×1.

**Test churn: ~771 call sites** across 105 files / 49,120 lines — `fetchAll(`
197, `fetchOne(` 136, `execute(` 339, `withTransaction` 69, `fetchExactlyOne`
22, `fetchZeroOrOne` 4, `fetchAllValues` 3, `fetchAtMost(` 1. Nearly all
mechanical (`try` → `try await`, `func test…` → `func test…() async throws`),
but it is ~771 edits and every XCTest expectation-based timing test needs
re-examination. Two contract suites are the real work:
`SQLDriverContractTests.swift` (790 lines) and `GRDBDriverContractTests.swift`
(1,004 lines).

Docs: 12 DocC pages carry `try`-prefixed examples (137 occurrences), all of
which are compiled documentation examples.

### 2b. Reduced form (async scope only) — recommended

The contract diff shrinks to **3 protocol requirements + 1 extension helper**
(`withValidatedTransaction`). `XLDatabaseDriverConnection` — 6 requirements,
6 `*Validated` helpers, `collectAllRows`/`collectFirstRow` — is **untouched**,
and `PhysicalStatement` stays non-`Sendable` with the same guarantee it has
today.

The public-API and test churn in §2a is *not* avoided by the reduced form
(§5 explains why, and why that is acceptable). What the reduced form avoids is
the redesign column: the cursor invariant, the streaming seam, and the
row-normalization hot path all survive unchanged.

### 2c. The live-query path cannot go async at all — a hard constraint

`GRDBSQLDatabase.publisher(fetch:)` calls
`ValueObservation.tracking(fetch)` with a closure typed
`(Database) throws -> T`
([GRDBSQLDatabase.swift:450-462](../Sources/SwiftQL/GRDBSQLDatabase.swift#L450)).
`ValueObservation` re-runs that closure itself, on its own scheduler, whenever
the tracked region changes. **It has no async overload and cannot take one** —
region tracking works by observing which statements the closure executes during
a synchronous database access.

So `publish()`, `publishOne()`, and the [#308] `AsyncThrowingStream` work
planned for v1.5.5 must all keep calling the **synchronous** connection
contract, forever, regardless of what the scope methods do. Under the full
async contract this layer would need a duplicate synchronous execution path —
i.e. the full contract does not eliminate the sync contract, it merely adds to
it. Under the reduced form this falls out for free, because the connection
contract that `ValueObservation` needs is the one that never changed.

This also confirms the milestone split is already correct: **[#308] async
live-query streams do not depend on an async driver contract.** They are async
at the delivery boundary over a synchronous fetch. v1.5.5 can proceed untouched.

## 3. The cursor-confinement problem

The invariant at stake is stated in the contract itself: `PhysicalStatement` is
"intentionally connection-owned and is not required to be `Sendable`"
([SQLDatabaseDriver.swift:62-70](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L62)),
and `forEachRow`'s callback is synchronous "so a driver cursor and its owning
connection cannot escape through this value"
([SQLDatabaseDriver.swift:98-105](../Sources/SwiftQLCore/SQLDatabaseDriver.swift#L98)).
An `await` inside the cursor loop breaks this by construction: a value held
across a suspension point outlives the synchronous access that owned it.

**What GRDB does, and why.** GRDB marks *both* relevant types explicitly
non-`Sendable`, with a comment giving the reason:

```swift
// Explicit non-conformance to Sendable: statements must be used from
// a serialized database access dispatch queue.
@available(*, unavailable)
extension Statement: Sendable { }
```
(`GRDB/Core/Statement.swift` line 626;
identical treatment for `Database` at
`GRDB/Core/Database.swift` line 1737.)

And GRDB's async API is shaped **exactly** like the reduced form recommended
here — async at the scope, synchronous inside:

```swift
public func read<T>(_ value: @Sendable @escaping (Database) throws -> T) async throws -> T
```

Note the closure: `throws`, not `async throws`. GRDB — a mature, heavily
concurrency-audited library — deliberately declines to let anything be awaited
while a `Database` is in hand. That is the strongest available evidence for
option (d).

| Option | Verdict |
|---|---|
| **(a) Actor-isolated connection** | **No.** Actors are *reentrant*: another task can interleave on the same actor at every `await`, so a half-stepped cursor is exposed to interleaved access — the precise hazard the current design forbids. Non-`Sendable` `PhysicalStatement` cannot cross the actor boundary anyway, and per-row actor hops would dominate the row cost. |
| **(b) `~Copyable`/`borrowing` statement** | **No — not expressible.** A `borrowing` binding cannot span a suspension point; the borrow must end before the `await`. Noncopyability prevents *duplication*, which was never the failure mode — escape and interleaving are. It solves the wrong problem, and cannot solve it across `await` in any case. |
| **(c) `AsyncSequence` row streaming** | **No.** Every `next()` is a suspension point, so the connection is pinned out of the pool for the consumer's lifetime, at the consumer's pace. Unbounded connection occupancy under WAL is a deadlock source, not backpressure. [#249] already rules this out for the synchronous result set on the same grounds. |
| **(d) Sync iteration inside an async scope** | **Yes.** `withReadConnection` is `async`; the body is synchronous; the cursor provably cannot outlive it because there is no suspension point available to it. Zero change to `forEachRow`, the reused normalization buffer, or `XLRowStreamControl`. This is GRDB's answer. |

## 4. Swift concurrency mechanics

**Sendability.** Dialect values are already fine — `XLSQLiteValue` and the
binding packets are `Sendable`, which is what the 182 existing annotations buy.
The `Result` generic on the scope methods gains a `Sendable` requirement (it
crosses the suspension point). `PhysicalStatement` must **remain**
non-`Sendable`; under the reduced form it never crosses an isolation boundary,
so nothing is needed beyond leaving it alone.

**Isolation model: serial executor, not actor-per-connection.** GRDB's
`asyncRead`/`asyncWrite` already own a serialized dispatch queue per connection
(`SerializedDatabase`). Layering an actor on top would add a second
serialization point and, worse, would add *reentrancy* where the dispatch queue
provides none. The adapter should surface GRDB's existing serialization, not
replace it. For the [#136] native adapter, the same shape applies: one serial
executor per `sqlite3*`, connection state confined to it.

**Reentrancy — the concrete must-fix.** SwiftQL guards reentrant transactions
with `GRDBTransactionScopeTracker`, and it is implemented with
**`Thread.current.threadDictionary`**
([GRDBDatabaseDriver.swift:895-899](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L895)).
Its own documentation states the assumption it rests on: *"Scoped
per-`Thread` rather than per-pool: `body` runs synchronously to completion, so a
call nested inside it is necessarily on the same thread as the active scope"*
([GRDBDatabaseDriver.swift:844-847](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L844)).

Async invalidates that premise in both directions. A task that suspends inside
an async `body` may resume on a different thread — so a genuinely reentrant call
is **missed** (unsound); and an unrelated task scheduled onto a thread whose
dictionary was not cleaned up is **falsely rejected** (incomplete). This is not
a tolerable degradation, because the thing it guards is not recoverable: GRDB's
reentrant-write guard is an unconditional `fatalError("Database methods are not
reentrant.")` that fires before any SwiftQL code runs. A missed guard is a
crash, not a thrown `XLTransactionScopeError`.

The fix is a `@TaskLocal` marker rather than a thread dictionary. It is small
(one type, ~40 lines) but it is a genuine redesign with its own test matrix, and
async makes the failure it prevents *easier* to reach — `try await
db.withTransaction { ... try await somethingElse() ... }` is a natural thing to
write and an invitation to nest. It should be treated as a first-class
deliverable of this work, not a follow-up.

**Cancellation propagation.** Today: one pre-flight `Task.isCancelled` check
before opening a transaction
([GRDBSQLDatabase.swift:1291](../Sources/SwiftQL/GRDBSQLDatabase.swift#L1291)),
honestly documented as having "no later cooperative cancellation point."
Async does not improve this for free — as established in §1, GRDB 6.29.3 has no
cancellation handling whatsoever. Building it means:

- `withTaskCancellationHandler` around the scope, calling `interrupt()`;
- but GRDB exposes `interrupt()` only on the **pool**
  (`GRDB/Core/DatabasePool.swift` line 299),
  which calls `sqlite3_interrupt` on every connection
  (`GRDB/Core/Database.swift` line 1079).
  Cancelling one task would abort **unrelated in-flight reads** on other
  connections. Per-statement interruption is not reachable through GRDB 6's
  public API.

So: usable cancellation is a **[#136] native-adapter capability**, not a v2 GRDB
one. The v2 GRDB adapter should ship the async scope with cancellation checked
at scope entry and at each `XLRowStreamControl` decision point — cheap, sound,
and honest — and document that mid-statement interruption arrives with the
native adapter. (SwiftQL calls neither `sqlite3_interrupt` nor
`sqlite3_progress_handler` anywhere today; both are net-new.)

**Priority inversion.** GRDB's async `read` is
`withUnsafeThrowingContinuation` over a dispatch queue at a fixed QoS. Swift
priority donation does not cross that boundary: a `.userInitiated` task awaiting
behind a `.utility` write gets no escalation. Not fixable inside SwiftQL against
GRDB 6 — it is fixable in the [#136] adapter by owning the executor. Worth
documenting as a known v2 limitation rather than hidden.

## 5. Migration and source compatibility

**The toolchain floor is not the obstacle — say this plainly.** `async`/`await`
requires Swift 5.5 and, on Apple platforms, iOS 13 / macOS 10.15. SwiftQL pins
`swift-tools-version: 5.9` with `platforms: [.iOS(.v16), .macOS(.v13)]`
([Package.swift:1,9](../Package.swift#L9)), and CI verifies exact Swift 5.9.2 on
Ubuntu 22.04 ([COMPATIBILITY.md](../COMPATIBILITY.md)). Every one of those
floors is comfortably above what async needs. **An async contract does not
require raising the 5.9 floor.** The thing that raises the floor is Swift 6
*language mode* ([#133]), which is a separate, already-planned v2 decision.
Async could technically ship in 1.x; the argument against is API-break scope
(below), not toolchain.

**Can both contracts coexist? Yes — but only in the reduced form.** This is the
decisive structural argument:

- **Sync facade over async: unsafe. Never do this.** It requires blocking on a
  semaphore to await a continuation, which is precisely the cooperative-pool
  forward-progress hazard from §1, deliberately reintroduced. It also deadlocks
  if the awaited work needs the calling thread.
- **Async facade over sync: safe, and genuinely non-blocking here** — because
  GRDB's `asyncRead` enqueues and returns rather than blocking, so a SwiftQL
  `async fetchAll()` layered on it really does free the cooperative thread. This
  is not a fake async wrapper.
- **Both, side by side: the actual recommendation.** Because the *connection*
  contract stays synchronous in both, duplication is confined to the scope
  layer: `XLDatabaseDriver` grows from 3 methods to 6 (3 sync + 3 async), and
  `XLRequest` from 5 fetch methods to 10. The connection protocol, the
  streaming seam, the row-normalization hot path, and every `*Validated` helper
  are shared verbatim. Under a *full* async contract this sharing is impossible
  and you maintain two complete execution stacks — which, per §2c, you would be
  forced into anyway by `ValueObservation`.

**What breaks for downstream clients.** In the coexistence design: nothing, at
first. Existing sync call sites keep compiling; async is additive. That makes it
shippable inside v2 alongside the other breaks rather than as a v3 event. The
sync surface should be deprecated on the same schedule as the [#113] adapter
boundary and removed no earlier than v3. Third-party `XLDatabaseDriver`
conformers do break — but that population is small and [#113] is already
reshaping that protocol in the same milestone, which is the ordering argument in
§6.

**Macro source stability: yes, and it is close to free.** The macro reads the
user's declared signature and today *rejects* effect specifiers outright
([SQLQueryMacro.swift:190-198](../Sources/SQLMacros/SQLQueryMacro.swift#L190)).
Replacing that rejection with a branch — declare `throws`, get the sync
executor; declare `async throws`, get `try await` — makes the *user's own
declaration* select the path, so existing declarations stay source-stable while
new ones opt in. The emission sites are hardcoded string builders
([SQLQueryMacro.swift:684](../Sources/SQLMacros/SQLQueryMacro.swift#L684),
[SQLQueriesMacro.swift:171,210,260](../Sources/SQLMacros/SQLQueriesMacro.swift#L171)):
4 signature sites, 4 `try` sites, 1 diagnostic. This is also what finally lets
SwiftQL deliver the `async throws` spelling its own ROADMAP has been publishing
since v1.

## 6. Milestone placement

**v2**, sequenced **after [#113] and [#133], before [#136].**

- **After [#113] (GRDB adapter boundary).** [#113] is the issue that re-cuts the
  adapter contract — it already lists "cancellation" and "concurrency/isolation
  behavior" in its scope. Changing the same protocol twice in one milestone is
  pure waste, and doing async *first* means [#113] re-does it.
- **After [#133] (Swift 6 mode).** Strict concurrency is what makes the
  sendability and isolation obligations in §4 *compiler-checked* rather than
  reviewed by hand. Writing an isolation model in Swift 5 mode and validating it
  later is the expensive ordering. [#133] is already a P2 v2 release gate.
- **Before [#136] (v2.1 native SQLite adapter).** [#136] is a from-scratch
  adapter. It must be written once, against the final contract. Writing it
  synchronously and converting it in v2.2 doubles the most expensive single
  piece of work on the roadmap — and §4 shows [#136] is also where real
  cancellation and executor control actually become implementable.
- **Well before v2.2 ([#137], PostgreSQL).** A network dialect has no
  synchronous design worth shipping. If the contract is still sync then, it
  breaks then, with two adapters already built on it.
- **Not in v1.5.5.** [#308]/[#309] are async at the *delivery* boundary over a
  synchronous `ValueObservation` fetch (§2c) and have no dependency on this
  work. [#249] is deliberately synchronous. v1.5.5 proceeds unchanged; this
  analysis reinforces that split rather than disturbing it.

Suggested decomposition (one issue each, in order): async scope methods on the
contract + `withValidatedTransaction`; `@TaskLocal` reentrancy tracker
replacing the thread-dictionary one; GRDB adapter async scope implementation;
additive async `XLRequest`/`XLWriteRequest`/`XLTransactionalDatabase` surface;
macro effect-specifier passthrough; async contract test suite. The reentrancy
tracker is the only item that is not mechanical, and it is the one that must
not be deferred.

## 7. Recommendation

**Do it, in the reduced form: async scope, synchronous cursor. Land it in v2
between [#113]/[#133] and [#136].**

Concretely — `withReadConnection`, `withWriteConnection`, `withTransaction`
become `async`; `XLDatabaseDriverConnection` and `XLRowStreamControl` do not
change at all; the sync scope methods remain alongside for one major version;
`GRDBTransactionScopeTracker` moves to `@TaskLocal`; the macro passes the user's
effect specifiers through; and mid-statement cancellation is documented as
arriving with [#136], not v2.

The case rests on two things and not on performance: SwiftQL currently blocks
cooperative-pool threads and cannot express the `async throws` API its own
ROADMAP advertises; and v2.2's PostgreSQL adapter has no synchronous design, so
the contract breaks in v2.2 if it does not break in v2 — by which point two
adapters are built on it.

### The strongest counterargument, addressed

*"If the connection contract stays synchronous, you have not really gone async.
A network dialect needs to await per row, per packet — so the reduced form
solves the on-device problem and then fails exactly where you claim its main
justification lies (v2.2 PostgreSQL)."*

This is the real objection, and it is partly right. The response has three
parts, the last of which is a concession:

1. **The common case is genuinely covered.** A non-cursor PostgreSQL query is
   one round trip: send `Parse`/`Bind`/`Execute`, await, receive the complete
   `DataRow` set. An async `withReadConnection` gives the adapter exactly the
   suspension point it needs to do that I/O, and rows are then handed to
   `forEachRow` synchronously from a local buffer. This is how most client
   drivers behave by default, and it is a correct, complete implementation of
   the contract.
2. **Where it does not cover — server-side cursors, `DECLARE`/`FETCH`, streamed
   `COPY` — the alternative is not better.** Awaiting per row means holding a
   server-side cursor and a pooled connection at the consumer's pace, which is
   the same unbounded-occupancy failure §3(c) rejects for SQLite, with network
   timeouts added. A row-batching design (await per *chunk*, iterate the chunk
   synchronously) fits the reduced contract unchanged and is what a competent
   PostgreSQL adapter should do regardless.
3. **The concession: this is not fully settled, and should not be settled
   now.** True streaming for a network dialect may want a third seam — an async
   *batch* provider beneath the synchronous row callback. Whether it does is a
   question that needs a real dialect in hand, not speculation from an
   SQLite-only codebase. That is precisely what [#137]'s "vertical slice" framing
   exists to answer. The reduced form is chosen partly *because* it leaves that
   door open: adding an async batch seam later is additive, whereas having
   already made `forEachRow` async would have destroyed the cursor invariant
   for every adapter to buy a capability only one of them needed.

The symmetric counterargument — *"async buys an embedded library nothing, so do
nothing"* — is answered by §1: the cooperative-pool blocking hazard is real
today, is a correctness issue under Swift 6 rather than a performance one, and
the ROADMAP has been publishing the async spelling as the target API since v1.
Doing nothing is the option that requires the retraction.

---

[#113]: https://github.com/lukevanin/swiftql/issues/113
[#133]: https://github.com/lukevanin/swiftql/issues/133
[#136]: https://github.com/lukevanin/swiftql/issues/136
[#137]: https://github.com/lukevanin/swiftql/issues/137
[#249]: https://github.com/lukevanin/swiftql/issues/249
[#308]: https://github.com/lukevanin/swiftql/issues/308
[#309]: https://github.com/lukevanin/swiftql/issues/309
