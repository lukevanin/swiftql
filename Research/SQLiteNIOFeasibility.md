# Feasibility: `vapor/sqlite-nio` as SwiftQL's native SQLite adapter

**Verdict: NO-GO.** `sqlite-nio` cannot satisfy the v2.1 native-adapter
requirements without being substantially rewritten, and adopting it would
impose swift-nio on every SwiftQL client while *removing* capabilities SwiftQL
already relies on.

Analysis performed against `vapor/sqlite-nio` `main` @ `Modernize for Swift 6.1
(#109)` (2026-07-28) and released tags up to **1.13.0**, compared against
SwiftQL's `XLDatabaseDriver`/`XLDatabaseDriverConnection` contract
([SQLDatabaseDriver.swift](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)) and
the [ROADMAP](../ROADMAP.md) v2.1 requirement list.

---

## 1. What sqlite-nio actually exposes

The entire public execution surface is one method, in two spellings:

```swift
func query(_ query: String, _ binds: [SQLiteData], _ onRow: @escaping @Sendable (SQLiteRow) -> Void) async throws
func query(_ query: String, _ binds: [SQLiteData], logger: Logger, _ onRow: @escaping @Sendable (SQLiteRow) -> Void) -> EventLoopFuture<Void>
```

Its implementation (`SQLiteConnection.query`) is, per call:
`sqlite3_prepare_v3` → `column_count` loop → bind → `step` to exhaustion →
`finalize`. `SQLiteStatement` is `internal`; there is no public prepared
statement, no cursor, and no statement handle of any kind. The source carries a
literal `// TODO:` about someday passing `SQLITE_PREPARE_PERSISTENT`.

Supporting surface: `SQLiteData` (5 cases, BLOB as NIO `ByteBuffer`),
`SQLiteRow` (eagerly materialised `[SQLiteData]` + name→offset table),
`SQLiteError`, `SQLiteCustomFunction`, and a well-built multiplexed hook
registry (`SQLiteConnection+Hooks.swift`).

## 2. Requirement-by-requirement

| v2.1 requirement (ROADMAP §v2.1) | sqlite-nio | Notes |
|---|---|---|
| Adapter-contract parity | ❌ | SwiftQL's contract is **synchronous** (`withReadConnection`, `fetchAll`, `bind` are all `mutating func … throws`). sqlite-nio is `EventLoopFuture`/`async` end to end, executing on an `NIOThreadPool`. |
| Per-connection statement preparation and caching | ❌ | No public statement type. Every execution re-prepares and finalises. SwiftQL today calls GRDB `database.cachedStatement(sql:)` ([GRDBDatabaseDriver.swift:571](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L571)). |
| Binding | ⚠️ | Positional only — `binds[i]` → index `i+1`. `XLBindingKey` has a `.named(String)` case ([SQLDialect.swift:173](../Sources/SwiftQLCore/SQLDialect.swift#L173)); no `sqlite3_bind_parameter_index` is exposed. |
| Decoding | ⚠️ | Works, but every row is fully materialised before delivery, and BLOBs arrive as `ByteBuffer`, adding a conversion at every codec boundary. |
| Transactions | ❌ | No API at all. `BEGIN`/`COMMIT`/`ROLLBACK` as text strings; no savepoints, no nesting/reentrancy guard. SwiftQL's `withTransaction` + `XLTransactionScopeError` semantics would be hand-rolled. |
| Errors | ✅ | `SQLiteError` is good; connections open with `SQLITE_OPEN_EXRESCODE`, so extended result codes are available. |
| Cancellation | ❌ | `onRow` returns `Void` — there is no early stop, so `XLRowStreamControl.stop` and `fetchOne` cannot avoid stepping the whole result set. Compounded by `SQLITE_OMIT_PROGRESS_CALLBACK` in the vendored build: no `sqlite3_progress_handler`, so long statements cannot be interrupted cooperatively. |
| Functions | ✅ | `SQLiteCustomFunction` with per-connection install/uninstall. |
| Collations | ❌ | No `sqlite3_create_collation` wrapper. |
| Observation | ⚠️ | Raw hooks only (see §5). No region tracking, no snapshot-consistent re-fetch, no busy retry — i.e. none of what `ValueObservation` gives SwiftQL's live queries today ([GRDBSQLDatabase.swift:461](../Sources/SwiftQL/GRDBSQLDatabase.swift#L461)). |
| Schema/version invalidation, safe reprepare | ➖ | Vacuously "safe" because nothing is cached — which is the same as failing the caching requirement. |
| Warm-up and metrics | ❌ | Nothing to warm up; `SQLITE_OMIT_TRACE` removes `sqlite3_trace_v2`, so no statement-level timing or SQL logging either. |
| No GRDB dependency | ✅ | Trades GRDB (zero dependencies) for swift-nio + swift-log. |

## 3. Structural blockers

**3.1 Sync/async impedance mismatch.** This is the decisive one. SwiftQL's
driver seam is synchronous by design — `PhysicalStatement` is explicitly
connection-owned and deliberately *not* `Sendable`, precisely so a cursor cannot
escape its connection access. sqlite-nio requires hopping to an `NIOThreadPool`
and awaiting a future for every operation. The three ways out are all bad:

- Block on `future.wait()` inside the driver — deadlocks if called from an
  event loop or from the thread pool itself, and serialises everything anyway.
- Make `XLDatabaseDriver`/`XLDatabaseDriverConnection` async — a breaking change
  that propagates through the executor, the static-query path, the macro-generated
  call sites, and the live-query publishers. That is a v3-scale API break, and it
  is work you would owe regardless of which SQLite backend you picked.
- Use only sqlite-nio's C target — **impossible**: `products:` exposes
  `SQLiteNIO` only, so `VaporCSQLite` is not reachable from another package.

**3.2 Toolchain floor.** SwiftQL 1.x pins `swift-tools-version: 5.9` and CI
verifies exact Swift 5.9.2 on Ubuntu 22.04 ([COMPATIBILITY.md](../COMPATIBILITY.md)).
sqlite-nio's tools-version history:

| sqlite-nio | tools-version | swift-nio floor |
|---|---|---|
| 1.7.0 | 5.7 | 2.42.0 |
| 1.8.8 | 5.7 | 2.58.0 |
| 1.9.0 | 5.8 | 2.65.0 |
| **1.13.0 (latest)** | **6.1** | **2.101.3** |

The latest release is unresolvable by a 5.9 toolchain. Pinning back to the last
5.8-era release (1.9.0) forfeits the hook API, which is the one part worth
having. For v2.1 — post-Swift-6-mode (#133) — a 6.1 floor is tolerable, but it
still hard-forecloses back-porting the adapter to the 1.x line.

**3.3 Dependency surface.** swift-nio 2.101.3 drags in NIOCore, NIOPosix,
NIOEmbedded, NIOFoundationCompat/NIOFoundationEssentialsCompat, plus
swift-atomics / swift-collections / swift-system, and swift-log. For a library
whose current runtime deps are GRDB (no dependencies) and OpenCombine, that is a
material regression in graph size, binary size, and audit surface for every
downstream iOS client — in exchange for a thinner SQLite API than the one being
replaced.

## 4. Vendored-SQLite build options: a mixed bag with one sharp edge

`VaporCSQLite` compiles amalgamation **3.53.0** with prefixed symbols
(`sqlite_nio_sqlite3_*`). Determinism is a genuine plus over linking system
libsqlite3, but the option set diverges meaningfully from what SwiftQL's
conformance census and COMPATIBILITY matrix are calibrated against (SQLite
3.53.3 via GRDB):

Enabled and useful: `FTS3/4/5`, `RTREE`, `SESSION`, `COLUMN_METADATA`,
`DBSTAT_VTAB`, `UNLOCK_NOTIFY`, `MAX_VARIABLE_NUMBER=250000`, `DQS=0`.

Also enabled: `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION`, which is worth a note
because it interacts with the #293 build validator — though **more narrowly than
the first draft of this report claimed.** Per
[sqlite.org/compile.html](https://www.sqlite.org/compile.html), the option
suppresses "unknown function" errors *only* under `EXPLAIN` and
`EXPLAIN QUERY PLAN`, substituting a no-op `unknown()`; ordinary statements still
fail to prepare. Since
[`SQLitePrepareV3Probe.prepare`](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)
passes manifest SQL verbatim with no `EXPLAIN` wrapper, the validator is *not*
defeated by this option. The residual risk is latent rather than active: wrapping
validation in `EXPLAIN` would look like a harmless optimisation and would
silently disable unknown-function detection. See
[SQLiteCFeasibility.md §1.4](SQLiteCFeasibility.md) for the measured behaviour on
Apple's SQLite (which enables this option) and for the resulting rule — never
prepare validation statements under `EXPLAIN`, on any provenance.

Omitted, and each one costs something:

- `SQLITE_OMIT_LOAD_EXTENSION` — no runtime extension loading, at all.
- `SQLITE_OMIT_PROGRESS_CALLBACK` — no cooperative interrupt (§2, cancellation).
- `SQLITE_OMIT_TRACE` — no `sqlite3_trace_v2`; no SQL logging or per-statement metrics.
- `SQLITE_OMIT_DESERIALIZE` — no `sqlite3_serialize`/`deserialize`.
- `SQLITE_OMIT_SHARED_CACHE` — multiple connections to one in-memory database
  are impossible, so an in-memory *pool* cannot exist. Low impact for SwiftQL
  today (in-memory usage is via single-connection `DatabaseQueue()`), but it
  removes an option.

## 5. Concurrency and contention

- **No pool.** One `SQLiteConnection` = one `sqlite3*`. SwiftQL's driver
  distinguishes read from write connections and leans on `DatabasePool`'s WAL
  multi-reader concurrency ([GRDBDatabaseDriver.swift:116-148](../Sources/SwiftQL/GRDBDatabaseDriver.swift#L116)).
  You would build pooling, WAL setup, and reader/writer routing yourself. The
  package's own docs concede the `SQLiteDatabase` protocol intended for pooling
  "has become clear that it was poorly designed."
- **Forced `SQLITE_OPEN_FULLMUTEX`.** Every call takes SQLite's serialized-mode
  mutex. GRDB opts for `NOMUTEX` plus its own serialization, which is cheaper.
- **Unconfigurable busy handler: `{ _, _ in 1 }`** — retry forever, no backoff,
  no timeout, no way to override. Under WAL contention this spins instead of
  surfacing `SQLITE_BUSY`, which is exactly the signal
  [GRDBLiveQueryRetryPolicy](../Sources/SwiftQL/GRDBLiveQueryRetryPolicy.swift)
  `.retryBusy` is built on.
- **No `Configuration.prepareDatabase` equivalent.** `journal_mode`,
  `foreign_keys`, `busy_timeout` etc. are text PRAGMAs you issue by hand;
  function registration must be re-run per connection with no hook to do it.
- Minor: the future-based `query` allocates one `eventLoop.submit` future *per
  result row* and `andAllSucceed`s them. A 100k-row result creates 100k
  event-loop tasks. The `async` overload does not have this problem.

## 6. What *is* worth taking

`SQLiteConnection+Hooks.swift` (871 lines) is the strongest thing in the
package: it multiplexes SQLite's single-slot update/commit/rollback/authorizer
hooks across many Swift observers, with scoped/pinned token lifetimes,
validator-vs-observer separation, and teardown on close. SwiftQL cannot register
an update hook today because GRDB owns that slot — so this design is directly
relevant to a first-party adapter's observation layer. **Take the pattern, under
its MIT licence; do not take the dependency.**

## 7. Recommendation

Build the v2.1 adapter directly against the SQLite C API, as originally planned.

1. **The prove-out already exists in-repo.** `SQLitePrepareV3Probe` +
   `SQLiteBuildValidationRuntime` already drive `sqlite3_prepare_v3`, own a
   dedicated connection, and return only copied Swift values — with a strict
   no-handle-escapes discipline that matches `XLDatabaseDriverConnection`'s
   design intent. That is the seed of the adapter, and it is synchronous.
2. **Decide the SQLite provenance question separately from the driver
   question.** If a pinned, vendored amalgamation is wanted over system
   libsqlite3, vendor a C-only target in-repo with SwiftQL's own `SQLITE_*`
   options — keeping `PROGRESS_CALLBACK` and `TRACE`, which Vapor omits —
   rather than inheriting Vapor's option set. This also cleanly decouples the
   validator from GRDB's `CSQLite`. For the full recommended option set, and for
   why the binding validator rule is "never prepare under `EXPLAIN`" rather than
   any particular compile flag, see
   [SQLiteCFeasibility.md §1.4–1.5](SQLiteCFeasibility.md).
3. **Adopt sqlite-nio's hook-multiplexing design** for the observation layer.
4. **Treat the sync→async driver-contract question as its own decision.** If
   SwiftQL is going async at v2/v3, do it deliberately in the core contract —
   not as a side effect of picking a backend that happens to be NIO-shaped.

Revisit only if sqlite-nio publicly exposes prepared statements with caching,
named binds, an early-stop row callback, and transaction/collation APIs. As of
1.13.0 none of those are on offer, and its stated direction is toward being a
Fluent/Vapor server driver, not an embedded-app storage engine.
