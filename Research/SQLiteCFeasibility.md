# Feasibility: a direct SQLite C adapter for SwiftQL v2.1

**Verdict: GO, with conditions.** Every v2.1 requirement in
[ROADMAP.md:696-705](../ROADMAP.md) is reachable directly against the SQLite C
API, and SwiftQL's driver contract is unusually well shaped for it — the seam is
synchronous, `PhysicalStatement` is deliberately connection-owned and not
`Sendable`, and the streaming seam already forbids a cursor from escaping its
connection access. The cost is not distributed evenly: roughly 80% of the
requirement list is small, mechanical, and provable in the first two weeks, and
one requirement — observation — is larger than everything else combined.

The four conditions are stated in §7. The load-bearing ones are that observation
ships as its own slice with an explicit reduced-fidelity fallback, and that the
SQLite provenance decision is made *before* the adapter is written, not after.

This report is the follow-on to
[SQLiteNIOFeasibility.md](SQLiteNIOFeasibility.md), whose §7.1 asserted that
"the prove-out already exists in-repo." §5.1 below tests that claim and finds it
half true.

Analysis performed against the worktree at `5eb28fc` (SwiftQL v1.5.2), GRDB
6.29.3 as resolved in `.build/checkouts/GRDB.swift`, and SQLite as shipped in
the macOS 26.5 SDK (`SQLITE_VERSION "3.51.0"`,
`SQLITE_SOURCE_ID "2025-06-12 …f0ca7bba…apl"`).

---

## 0. What was actually checked

Claims in this report come from one of four places, and are marked accordingly:

- **in-repo** — a file:line in this worktree or in the resolved GRDB checkout;
- **header** — the SDK's `sqlite3.h` at
  `$(xcrun --show-sdk-path)/usr/include/sqlite3.h`;
- **measured** — a command run on this machine, with the command shown;
- **upstream** — sqlite.org documentation, quoted.

Two findings below correct or update existing repository documents. They are
flagged inline: §1.4 (the `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` characterisation
in the sqlite-nio report is narrower than stated) and §1.2
([COMPATIBILITY.md:146](../COMPATIBILITY.md) is stale about
`SQLITE_ENABLE_SNAPSHOT`).

---

## 1. SQLite provenance

### 1.1 What is linked today, and why it already fails a v2.1 requirement

SwiftQL already contains direct-C SQLite code. It reaches `sqlite3_prepare_v3`
through GRDB:

```swift
// Package.swift:157-165
.target(
    name: "SwiftQLSQLiteBuildValidationValidator",
    dependencies: [
        …
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "CSQLite", package: "GRDB.swift"),
    ]
),
```

`CSQLite` is GRDB's target, not SwiftQL's, and it is a **system library**:

```swift
// .build/checkouts/GRDB.swift/Package.swift:49-51
.systemLibrary(
    name: "CSQLite",
    providers: [.apt(["libsqlite3-dev"])]),
```

```
// .build/checkouts/GRDB.swift/Sources/CSQLite/module.modulemap
module CSQLite [system] {
    header "shim.h"
    link "sqlite3"
    export *
}
```

Two consequences follow immediately, and both are independent of which
provenance option is chosen:

1. **SwiftQL must own its own C module target regardless.** ROADMAP.md:705
   requires "no GRDB dependency for clients selecting the native adapter."
   Today the only route to `sqlite3_*` symbols is a GRDB product. A
   `CSwiftQLSQLite` target is a prerequisite for *every* other slice, and it is
   the cheapest thing on the list.

2. **That target must include a C shim, not just a module map.** GRDB's
   `shim.h` exists because two SQLite entry points are variadic and therefore
   uncallable from Swift:

   ```c
   // .build/checkouts/GRDB.swift/Sources/CSQLite/shim.h
   static inline void _registerErrorLogCallback(_errorLogCallback callback) {
       sqlite3_config(SQLITE_CONFIG_LOG, callback, 0);
   }
   static inline void _disableDoubleQuotedStringLiterals(sqlite3 *db) {
       sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 0, (void *)0);
       sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 0, (void *)0);
   }
   ```

   `sqlite3_config` and `sqlite3_db_config` are the only way to reach
   `SQLITE_DBCONFIG_DQS_*`, `SQLITE_DBCONFIG_DEFENSIVE`,
   `SQLITE_DBCONFIG_ENABLE_FKEY`, and the error-log callback. A native adapter
   that skips the shim silently forfeits all of them. §1.5 explains why DQS in
   particular is not optional.

### 1.2 Option A — system `libsqlite3` via a `CSwiftQLSQLite` module map

This is what GRDB does and what SwiftQL therefore already ships on. The version
question is where it gets uncomfortable.

**Apple platforms.** The SDK header pins `SQLITE_VERSION "3.51.0"` with source
ID ending `…apl` — Apple's patched build, not an upstream SQLite.org source ID.
The compile options are not what an upstream build produces
(measured, `sqlite3 :memory: "pragma compile_options;"` on macOS 26.5):

```
CODEC=see-cccrypt            DQS=3                    ENABLE_API_ARMOR
ENABLE_COLUMN_METADATA       ENABLE_FTS3/4/5          ENABLE_MATH_FUNCTIONS
ENABLE_PREUPDATE_HOOK        ENABLE_SNAPSHOT          ENABLE_STMT_SCANSTATUS
ENABLE_UNKNOWN_SQL_FUNCTION  MAX_VARIABLE_NUMBER=500000
OMIT_LOAD_EXTENSION          THREADSAFE=2             MUTEX_UNFAIR
```

Three of these matter for SwiftQL and are discussed below: `DQS=3` (§1.5),
`MAX_VARIABLE_NUMBER=500000` (§1.5), and `ENABLE_UNKNOWN_SQL_FUNCTION` (§1.4).
The version is tied to the OS release and is not selectable by the application —
an iOS 16 device and an iOS 18 device link different SQLite libraries from the
same app binary.

**Linux.** The repository has already hit the floor problem and documented it:

> Ubuntu 22.04's system SQLite 3.37 predates `UNIXEPOCH`, which is a required
> capability in SwiftQL's real-SQLite conformance corpus.
> — [COMPATIBILITY.md:129-131](../COMPATIBILITY.md)

CI's response was to stop using the system library and build the amalgamation —
i.e. **the project already rejected pure Option A on one of its two pinned
support points.**

**Version spread today.** Conformance evidence is captured against SQLite 3.51.0
([COMPATIBILITY.md:69-71](../COMPATIBILITY.md)); Linux CI runs 3.53.3
([COMPATIBILITY.md:112](../COMPATIBILITY.md)). Under Option A a shipped iOS app
adds a third, fourth, and fifth version that no CI cell ever exercised.

> **Documentation drift found.** [COMPATIBILITY.md:145-148](../COMPATIBILITY.md)
> states that "the pinned amalgamation intentionally leaves that optional
> [snapshot] API disabled." The workflow contradicts this: it compiles with
> `-DSQLITE_ENABLE_SNAPSHOT`
> ([.github/workflows/swift.yml:512](../.github/workflows/swift.yml)), asserts
> `sqlite3_snapshot_get` is an exported symbol
> ([swift.yml:520](../.github/workflows/swift.yml)), and passes
> `-DSQLITE_ENABLE_SNAPSHOT` to `swiftc`
> ([swift.yml:541](../.github/workflows/swift.yml)). This is not a cosmetic
> discrepancy — snapshot availability is the pivot in §4.3 between
> snapshot-consistent and writer-serialized observation.

### 1.3 Option B — vendor the amalgamation in-repo

Also partly pre-proven. CI already downloads a SHA3-256-verified amalgamation
and compiles it with a SwiftQL-chosen option set
([swift.yml:494-516](../.github/workflows/swift.yml)):

```sh
cc -O2 -fPIC \
  -DSQLITE_THREADSAFE=1 \
  -DSQLITE_ENABLE_COLUMN_METADATA \
  -DSQLITE_ENABLE_FTS5 \
  -DSQLITE_ENABLE_MATH_FUNCTIONS \
  -DSQLITE_ENABLE_SNAPSHOT \
  -shared "$sqlite_source/sqlite3.c" -o …/libsqlite3.so
```

Moving this from workflow shell into a SwiftPM `.target` with `cSettings:
[.define(…)]` is straightforward. `.define` is not an unsafe flag, so a
downstream package can still depend on SwiftQL — this is the constraint that
would bite if the build needed `.unsafeFlags`, and it does not.

Two costs are specific to vendoring and neither is theoretical.

**Binary size.** Upstream figures, `-Os`, no optional features:

| Platform | Compiler | Size |
|---|---|---|
| MacOS M1 | clang 14.0.0 | 750 KB |
| Ubuntu 20.04.5 x64 | gcc 9.4.0 | 650 KB |

— [sqlite.org/footprint.html](https://www.sqlite.org/footprint.html), as of
2023-07-04; larger with FTS5 and RTREE. Against system `libsqlite3`, which lives
in the dyld shared cache on Apple platforms, the marginal app cost is
effectively zero. Roughly 0.75–1 MB is the honest sticker price of determinism.

**Symbol collision — the sharp edge of Option B.** During v2.1 both adapters
ship, so one binary can link the GRDB adapter (which resolves `sqlite3_*`
dynamically against system `libsqlite3`) *and* a statically-linked amalgamation
defining the same symbols. Static definitions satisfy undefined symbols before
the dylib is consulted, so GRDB would silently start executing against the
vendored library — a different version, different options, and a different
`sqlite3_source_id()` than the one CI reports. `vapor/sqlite-nio` solves exactly
this by prefixing every symbol (`sqlite_nio_sqlite3_*`). **If Option B is
chosen, symbol prefixing is mandatory, not optional**, and proving it is a
day-one task (§6, S0). It is the single most likely source of a
"works-in-CI, wrong-in-app" failure in this whole plan.

**App Store.** No App Store rule prohibits either option. System `libsqlite3` is
a public SDK library (`libsqlite3.tbd`); vendoring adds the bytes above to the
app download. Neither triggers review issues. This is a size and determinism
decision, not a policy one.

### 1.4 The `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` trap — narrower than reported

[SQLiteNIOFeasibility.md §4](SQLiteNIOFeasibility.md) states that with this
option enabled, "`sqlite3_prepare_v3` *accepts* statements calling functions that
do not exist," and that build validation against such a SQLite "would silently
stop catching misspelled or unregistered function names." The effect is real but
scoped more narrowly than that, and the correction changes the risk assessment.

Upstream, verbatim:

> When the SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION compile-time option is activated,
> SQLite will suppress "unknown function" errors when running an EXPLAIN or
> EXPLAIN QUERY PLAN. Instead of throwing an error, SQLite will insert a
> substitute no-op function named "unknown()". The substitution of "unknown()"
> in place of unrecognized functions only occurs on EXPLAIN and EXPLAIN QUERY
> PLAN, not on ordinary statements.
> — [sqlite.org/compile.html](https://www.sqlite.org/compile.html)

Measured on Apple's SQLite 3.51.0, which **has the option enabled** (§1.2):

| Statement | `sqlite3_prepare` |
|---|---|
| `SELECT no_such_fn(1);` | **FAIL** — `no such function` |
| `SELECT lenght('a');` (misspelled builtin) | **FAIL** |
| `CREATE TABLE t(a); SELECT no_such_fn(a) FROM t;` | **FAIL** |
| `EXPLAIN SELECT no_such_function_xyz(1);` | **OK** — accepted |
| `EXPLAIN QUERY PLAN SELECT no_such_fn(1);` | **OK** — accepted |

Three conclusions:

1. **The #293 validator is not currently defeated.**
   [`SQLitePrepareV3Probe.prepare`](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift#L158-L165)
   passes the manifest SQL to `sqlite3_prepare_v3` verbatim with `prepFlags: 0` —
   no `EXPLAIN` wrapper. Unknown-function detection works today on Apple's
   build despite the option being on.

2. **The trap is a latent one, and it is pointed at a plausible future change.**
   Wrapping validation in `EXPLAIN` is an obvious-looking optimisation ("we only
   want the plan, not the statement"). Doing so would silently disable
   unknown-function detection on every Apple platform — where the option is
   already enabled and outside SwiftQL's control. This belongs in the
   validator's own test suite as a negative control, not in a design document.

3. **For a vendored build the rule is still "do not enable it,"** but the
   binding constraint is the stronger one: *never prepare validation statements
   under `EXPLAIN`*, on any provenance. The second rule subsumes the first.

### 1.5 Recommended `SQLITE_*` option set

The governing principle: **the vendored option set must not create capabilities
that do not exist on the system path.** v2.1 requires the shared corpus to pass
on both adapters ([ROADMAP.md:702-703](../ROADMAP.md)); if a vendored build
enables something Apple's build omits, the corpus splits and the conformance
inventory stops meaning one thing.

| Option | Setting | Justification |
|---|---|---|
| `SQLITE_THREADSAFE` | `=1` | Matches [swift.yml:508](../.github/workflows/swift.yml). Serialized *default*, but per-connection `SQLITE_OPEN_NOMUTEX` downgrades individual connections — upstream: "The SQLITE_OPEN_NOMUTEX and SQLITE_OPEN_FULLMUTEX flags … can also be used to adjust the threading mode of individual database connections at run-time." `=2` would foreclose ever opting a connection back into FULLMUTEX. See §3.1. |
| `SQLITE_DQS` | `=0` | **Non-negotiable.** Upstream: "The recommended setting is 0 … the default setting is 3 for maximum compatibility with legacy applications." Apple ships `DQS=3` (§1.2). With DQS on, a misspelled quoted identifier silently degrades into a string literal, which SwiftQL's renderer cannot catch and the #293 validator cannot see. On the *system* path this must be set per-connection via the shim's `sqlite3_db_config(SQLITE_DBCONFIG_DQS_DDL/DML, 0)` — exactly as GRDB does. |
| `SQLITE_ENABLE_FTS5` | on | Already required: GRDB defines it (`GRDB.swift/Package.swift:8` in the resolved checkout), CI builds it ([swift.yml:510](../.github/workflows/swift.yml)), Apple ships it. |
| `SQLITE_ENABLE_MATH_FUNCTIONS` | on | Same three-way agreement ([swift.yml:511](../.github/workflows/swift.yml)). |
| `SQLITE_ENABLE_COLUMN_METADATA` | on | Same ([swift.yml:509](../.github/workflows/swift.yml)). Also supplies `sqlite3_column_table_name`/`_origin_name`, which is the cheapest route to mapping result columns back to source tables for observation region inference (§4.2). |
| `SQLITE_ENABLE_SNAPSHOT` | on | Already enabled and symbol-asserted in CI ([swift.yml:512, 520](../.github/workflows/swift.yml)) and present in Apple's build. This is the pivot for §4.3 — without it, observation must fall back to writer-serialized re-fetch. |
| `SQLITE_USE_URI` | `=1` | Required for `file:name?mode=memory&cache=shared`, i.e. for an in-memory *pool* rather than a single in-memory connection. Apple ships it. |
| `SQLITE_MAX_VARIABLE_NUMBER` | `=32766` (upstream default) | Deliberately the **lower** of the two paths. Apple ships 500000; a stock amalgamation defaults to 32766. Pinning the vendored build to the floor means any query that passes conformance passes everywhere. Pinning it to 500000 would let a query pass on the vendored path and fail on stock Linux. |
| `SQLITE_OMIT_LOAD_EXTENSION` | on | Apple's build omits extension loading (§1.2). Enabling it on the vendored path would create a capability that cannot exist on iOS, violating the governing principle above, and widens attack surface for no v2.1 requirement. |
| `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` | **off** | §1.4. Paired with a validator rule forbidding `EXPLAIN`-wrapped preparation. |
| `SQLITE_OMIT_PROGRESS_CALLBACK` | **never** | `sqlite3_progress_handler` is the cooperative-interrupt mechanism for cancellation (§2, row 7). Omitting it is what makes cancellation impossible in `sqlite-nio`. |
| `SQLITE_OMIT_TRACE` | **never** | `sqlite3_trace_v2` with `SQLITE_TRACE_PROFILE` is the per-statement timing source for the metrics requirement ([ROADMAP.md:704](../ROADMAP.md)). |
| `SQLITE_ENABLE_STMT_SCANSTATUS` | **off** in release | Upstream: "not recommended for production builds because of the added run-time cost even when the performance statistics are not used." Apple enables it; SwiftQL should not, and should not build metrics that depend on it. |
| `SQLITE_DEFAULT_MEMSTATUS` | `=0` | Removes allocator bookkeeping SwiftQL does not read. Apple sets it. |
| `SQLITE_ENABLE_API_ARMOR` | on in debug only | Upstream: "intended as an aid for application testing and debugging… Applications should not depend on SQLITE_ENABLE_API_ARMOR for safety." Useful while §5's lifetime discipline is being established; not a release dependency. |

Deliberately left to per-connection PRAGMA/`db_config` rather than compile
options, matching GRDB's `Configuration` model: `journal_mode=WAL`,
`foreign_keys=ON`, `busy_timeout`, `synchronous`. These are per-connection
policy and belong in the `onOpen` hook (§3.4), not baked into the library.

### 1.6 Provenance recommendation

**Support both; default to system; make the vendored target the CI and
conformance authority.**

| Criterion | System `libsqlite3` | Vendored amalgamation |
|---|---|---|
| Version determinism | ✗ — ≥3 versions across macOS/iOS/Linux, plus per-OS-release drift | ✓ — one SHA3-256-pinned source |
| Source ID provenance | ✗ — Apple's `…apl` ID is not an upstream ID | ✓ |
| Compile options controllable | ✗ — must be worked around per-connection | ✓ |
| Binary size | ✓ — ~0 (shared cache) | ✗ — ~0.75–1 MB |
| App Store | ✓ | ✓ (no rule either way) |
| CI reproducibility | ✗ — already failed on Ubuntu 22.04 | ✓ — already in use |
| Coexists with GRDB adapter in one binary | ✓ | ⚠ — requires symbol prefixing (§1.3) |
| Existing in-repo proof | ✓ (via GRDB's `CSQLite`) | ✓ (CI shell, not SwiftPM) |

The split is deliberate. Clients who want the smallest binary and Apple's
patched, security-updated SQLite pick system. Clients who want the exact SQLite
the conformance inventory was measured against pick vendored. Conformance
evidence is only ever generated on the vendored target, so a claim in
[Conformance/SQLite/REPORT.md](../Conformance/SQLite/REPORT.md) always names one
library. The `SQLiteBuildValidationRuntime` capability capture
([SQLiteBuildValidationRuntime.swift:201-268](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidationRuntime.swift))
already records `compile_options`, `sqlite_version`, and `sqlite_source_id` per
run, so the machinery to *detect* a provenance mismatch at build-validation time
exists and needs no new design.

---

## 2. Requirement-by-requirement

Against [ROADMAP.md:696-705](../ROADMAP.md). "Effort" is relative to the whole
adapter, not absolute.

| v2.1 requirement | Feasible | C primitives | Effort | Notes |
|---|---|---|---|---|
| Adapter-contract parity | ✓ | — | M | The contract is *already* the right shape. `XLDatabaseDriverConnection` is synchronous and `mutating` ([SQLDatabaseDriver.swift:66-95](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)); `PhysicalStatement` is documented as connection-owned and not required to be `Sendable` ([:64-65](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)). This is the exact shape a `sqlite3_stmt*` wants. Contrast §3 of the sqlite-nio report, where the mismatch was the decisive blocker. One real design question in §5.4. |
| Per-connection preparation and caching | ✓ | `sqlite3_prepare_v3` + `SQLITE_PREPARE_PERSISTENT`, `sqlite3_reset`, `sqlite3_clear_bindings`, `sqlite3_finalize` | S | Replaces `database.cachedStatement(sql:)` ([GRDBDatabaseDriver.swift:571](../Sources/SwiftQL/GRDBDatabaseDriver.swift)). A per-connection `[String: OpaquePointer]` keyed on rendered SQL, finalized at connection close. `SQLITE_PREPARE_PERSISTENT` (header, `sqlite3.h:4389-4392`) is the documented hint for exactly this. Ownership is enforced by the existing `connectionIdentifier` check ([:683-690](../Sources/SwiftQL/GRDBDatabaseDriver.swift)), portable verbatim. |
| Named + positional binding | ✓ | `sqlite3_bind_parameter_index`, `sqlite3_bind_parameter_count`, `sqlite3_bind_parameter_name` | S | `XLBindingKey` has `.named(String)` and `.indexed(Int)` ([SQLDialect.swift:173-176](../Sources/SwiftQLCore/SQLDialect.swift)). Direct C is *better* here than GRDB: `GRDBDatabaseDriverConnection.statementArguments` currently reconstructs the whole physical parameter table positionally to dodge two GRDB normalization hazards it documents at [GRDBDatabaseDriver.swift:718-726](../Sources/SwiftQL/GRDBDatabaseDriver.swift) — a named placeholder shifting `?NNN`, and `:3`/`?3` collapsing after prefix-stripping. Neither hazard exists when calling `sqlite3_bind_parameter_index` directly. **This code gets simpler, not harder.** |
| Decoding | ✓ | `sqlite3_column_type/_int64/_double/_text/_blob/_bytes` | S | `XLSQLiteValue` has exactly SQLite's five storage classes ([SQLiteDialect.swift:24](../Sources/SwiftQLCore/SQLiteDialect.swift)). The `DatabaseValue → XLSQLiteValue` bridge at [GRDBDatabaseDriver.swift:783-799](../Sources/SwiftQL/GRDBDatabaseDriver.swift) becomes a direct switch on `sqlite3_column_type`, removing one representation hop. Codec policy stays in `SwiftQLCore` — adapters do not own it (release gate, [ROADMAP.md](../ROADMAP.md)). |
| Transactions | ✓ | `BEGIN`/`COMMIT`/`ROLLBACK`, `sqlite3_get_autocommit` | M | `withTransaction` already has fully-specified semantics: pinned connection, reentrancy rejection, `CancellationError` on an already-cancelled task, rollback preserving the original error ([GRDBSQLDatabase.swift:1276-1312](../Sources/SwiftQL/GRDBSQLDatabase.swift)). `GRDBPinnedConnectionBox` ([GRDBDatabaseDriver.swift:217-251](../Sources/SwiftQL/GRDBDatabaseDriver.swift)) and `GRDBTransactionScopeTracker` ([:862-900](../Sources/SwiftQL/GRDBDatabaseDriver.swift)) are adapter-agnostic and port with a type substitution. **Simplification available:** GRDB's non-reentrant writer traps with an uncatchable `fatalError` ([:840-846](../Sources/SwiftQL/GRDBDatabaseDriver.swift)), which is why the tracker must pre-reject. A first-party pool can make reentrancy a plain `throw`. |
| Savepoints | ✓ | `SAVEPOINT`/`RELEASE`/`ROLLBACK TO` | S | Not supported today — [COMPATIBILITY.md:44-47](../COMPATIBILITY.md) is explicit that a "nested transaction/savepoint API" is not claimed. So this is **net-new surface, not parity**, and needs a public API decision independent of the adapter. |
| Errors | ✓ | `sqlite3_errmsg`, `sqlite3_extended_errcode`, `SQLITE_OPEN_EXRESCODE` | S | `XLDatabaseContractError` ([SQLDatabaseDriver.swift:5-59](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)) is the target shape; the probe already demonstrates correct error extraction, including copying SQLite-owned strings *before* the next SQLite call can replace them ([SQLitePrepareV3Probe.swift:169-172](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)). `SQLITE_OPEN_EXRESCODE` is `0x02000000` (header, `sqlite3.h:623`). **Constraint:** `GRDBLiveQueryRetryPolicy.retryBusy` matches on `resultCode == .SQLITE_BUSY` ([GRDBLiveQueryRetryPolicy.swift:38](../Sources/SwiftQL/GRDBLiveQueryRetryPolicy.swift)), so the native error type must expose a *primary* result code distinctly from the extended one. |
| Cancellation | ✓ | `sqlite3_interrupt`, `sqlite3_progress_handler` | S | Two levels. Row-level early stop is already contractual — `XLRowStreamControl.stop` ([SQLDatabaseDriver.swift:102-105](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)) — and maps to simply not calling `sqlite3_step` again, which is *strictly better* than GRDB's cursor and vastly better than `sqlite-nio`'s `Void`-returning `onRow`. Statement-level interrupt of a long-running step needs `sqlite3_progress_handler` polling `Task.isCancelled`, or `sqlite3_interrupt` from another thread (header, `sqlite3.h:2911`; note the documented caveat that it must not race connection close). |
| Custom functions | ✓ | `sqlite3_create_function_v2` | S | `XLCustomFunctionRegistration` currently carries a `@Sendable () -> DatabaseFunction` thunk ([SQLCustomFunction.swift:64](../Sources/SwiftQL/SQLCustomFunction.swift)) — a GRDB type in what should be an adapter-neutral value. **This needs refactoring before the adapter, not during it:** the registration should vend an adapter-neutral closure, with each adapter supplying its own bridge. The existing implicit-registration semantics (re-register on whatever pooled connection serves the statement, relying on `sqlite3_create_function` replacing same-name/same-arity registrations — [GRDBDatabaseDriver.swift:668-681](../Sources/SwiftQL/GRDBDatabaseDriver.swift)) transfer unchanged. |
| Collations | ✓ | `sqlite3_create_collation_v2` | XS | `GRDBDatabaseBuilder.addCollation` ([GRDBSQLDatabase.swift:760-767](../Sources/SwiftQL/GRDBSQLDatabase.swift)) is a one-line wrapper over a `prepareDatabase` hook. Direct equivalent. Note SQLite matches collation names ASCII-case-insensitively, which `sqliteASCIIFolded` ([SQLiteBuildValidationRuntime.swift:414](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidationRuntime.swift)) already implements. |
| Observation | ⚠ | `sqlite3_update_hook`, `sqlite3_commit_hook`, `sqlite3_rollback_hook`, `sqlite3_set_authorizer`, `sqlite3_snapshot_*` | **XL** | §4. This is the whole risk. |
| Schema/version invalidation, safe reprepare | ✓ | `sqlite3_prepare_v3` auto-reprepare, `PRAGMA schema_version`, authorizer schema-change detection | S | Largely free: statements prepared with `_v2`/`_v3` reprepare themselves on schema change and no longer surface `SQLITE_SCHEMA` to the caller. What is *not* free is invalidating SwiftQL's own caches; GRDB tracks this explicitly via `StatementAuthorizer.invalidatesDatabaseSchemaCache` (`GRDB/Core/StatementAuthorizer.swift:22-26`). Since §4.2 installs an authorizer anyway, this comes along for free with it. |
| Codec / dialect-value parity | ✓ | — | S | Enforced by construction: both adapters produce `XLSQLiteValue`, and codec policy lives in `SwiftQLCore`. |
| Shared corpus on both adapters | ✓ | — | M | The corpus exists: [`GRDBDriverContractTests`](../Tests/SQLTests/GRDBDriverContractTests.swift) (1,004 lines), the 141-case combinatorial manifest, 18 Northwind scenarios, 12 observation-stress cases ([COMPATIBILITY.md:83-94](../COMPATIBILITY.md)). Cost is generalising the harness over an adapter, not writing tests. Issue #260 owns this. |
| Warm-up and metrics | ✓ | `sqlite3_prepare_v3` at open, `sqlite3_trace_v2`, `sqlite3_stmt_status` | S | **Net-new, not parity** — `grep -rn "warm\|metric" Sources/` returns nothing. Warm-up = prepare the #292 manifest's statements at connection open, which is the same operation the #293 validator already performs. |
| No GRDB dependency | ✓ | — | S | Requires the `CSwiftQLSQLite` target (§1.1) and the `XLCustomFunctionRegistration` refactor above. |

**Score: 15 of 16 rows are S or M.** One row is XL.

---

## 3. Connection pooling and concurrency

GRDB supplies `DatabasePool` (893 lines), `SerializedDatabase` (288),
`SchedulingWatchdog` (68), and `Configuration` (488). Not all of that is needed,
but it sets the scale: a competent first-party pool is a four-figure line count,
not a three-figure one.

### 3.1 Threading mode

`SQLITE_OPEN_NOMUTEX` plus SwiftQL's own serialization, matching GRDB, not
`SQLITE_OPEN_FULLMUTEX`. Upstream is explicit that per-connection flags adjust
the threading mode at run time when `SQLITE_THREADSAFE != 0`, which is why §1.5
recommends `SQLITE_THREADSAFE=1` rather than `=2` — it keeps FULLMUTEX
reachable per connection if a client ever needs it.

`NOMUTEX` means "no two threads may use this connection concurrently," which is
precisely the invariant `XLDatabaseDriverConnection`'s non-`Sendable`
`PhysicalStatement` already encodes in the type system (§5.4). The threading
mode and the contract agree; that is the good news, and it is not an accident —
it is why this contract is a better fit for direct C than for `sqlite-nio`.

For comparison: `sqlite-nio` forces `SQLITE_OPEN_FULLMUTEX`
([SQLiteNIOFeasibility.md §5](SQLiteNIOFeasibility.md)), paying the serialized
mutex on every call.

### 3.2 Reader/writer routing and WAL

The contract already distinguishes them —
`withReadConnection` / `withWriteConnection` / `withTransaction`
([SQLDatabaseDriver.swift:281-291](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)) —
and the GRDB driver maps them onto `pool.read`, `pool.writeWithoutTransaction`,
and `pool.write` ([GRDBDatabaseDriver.swift:110-164](../Sources/SwiftQL/GRDBDatabaseDriver.swift)).
The native shape is standard:

- **one** writer connection behind a serial queue;
- **N** reader connections (GRDB defaults to 5) behind a semaphore-guarded pool;
- `PRAGMA journal_mode=WAL` once at database open (it is persistent in the file
  header, but re-asserting per connection is harmless and self-documenting);
- readers open `SQLITE_OPEN_READONLY`, which makes "a write leaked onto a
  reader" an `SQLITE_READONLY` error rather than silent corruption.

WAL is what makes multi-reader concurrency real; without it every read
serializes behind the writer and the pool is decorative.

### 3.3 Busy handling

**Do not install an unbounded busy handler.** This is the mistake `sqlite-nio`
makes (`{ _, _ in 1 }` — retry forever, no backoff, no override). SwiftQL cannot
afford it, because `SQLITE_BUSY` is a *signal SwiftQL consumes*:
`GRDBLiveQueryRetryPolicy.retryBusy` retries only errors whose primary result
code is `SQLITE_BUSY`, at 0.1/0.2/0.4 s
([GRDBLiveQueryRetryPolicy.swift:23-43](../Sources/SwiftQL/GRDBLiveQueryRetryPolicy.swift)).
Swallowing BUSY inside the C layer would make that policy dead code and turn
contention into an unbounded hang.

Recommended: a bounded `sqlite3_busy_timeout` (GRDB's default is ~5 s) that
surfaces `SQLITE_BUSY` on expiry, leaving the existing retry policy — and its
existing tests, [`GRDBLiveQueryRetryTests`](../Tests/SQLTests/GRDBLiveQueryRetryTests.swift) —
in charge of recovery.

### 3.4 The `prepareDatabase` hook

`Configuration.prepareDatabase` is load-bearing in two places today: function
registration ([GRDBSQLDatabase.swift:736-749](../Sources/SwiftQL/GRDBSQLDatabase.swift)),
collation registration ([:760-767](../Sources/SwiftQL/GRDBSQLDatabase.swift)),
and the validator's `PRAGMA query_only = ON`
([SQLiteBuildValidator.swift:55-57](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidator.swift)).

A native pool needs the equivalent — `onOpen: (Connection) throws -> Void`, run
on every connection the pool creates, before that connection serves anything.
This is where `journal_mode`, `foreign_keys`, `busy_timeout`, `synchronous`,
DQS disabling (§1.5), functions, and collations all land. It is small, and it
is a hard prerequisite for functions and collations, so it must land in the
same slice as the pool.

### 3.5 Reentrancy trapping — already solved, adapter-agnostically

`GRDBTransactionScopeTracker` ([GRDBDatabaseDriver.swift:862-900](../Sources/SwiftQL/GRDBDatabaseDriver.swift))
detects root-executor re-entry using a per-`Thread` dictionary keyed on
`XLDatabaseIdentifier`. It touches no GRDB type. It ports as a rename. The
subtle correctness requirement it documents at [:1294-1300](../Sources/SwiftQL/GRDBSQLDatabase.swift) —
that `withActive` must be entered *inside* the writer closure, on the thread
that will run the body — applies identically to a first-party pool, and the
comment is worth carrying across verbatim.

Note the hazard it guards against is not merely a deadlock: at
[:170-179](../Sources/SwiftQL/GRDBDatabaseDriver.swift) the code explains that a
stray read from inside a transaction would *silently lease a different
connection and return last-committed state*, missing the transaction's own
writes. That failure mode is a property of any WAL multi-reader pool, so it
survives the port unchanged and must be tested on the native adapter, not
assumed.

---

## 4. Observation / live queries

This is the largest single chunk, larger than everything in §2 and §3 combined.

### 4.1 What has to be replaced

Today one call site does all of it:

```swift
// GRDBSQLDatabase.swift:461-464
ValueObservation
    .tracking(fetch)
    .publisher(in: databasePool)
    .eraseToAnyPublisher()
```

Behind those four lines (measured, `wc -l` on the resolved checkout):

| GRDB component | Lines | Role |
|---|---|---|
| `ValueObservation/` (whole directory) | 3,124 | Observation API, reducers, schedulers, `ValueConcurrentObserver` (905), `ValueWriteOnlyObserver` (488) |
| `Core/TransactionObserver.swift` | 1,632 | Observer registry, event dispatch, transaction lifecycle |
| `Core/DatabasePool.swift` | 893 | Pool + observation integration |
| `Core/DatabaseRegion.swift` | 471 | (table × columns × rowIds) regions and intersection |
| `Core/SerializedDatabase.swift` | 288 | Writer serialization |
| `Core/StatementAuthorizer.swift` | 244 | Region inference at prepare time |
| `Core/DatabaseSnapshotPool.swift` | 382 | Snapshot-isolated reads |
| `Core/WALSnapshot{,Transaction}.swift` | 188 | WAL snapshot capture/restore |
| **Total** | **~7,200** | |

A first-party replacement does not need all of that — SwiftQL has one reducer
shape, not GRDB's full operator set — but the honest estimate for a
region-tracking, snapshot-consistent, busy-retrying observer is **1,500–2,500
lines of new, concurrency-sensitive code**, and it is the code most likely to
produce flaky tests.

### 4.2 Region inference via `sqlite3_set_authorizer`

This is the mechanism GRDB uses and there is no alternative. The authorizer is
installed on the connection, reset before each preparation, and accumulates
what the statement reads:

```swift
// StatementAuthorizer.swift:18-26
/// What a statement reads.
var selectedRegion = DatabaseRegion()
/// What a statement writes.
var databaseEventKinds: [DatabaseEventKind] = []
/// True if a statement alters the schema in a way that requires
/// invalidation of the schema cache.
var invalidatesDatabaseSchemaCache = false
```

registered via `sqlite3_set_authorizer` with an `Unmanaged` self pointer
(`GRDB/Core/StatementAuthorizer.swift:39-51`).

Two constraints follow, and both are easy to miss:

**Single-slot.** Upstream (header, `sqlite3.h:3412`): "Each call to
sqlite3_set_authorizer overrides the [previous one]." Same for
`sqlite3_update_hook`, `sqlite3_commit_hook`, `sqlite3_rollback_hook`. If
SwiftQL owns the connection it owns all four slots, which is exactly why this
cannot be built on top of GRDB today — GRDB holds them. It is also why the
multiplexing pattern in §4.5 matters: SwiftQL will have many concurrent live
queries and only one hook slot each.

**The truncate optimization.** GRDB's authorizer exists partly to *suppress a
SQLite optimization*:

> `StatementAuthorizer` provides information about compiled database
> statements, and prevents the truncate optimization when row deletions are
> observed by transaction observers.
> — `GRDB/Core/StatementAuthorizer.swift:9-14`

Confirmed upstream (header, near `sqlite3_update_hook`): the update hook "is
not invoked when rows are deleted using the truncate optimization." So a bare
`DELETE FROM t` with no `WHERE` fires **no** update-hook callbacks and a naive
observer misses the entire deletion. This is a real, silent correctness bug that
a first implementation will almost certainly ship, and it belongs in the
observation slice's test plan on day one.

### 4.3 Change detection and re-fetch

`sqlite3_update_hook` yields `(op, dbName, tableName, rowid)` — enough to
intersect against a `(table × columns × rowIds)` region, which is exactly the
granularity `DatabaseRegion.isModified(by:)`
(`GRDB/Core/DatabaseRegion.swift:218`)
operates at. `sqlite3_commit_hook` and `sqlite3_rollback_hook` provide the
transaction boundary: buffer events, decide at commit, discard at rollback.

**Documented fidelity limits of the hook itself** (header, `sqlite3_update_hook`
doc comment) — these are SQLite's, not GRDB's, so *GRDB has them too* and they
are not regressions:

- not invoked for `WITHOUT ROWID` tables;
- not invoked for internal system tables;
- not invoked when conflicting rows are deleted by `ON CONFLICT REPLACE`;
- not invoked under the truncate optimization (§4.2).

**Snapshot-consistent re-fetch** is the genuinely hard part.
`ValueConcurrentObserver` (905 lines) exists to fetch *concurrently* on a reader
while remaining consistent with the transaction that triggered it, which
requires `sqlite3_snapshot_get`/`_open` — hence §1.5's
`SQLITE_ENABLE_SNAPSHOT`, which CI already enables
([swift.yml:512, 520](../.github/workflows/swift.yml)) and Apple already ships.
Where snapshots are unavailable, GRDB degrades to `ValueWriteOnlyObserver` (488
lines), which re-fetches on the writer connection — correct, but it serializes
every live query behind the writer.

**A first-party v2.1 observer should ship the writer-serialized model first and
treat the concurrent/snapshot model as a later optimization.** It is roughly a
third of the code, it is far easier to test deterministically, and it is
strictly correct — it trades throughput, not consistency. The 12
observation-stress cases from #255 ([COMPATIBILITY.md:92-94](../COMPATIBILITY.md))
are the acceptance gate for whether that trade is acceptable.

### 4.4 Realistic fidelity loss

| Property | Achievable in v2.1? |
|---|---|
| Table-level invalidation | ✓ trivially |
| Column-level region narrowing | ✓ — authorizer `SQLITE_READ` gives (table, column) |
| RowID-level narrowing | ✓ — update hook gives the rowid |
| Correct behaviour on `WITHOUT ROWID` / truncate / REPLACE-conflict | ⚠ — requires the authorizer counter-measures of §4.2; GRDB has the same substrate limits |
| Snapshot-consistent concurrent re-fetch | ✗ initially — writer-serialized instead (§4.3) |
| Busy retry on observation | ✓ — `GRDBLiveQueryRetryPolicy` is adapter-agnostic once the error type exposes a primary result code (§2) |
| Positive-demand startup, independent subscriber state, cancellation | ✓ — [`GRDBOpenCombineValuePublisher`](../Sources/SwiftQL/GRDBOpenCombineValuePublisher.swift) (154 lines) is the model, and its only GRDB coupling is `AnyDatabaseCancellable`; a first-party cancellable makes it fully portable |
| Initial-value delivery without a redundant second fetch | ⚠ — this is precisely what `SQLITE_ENABLE_SNAPSHOT` buys ([swift.yml:530-533](../.github/workflows/swift.yml)) |

### 4.5 On borrowing `sqlite-nio`'s `SQLiteConnection+Hooks.swift`

[SQLiteNIOFeasibility.md §6](SQLiteNIOFeasibility.md) flags this 871-line file
(MIT) as the strongest thing in that package and recommends taking the pattern.
Concurring, with one correction of emphasis: the sqlite-nio report frames the
value as solving "GRDB owns that slot." That framing dissolves once SwiftQL owns
the connection — SwiftQL will own all four hook slots outright.

The value is the *other* problem the file solves: fanning one physical hook out
to many logical observers, with scoped/pinned token lifetimes, validator-vs-
observer separation, and teardown on close. SwiftQL will have N concurrent live
queries per pool and exactly one `sqlite3_update_hook` slot per connection, so a
registry with correct lifetime semantics is required regardless. That design is
worth studying and adapting under MIT — with the attribution the release gates
require ("adopted third-party behavior has pinned source and license
provenance", [ROADMAP.md](../ROADMAP.md)) — and not worth reinventing.

---

## 5. Memory safety and lifetime discipline

### 5.1 Is the existing direct-C code a genuine seed? Partly.

[SQLiteNIOFeasibility.md §7.1](SQLiteNIOFeasibility.md) claims "the prove-out
already exists in-repo." Assessed honestly:

**Genuinely reusable — the discipline, and it is excellent:**

- Finalize-on-every-path, with an explicit rationale for checking the finalize
  result *before* the inspection result so a lifecycle failure is never masked
  ([SQLitePrepareV3Probe.swift:218-245](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)).
- Finalizing on the *error* path too, including when `prepare_v3` fails but
  still wrote a statement pointer ([:173-175, 186-188](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)).
- Copying every SQLite-owned string before the next SQLite call can invalidate
  it ([:169-172, 318-322](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)).
- Exact byte counts rather than NUL-terminated lengths, with an explicit
  embedded-NUL rejection and an `Int32.max` guard ([:124-148](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)).
- Tail-pointer validation that rejects a non-advancing or out-of-range tail
  ([:183-193](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift)).
- The "no handle escapes" contract, stated as a contract, at [:110-118](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift).

**Not reusable — the shape, and the gap is larger than it looks:**

- It is a **single-purpose probe.** It only prepares and inspects. There is no
  `sqlite3_bind_*`, no `sqlite3_step`, no `sqlite3_reset`, no
  `sqlite3_column_*` anywhere in the target. Roughly the first 15% of a driver.
- Its lifetime model is the **opposite** of the adapter's. The probe's entire
  safety argument is *finalize immediately, always*. A caching adapter must
  **not** finalize — it must `sqlite3_reset` + `sqlite3_clear_bindings` and
  finalize only at connection close. Every invariant that makes the probe
  obviously correct has to be re-argued for a statement that outlives its use.
- It does not own its connection. It borrows GRDB's
  (`database.sqliteConnection`, [:127](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift))
  and depends on GRDB for the connection, the configuration, and the module map
  (§1.1). It has never opened a `sqlite3*`.
- Its concurrency model is a serialized read-only `DatabaseQueue`
  ([SQLiteBuildValidator.swift:52-63](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidator.swift)),
  not a multi-connection WAL pool.

**Verdict: a genuine seed for the *coding standard*, not for the *code*.** Its
real value is that it proves the team can write this class of code to a high
standard and that the review culture demands it — which is a better predictor of
success than a partial implementation would be. But the sqlite-nio report's
phrasing overstates the head start; the honest figure is that S0+S1 (§6) start
close to zero lines of transferable implementation.

### 5.2 `SQLITE_TRANSIENT` vs `SQLITE_STATIC`

Both are macros containing casts (header, `sqlite3.h:6354-6355`):

```c
#define SQLITE_STATIC      ((sqlite3_destructor_type)0)
#define SQLITE_TRANSIENT   ((sqlite3_destructor_type)-1)
```

Swift's C importer does not import either. They must be re-declared:

```swift
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

This is a well-known step, and getting it wrong is not a compile error — it is a
use-after-free.

**Recommendation: `SQLITE_TRANSIENT` everywhere, unconditionally, in v1 of the
adapter.** The reasoning is specific rather than generic caution:

- Swift `String` has no stably-addressable UTF-8 storage. The pointer from
  `withUTF8`/`withCString` is valid only inside the closure. `SQLITE_STATIC`
  there is a use-after-free the moment the closure returns — and the bug is
  timing-dependent, so it survives testing.
- `Data`'s `withUnsafeBytes` has the same property.
- `SQLITE_STATIC` is only sound if the adapter owns a byte buffer that provably
  outlives every `sqlite3_step` on that statement — i.e. until `sqlite3_reset`
  or the next `sqlite3_bind_*` on that parameter. With a *cached* statement
  (§2), "until reset" is a much longer and much less obvious window than with
  the probe's prepare-and-finalize model.
- The upside is one `memcpy` per bound string/blob. That is not worth the class
  of bug. Revisit only with a profile showing it matters, and only behind an
  explicitly-owned buffer type.

Integers and doubles are passed by value; the question does not arise.

### 5.3 Cursor confinement — already contractual

The streaming seam is exactly right for `sqlite3_step`:

```swift
// SQLDatabaseDriver.swift:99-105
/// Package-scoped control returned by one streamed-row callback.
///
/// The callback is synchronous so a driver cursor and its owning connection
/// cannot escape through this value.
package enum XLRowStreamControl: Sendable { case advance; case stop }
```

and the implementation requirement is spelled out at
[:108-114](../Sources/SwiftQLCore/SQLDatabaseDriver.swift): keep the physical
cursor inside the current connection access, copy or normalize every value
before advancing, stop immediately when requested, release cursor resources on
return **or throw**.

Mapped onto C, that is: `sqlite3_step` in a loop; per row, read every column
into `XLSQLiteValue` (which copies — `.text(String)` and `.blob(Data)` are
owning); call `body`; on `.stop`, `defer`ed `sqlite3_reset` and return. The
reusable-normalization-buffer trick at
[GRDBDatabaseDriver.swift:636-658](../Sources/SwiftQL/GRDBDatabaseDriver.swift),
including its copy-on-write reasoning, transfers unchanged.

Critically, `sqlite3_reset` must run on the throwing path too, or a cached
statement is left mid-cursor and the *next* use of it fails confusingly. A
`defer` inside `forEachRow` is the whole fix, and it is the single most
important line in the adapter.

### 5.4 What the non-`Sendable` `PhysicalStatement` helps with — and constrains

**Helps, decisively.** `PhysicalStatement` is an associated type with no
`Sendable` requirement and a documented connection-ownership rule
([SQLDatabaseDriver.swift:64-70](../Sources/SwiftQLCore/SQLDatabaseDriver.swift)).
That is what makes it legal to put an `OpaquePointer` to a `sqlite3_stmt` in it
at all. Under Swift 6 strict concurrency a `Sendable` requirement here would
force either an actor hop per statement or an `@unchecked Sendable` escape
hatch. The contract as written needs neither. Combined with `NOMUTEX` (§3.1),
type-level confinement and SQLite's threading requirement are the same
invariant — which is the strongest single argument that this contract was
designed for this adapter even though it was written for GRDB.

**Constrains, in one specific and important way.** `bind` returns a
`PhysicalStatement`:

```swift
// SQLDatabaseDriver.swift:84-88
mutating func bind(
    _ value: Dialect.Value,
    to key: XLBindingKey,
    in statement: PhysicalStatement
) throws -> PhysicalStatement
```

This is value semantics. GRDB satisfies it by accumulating into a dictionary and
returning a modified copy ([GRDBDatabaseDriver.swift:600-602, 779](../Sources/SwiftQL/GRDBDatabaseDriver.swift)).
A native adapter's *natural* implementation would call `sqlite3_bind_*`
immediately — but then the returned "copy" aliases the same `sqlite3_stmt*`, and
value semantics become a lie. Two callers holding what look like independent
statements would stomp each other's bindings, silently.

Two options:

- **(a) Deferred bindings** — keep `[XLBindingKey: XLSQLiteValue]` in the
  struct, apply all binds immediately before `step`. Preserves honest value
  semantics, mirrors GRDB exactly, keeps the contract unchanged, and costs one
  dictionary per execution.
- **(b) Reference-backed handle** — a final class with an ownership token,
  `bind` returning `self`. Faster, but `PhysicalStatement` stops behaving like a
  value and every existing test that assumes copy independence has to be
  re-audited.

**Recommend (a).** It is the only option that satisfies the published contract
without changing it, and if profiling later justifies (b), that is a contained
optimization behind the same seam. This decision should be made explicitly in
slice S1, not discovered in S2.

The `connectionIdentifier` ownership check
([GRDBDatabaseDriver.swift:683-690](../Sources/SwiftQL/GRDBDatabaseDriver.swift))
becomes *more* important with raw pointers than it is with GRDB's `Statement`
class, and should be kept and tested first, not last.

---

## 6. Effort, risk, and staging

### 6.1 Slices

| # | Slice | Size | Depends on | Proves |
|---|---|---|---|---|
| S0 | `CSwiftQLSQLite` target: system-library module map + `shim.h` (variadic `db_config`/`config` wrappers, §1.1). If vendoring: amalgamation target + **symbol-prefix proof** (§1.3). | XS–S | — | GRDB-free access to `sqlite3_*` on macOS and Linux; that both adapters can coexist in one binary |
| S1 | Connection: `open_v2` (NOMUTEX/EXRESCODE), prepare/bind/step/reset/finalize, `XLSQLiteValue` round-trip, `XLDatabaseDriverConnection` + `XLStreamingDatabaseDriverConnection` conformance. Single connection, no pool, no cache. Settle §5.4(a) here. | M | S0 | **The go/no-go signal.** Contract parity without touching the contract |
| S2 | Statement cache (`SQLITE_PREPARE_PERSISTENT`, reset+clear_bindings, finalize at close) + schema-change invalidation | S | S1 | Caching requirement; no leaks under churn |
| S3 | Pool: serial writer + N readonly readers, WAL, bounded `busy_timeout` surfacing `SQLITE_BUSY`, `onOpen` hook, reentrancy tracker port | L | S1 | Concurrency requirement; §3.5's stale-read hazard is actually caught |
| S4 | Transactions + savepoints; error taxonomy mapped to `XLDatabaseContractError` with primary/extended codes | M | S3 | `XLTransactionScopeError` semantics preserved verbatim |
| S5 | Custom functions + collations. Includes the `XLCustomFunctionRegistration` de-GRDB-ing (§2) | S | S3 | Existing `SQLCustomFunction`/`SQLCustomCollation` tests pass unchanged |
| S6 | Cancellation: row-level stop (free from S1) + `progress_handler`/`interrupt` | S | S1 | Long statements are interruptible |
| S7 | **Observation**: authorizer region inference, hook multiplexing, commit/rollback buffering, truncate-optimization counter-measure, writer-serialized re-fetch, retry-policy integration | **XL** | S3, S4 | The 12 #255 observation-stress cases |
| S8 | Warm-up (prepare #292 manifest at open) + metrics (`trace_v2` PROFILE) | S | S2 | Net-new v2.1 surface |
| S9 | Shared-corpus parity harness (#260): generalise `GRDBDriverContractTests`, combinatorial manifest, Northwind, observation stress over both adapters | M | S7 | [ROADMAP.md:702-703](../ROADMAP.md) |

S7 alone is plausibly 40% of the total. S0–S6 are the comfortable part.

### 6.2 What can be proven early, and cheaply

- **Day 1 (S0):** a `CSwiftQLSQLite` target compiles and links on macOS and
  Linux with no GRDB dependency, and `sqlite3_libversion()` returns the expected
  string on both. If vendoring: `nm` proves the prefixed symbols do not collide
  with system `libsqlite3` in a binary that also links GRDB.
- **Week 1 (S1):** retarget
  [`GRDBDriverContractTests`](../Tests/SQLTests/GRDBDriverContractTests.swift)
  (1,004 lines) at the native connection. **This is the single best early
  signal in the whole plan** — it is an existing, comprehensive, adapter-shaped
  test suite, and it exercises exactly the seam most likely to reveal a
  contract mismatch. If S1 passes it without modifying
  `Sources/SwiftQLCore/SQLDatabaseDriver.swift`, the central architectural bet
  is proven.
- **Week 2 (S1):** `XLSQLiteValue` round-trips through bind→step→column for all
  five storage classes, including empty text, empty blob, and NUL-containing
  blobs — plus a deliberate `SQLITE_STATIC` misuse test to confirm §5.2's
  reasoning under ASan.
- **Week 3 (S2/S3):** run the 141-case combinatorial manifest against the
  native connection. Rendering is shared, so any divergence is a driver bug and
  nothing else.

### 6.3 Failure modes that would justify abandoning

| Failure mode | Signal | Response |
|---|---|---|
| Contract parity needs contract changes — especially `bind`'s value semantics (§5.4) | S1 cannot pass `GRDBDriverContractTests` without editing `SQLDatabaseDriver.swift` | **Stop.** The sync contract itself is the problem, and that is a v3 decision (matching [SQLiteNIOFeasibility.md §7.4](SQLiteNIOFeasibility.md)), not something to settle inside an adapter |
| Symbol collision unresolvable under vendoring | S0 `nm` proof fails, or GRDB observably runs on the vendored library | Fall back to system-only provenance; determinism is then a CI property, not a shipping one |
| Observation cannot reach #255 fidelity | S7 stress cases flake or fail | **Ship the native adapter without live queries.** Clients needing observation keep the GRDB adapter. This is a legitimate reduced-scope v2.1, and it should be pre-agreed as acceptable rather than discovered under deadline |
| Pool concurrency bugs that only appear under load | Intermittent S3/S7 failures; note the machine is already known-noisy for concurrent suites | Timebox. If a WAL/pool race resists diagnosis for more than a slice, adopt writer-serialized reads (correct, slower) and revisit |
| Effort overruns S7 | S7 exceeds its estimate by >2× | Split: ship S0–S6 + S8 + S9 as "native adapter, non-observing" in v2.1; observation moves to v2.1.1 |

Note that three of five responses are *reduced scope*, not abandonment. That is
the real argument for this approach: it degrades gracefully. The sqlite-nio path
did not — its blockers were structural and all-or-nothing.

---

## 7. Recommendation

**GO, with four conditions.**

The requirement list is reachable, the contract is already the right shape, and
15 of 16 requirement rows are small or medium. Direct C is also, in three
specific places, *simpler* than what exists today: named binding loses two
documented GRDB normalization hazards (§2), early row-stop becomes trivial
(§2), and reentrancy can throw instead of pre-empting an uncatchable
`fatalError` (§2). The one large risk — observation — is isolated in a single
slice that can be deferred without invalidating the rest.

The conditions:

1. **Decide provenance before writing the adapter.** §1.6 recommends supporting
   both with system as the default and the vendored target as the conformance
   authority. If vendoring is chosen, symbol prefixing is mandatory and must be
   proven in S0 (§1.3) — this is the highest-probability
   "works-in-CI, wrong-in-app" failure in the plan.

2. **Pre-agree that observation may ship reduced or deferred.** S7 is ~40% of
   the effort and the entire risk. A v2.1 that ships a native adapter for
   execution while live queries continue to require the GRDB adapter is a good
   outcome, and deciding that *now* is much cheaper than deciding it in month
   four. Snapshot-consistent concurrent re-fetch should be explicitly
   out of scope for the first version (§4.3).

3. **Make S1 the go/no-go gate, judged by an unmodified contract.** If
   `GRDBDriverContractTests` passes against the native connection without
   editing `Sources/SwiftQLCore/SQLDatabaseDriver.swift`, proceed. If it does
   not, the finding is about the contract, not the adapter, and belongs with the
   v3 sync/async decision.

4. **Fix three things that are prerequisites, not adapter work.**
   `XLCustomFunctionRegistration` currently carries a GRDB `DatabaseFunction`
   thunk in what should be an adapter-neutral value (§2) and must be refactored
   first. `SQLiteBuildValidationValidator` must move off GRDB's `CSQLite`
   product onto `CSwiftQLSQLite` (§1.1). And the validator needs a negative-
   control test asserting it never prepares under `EXPLAIN` (§1.4) — cheap now,
   and the only thing standing between Apple's already-enabled
   `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` and a silently blind #293 validator.

Two documentation corrections fall out of this analysis and should be made
regardless of the go/no-go:
[COMPATIBILITY.md:145-148](../COMPATIBILITY.md) is stale about
`SQLITE_ENABLE_SNAPSHOT` (§1.2), and
[SQLiteNIOFeasibility.md §4](SQLiteNIOFeasibility.md)'s characterisation of
`SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` is broader than SQLite's documented and
measured behaviour (§1.4).
