# Changelog

## [1.4.4] - 2026-07-23

### Added

- Added `INSERT OR ROLLBACK/ABORT/FAIL/IGNORE/REPLACE` through `Insert(_:or:)`
  and the functional `insert(_:or:)`. The conflict algorithm is part of the
  `INSERT` keyword and applies to every uniqueness constraint the statement
  violates.
- Added the `REPLACE INTO` statement through `Replace` and the functional
  `replace(_:)`, the SQLite shorthand for `INSERT OR REPLACE INTO`.
- Added `INSERT ... ON CONFLICT` upsert support through `OnConflict`, the
  functional `onConflict`/`onConflictDoNothing` methods, and `XLSchema.excluded`
  for referencing the proposed row. Both `DO NOTHING` and `DO UPDATE SET ...`
  (with an optional `WHERE` filter) forms are covered.
- Added `INSERT ... RETURNING` through the `Returning` clause and the
  `returning(_:)` method on insert statements (including `ON CONFLICT` upserts).
  A returning statement is fetchable — `makeRequest(with:).fetchAll()` yields the
  affected rows projected through the supplied result. SQLite rejects
  statement-aliased names in `RETURNING`, so the returned columns render
  unqualified; the statement executes on a write connection and is not
  observable as a live query. Requires SQLite 3.35.0.
- Recorded the new conflict-resolution, replace, upsert, and insert-returning
  surfaces in the #190
  canonical SQLite conformance inventory. It records 109 public-surface feature records: 101
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  5 unimplemented. Of the 156 evidence records, 97 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.

### Migration

No migration is required for v1.4.4. Every change is additive, and the existing
insert surface remains source-compatible.

## [1.4.3] - 2026-07-23

### Added

- Added the `date`, `time`, `datetime`, `julianDay`, `unixEpoch`, and `strftime`
  constructors on text time-value expressions. Each takes ordered
  `XLDateModifier` values, and SQLite applies them left to right, so the Swift
  argument order is the evaluation order — `moment.datetime(.months(1),
  .startOfMonth)` renders `datetime(..., '+1 months', 'start of month')`.
  Optional receivers preserve optionality.
- Added `XLDateModifier`, an ordered modifier type covering the relative-offset
  (`.days`/`.hours`/`.minutes`/`.seconds`/`.months`/`.years`), anchoring
  (`.startOfDay`/`.startOfMonth`/`.startOfYear`/`.weekday(_:)`), `.ceiling`,
  `.floor`, `.localTime`, `.utc`, and `.subsecond` modifiers available in every
  SQLite release the library validates against (3.42.0 and later). A modifier
  renders as a quoted string literal, so it cannot inject SQL; input-interpretation
  modifiers whose availability varies by release (`unixepoch`, `julianday`,
  `auto`) stay reachable through `XLDateModifier(_:)` rather than as named
  members.
- Added the `year`, `month`, `day`, `hour`, `minute`, `second`, `dayOfYear`,
  `dayOfWeek`, and `weekOfYear` component accessors, each reinterpreting a
  `strftime` substitution as an `Int` with `CAST(... AS INTEGER)`. An optional
  receiver preserves `NULL`.
- Moved `syntax.expression.date-functions` from partial to supported in the
  conformance inventory with new rendering and real-SQLite execution evidence,
  and regenerated the report.

### Changed

- `unixEpoch(_:)` returns `TimeInterval` rather than `Int`, because the
  constructor accepts arbitrary modifiers — including `.subsecond`, which makes
  SQLite return fractional seconds that an `Int` cannot represent. This mirrors
  the legacy `unixepoch(date:modifiers:)` surface. `toUnixTimestamp()` still
  returns `Int` for the no-modifier integer case.

### Migration

Date comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`) and julian-day subtraction
(`-`) reuse the existing generic `XLComparable` and floating-point operators
over date-function results rather than adding date-specific overloads, so
existing call sites are unaffected.

The legacy `unixepoch(date:modifiers:)`, `toUnixTimestamp()`, and
`XLDateFunctionModifiers` surface is retained for source compatibility.

## [1.4.2] - 2026-07-22

### Added

- Added `like(_:escape:)` across the same four optionality shapes as `like`.
  `ESCAPE` renders inside its own `LIKE` production, so a second `LIKE` in the
  same predicate cannot absorb it. SQLite requires the escape value to be
  exactly one character; a longer or empty value prepares and then fails when
  the statement is stepped, because no Swift type can express that constraint.
- Added `notIn` value-list, subquery, and common-table expressions mirroring the
  existing `in` shapes. The negation is carried by the `IN` node itself rather
  than by a wrapping `NOT`, so composing a predicate cannot move it outwards.
- Added optional-operand and NULL-candidate support to `in` and `notIn`,
  including the result-builder subquery form for optional receivers and NULL
  elements in a value list.
- Added `nullableSubquery(alias:_:)` and `nullableSubqueryExpression(alias:_:)`
  for subqueries on the nullable side of a `LEFT JOIN`, and flattened scalar
  subquery results so an optional inner statement no longer double-wraps
  `Optional`.
- Added connection-registered custom collating sequences.
  `GRDBDatabaseBuilder.addCollation(_:compare:)` registers a sequence on every
  connection the builder creates, mirroring the existing `addFunction`, and
  `XLCollation` gained `init(rawValue:)` so a name outside the three built-ins
  can be expressed.
- Added the `REGEXP` operator across the same four optionality shapes as `glob`.
  SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and ships no
  implementation, so the operator prepares only once the application registers a
  two-argument `regexp` function.
- Completed the generated real-SQLite operator conformance matrix. Every public
  operator overload now carries both prepare and semantic execution evidence,
  packed by operator family and optionality shape, and the corresponding
  inventory record moves from partial to supported.
- Added real-SQLite IN-subquery conformance cases for both query-backed entry
  points, and revived the same-table IN-subquery execution test so distinct
  aliases across two nesting levels are pinned by an executing test.

### Changed

- `XLCollation` is now a `RawRepresentable` struct rather than an enumeration.
  `.binary`, `.nocase`, and `.rtrim` remain available as static members and
  still render as bare grammar tokens. A custom name renders as a quoted
  identifier — `COLLATE "myCollation"` — which SQLite resolves to the same
  sequence, so `collate(_:)` does not become an arbitrary raw-SQL escape hatch.
  Equality and hashing fold ASCII case, matching how SQLite resolves collation
  names.

### Deprecated

- Deprecated the `subquery(alias:)` overload constrained to `XLMetaNullable`.
  It can never be selected, because no `select` function produces a statement
  over a nullable row type. Use `nullableSubquery(alias:_:)` instead.

### Migration

Existing `in`, `like`, `collate(_:)`, and `subquery(alias:)` call sites remain
source-compatible.

`XLCollation` changed from an enumeration to a struct. Code that switches
exhaustively over a collation value must gain a `default` case:

```swift
switch collation {
case .binary, .nocase, .rtrim:
    …
default:
    …
}
```

Register a custom collating sequence before naming it in a query. SQLite
resolves collations at preparation and reports `no such collation sequence`
otherwise:

```swift
builder.addCollation("localized") { lhs, rhs in
    lhs.compare(rhs, options: [], range: nil, locale: .current)
}
…
OrderBy(person.name.collate(XLCollation(rawValue: "localized")).ascending())
```

`REGEXP` requires the application to register a two-argument `regexp` function
on the connection. Without it, a statement using the operator fails to prepare
with `no such function: regexp`.

Select a scalar subquery on the nullable side of a join with
`nullableSubquery(alias:_:)`; the deprecated `XLMetaNullable` overload of
`subquery(alias:)` was never selectable.

## [1.4.1] - 2026-07-22

### Added

- Added constrained `cast(to:)` overloads across the Bool, integer, real, text,
  data, and optional conversion matrix. Source nullability is preserved and
  unsupported cast directions remain unavailable at compile time. The
  directional `toInt()`, `toDouble()`, `toString()`, and `toData()` helpers now
  delegate through the new API.
- Added a typed `all()` expression that renders an unqualified `*`, and
  `count(all())` with an `Int` result and exact `COUNT(*)` rendering. Row-count
  semantics are covered for populated, empty, and all-NULL SQLite inputs.
- Added typed `isBetween(_:_:)` and `isNotBetween(_:_:)` expressions. Nullable
  operands yield optional Boolean results, and each complete predicate is
  grouped so SQLite precedence is unambiguous. Compile-fail fixtures reject
  mismatched and non-comparable operand types in every compatibility cell.
- Added `total()` overloads for integer, real, nullable integer, and nullable
  real expressions. They preserve SQLite's non-null `Double` semantics,
  returning `0.0` for empty and all-NULL inputs, in deliberate contrast with
  the optional `sum()` API.
- Broadened `averageOrNull(distinct:)` to integer and real expressions and to
  their nullable forms, preserving a `Double?` result and plain `AVG(...)`
  rendering.
- Extended the bounded combinatorial SQLite corpus from 141 to 168 cases with
  explicit function, aggregate, JSON, `PRINTF`, and cast coverage. Every new
  case executes against real SQLite with an independent raw-SQL semantic
  oracle, including exact JSON capability attestation for `JSON_VALID/1` and
  `JSON_ARRAY_LENGTH/1,/2`.

### Changed

- Both real Swift 5.9 compatibility cells moved from the retiring `macos-14`
  runner to `ubuntu-22.04`. The cells install the exact official Swift 5.9.2
  archive under pinned detached-signature and signing-key verification, and
  privately link a checksum-verified SQLite 3.53.3 build so an older system
  SQLite cannot silently reduce the conformance surface. The complete
  compatibility build and the full package test suite continue to run in both
  committed- and clean-resolution modes.

### Migration

No migration is required for v1.4.1. Every change is additive or confined to
continuous integration, and the v1.3 public source and runtime contracts are
preserved.

## [1.3.0] - 2026-07-20

### Added

- Added the #190 canonical SQLite conformance inventory and deterministic
  generated report. It records 105 public-surface feature records: 97
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  5 unimplemented. Of the 141 evidence records, 89 exercise real SQLite and
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
