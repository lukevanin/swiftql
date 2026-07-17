# Changelog

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
