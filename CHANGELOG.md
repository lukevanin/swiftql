# Changelog

## [1.6.0] - Unreleased

### Added

- `XLJSONPath`, a typed SQLite JSON path built from segments rather than
  written as a string literal (issue #588). `XLJSONPath.root` is the document
  root, `key(_:)` adds an object member, `index(_:)` adds an array element
  counted from the start, and `last` and `index(fromEnd:)` count back from the
  end. A key is quoted only where SQLite's path grammar needs it -- when the
  key is empty, or holds a `.` or a `[` -- so a key that holds either names
  that key instead of changing the shape of the path. A key holding a `"`, a
  `\`, or a control character resolves only on a SQLite that unescapes JSON
  labels: JSON stores such a key escaped, older engines match a path label
  against that raw escaped text, and newer engines unescape both sides first,
  so no single spelling suits both. SwiftQL renders for the newer behaviour,
  which is what SQLite documents. A path renders through the same text
  formatter as any other text operand, so it cannot carry raw SQL. SQLite has
  no negative array index, so `index(_:)` stops with a diagnostic message when
  it is given one, and names `last` and `index(fromEnd:)` as the remedy.
  `appended` names the position one past the last element, rendered `[#]`,
  which is SQLite's idiom for appending to an array.

- `jsonArrayLength(path:)` gains an `XLJSONPath` overload (issue #588). The
  existing `String` overload is unchanged.

- SQLite's two JSON selection operators, added in SQLite 3.38.0 (issue #589).
  `jsonElement(at:)` renders `->` and returns the selected element as JSON
  text, so a selected string keeps its quotes and a JSON `null` reads back as
  the four characters `null`. `jsonValue(at:as:)` renders `->>` and returns
  the element as a SQL value of the requested type, so a selected string loses
  its quotes and a JSON `null` reads back as SQL `NULL`. Both results are
  optional, because a path that matches nothing yields SQL `NULL`. Both are
  methods rather than Swift operators: the compiler reserves `->` and refuses
  to declare it. SQLite's bare-name form on the right of the operator is not
  exposed, because `XLJSONPath.key(_:)` already names any single key and also
  composes.

## [1.5.7] - 2026-08-27

### Removed

- Four public types that nothing referenced, in SwiftQL or anywhere in this
  repository (issue #555): `XLDatabaseMetadata` and its only conformer
  `XLDatabaseMetadataObject`, `XLTableName`, and `XLUnionDependency`. Each was
  declared and never used -- no call site, no conformance, no mention outside
  its own declaration.

- Six unreferenced members of `SQLiteBuildValidationRuntimeMetadata` (issue
  #555). Five computed capability sets --  `compileOptionCapabilities`,
  `functionCapabilities`, `collationCapabilities`, `moduleCapabilities`, and
  `extensionCapabilities` -- which nothing read; the `has…(named:)` predicates
  beside them are how capabilities are actually resolved. And
  `hasFunction(named:argumentCount:)` loses its `argumentCount` parameter: no
  caller ever passed one, and arity was the wrong question to ask anyway, since
  SQLite reports `-1` for a variadic function.

### Changed

- `Select(_ meta:)` now traps with a diagnostic message when a dynamic
  projection cannot enumerate its columns against the definition reader, in
  place of the bare `try!` it used before (pull request #584). The message
  names the projection type, the underlying error, and the
  `XLStaticRowReadable` overload that skips the replay, which is the remedy
  when a static row layout was erased to `any XLRowReadable`. The same input
  trapped before this change, so no working code is affected; only the
  diagnostic is.

### Fixed

- A NaN `Double` bound through a `@SQLQuery` macro parameter is now rejected
  where the value is captured, rather than further down at the driver boundary
  (issue #554). SwiftQL's documented policy is that binding a NaN throws
  `XLSQLValueEncodingError.realBindingWouldBecomeNull` instead of letting SQLite silently store SQL `NULL` in its place, and
  `_xlQueryParameterBinding` -- the capture behind every macro parameter --
  was the one capture path missing that check. **Nothing was ever stored as
  `NULL` through it**: `GRDBDatabaseDriver` rejects a NaN `REAL` before the
  value reaches SQLite, so executing such a query already threw. It now throws
  from the capture, with the same error the driver produced, so every capture
  path agrees. A caller who invokes `_xlQueryParameterBinding` directly and
  inspects its result, rather than executing, sees the throw where they
  previously saw `.real(nan)`. Infinities are unaffected: they survive
  SQLite's binding round trip and remain valid bound values.

- A `RETURNING` request now registers custom functions that opt into implicit
  registration, so a data-changing statement whose clauses call one executes
  instead of failing with SQLite's "no such function" error (issue #553).
  `GRDBDatabase.makeRequest(with: any XLReturningStatement<Row>)` built its
  request without passing the rendered encoding's registrations, so the
  registration table reaching the connection was empty -- a predicate that
  worked in a plain `SELECT` failed once the same statement was written as
  `UPDATE ... RETURNING` or `DELETE ... RETURNING`. Functions registered
  upfront with `GRDBDatabaseBuilder.addFunction(_:)` were never affected.
  Static query descriptors still register nothing, which is deliberate and now
  documented: a descriptor keeps only deterministic SQL and parameter
  metadata, and a registration is a live closure that cannot survive into it.

## [1.5.6] - 2026-08-04

### Added

- `@SQLTable` and `@SQLResult` now declare a `Sendable` conformance for the
  models they expand, so a value built entirely from column values can be
  shared across isolation domains without the conformance being written out at
  every declaration (issue #531). Swift already infers `Sendable` for a struct
  whose stored properties are all `Sendable`, but withholds that inference from
  a type other modules can see, which is why a `public` model used to warn
  under complete strict-concurrency checking and left callers reaching for
  `nonisolated(unsafe)` to silence it. The macros fill in exactly that gap:
  a `public` or `package` model gets the conformance, and a model that is
  `internal` or narrower keeps the compiler's own inferred one and gets nothing
  generated. This is a public API addition. A model that already states
  `Sendable`, or `@unchecked Sendable`, keeps its own declaration and gets no
  second one, so existing declarations such as the `TodoKit` schema still
  compile unchanged. The generated conformance is checked rather than asserted,
  so a `public` model holding a non-`Sendable` stored property is now diagnosed
  on the generated extension where it previously compiled silently; declaring
  `@unchecked Sendable` on such a model takes responsibility for it and turns
  the generation off. Generic models are left alone, because the conditional
  conformance they need cannot be written by an extension macro without the
  compiler reporting `circular reference expanding extension macros`;
  `SQLScalarResult` and `SQLRow2`...`SQLRow6`, the shapes behind `#row`, are
  the affected types and they were not `Sendable` before this either. The
  conformance requires Swift 6.0 or later, since Swift 5.9 treats a
  macro-expanded extension as a separate source file for the rule that a
  `Sendable` conformance must be declared alongside its type and warns on every
  model; the 5.9 support point keeps the behaviour it had. See COMPATIBILITY.md.
- Added a `SwiftQLExamples` library product (issue #480), holding the
  pre-expanded schema and declared queries the Getting Started playground
  imports. A classic Xcode playground has no `Package.swift` of its own and
  cannot reliably load a Swift macro compiler plugin, so the example schema is
  built during the ordinary package build and the playground calls
  already-expanded API. It is example code rather than a supported API, and
  nothing in `SwiftQL` or `SwiftQLCore` depends on it.

### Changed

- `SQLiteBuildValidator` now reports the schema checks it could not run, and
  stops preparing queries once the snapshot's schema identity is already known
  not to match the manifest (issue #440). When
  `SQLiteBuildValidationRuntime.capture` fails, the row-count and fingerprint
  checks used to vanish from the report; they now appear as `.unsupported`
  `schema.row-count` and `schema.fingerprint` diagnostics, so a reader can tell
  a check that could not run apart from one that was never in the report. When
  a schema identity mismatch is already recorded, every manifest entry gets one
  deterministic `schema.mismatch-skipped` outcome instead of a preparation
  whose result is already meaningless. `overallVerdict` resolution, the
  manifest format, the CLI surface, and every existing pass/fail outcome are
  unchanged, and canonical reports remain byte-identical across repeated runs.

### Fixed

- Nullable columns can now be assigned in a `Setting` closure the way any
  Swift optional is: `row.occupationId = "occ-1"` sets the column,
  `row.occupationId = nil` sets it to SQL `NULL`, and an optional-typed
  expression — a `XLNamedBindingReference<String?>` whose bound value may be
  `NULL` at runtime, or another nullable column — assigns with the same
  spelling. Previously the generated setter's type was
  `Optional<any XLExpression<T?>>`, where the outer `Optional` meant "leave
  this column out of the `SET` clause"; that collided with the column's own
  optionality, and no assignment of a plain value or of `nil` compiled at
  all. Generated `MetaUpdate` types now route column assignment through
  key-path member lookup over typed per-column slots (`XLColumnUpdate` /
  `XLNullableColumnUpdate`), so participation in the `SET` clause is tracked
  separately from the value's own optionality and one column name resolves
  against every assignment shape. A column the closure never assigns still
  stays out of the statement, non-optional columns behave as before, and
  `MetaUpdate`'s memberwise initializer keeps its v1 shape, where a `nil`
  argument still means "omit this column".

- Fixed `SwiftQLSQLiteBuildValidationPlugin` failing every Xcode build of a
  plugin-adopting target (issue #492). `context.tool(named:)` resolves a
  build-tool plugin's tool to `$BUILD_DIR/$CONFIGURATION/<target name>`, while
  Xcode's build system names a package executable after its *product*. The
  validator's target (`SwiftQLSQLiteBuildValidationValidatorCLI`) and product
  (`swiftql-build-validate`) had different names, so Xcode built the
  validator's library dependencies, left the executable out of the adopting
  target's dependency graph, and failed with `Build input file cannot be found`
  before validation ran — on a valid manifest as much as an invalid one.
  `swift build` resolved the same graph correctly, which is why only Xcode was
  affected. The executable target is now named `swiftql-build-validate`,
  matching its product; its source directory is unchanged. Both build systems
  now agree: a valid manifest builds, and an invalid one fails with the
  validator's own diagnostic.
  `IntegrationTests/BuildValidationPluginFixture/verify-xcode.sh` drives that
  agreement through `xcodebuild` so the two names cannot drift apart again. No
  public API changed, and the `swiftql-build-validate` product and its CLI
  contract are unchanged.

## [1.5.5] - 2026-07-30

### Added

- Added canonical async live-query streams, `stream()`/`stream(bindings:)` and
  `streamOne()`/`streamOne(bindings:)`, to `XLRequest` (issue #308): a
  `for try await` loop is now the single source of truth for SwiftQL
  live-query observation — immutable-packet capture, retry, decoding, and
  buffering all live in one GRDB-native `AsyncThrowingStream` source
  (`GRDBLiveQueryAsyncBridge`, built directly on `ValueObservation.start`),
  rather than being duplicated per adapter.
- Defined the buffering, snapshot-lifecycle, and cancellation contract that
  the async streams and their adapters follow (issue #291): at most one
  undelivered snapshot is ever held per stream ("bound-1 newest wins"), and
  resuming or replenishing demand never forces a fresh fetch — it only
  surfaces whatever GRDB already produced. Recorded in
  <doc:LiveQueries>, "Buffering and Resumed-Demand Semantics", alongside the
  rejected alternatives.
- Added `XLObservableQuery`/`XLObservableQueryRow` (issue #97): `@Observable`
  (`iOS 17`/`macOS 14`+) wrappers over `stream()`/`streamOne()` exposing
  `rows`/`row`, `isLoading`, and `error` as `@MainActor` state, for SwiftUI
  clients on platforms that ship the `Observation` framework. Package's
  existing iOS 16/macOS 13 floor is unchanged.
- Added `XLResultSet` (issue #249): a connection-scoped, lazy, single-pass
  typed result set whose `next() throws -> Row?` steps and decodes exactly
  one row at a time, via new `withResultSet(_:)`/`withResultSet(bindings:_:)`
  methods on `XLRequest` and a driver-neutral pull-based streaming seam
  (`makeValuesStepper(_:)`) in `SwiftQLCore`.

### Changed

- Rebuilt `publish()`/`publish(bindings:)`/`publishOne()`/`publishOne(bindings:)`
  as Combine adapters over `stream()`/`streamOne()` (issue #309): Combine is
  now a leaf adapter mapping `Subscribers.Demand` onto a pull loop over a
  fresh async stream per subscriber, rather than an independent
  `ValueObservation`-backed observation engine. Public signatures are
  unchanged; a real demand-accounting over-delivery bug found during the
  rebuild is fixed as part of this change.

## [1.5.4] - 2026-07-28

### Added

- Added method-style scalar expression functions matching the existing
  majority style (issue #3): `all().count()`, `a.min(b, ...)`/`a.max(b, ...)`
  (at least one further expression, both because SQLite's scalar `MIN`/`MAX`
  is meaningless with fewer and to stay unambiguous against the deprecated
  zero-argument aggregate `min(distinct:)`/`max(distinct:)` methods of the
  same name), `condition.iif(then:else:)`, and `"...".printf(...)`. The
  previous free functions (`count(_:)`, `min(_:)`/`max(_:)`, `iif(_:then:else:)`,
  `printf(format:_:)`) are deprecated in favor of the new methods, matching
  the existing `sum()`/`average()` → `sumOrNull()`/`averageOrNull()`
  deprecation precedent.
- Added a `Setting(_:_:)` initializer that infers `Setting`'s row type from
  the same table reference already passed to the preceding `Update(_:)`,
  instead of requiring an explicit generic parameter (issue #96):
  `Update(person); Setting(person) { row in row.age = 42 }`. The existing
  `Setting { ... }` and `Setting(metaInstance)` initializers are unchanged.
- Restored the `#row` ad hoc row projection macro (issue #408, follow-up to
  #20; originally shipped in #383, then reverted after a Swift 5.9.2 IRGen
  compiler crash). The single-column shape (`SQLScalarResult`) is available
  on every compatibility cell; the two-to-six column shapes (`SQLRow2`
  through `SQLRow6`) are gated to Swift 6.1+ — SwiftQL's first source-level
  API divergence across compiler cells, documented in COMPATIBILITY.md's new
  "Swift 5.9 and Swift 6.0 API surface gaps" section. The underlying IRGen
  crash reproduces on both the pinned Swift 5.9.2 toolchain (Docker-verified)
  and the pinned Swift 6.0 cell (Xcode 16.2, observed directly in this
  release's CI), and isn't confined to one crossing point: `fetchAll()`,
  `publish()`, and `publishOne()` each hit it independently for a
  2+-generic-parameter row type. Swift 6.1 (Xcode 16.4) is the first cell
  confirmed free of the crash.
- Added `XLQueryObserver` and `XLQueryRowObserver` (issue #28):
  `ObservableObject` wrappers around `publish()`/`publishOne()` that expose
  `@Published rows`/`row` and `@Published error`, so a SwiftUI view model
  can adopt a live query directly without hand-writing a Combine sink. No
  new package dependency — the package conforms to `Combine.ObservableObject`
  (or `OpenCombine`'s equivalent on Linux) without importing SwiftUI itself.

### Changed

- `GRDBRequest.decodeRows(packet:)` accumulates into an outer array and
  returns `Void` from its `withReadConnection`/`withTransaction` closures,
  instead of returning `[Row]` directly. This protects every
  multi-generic-parameter `Row` type from the IRGen crash described above at
  zero cost on other `Row` types — motivated by, but not exclusive to,
  `#row`'s new shapes.

### Deprecated

- Deprecated the free functions `count(_:)`, `min(_:)`/`max(_:)`,
  `iif(_:then:else:)`, and `printf(format:_:)` in favor of their method-style
  equivalents (issue #3). Each keeps a source-compatible signature, including
  a deprecated single-argument `min(_:)`/`max(_:)` overload that preserves
  the prior variadic form's single-argument behavior (SQLite parses
  `MIN(expr)`/`MAX(expr)` as its aggregate function, not a scalar comparison)
  rather than changing it.

### Migration

No migration is required for v1.5.4. Every change is additive or a
source-compatible deprecation; `#row`'s two-to-six column shapes are the
package's first API surface unavailable on Swift 5.9 rather than a removal.

Confirmed and closed out two investigations opened as issues, with no
production code changes: chaining multiple optional fallbacks through
`coalesce`/`??` already composed correctly into SQLite's variadic
`COALESCE` (issue #7 — a footgun where `??` applied to a plain Swift
`Optional` silently falls back to the standard library's operator instead
of rendering `COALESCE` is now called out as a `> Warning` in
`Expressions.md`), and an already-optional scalar-subquery result already
flattened to a single-layer `T?` rather than `T??` (issue #162 — the three
observable NULL states now have direct real-SQLite test coverage).

## [1.5.3] - 2026-07-28

### Added

- Added `@SQLCodec(key)` (issue #66), a zero-storage property attribute
  macro that selects a named contextual value codec (from the v1.2 #188
  registry) on an individual `@SQLTable`/`@SQLResult` stored property,
  without wrapping the property, changing its Swift type, or altering the
  type's memberwise initializer, mutability, `Equatable`, or `Codable`
  behavior. Two properties of the same Swift type can now use two different
  storage conventions on one table. The macro emits the codec key as stable
  metadata (a `_swiftQLPropertyCodecKeys` dictionary keyed by column name)
  and generates a `staticResultField(...)` convenience per annotated
  property that already supplies `selection: .explicit(key)`, so callers
  never repeat the key by hand. Selection still resolves through the
  existing explicit-property/query-override/database-default precedence
  from #188; the attribute only supplies the "explicit" input.
- Added `XLJSONValueCodec` (issue #65), a codec factory that stores any
  application `Codable` value as SQLite `TEXT` or `BLOB`, with an immutable,
  `Sendable` snapshot of the relevant `JSONEncoder`/`JSONDecoder` strategies
  (key/date/data strategy, key sorting) captured at codec construction — no
  live shared encoder/decoder instance and no process-global JSON
  configuration. `TEXT` and `BLOB` are distinct, non-interchangeable storage
  identities. Malformed or incompatible data fails with a structured,
  catchable `XLValueCodecError` that wraps the underlying `EncodingError`/
  `DecodingError`, never a default value.
- Added three named SQLite numeric `Date` codec presets (issue #62):
  `UnixMilliseconds` (`INTEGER`, rounded to the nearest millisecond,
  rejecting `Int64` overflow), `UnixSeconds` (`REAL`,
  `Date.timeIntervalSince1970` stored as-is), and `JulianDay` (`REAL`,
  matching SQLite's own `julianday()` linear relationship). None is an
  implicit default — encoding without an explicit selector or a registered
  database default throws `.ambiguousCodec`. Every preset rejects a
  non-finite `Date` at encode time and a non-finite stored `REAL` at decode
  time with a structured error.
- Added `XLDateTextCodec` (issue #61): a versioned, SQLite-compatible
  standard `Date`-as-`TEXT` preset (fixed proleptic-Gregorian calendar, UTC
  offset, millisecond fractional precision, `Z`-suffixed
  `YYYY-MM-DDTHH:MM:SS.SSSZ` text, directly usable by SQLite's `date`/
  `time`/`datetime`/`julianday`/`strftime` and comparison operators without
  a dialect conversion expression), plus `XLDateTextCodec.custom(key:format:)`
  for applications that need a different fixed UTC offset or fractional
  precision via an explicit, immutable `XLDateTextFormat` — no process-global
  or shared mutable `DateFormatter`. The standard preset's supported
  proleptic-Gregorian year range is `0001...9999`; dates outside it fail to
  encode with a structured error rather than being silently clamped.
- Added `XLUUIDValueCodec.text` and `.blob` (issue #192): named, versioned
  presets that persist Foundation `UUID` as canonical lowercase hyphenated
  `TEXT` or the canonical 16-byte RFC 4122 `BLOB`, using only the existing
  #188 registry — no retroactive `UUID` conformance and no wrapper struct.
  Both target the same `(UUID, sqlite)` value/dialect pair, so they always
  agree on equality (case-insensitive text decode, canonicalized lowercase
  encode) but can never both be installed as the database default at once.
  Malformed input (invalid text, wrong `BLOB` length) surfaces as a
  structured `XLUUIDValueCodecError` carrying codec and property context.

### Migration

No migration is required for v1.5.3. Every codec preset and `@SQLCodec` are
new, additive surfaces built entirely on the existing v1.2 contextual
value-codec registry (#188) and v1.2 static query descriptors (#129); no
existing public API, persisted representation, or codec precedence rule
changed. Applying a new preset or `@SQLCodec` to an existing property is a
schema/data migration for that property alone, exactly like changing any
codec's key or version — the same rule the v1.2 registry already documents.

### Known limitations

- `@SQLCodec` selects among codecs already registered with the
  configuration passed to `staticResultField`; it does not register one
  itself. An unregistered key, or a key registered for a different Swift
  value type or dialect, fails the same way an explicit
  `XLValueCodecSelection` fails elsewhere — with the same `XLValueCodecError`
  cases, at the same "explicit" precedence tier, before any row is touched.
- The numeric and text `Date` codecs stay in SwiftQL's value-coding layer;
  none of them adds a SQL-level `julianday`/`strftime` expression-builder
  helper — value coding stays separate from SQLite's date/time operators
  and functions, which remain other issues' scope.
- PostgreSQL's native `UUID`/`JSONB`/timestamp mappings (tracked separately
  as issue #137) are untouched by this release; these presets are SQLite-
  specific, and a future PostgreSQL dialect module supplies its own mapping
  for the same Swift domain types without changing any codec added here.

## [1.5.2] - 2026-07-27

### Added

- Added a versioned, deterministic SQLite build-validation manifest
  (issue #292): `SwiftQLSQLiteBuildValidationManifest` projects static
  `XLStaticQueryDescriptor`s — SQL text, parameters, result columns, required
  capabilities, and a checked-in schema snapshot's identity/hash/fingerprint —
  into a canonical JSON sidecar. The manifest cross-checks declared
  parameters against the raw SQL text before any consumer runs, and resolves
  #190/#191/#254 conformance references through an injected
  `SQLiteBuildValidationReferenceRegistry` rather than depending on their
  test-only fixture targets. Same input always produces byte-identical
  output: sorted keys, no escaped slashes, sorted/deduplicated arrays.
- Added the standalone SQLite static-query build validator (issue #293): the
  `swiftql-build-validate` executable and its `SwiftQLSQLiteBuildValidationValidator`
  library consume a #292 manifest and its checked-in SQLite snapshot, open one
  dedicated read-only, query-only connection, and prepare every manifest entry
  with `sqlite3_prepare_v3` — proving the SQL parses, referenced
  tables/columns/functions/collations resolve, bind/result metadata matches
  the manifest, and declared capabilities are present in captured runtime
  evidence. Verdicts are fail-closed (`passed`/`failed`/`unsupported`, only
  `passed` succeeds) and the canonical JSON report is deterministic across
  repeated runs against the same inputs. It does not prove result values, row
  counts, or runtime behavior — those stay #214's responsibility, and every
  report names them explicitly under `delegated_checks`.
- Added `SwiftQLSQLiteBuildValidationPlugin` (issue #294), a SwiftPM
  `.buildTool()` plugin that wraps the #293 validator into an ordinary `swift
  build`. A target opts in by listing the plugin and placing a manifest and
  snapshot directly in its own source directory; the plugin declares them as
  explicit build-command inputs and the canonical report as an explicit
  output (never a `.prebuildCommand`), so SwiftPM's own incremental planner —
  not the plugin — decides when to re-run validation. A `failed` or
  `unsupported` verdict fails the build and forwards the validator's
  diagnostic to `swift build`'s output.

### Migration

No migration is required for v1.5.2. The manifest, validator, and plugin are
new, additive surfaces with no changes to any existing public API.

### Known limitations

- The validator proves schema/parameter/capability agreement with the real
  SQLite parser, not result values, row counts, or application behavior.
- Manifest entries can be generated in-process:
  `SQLiteBuildValidationQueryEntry(id:descriptor:declaredAliases:)` projects an
  existing `XLStaticQueryDescriptor` into sidecar form, deriving the SQL,
  parameter layout, and result columns, and recovering each parameter's
  physical placeholder index by scanning the rendered SQL. What no macro or
  tool in this release does is emit a manifest from a `@SQLQuery` declaration:
  the v1.5.1 declaration macro builds on the transitional `sql { }` statement
  path and does not lower to a descriptor, so that route stays a future #26
  boundary gated on the v2 catalog work (#212, #214). A target's snapshot is
  still supplied by you.
- The plugin is verified under `swift build`. Building a plugin-adopting
  package in Xcode 26.5 fails before validation runs, reporting `Build input
  file cannot be found` for the validator executable, on a valid manifest as
  well as an invalid one (#492). Fixed in v1.5.6; on v1.5.2 through v1.5.5 the
  plugin is usable from `swift build` and CI only.

## [1.5.1] - 2026-07-26

### Added

- Added `@SQLQuery` (issues #18/#26), an attached peer macro that lowers a
  query-specification function — an instance method on a database extension
  whose body builds a `sql { }` statement from its own parameters — into a
  value-free statement builder and a cached, cardinality-dispatched executor.
  Labeled parameters and result cardinality are derived from the function's
  own signature: `[Row]` fetches all rows, `Row?` fetches zero-or-one, a bare
  `Row` fetches exactly one (throwing `XLQueryCardinalityError.noRowsMatched`
  or `.moreThanOneRowMatched`), and the legacy `any/some
  XLQueryStatement<Row>` spelling fetches all rows. Every invocation
  constructs a fresh, immutable binding packet; callers never construct or
  mutate a binding themselves and never bind by textual SQL substitution.
- Added `@SQLQueries` (issues #18/#26, the recommended packaging), an
  attached member macro that reads every specification out of a nested
  `private struct Query` container inside one `@SQLQueries`-attached database
  extension, and generates the executors as members of the database itself —
  carrying the specification's own name (`personByName(name:)`, not
  `fetchPersonByName`) because they land in a different scope. Generates a
  connection-scoped `Context`, an `execute(_:)` entry point for running
  several declared queries in one scope, and one database-level convenience
  executor per specification.
- Added the frozen-literal guard: both macros reject, at the declaration
  site, every parameter-reference shape their signature-driven rewrite cannot
  turn into a named placeholder — a string interpolation, a nested-closure
  capture, a direct call argument, a local-binding initializer, a
  hand-constructed binding, a shadowing declaration, member access on a
  parameter, a collection-typed parameter, and an unreferenced parameter.
  Every remaining reference shape the rewrite reaches is rewritten to a named
  placeholder, so the encoding has no path that silently freezes a stale
  argument value into the cached SQL.
- Added `XLRenderOnceCache` and `XLPreparedQueryCacheKey`: each declaration
  renders its value-free statement to SQL at most once per
  `(databaseIdentifier, dialectIdentifier)` and reuses the resulting request
  on every later call, so the underlying GRDB connection reuses one physical
  prepared statement across calls with different argument values.
  `GRDBDatabase.preparedQueryCacheKey` opts the GRDB adapter into this
  reuse; `XLDatabase.preparedQueryCacheKey` defaults to `nil` (render on every
  call) so existing third-party adapters keep compiling.
- Added the `DeclaredQueries` DocC article covering the `@SQLQuery` and
  `@SQLQueries` forms, the frozen-literal guard, render-once caching and its
  concurrency/`Sendable` story, and the v1.5 transitional-syntax note.
- Added typed multi-statement transaction scopes (issue #284):
  `XLTransactionalDatabase.withTransaction(_:)` runs an ordered sequence of
  typed `XLRequest`/`XLWriteRequest` invocations — reads and writes alike —
  on one pinned GRDB connection as a single atomic unit, committing only
  after the whole body succeeds and rolling back every write on a
  preparation, binding, execution, decoding, or user-thrown failure, with no
  GRDB type anywhere in the contract. `@SQLQueries`'s generated `execute(_:)`
  is now sugar over this same primitive, so declared-query calls and
  `makeRequest(with:)` calls in one `execute(_:)` closure commit or roll back
  together. Calling `withTransaction(_:)` again from inside an active body —
  whether on the scope it was given or on the original database captured
  from the enclosing closure — is rejected with a catchable
  `XLTransactionScopeError.nestedTransactionUnsupported` before any pool
  access, instead of the uncatchable crash GRDB's own reentrant-write guard
  would otherwise raise. A scope value used after its body returns throws
  `.scopeEscaped`; `publish()`/`publishOne()` inside a transaction throws
  `.liveQueriesUnsupportedInTransaction`; an already-cancelled task throws
  `CancellationError` before the transaction opens. Documented in
  `GettingStarted`'s "Typed multi-statement transaction scopes".
- Added composite/nested result selection (issue #6): a stored property on an
  `@SQLTable`/`@SQLResult` type can now itself be another `@SQLTable`/
  `@SQLResult` type. The generated `staticRowLayout(using:...)` factory
  flattens every one of the nested type's own columns into the enclosing
  type's flat SQL result (re-aliased with the property name as a prefix, e.g.
  `employee_id`, `employee_name`), and reconstructs the nested value before
  building the enclosing type. Nesting composes to any depth, since a
  composite property's argument is itself the nested type's own
  `staticRowLayout(using:...)` result.
- Added the `XLStaticRowFieldSource` protocol and `XLStaticFieldGroup` type to
  `SwiftQL`. Every generated `staticRowLayout(using:...)` parameter now takes
  an `XLStaticRowFieldSource` value; both an ordinary `XLStaticSelectField`
  (through a default implementation, so no scalar call site changes) and an
  `XLStaticRowLayout` (for a nested composite property) conform to it. The
  macro has no semantic access to a property's type declaration, so it never
  has to detect which case applies -- Swift's own conformance checking
  resolves it from whichever value the caller passes to a given property.
- Extended the unsupported-column-type diagnostic to name both supported
  property shapes (a scalar `XLLiteral` column, or a nested `@SQLTable`/
  `@SQLResult` composite), so a property type the macro cannot resolve as
  either is rejected with an actionable message instead of only failing
  downstream with an opaque protocol-conformance error.
- Added the issue #256 `@SQLTable`/`@SQLResult` macro regression corpus:
  expansion and diagnostic tests for reserved/escaped and Unicode
  identifiers, SQL-keyword-like property names, doubly-wrapped optionals,
  every reserved generated-member name, mixed access-control modifiers, and
  a wide (12-property) row; and a checked-in downstream consumer fixture
  (`IntegrationTests/Swift5Client`) that compiles and executes BLOBs,
  optionals, `XLEnum` columns, a wide row, and composite/nested result
  selection against real SQLite without `@testable`. Each case's provenance
  and disposition (including the still-unsupported optional composite
  property, gated on issue #6) is recorded in
  `Tests/SQLMacrosTests/MacroRegressionCorpus.json`, a sibling to the #190
  SQL-syntax conformance inventory scoped to macro code-generation instead.
- Added the `@SQLFunction` macro (#25), which generates the `XLCustomFunctionDefinition`
  and `makeSQL(context:)` boilerplate for a custom `XLCustomFunction` conformer
  from its stored properties — one positional SQL argument per property, in
  declaration order. `execute(reader:)`, the actual computation, is still
  written by hand. The macro is opt-in sugar: hand-written `XLCustomFunction`
  conformances that implement `definition` and `makeSQL` themselves keep
  working unchanged.
- Added implicit custom-function registration. A custom function conforming to
  `XLCustomFunction` can opt in by calling the new
  `XLBuilder.customFunctionCall(_:parameters:)` from `makeSQL(context:)`
  instead of `simpleFunction(name:parameters:)`. `GRDBDatabase` then registers
  the function with SQLite automatically the first time a rendered statement
  referencing it executes, without requiring a `GRDBDatabaseBuilder.addFunction`
  call beforehand. Because `GRDB.DatabasePool` maintains several persistent
  reader connections and a registration only affects the one physical
  connection it runs on, the function is (cheaply) re-registered on every
  execution rather than tracked as "already registered" once, so it works
  correctly no matter which pooled connection services a given call.
  `GRDBDatabaseBuilder.addFunction` is unchanged and continues to work exactly
  as before for functions that keep calling `simpleFunction` directly, or for
  callers who prefer registering everything upfront.

### Migration

No migration is required for v1.5.1. `@SQLQuery` and `@SQLQueries` are new,
additive macros; the one new `XLDatabase.preparedQueryCacheKey` protocol
requirement has a default (`nil`) that keeps every existing conformer,
including third-party `XLDatabase` adapters, source-compatible.

### Known limitations

- Only `SELECT`-shaped specifications are supported; a write statement
  (`INSERT`/`UPDATE`/`DELETE`, with or without `RETURNING`) is not yet an
  accepted return shape. A `.command` cardinality dispatching to
  `XLWriteRequest.execute` remains future work.
- Collection-typed parameters (`[T]`, `Set`, `Dictionary`) are rejected,
  because a variable-length `IN` list would change the rendered SQL text with
  the element count.
- The generated executor is synchronous and throwing; an `async` variant is
  additive future work.
- Peer and member names are derived from the specification's base name only,
  so two `@SQLQuery` functions sharing a base name but differing in
  parameter list generate colliding peer declarations — a loud
  duplicate-declaration compile error, not a silent one.
- Only one `@SQLQueries`-attached extension is supported per database type; a
  second would redeclare `Context` and `execute(_:)`.
- A composite/nested `@SQLTable`/`@SQLResult` property must be
  non-optional; an optional nested composite (representing an absent
  value from an outer join, for example) is not yet supported.
- `withTransaction(_:)` does not support nested transactions or savepoints —
  a nested call is rejected outright rather than silently composed — and
  cancellation is checked only once, before the transaction opens; the
  synchronous body has no cooperative mid-transaction cancellation point.
  Both remain tracked by v2 issue #113, matching the disposition the shared
  `SQLiteTransactionConformanceFixtures` capability table (issue #253)
  already recorded for the driver-level contract.

## [1.4.6] - 2026-07-25

### Changed

- Reduced SwiftQL query construction-and-rendering allocations without changing
  rendered SQL, entity metadata, query semantics, or the public 1.x API. A
  deterministic allocation profile attributed roughly three-quarters of the
  `swiftql_construction_and_rendering` phase's allocations to rendering;
  single-argument token append, a single-token `build()` fast path, and a
  one/two-component `scopedName` fast path cut render allocations about 15% and
  the phase median about 13-17% across the #128 harness read cases, with
  byte-identical SQL. No absolute CI latency gate was added (#166).
- Reused one per-row normalization buffer on the incremental GRDB decode path,
  removing the per-row `[XLSQLiteValue]` allocation (and a redundant `Array`
  copy) while preserving the #248 bounded-memory guarantee — the typed decode
  path materializes no intermediate matrix. This is an allocation-only change
  and is latency-neutral on the #250 harness, which showed the incremental
  regression is decode-compute bound rather than allocation bound; the
  remaining latency work is tracked in #353 (#266).

### Added

- Added the `swiftql-construction-profile` diagnostic executable. It counts
  per-operation heap allocations through the in-process `malloc_logger` hook and
  splits construction versus rendering timing for the #128 read queries. It is
  diagnostic evidence for #166, not part of any product runtime or a CI gate.

### Migration

No migration is required for v1.4.6. Every change is internal; the public API,
entity metadata, and rendered SQL are unchanged.

## [1.4.5] - 2026-07-24

### Added

- Added `NATURAL JOIN` and `USING (columns...)` join constraints through
  `Join.Natural(_:)`, `Join.NaturalLeft(_:)`, `Join.Inner(_:using:)`, and
  `Join.Left(_:using:)`, plus the fluent `naturalJoin`/`naturalLeftJoin` and
  `innerJoin(_:using:)`/`leftJoin(_:using:)` methods (also on `QueryBuilder`).
  A join renders exactly one of `ON <expr>`, `USING (cols)`, or — for
  `NATURAL` — no constraint at all.
- Added `RIGHT JOIN` through `Join.Right(_:on:)` and the fluent/`QueryBuilder`
  `rightJoin` methods. The joined (right-hand) table stays non-nullable; the
  `FROM` (left-hand) table must be declared with `XLSchema.nullableTable(_:as:)`
  so its columns decode as optionals when a joined row has no match. Requires
  SQLite 3.39.0 (2022-06) or later.
- Added `FULL OUTER JOIN` and completed `CROSS JOIN` coverage on `QueryBuilder`
  through `Join.FullOuter(_:on:)` and the fluent/`QueryBuilder`
  `fullOuterJoin`/`crossJoin` methods. A full outer join requires both sides
  nullable — the joined table via `XLMetaNullableNamedResult`, the `FROM`
  table via `nullableTable(_:as:)` — unlike `LEFT JOIN`, where only the
  joined side is nullable. Requires SQLite 3.39.0 or later. The previously
  broken `Join.Outer`, which emitted an invalid bare `OUTER JOIN`, stays
  removed in favor of `Join.Left`/`Join.FullOuter`.
- Added `MATERIALIZED` / `NOT MATERIALIZED` hints on common table expressions
  through a `materialization: XLCommonTableMaterialization` parameter on
  `XLSchema.commonTable`, `recursiveCommonTable`, `recursiveCommonTableExpression`,
  and the new scalar common-table constructors below. Omitting it — the
  default, `.unspecified` — renders the unchanged `alias AS (...)` form.
- Added a direct scalar common-table-expression surface —
  `XLSchema.scalarCommonTable`, `recursiveScalarCommonTable`,
  `scalarCommonTableExpression`, and `recursiveScalarCommonTableExpression` —
  so a `T`-typed recursive or non-recursive CTE no longer needs a
  one-property `@SQLResult`/`SQLScalarResult<T>` wrapper solely to carry one
  scalar column. The CTE renders an explicit column list (`cte(value) AS
  (...)` by default) instead of changing every scalar `SELECT`'s visible
  column label. `SQLScalarResult` remains source-compatible as a legacy shim.
- `UNION`, `UNION ALL`, `INTERSECT`, and `EXCEPT` on a chained statement no
  longer require `Row: XLResult`; they now reuse the first branch's existing
  row reader instead of rebuilding one from `Row: XLResult`, so a compound
  query over a bare literal type (`Int`, `String`, ...) composes without a
  result wrapper.
- Replaced the internal mutable recursive-CTE completion cell with an
  alias-first, two-phase, value-semantic `XLRecursiveCommonTableDraft`. The
  self-reference passed to a recursive CTE's body is now derived from its
  reserved alias alone, and completion is transactional: a throwing body
  rolls the draft back to its declared state so it can be retried.
  `recursiveCommonTable` and `recursiveCommonTableExpression` keep their
  existing signatures and render byte-for-byte identical SQL.

### Migration

No migration is required for v1.4.5. Every change is additive: existing
joins, common table expressions, and `SQLScalarResult` usage compile and
render unchanged.

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
- Added `UPDATE` support scoped by a `WITH` common table expression through
  `XLWithStatement.update`, so a factored common table expression can drive an
  update, for example `with(cte).update(t).set { ... }.from(cte).where(...)`.
- Added `INSERT ... RETURNING` through the `Returning` clause and the
  `returning(_:)` method on insert statements (including `ON CONFLICT` upserts).
  A returning statement is fetchable — `makeRequest(with:).fetchAll()` yields the
  affected rows projected through the supplied result. SQLite rejects
  statement-aliased names in `RETURNING`, so the returned columns render
  unqualified; the statement executes on a write connection and is not
  observable as a live query. Requires SQLite 3.35.0.
- Added `DELETE ... RETURNING` through the same `returning(_:)` clause on delete
  statements, yielding the deleted rows. Requires SQLite 3.35.0.
- Added `UPDATE ... RETURNING` through the same `returning(_:)` clause on update
  statements, yielding the updated rows. This completes RETURNING for INSERT,
  UPDATE, and DELETE. Requires SQLite 3.35.0.
- Confirmed and recorded the SELECT forms of data-changing statements:
  `INSERT ... SELECT` and the `UPDATE ... SET ... FROM (SELECT ...)` form (built
  with `fromExpression`). Both now carry real-SQLite execution evidence in the
  conformance inventory.
- Recorded the new conflict-resolution, replace, upsert, update-with-CTE,
  RETURNING (insert, delete, update), and INSERT/UPDATE SELECT surfaces in the
  #190 canonical SQLite conformance inventory. It records 114 public-surface feature records: 110
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  1 unimplemented. Of the 180 evidence records, 110 exercise real SQLite and
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
Selecting an `OrNull` aggregate — or any other already-optional expression —
inside `subquery` or `subqueryExpression` composes directly into a single
`Int?`, not `Int??`, so Swift models SQLite's single NULL state without an
explicit type-affinity wrapper:

```swift
let total = subquery {
    select(invoice.amount.sumOrNull()).from(invoice)
}
```
