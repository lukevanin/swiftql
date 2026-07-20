# Changelog

## [1.3.0] - 2026-07-20

### Added

- Added the #190 canonical SQLite conformance inventory and deterministic
  generated report. It records 101 public-surface feature records: 88
  supported, 3 partial, 2 capability-gated, 1 intentionally unsupported, and
  7 unimplemented. Of the 100 evidence records, 67 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.
- Added the #191 bounded combinatorial SQLite corpus with 141 stable generated
  cases across joins, subqueries, common table expressions, grouping,
  bindings, and related interactions, plus a deliberately broken-renderer
  negative control. Deterministic manifests and runtime provenance keep the
  exercised combinations reviewable without presenting them as exhaustive
  SQL coverage.
- Added the #254 immutable Northwind SQLite snapshot and 18 stable correctness
  scenarios for realistic joins, aggregates, subqueries, compound queries,
  common table expressions, decoding, CRUD, and rollback behavior.
- Added the #255 live-query observation stress suite with 12 stable cases for
  concurrent writes, invalidation, delivery, cancellation, transient-busy
  retries, and database isolation.
- Added the #132 research prototype for deterministic build-time preparation
  of static query descriptors against the checked-in Northwind snapshot. The
  prototype owns a read-only validation connection, finalizes every prepared
  statement, and emits a reproducible report; it is internal research, not a
  public validator, build plugin, macro, schema system, or v1.3 API.

### Migration

No migration is required for v1.3. The milestone adds conformance evidence,
correctness and stress coverage, internal research artifacts, and refreshed
documentation while preserving the v1.2 public source and runtime contracts.

## [1.2.0] - 2026-07-19

### Added

- Added the GRDB-free `SwiftQLCore` product with orthogonal SQL-dialect,
  dialect-value, logical-statement, validated database-driver, and transaction
  contracts. The existing `SwiftQL` product remains the application-facing
  facade with the current GRDB-backed SQLite implementation.
- Added immutable `XLStaticQueryDescriptor` definitions with durable canonical
  identities, explicit dialect requirements, parameter/result layouts,
  referenced entities, and cardinality. Raw prepared static-query handles are
  database-bound and `Sendable` without retaining a physical statement.
- Added generated static row layouts for `@SQLTable` and `@SQLResult`, including
  contextual value encoding and typed decoding without constructing default
  model instances or requiring `sqlDefault()`.
- Added immutable, value-free `XLQueryCapture` declarations and fresh
  `XLInvocationBindings` packets. Repeated calls keep runtime values out of
  logical requests, descriptors, identities, and statement caches.
- Added immutable contextual value-codec registries and database configuration
  snapshots. One Swift type can select different versioned SQLite
  representations without a process-global registry or retroactive literal
  conformance.
- Added shared adapter-neutral SQLite value/storage and transaction contract
  suites, each exercised against the production GRDB driver with stable case
  identities and durable semantic oracles.
- Added an independent cross-library SQLite benchmark baseline and a
  reproducible first-party source-coverage topology check.

### Changed

- GRDB result rows are stepped and decoded incrementally while their leased
  connection is active. Public `fetchAll()` and `fetchOne()` behavior remains
  eager and source-compatible, but intermediate GRDB and normalized row arrays
  are no longer retained.
- Literal decoding now uses a scoped field reader, and the sequential row reader
  is a value type, removing per-row reference allocation from the legacy typed
  decode path.
- `Select` no longer requires the result type itself to conform to `XLResult`;
  typed selection is carried by its row layout. Existing `XLResult` models
  continue to compile.
- First-party SQL renderers now use semantic `XLSeparator.list` and `.tuple`
  names. The legacy `.comma`, `.space`, raw-value, and custom-string separator
  APIs remain available throughout v1.
- Table and common-table `FROM` dependencies now share one dependency model,
  including value-semantic recursive common-table definitions and references.

### Fixed

- Non-finite `Double` literals now fail through validated encoding instead of
  emitting invalid SQLite tokens or silently changing the value.
- `COLLATE` names render as SQL grammar tokens, fluent `INSERT ... SELECT`
  clause chains execute against real SQLite, and the query builder's
  missing-`FROM` failure is covered by its documented contract.
- Generic list composition now implements `BETWEEN`, static result descriptors
  remove hidden default-value requirements, and separator cleanup preserves
  byte-identical SQL and binding order.

### Migration

Existing `makeRequest(with:)`, `XLNamedBindingReference`, `XLCustomType`,
`XLLiteral`, `XLResult`, explicit packet, and raw separator APIs remain
source-compatible in SwiftQL 1.x. No application must adopt the lower-level
v1.2 contracts merely to keep an existing query working.

For a new reusable query that needs durable identity, cross-task raw-value
execution, or contextual result layouts, construct and register an
`XLStaticQueryDescriptor` before opening a database, prepare it against that
database, and create a fresh `XLInvocationBindings` packet for every call. Do
not share the current `XLRequest` facade across tasks; it remains task-local.

Prefer `XLValueCodec` plus an immutable `XLValueCodingConfiguration` when one
application type has multiple persisted representations. Keep a legacy
`XLCustomType` wrapper only when preserving its existing v1 storage bytes and
introspection behavior is required. Changing a codec key, version, stable type
identifier, dialect, or storage identifier is a schema/data migration.

Validated encoding is now the explicit error boundary for unsupported literal
values such as non-finite `Double`. Code that constructs SQL from untrusted or
computed floating-point values should propagate that error instead of assuming
every `Double` has a SQLite literal spelling.

## [1.1.0] - 2026-07-17

### Added

- Added a verified tag-release workflow that reuses the complete Swift compiler
  matrix and DocC build, publishes deterministic provenance/checksum assets
  through an idempotent draft-first GitHub Release, and provides read-only test
  tags plus documented partial-release recovery.
- Added a least-privilege GitHub Pages workflow that builds documentation on
  pull requests and deploys only authorized `main` commits, with artifact and
  deployed-site provenance tied to the exact commit SHA.
- Added a non-mutating, warnings-as-errors DocC site generator with built-in
  validation for the SwiftQL landing page and all ten source articles. CI
  smoke-tests the same command used locally.
- Added an `XLEnum` guide with compile-checked integer- and string-backed enum
  examples and real SQLite coverage for valid and unknown stored raw values.
- Added compile-time-checked scenario mappings for every Swift example in the
  DocC landing page and source articles, with a catalog test that rejects
  untyped fences, stale API spellings, and unknown test markers.
- Added a provenance-aware warnings-as-errors gate for every supported compiler
  lane. It blocks SwiftQL-owned and unclassified warnings while reporting
  dependency and toolchain diagnostics separately.
- Added an external Swift package fixture that uses SwiftQL's public macros,
  typed queries, binding, and SQLite execution from Swift 5 language mode under
  the supported Swift 6 compiler. CI runs it with pinned and clean resolution.
- Added a reproducible `swiftql-benchmark` executable that reports raw samples,
  median, and p95 for SwiftQL construction/rendering, uncached SQLite
  preparation, statement-cache hits, reset/binding, execution, and production
  row decoding. All supported compiler lanes run a structure-only smoke test.
- Added `minOrNull(distinct:)`, `maxOrNull(distinct:)`, `sumOrNull(distinct:)`,
  `averageOrNull(distinct:)`, `groupConcatOrNull(distinct:)`, and
  `groupConcatOrNull(separator:)` APIs whose expression types represent SQLite
  NULL results.
- Added an opt-in GRDB live-query retry policy for transient `SQLITE_BUSY`
  failures. It performs three serialized retries after deterministic 0.1, 0.2,
  and 0.4 second delays, resets after a delivered value, and preserves terminal
  behavior by default.

### Deprecated

- Deprecated the nonoptional `min`, `max`, `sum`, `average`, and `groupConcat`
  aggregate APIs. Their signatures remain available throughout SwiftQL 1.x.
  The canonical APIs will return optional expressions in SwiftQL 2.

### Fixed

- Removed stale generated documentation from version control. Local static-site
  output is ignored and can no longer stage or commit unrelated work.
- Updated DocC examples and key public symbol documentation to the current API.
  Source documentation now generates cleanly with DocC warnings treated as
  errors.
- Prefix bitwise NOT (`~`) is now constrained to integer SQL expressions.
  Real-valued expressions such as `Double` are rejected by the Swift type
  checker.
- Generated `.columns(...)` helpers no longer call the deprecated `result`
  helper, and immutable table macros no longer emit never-mutated-local
  warnings. Projection factories are emitted as nominal macro members so their
  static lookup works across files on Swift 5.9. First-party sources, tests,
  benchmarks, and macro expansions now build without ordinary compiler
  warnings.
- All first-party product and test targets now compile without complete
  strict-concurrency warnings under the supported Swift 6 compiler. The
  compatibility matrix checks this without enabling Swift 6 language mode.
- String concatenation now renders as an explicitly grouped binary expression,
  so `COLLATE` and surrounding operators apply with unambiguous SQLite
  precedence.
- Empty and all-NULL aggregate results can now be modeled and decoded as Swift
  `nil` through the new optional-result APIs.

### Migration

Use an `OrNull` aggregate when SQLite can return NULL:

```swift
let total = invoice.amount.sumOrNull()
```

Choose a nonoptional fallback explicitly when required:

```swift
let total = invoice.amount.sumOrNull().coalesce(0)
```

The deprecated v1 APIs retain their old result types and may still throw when
SQLite returns NULL. Projects that treat warnings as errors must migrate
deprecated calls when adopting SwiftQL 1.1.

The deprecated `NotificationCenter.sqlEntitiesChangedObserver` and
`sqlCommitObserver` callbacks are now explicitly `@Sendable`, matching
Foundation's callback contract. Existing calls remain source-compatible, but
strict-concurrency checking may require captured mutable state to gain explicit
isolation.

Scalar subqueries already add an optional layer because they may return no row.
Until the nullable-subquery flattening API tracked by #162 is available, selecting
an `OrNull` aggregate inside `subquery` or `subqueryExpression` requires an
explicit type-affinity wrapper so Swift models SQLite's single NULL state:

```swift
let total: any XLExpression<Int?> = XLTypeAffinityExpression<Int?>(
    expression: subquery {
        select(invoice.amount.sumOrNull()).from(invoice)
    }
)
```
