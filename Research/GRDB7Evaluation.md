# Evaluation: GRDB 7 support for SwiftQL 1.x

> **Superseded for the v2 line.** SwiftQL **2.x adopts GRDB 7**
> ([#792](https://github.com/lukevanin/swiftql/issues/792)). The manifest
> declares `from: "7.0.0"` (`7.0.0..<8.0.0`) and the committed resolution pins
> 7.11.1. `COMPATIBILITY.md` and the README Install section state the new
> bound. The decision below still holds for the **1.x** line, which stays on
> GRDB 6, and the break list in §2 is what #792 applied. Where #792 departed
> from this document, §6 says so.

**Decision (v1 line): SwiftQL 1.x supports GRDB 6 only.** The 1.x manifest
keeps `from: "6.29.3"` (`6.29.3..<7.0.0`). Widening *that* line to a range
spanning both majors is **not** taken, because one manifest cannot name GRDB's
SQLite C product for both majors, and because a warning-clean and
strict-concurrency-clean build on GRDB 7 needs the `Row: Sendable` change that
belongs to v2.0
([#685](https://github.com/lukevanin/swiftql/issues/685)).

Issue: [#667](https://github.com/lukevanin/swiftql/issues/667). Evaluation
performed on `version/1.9` at `cd04812f` against GRDB **7.11.1**
(`b83108d10f42680d78f23fe4d4d80fc88dab3212`, the newest 7.x tag, and the only
version `from: "7.0.0"` resolved to), compared with GRDB **6.29.3** on the same
toolchain. Toolchain: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS arm64,
package in Swift 5 language mode (`-swift-version 5`, the package's only
language mode). No Linux or Swift 5.9 toolchain was run locally.

---

## 1. GRDB 7 requirements against SwiftQL's floors

| | SwiftQL 1.x | GRDB 6.29.3 | GRDB 7.0.0–7.9.x | GRDB 7.10.0–7.11.1 |
|---|---|---|---|---|
| `swift-tools-version` | 5.9 | 5.7 | **6.0** | **6.1** |
| iOS / macOS | 16 / 13 | 11 / 10.13 | 13 / 10.15 | 13 / 10.15 |
| SQLite C product | links `CSQLite` | `CSQLite` | **`GRDBSQLite`** | **`GRDBSQLite`** |
| `import GRDB` re-exports SQLite C | relies on it | yes (`GRDB/Export.swift`) | **no** | **no** |

GRDB 7's platform floors are below SwiftQL's, so platforms do not block it.
The toolchain floor does. SwiftPM ignores a tag whose tools version is newer
than the running toolchain, so a range spanning both majors would still resolve
GRDB 6 on Swift 5.9, and GRDB 7.9.x at most on Swift 6.0. The CI matrix would
then test different GRDB majors on different cells. That is workable, but it is
moot given §2.

## 2. Break list

Reproduction: in a scratch worktree, change the GRDB requirement to
`from: "7.0.0"`, delete `Package.resolved`, run `swift package resolve`, then
`swift build --build-tests`. Each step below lists what failed and the change
needed to reach the next failure.

### 2.1 Resolution and manifest — hard error

```text
error: product 'CSQLite' required by package 'swiftql' target
'SwiftQLSQLiteBuildValidationValidator' not found in package 'GRDB.swift'.
```

GRDB 7 renamed the `CSQLite` product to `GRDBSQLite`
([GRDB 7 migration guide, "Access to SQLite C functions"](https://github.com/groue/GRDB.swift/blob/v7.11.1/Documentation/GRDB7MigrationGuide.md)).
`SwiftQLSQLiteBuildValidationValidator` depends on
`.product(name: "CSQLite", package: "GRDB.swift")`, and three files import the
module:

- `Sources/SwiftQLSQLiteBuildValidationValidator/SQLitePrepareV3Probe.swift:1`
- `Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteExplainQueryPlanProbe.swift:1`
- `Tests/SwiftQLSQLiteBuildValidationValidatorTests/SQLitePrepareV3ProbeTests.swift:15`

SwiftPM has no product dependency that depends on the resolved version of the
package, so one manifest cannot name `CSQLite` for 6.x and `GRDBSQLite` for
7.x. The experiment renamed the product and the three imports to continue.

### 2.2 SQLite C symbols no longer reach `import GRDB` — compile errors

```text
Sources/SwiftQL/GRDBDatabaseDriver.swift:1044:25: error: cannot find 'sqlite3_next_stmt' in scope
Sources/SwiftQL/GRDBDatabaseDriver.swift:1046:16: error: cannot find 'sqlite3_stmt_busy' in scope
Sources/SwiftQL/GRDBDatabaseDriver.swift:1049:25: error: cannot find 'sqlite3_next_stmt' in scope
```

GRDB 6 declares `@_exported import CSQLite` / `SQLite3` / `SQLCipher`. GRDB 7
imports `GRDBSQLite` without re-exporting it. The compiler stopped at the first
failing batch, so the experiment added `import GRDBSQLite` to every file that
calls a `sqlite3_*` function without importing a SQLite module:
`GRDBDatabaseDriver.swift`, `SQLRegexpFunction.swift`,
`SQLiteBuildValidator.swift`, and `SQLiteBuildValidatorIntegrationTests.swift`.
`SwiftQL` declares no dependency on the `GRDBSQLite` product; the import
compiled only because SwiftPM exposes a transitive system-library module map on
this toolchain. GRDB's own guide says it is "unclear" whether projects can drop
the product dependency.

After §2.1 and §2.2, the library, every executable, and every test target
**built** against GRDB 7.11.1.

### 2.3 Default build — new warnings (blocking in CI)

A clean `swift build --build-tests` reports these diagnostics. The GRDB 6.29.3
baseline on the same toolchain reports only the last one.

| Location | Diagnostic | GRDB 7 cause |
|---|---|---|
| `Sources/SwiftQL/GRDBDatabaseBuilder.swift:99` | capture of `function` with non-`Sendable` type `F.Type` in a `@Sendable` closure | `Configuration.prepareDatabase(_:)` takes `@Sendable (Database) throws -> Void` |
| `Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift:430` | `nonisolated(unsafe)` is unnecessary for `Sendable` type `AnyDatabaseCancellable` | `AnyDatabaseCancellable` is `Sendable` in GRDB 7 and not in GRDB 6 |
| `Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift:788` | unused unstructured throwing task | none; pre-existing on Swift 6.4 with GRDB 6 too |

`scripts/ci/check-first-party-warnings.sh` treats first-party warnings as
errors in every cell, so the first two rows fail CI. The second row cannot be
fixed for both majors at once: GRDB 6 needs the shadow and GRDB 7 warns about
it, and `#if` cannot test a dependency's version.

### 2.4 Complete strict concurrency — new diagnostics (blocking on Swift 6.0)

The Swift 6.0 cells run `scripts/ci/check-strict-concurrency.sh`
(`-strict-concurrency=complete`). The same flags on both GRDB versions give
these diagnostics only under GRDB 7.11.1:

| Location | Diagnostic | GRDB 7 cause |
|---|---|---|
| `Sources/SwiftQL/GRDBRequest+LiveQuery.swift:182`, `:183`, `:184` | type `Value` does not conform to `Sendable` | `_ValueReducer.Value: Sendable` (GRDB 6: unconstrained) |
| `Sources/SwiftQL/GRDBRequest+LiveQuery.swift:183` | passing non-`Sendable` parameter `fetch` to a `@Sendable` closure | `ValueObservation.trackingConstantRegion(_:)` takes `@Sendable (Database) throws -> Value` |
| `Sources/SwiftQL/GRDBRequest+LiveQuery.swift:187`, `:188` | passing non-`Sendable` `onError` / `onChange` to a `@Sendable` closure | `ValueObservation.start(in:scheduling:onError:onChange:)` takes `@Sendable` callbacks |
| `Sources/SwiftQL/GRDBDatabaseBuilder.swift:99`, `:103` | capture of non-`Sendable` metatypes `F.Type` and `F.T.Type` | `@Sendable` `prepareDatabase` and `DatabaseFunction` closures |
| `Sources/SwiftQL/SQLCustomFunction.swift:147` | capture of non-`Sendable` metatype `F.T.Type` | `DatabaseFunction.init(_:argumentCount:pure:function:)` takes a `@Sendable` function |
| `Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift:987`, `:1119` | call to main actor-isolated `start(in:scheduling:onError:onChange:)` from a nonisolated context; non-`Sendable` `onError` / `onChange` | GRDB 7's default scheduler is `.mainActor`, which selects a `@MainActor` overload |
| `Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift:1116` | capture of non-`Sendable` `fetchProbe` in a `@Sendable` closure | `ValueObservation.tracking(_:)` takes a `@Sendable` fetch |

Diagnostics that appear identically with both GRDB versions, and so are not
GRDB 7 breaks: `JSONValueCodec.swift:234`, `:249`, `:282`, `:293` and
`XLAsyncStreamPublisher.swift:272` (`SendableMetatypes` on the Swift 6.4
toolchain), and the test warning at `LiveQueryBufferingSemanticsTests.swift:788`.

Production observation already passes an explicit `.async(onQueue:)`
scheduler (`GRDBRequest+LiveQuery.swift:186`), so GRDB 7's main-actor default
does not change SwiftQL's delivery queue.

### 2.5 Runtime

With §2.1 and §2.2 applied, `swift test --skip-build` against GRDB 7.11.1:
**1,628 XCTest cases in 10 test bundles, 0 failures, 0 skipped** (exit status
0), with the SQLite runtime reported as 3.51.0 (the macOS system library). No
runtime behavior changed. The breaks are all build-time: §2.1 and §2.2 as
errors, §2.3 and §2.4 as warnings that the CI gates reject. Live-query and
retry tests passed, including the bridge tests that §2.4 flags for isolation;
they pass because the package builds in Swift 5 mode, where GRDB's
`@preconcurrency` annotations keep those diagnostics as warnings.

## 3. Decision and rationale

The issue asks to widen only if the changes for both majors are small, source
compatible for v1 users, and do not weaken concurrency safety. None of the
three holds.

1. **The manifest cannot serve both majors.** §2.1 needs a product name that
   differs by major. The options are to drop the product and depend on
   transitive module visibility with `#if canImport(GRDBSQLite)` /
   `#elseif canImport(CSQLite)`, which relies on SwiftPM behavior that is not
   documented, and which this evaluation did not test on Linux's custom-SQLite
   path; or to
   vendor a SQLite C target, which is v2.1 native-adapter scope
   ([SQLiteCFeasibility.md](SQLiteCFeasibility.md)).
2. **CI cannot be warning-clean on both majors.** §2.3 row 2 flips between
   "required" and "unnecessary" with the major, and no compile-time condition
   selects on it.
3. **A clean strict-concurrency build needs `Row: Sendable`.** §2.4's live-query
   rows come from an unconstrained `Row` flowing into `ValueReducer.Value:
   Sendable`, and from a `fetch` closure that captures the non-`Sendable`
   `GRDBRequest` reader and logger. Adding `where Row: Sendable` to
   `XLRequest`'s observation members is source-breaking for v1 users whose row
   types are not `Sendable`. Hiding it with `@unchecked Sendable` boxes or
   `nonisolated(unsafe)` weakens concurrency safety, which #685 forbids.

A range of `"6.29.3"..<"8.0.0"` would also let a Swift 6.1+ clean resolution
select GRDB 7 for every adopter who has no GRDB constraint of their own, so
the unfixed breaks above would reach users who never asked for GRDB 7.

**Consequence for adopters:** an application already on GRDB 7 cannot adopt
SwiftQL 1.x. It must use GRDB 6 with SwiftQL 1.x. GRDB 7 support belongs with
the v2.0 changes that make it clean: `Row: Sendable` for observation
([#685](https://github.com/lukevanin/swiftql/issues/685)), the GRDB adapter
boundary ([#113](https://github.com/lukevanin/swiftql/issues/113)), and Swift 6
language mode ([#133](https://github.com/lukevanin/swiftql/issues/133)).

## 4. Findings for the v2.0 `Row` decision (#685)

- GRDB 7 requires `ValueReducer.Value: Sendable`. Every live-query member that
  reaches `ValueObservation` therefore needs `Row: Sendable`
  (`[Row]` for `stream()`, `Row?` for `streamOne()`).
- The `fetch`, `onError`, and `onChange` closures must be `@Sendable`. The
  `GRDBLiveQueryAsyncBridge.Start` typealias
  (`Sources/SwiftQL/GRDBLiveQueryAsyncStream.swift:39`) and
  `liveQueryStreamBridge(fetch:)` must carry `@Sendable`, and `fetch` must stop
  capturing the non-`Sendable` request reader and logger.
- `AnyDatabaseCancellable` is `Sendable` in GRDB 7, so the
  `nonisolated(unsafe)` cancellable shadows become unnecessary and warn.
- Custom function registration captures `F.Type` and `F.T.Type` in `@Sendable`
  closures (`GRDBDatabaseBuilder.swift:99`, `SQLCustomFunction.swift:147`), so
  `XLCustomFunction` and its value type need a `Sendable` metatype story too,
  not only `Row`.

## 5. What was not evaluated

- Linux. GRDB 7.11 defines `SQLITE_DISABLE_SNAPSHOT` on Linux, which interacts
  with the CI's `-DGRDBCUSTOMSQLITE -DSQLITE_ENABLE_SNAPSHOT` compiler override
  (`COMPATIBILITY.md`). This needs a Linux run if GRDB 7 is revisited.
- Swift 5.9 and 6.0 toolchains. §1's resolution behavior follows from GRDB's
  published tools versions; no cell proved it, because the range did not widen.
- Swift 6 language mode for the package. SwiftQL 1.x builds only in Swift 5
  mode; §2.4 approximates Swift 6 mode with complete strict concurrency.

## 6. What #792 found that this document did not

The v2.0 adoption ran the whole break list against the same GRDB 7.11.1, on a
package that declares `swift-tools-version: 6.1` and builds in Swift 6 language
mode. Four points differ from the sections above.

1. **Only one file needed `import GRDBSQLite`.** §2.2 listed four.
   `SQLRegexpFunction.swift`, `SQLiteBuildValidator.swift`, and
   `SQLiteBuildValidatorIntegrationTests.swift` name `sqlite3_*` functions in
   prose only, so `GRDBDatabaseDriver.swift` is the single file that calls one.
   The `SwiftQL` target declares the `GRDBSQLite` product for it, rather than
   relying on the transitive module map §2.2 observed.

2. **The `fetch` closure cannot decode a typed row.** §4 expected `@Sendable`
   annotations plus `Row: Sendable` to be enough. In Swift 6 language mode,
   `AsyncThrowingStream`'s `unfolding` closure is `@Sendable` as well, so a
   typed row must be produced inside a `Sendable` region wherever the decode is
   placed. The observation now fetches raw `[XLSQLiteValue]` rows and carries
   only the `Sendable` executor and logger, and one narrow, documented seam
   (`Sources/SwiftQL/GRDBLiveQueryRowDecoding.swift`) crosses the row reader
   into that region. Making the reader itself `Sendable` was measured and
   rejected: it requires `XLEncodable`, `XLColumnDependency`, the statement
   component structs, and the mutable `XLNamespace` alias allocator to be
   `Sendable` too, which is a separate public API change.

3. **`XLLogger` had to state its concurrency safety.** §4 treated the logger as
   a capture to remove. The live-query tests use the fetch log as the record
   that a fetch ran, and one of them blocks inside it on the database queue, so
   the log call must stay there. The protocol now refines `Sendable`, which is
   what SwiftQL has always needed from it: every fetch path already logs from a
   pooled reader connection.

4. **The metatype captures were removed, not constrained away.**
   `GRDBDatabaseBuilder.addFunction(_:)` now builds its registration through
   `XLCustomFunctionRegistration.make(_:)` outside the `@Sendable`
   `prepareDatabase` closure, and the registration requires a `Sendable`
   function result so the remaining `F.T.Type` capture is legal.

5. **`-DGRDBCUSTOMSQLITE` had to go.** §5 asked what the Linux cells would do.
   They failed to compile GRDB itself: `cannot find 'sqlite3_column_type' in
   scope`. GRDB 6 read the define as "import the custom SQLite module". GRDB 7
   reads it as "the GRDBCustom Xcode framework supplies the SQLite module", and
   its `#elseif GRDBCUSTOMSQLITE` branch imports nothing, so no SQLite module
   reached GRDB under SwiftPM. The compiler override now passes no SQLite
   define. The pinned library still reaches GRDB through the include and
   library paths, because the `GRDBSQLite` module map includes `<sqlite3.h>`
   and links `sqlite3`.

6. **A live query may deliver the same value twice, on every platform.** This
   is the finding with the widest reach, and it is not a Linux one. GRDB
   fetches an observation's initial value from a pool reader, then fetches
   again when it takes its first write access, because writes may have landed
   in between. `ValueConcurrentObserver.swift` says that GRDB cannot tell
   whether such a write touched the observed value, and that it may therefore
   notify the same value twice. It says this for the snapshot path and for the
   path without it. Snapshot support only lets GRDB detect that nothing at all
   changed.

   Eleven live-query tests asserted the number of deliveries, or that no
   delivery repeated a value. GRDB never promised either, and
   <doc:LiveQueries> promises the latest known state rather than a commit log.
   They passed on macOS because the repeat did not happen to fire, not because
   macOS prevents it. They now assert the sequence of distinct states, with no
   platform condition, and <doc:LiveQueries> states the repeat.

   The change was checked by making the repeat deterministic: with every
   observation delivery duplicated, the whole suite passes on macOS.

The Linux question in §5 is answered in `COMPATIBILITY.md`: GRDB 7 defines
`SQLITE_DISABLE_SNAPSHOT` for its own target on Linux, a target-level define
cannot be removed from outside the package, and the Swift-side snapshot path is
therefore compiled out on the Linux cells whatever the override passes. That
makes the second startup fetch certain there, rather than introducing it.
