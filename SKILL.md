---
name: swiftql
description: Use when Codex works in a Swift package or Apple application that uses SwiftQL to define typed tables and results, declare or modify SQLite queries, run typed transactions, observe live results, pass immutable bindings, add contextual codecs, prepare static queries, integrate a database adapter, or diagnose SwiftQL execution boundaries. Use the checked-out public v1 contract; 1.5.6 is the latest published package, adding nullable-column assignment in `Setting` closures on top of v1.5.5 async live-query streams, `@Observable` query wrappers, and lazy result sets, v1.5.4 method-style scalar functions and observers, v1.5.3 contextual codec presets and `@SQLCodec`, v1.5.2 build-time query validation, and v1.5.1 declared-query macros (`@SQLQuery`/`@SQLQueries`) and typed transaction scopes. Do not use this skill to teach SQL generally or claim unshipped features.
---

# SwiftQL

SwiftQL is a typed, SQL-shaped SQLite DSL layered on GRDB. Keep schema objects,
query structure, and invocation values separate, and verify every API against
the checked-out package version before editing consumer code. This skill covers
tables and results, declared and hand-built queries, bindings, decoding,
transactions, live queries, contextual codecs, build-time validation, and the
repository's validation commands. It does not teach SQL and never claims
roadmap work as shipped API.

## Establish the package boundary

- Add `https://github.com/lukevanin/swiftql.git` with Swift Package Manager and
  attach the `SwiftQL` library product to each application target that imports
  it. It carries the macros, the DSL, contextual codecs, and the GRDB-backed
  SQLite driver.
- Depend directly on `SwiftQLCore` only when implementing a dialect or database
  adapter. It deliberately contains no usable GRDB connection.
- Require Swift tools 5.9 and Swift 5 language mode, iOS 16 or later, or macOS
  13 or later. Linux is covered by the pinned Swift 5.9.2 cell through
  OpenCombine 0.14.0. Swift 6.0 through 6.3 compilers are tested, always in
  Swift 5 language mode; Swift 6 language mode, non-SQLite dialects, and
  non-GRDB drivers are unsupported.
- Two surfaces need more than that floor: `XLObservableQuery` and
  `XLObservableQueryRow` require iOS 17 or macOS 14 for the `Observation`
  framework, and `#row`'s two-to-six column shapes (`SQLRow2` through
  `SQLRow6`) require Swift 6.1 or later, because earlier compilers crash during
  IR generation. `#row`'s single-column shape works everywhere.
- Read [the changelog](CHANGELOG.md) before choosing a package requirement.
  `1.5.6` is the latest published package. Pin a source revision only when
  intentionally testing later changes from `main`.

## Prefer the v1.5 declared-query workflow

1. Declare stored rows with `@SQLTable` and projections with `@SQLResult`. A
   stored property may itself be another `@SQLTable`/`@SQLResult` type, which
   decodes a joined row into a nested value; a composite property must be
   non-optional.
2. Declare reads as functions with `@SQLQueries` (the recommended packaging) or
   `@SQLQuery`. Parameters come from the signature, cardinality from the return
   type, and the macro renders SQL once per database and builds a fresh
   immutable binding packet per call.
3. Group statements that must succeed or fail together in
   `withTransaction { scope in ... }`, and use only `scope` inside it.
4. Use `stream()`/`streamOne()` for live data, and the synchronous
   `fetchAll()`/`fetchOne()`/`withResultSet(_:)`/`execute()` methods otherwise.
5. Fall back to a hand-built `sql { schema in ... }` statement plus
   `makeRequest(with:)` for what declared queries cannot express in v1.5, above
   all writes, which are not yet an accepted declaration shape.
6. Let preparation, binding, driver, and decoding errors propagate unless the
   application has an explicit error policy.

Define the table and its declared queries together. Only one `@SQLQueries`
extension is supported per database type, so put every specification for one
database in a single container.

<!-- compile-test: IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift#schema -->
```swift
import SwiftQL

@SQLTable(name: "SkillPerson")
struct SkillPerson: Equatable {
    var id: String
    var name: String
}

@SQLQueries
extension GRDBDatabase {

    // Generated executors become members of `GRDBDatabase`, never of this
    // container, so the container stays private to its file.
    private struct Query {

        // The return type chooses the cardinality: `[Row]` fetches every
        // match, `Row?` fetches zero or one, and a bare `Row` insists on
        // exactly one.
        func skillPeopleByName(name: String) -> [SkillPerson] {
            sqlResult { schema in
                let person = schema.table(SkillPerson.self)
                Select(person)
                From(person)
                Where(person.name == name)
            }
        }
    }
}
```

The full lifecycle — create, insert in a transaction, read through the declared
query, update, and delete — keeping values in bindings rather than in rendered
SQL:

<!-- compile-test: IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift#lifecycle -->
```swift
enum SkillQueryError: Error {
    case missingParameter(String)
}

// A request owns rendered SQL and an immutable parameter layout. Values for
// one call live in a separate packet built against that layout.
func skillTextPacket(
    _ parameters: [(name: String, value: String)],
    for layout: XLParameterLayout
) throws -> XLInvocationBindings<XLSQLiteValue> {
    try XLInvocationBindings<XLSQLiteValue>(
        layout: layout,
        bindings: try parameters.map { parameter in
            guard let slot = layout.slot(for: .named(parameter.name)) else {
                throw SkillQueryError.missingParameter(parameter.name)
            }
            return try XLInvocationBinding(
                slot: slot,
                value: .text(parameter.value)
            )
        }
    ).validatingComplete()
}

func runSkillLifecycle(in database: GRDBDatabase) throws -> [SkillPerson] {
    // `sqlCreate` renders `CREATE TABLE IF NOT EXISTS`. It is not a migration
    // engine and never alters an existing table.
    try database.makeRequest(with: sqlCreate(SkillPerson.self)).execute()

    // Statements that must succeed or fail together share one transaction on
    // one pinned connection. Use `scope`, never the captured `database`.
    try database.withTransaction { scope in
        try scope.makeRequest(
            with: sqlInsert(SkillPerson(id: "ada", name: "Ada Lovelace"))
        ).execute()
        try scope.makeRequest(
            with: sqlInsert(SkillPerson(id: "grace", name: "Grace Hopper"))
        ).execute()
    }

    // The declared query renders once per database and reuses one prepared
    // statement. Each call builds a fresh immutable packet from its arguments.
    _ = try database.skillPeopleByName(name: "Grace Hopper")

    // Writes are not a declared-query shape in v1.5, so they keep their values
    // out of the rendered SQL with named bindings instead.
    let idParameter = XLNamedBindingReference<String>(name: "id")
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let renameRequest = database.makeRequest(
        with: sql { schema in
            let person = schema.into(SkillPerson.self)
            Update(person)
            Setting(person) { row in
                row.name = nameParameter
            }
            Where(person.id == idParameter)
        }
    )
    try renameRequest.execute(
        bindings: try skillTextPacket(
            [
                (name: "id", value: "grace"),
                (name: "name", value: "Grace B. Hopper"),
            ],
            for: renameRequest.parameterLayout
        )
    )

    let deleteRequest = database.makeRequest(
        with: sql { schema in
            let person = schema.into(SkillPerson.self)
            Delete(person)
            Where(person.id == idParameter)
        }
    )
    try deleteRequest.execute(
        bindings: try skillTextPacket(
            [(name: "id", value: "grace")],
            for: deleteRequest.parameterLayout
        )
    )

    return try database.skillPeopleByName(name: "Ada Lovelace")
}
```

Use `sqlCreate` only for basic table creation. It adds no declared SQLite type
names, primary keys, uniqueness, foreign keys, indexes, or migrations, and it
never upgrades an existing table. Keep schema evolution in an explicit
application-owned migration system such as GRDB's `DatabaseMigrator`.

Read the [declared-queries guide](https://lukevanin.github.io/swiftql/documentation/swiftql/declaredqueries/)
and [getting started](https://lukevanin.github.io/swiftql/documentation/swiftql/gettingstarted/)
rather than reproducing those contracts in consumer comments;
[select queries](https://lukevanin.github.io/swiftql/documentation/swiftql/queries/)
and [expressions](https://lukevanin.github.io/swiftql/documentation/swiftql/expressions/)
cover joins, grouping, subqueries, common table expressions, and operators.

### Declaration limits to respect

- Only `SELECT`-shaped specifications are supported; a write, with or without
  `RETURNING`, is not an accepted return shape in v1.5.
- Collection-typed parameters (`[T]`, `Set`, `Dictionary`) are rejected, because
  a variable-length `IN` list would change the rendered SQL text.
- Generated executors are synchronous and throwing; there is no `async` variant.
- Executor names derive from the specification's base name only, so two
  specifications sharing a base name collide with a duplicate-declaration error.
- The frozen-literal guard rejects, at the declaration site, every parameter
  reference it cannot turn into a named placeholder: string interpolation,
  nested-closure capture, a direct call argument, a local-binding initializer,
  a hand-constructed binding, a shadowing declaration, member access on a
  parameter, a collection parameter, and an unreferenced parameter. Write
  `column == parameter`; never route around a diagnostic by interpolating.

## Bind parameters and decode results

- For a hand-built request, retain the request and build a fresh immutable
  `XLInvocationBindings<XLSQLiteValue>` packet per call. Missing is not `NULL`:
  omitting a binding fails completeness validation, while `.null` is a present
  value accepted only by a nullable slot.
- Do not turn runtime values into identifiers, ordering choices, placeholder
  counts, or SQL grammar. Bind values; keep grammar and identifiers in the
  Swift expression graph. Use intrinsic `Bool`, `Int`, finite `Double`,
  `String`, and `Data` storage directly and contextual codecs for everything
  else, and never render a non-finite `Double` as an inline numeric token.
- Decode into the selected `@SQLTable` or `@SQLResult` row. Prefer `fetchAll()`
  for a retained array, `withResultSet(_:)` when the result may be large or
  iteration may stop early, and `fetchOne()` for zero-or-one. An `XLResultSet`
  is valid only inside its `withResultSet(_:)` callback and throws
  `XLResultSetError.closed` afterwards.
- Treat `XLInvocationBindingError` and `XLRequestBindingError` as caller
  contract failures. Adapter authors should preserve structured
  `XLDatabaseContractError` categories; the established GRDB facade can still
  expose `DatabaseError` or `XLColumnReadError` where its compatibility policy
  requires those concrete errors.

## Keep transactions explicit

- `withTransaction(_:)` is the shipped typed transaction contract. It runs an
  ordered sequence of typed requests on one pinned connection, commits when the
  body returns, and rolls back every write when it throws.
- Use only the pinned scope inside the body. Re-entering the root database or
  calling `withTransaction(_:)` again throws
  `XLTransactionScopeError.nestedTransactionUnsupported`; using a scope after
  its body returns throws `.scopeEscaped`; starting a live query inside one
  throws `.liveQueriesUnsupportedInTransaction`.
- Do not claim nested transactions, savepoints, or mid-transaction cancellation
  hooks. Cancellation is checked once, before the transaction opens.
- `@SQLQueries`'s generated `execute(_:)` is sugar over the same primitive, so
  declared-query and `makeRequest(with:)` calls in one closure commit or roll
  back together. Migrations stay application or driver work; `sqlCreate` is not
  a migration engine.

## Observe live results

`stream()` and `streamOne()` are the canonical live-query API; the Combine
`publish()`/`publishOne()` methods are adapters over that same source rather
than a second observation engine.

<!-- compile-test: IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift#live -->
```swift
func observeSkillPeople(
    named name: String,
    in database: GRDBDatabase
) async throws {
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let request = database.makeRequest(
        with: sql { schema in
            let person = schema.table(SkillPerson.self)
            Select(person)
            From(person)
            Where(person.name == nameParameter)
        }
    )
    let bindings = try skillTextPacket(
        [(name: "name", value: name)],
        for: request.parameterLayout
    )
    // The packet is captured once; every refresh and retry reuses it.
    // Cancelling the consuming task ends iteration and tears the observation
    // down, and never throws `CancellationError`.
    for try await people in request.stream(bindings: bindings) {
        print("\(people.count) matching rows")
    }
}
```

- Constructing a stream performs no database work; the first `next()` starts the
  GRDB observation. Each call creates one independent single-consumer stream, so
  two consumers must call `stream()` twice.
- At most one undelivered snapshot is buffered per stream, newest wins, and
  resuming demand never forces a fresh fetch.
- Fetching is all-or-nothing: a failed execution or row decode throws the
  original error instead of yielding a truncated result.
- For SwiftUI, prefer `XLObservableQuery`/`XLObservableQueryRow` on iOS 17 or
  macOS 14 and later, and `XLQueryObserver`/`XLQueryRowObserver` below that.
- Read [live queries](https://lukevanin.github.io/swiftql/documentation/swiftql/livequeries/)
  for the full buffering, cancellation, retry, and delivery contract.

## Respect dialect, driver, and codec ownership

- Let `XLSQLiteDialect` own SQLite grammar, placeholder spelling, identifiers,
  storage classes, and required capabilities, and let the driver own
  connections, physical statements, transport binding, execution, and row
  reads. Keep physical statements on the connection that prepared them: a
  logical request or prepared handle is database-bound but owns none.
- Prefer immutable contextual `XLValueCodec` registrations when one Swift type
  has one or more database representations. Select codecs deterministically,
  snapshot the configuration in the database or prepared handle, and treat a
  codec key or version change as a schema/data compatibility decision.
- v1.5.3 ships named presets rather than implicit defaults: `XLDateTextCodec`,
  the `UnixMilliseconds`/`UnixSeconds`/`JulianDay` numeric `Date` codecs,
  `XLJSONValueCodec`, and `XLUUIDValueCodec.text`/`.blob`. Encoding without an
  explicit selector or a registered database default throws `.ambiguousCodec`.
  `@SQLCodec(key)` selects a registered codec on one stored property; it does
  not register one, and an unregistered key fails like any explicit selection.

Read [contextual codecs](https://lukevanin.github.io/swiftql/documentation/swiftql/customtypes/) and
[prepared execution boundaries](https://lukevanin.github.io/swiftql/documentation/swiftql/advancedusage/)
for the exact selection order, structured errors, row lifetime, and driver
contracts.

## Use static queries and build-time validation where they earn their keep

Choose a static query when the definition needs durable identity, explicit
parameter and result metadata, cardinality, registration before a database is
opened, or a raw-value handle that can cross tasks.

- Declare invocation inputs with `XLQueryCapture`; runtime Swift values are not
  inferred from bare variables in the runtime DSL.
- Render and validate the statement, then construct an immutable
  `XLStaticQueryDescriptor`. Never store a database, connection, prepared
  statement, or invocation value in it, and give each definition a stable
  `XLQueryDefinitionIdentity` persisted as canonical bytes or hex, never as a
  Swift `hashValue`. Prepare it through
  `GRDBDatabase.prepareInvocation(with:)`, then make a fresh packet per call
  matching the descriptor's cardinality.
- v1.5.2's `swiftql-build-validate` executable and
  `SwiftQLSQLiteBuildValidationPlugin` check a manifest of static descriptors
  against a checked-in schema snapshot during `swift build`. They prove the SQL
  parses and that schema, parameter, and capability metadata agree, and prove
  nothing about result values, row counts, or behavior. No macro emits a
  manifest from a `@SQLQuery` declaration yet. On the published v1.5.2 through
  v1.5.5 packages a plugin-adopting target also fails to build under Xcode 26.5
  before validation runs, which is issue #492; drive it with `swift build`
  there. v1.5.6 fixes that and builds under both.

Read the [static-query guide](https://lukevanin.github.io/swiftql/documentation/swiftql/staticqueries/)
for descriptor construction, captures, cardinality, preparation, and typed
layouts.

## Avoid compatibility and escape-hatch traps

- Prefer declared queries, `withTransaction(_:)`, and `stream()`/`streamOne()`
  over the surfaces they wrap. Reach for `makeRequest(with:)`, mutating `set`,
  raw prepared handles, or direct GRDB only for what the high-level path does
  not cover. Keep existing `makeRequest(with:)`, mutating `set`, `XLCustomType`,
  legacy literal readers, and raw `XLSQLiteValue` code working when maintaining
  v1 clients, but write new code with explicit invocation packets,
  `XLFieldReader`, contextual codecs, and static descriptors.
- Do not write the free functions `count(_:)`, `min(_:)`/`max(_:)`,
  `iif(_:then:else:)`, or `printf(format:_:)` in new code. v1.5.4 deprecated
  them in favor of `all().count()`, `a.min(b, ...)`/`a.max(b, ...)`,
  `condition.iif(then:else:)`, and `"...".printf(...)`. The non-optional `min`,
  `max`, `sum`, `average`, and `groupConcat` aggregates remain deprecated in
  favor of their `OrNull` spellings.
- Do not share `XLRequest` across tasks; it is not `Sendable`. Use the raw
  prepared invocation/static handles for supported cross-task raw-value work.
- SwiftQL exposes no general raw-fragment API. When unsupported SQL genuinely
  requires a direct GRDB escape hatch, isolate it at the application boundary,
  allowlist any dynamic grammar or identifiers, and bind all data values.
- Do not use deprecated pre-XL names such as `SQLNamedBindingReference`, and do
  not use `Join.Outer`, removed in favor of `Join.Left` and `Join.FullOuter`.

Check [the README](README.md) and [compatibility matrix](COMPATIBILITY.md) before
changing product, platform, dependency, or concurrency claims.

## Report SQLite support from canonical evidence

- Treat the versioned [inventory](Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json) as
  the source of truth and its [report](Conformance/SQLite/REPORT.md) as a generated
  view; use the [compatibility guide](COMPATIBILITY.md#sqlite-conformance-inventory)
  to interpret it. It records 114 feature records: 110 supported, 0 partial,
  2 capability-gated, 1 intentionally unsupported, and 1 unimplemented.
- Keep those five statuses distinct. Bind every claim to the feature's recorded
  SQLite version, source ID, compile options, capabilities, evidence, and
  rationale before claiming support.
- Of the 180 evidence records, 110 exercise real SQLite against one captured
  environment, SQLite 3.51.0. Evidence is reusable, so evidence and feature
  counts do not map one to one; never turn this into an exhaustive-SQL claim.
- The generated corpus holds 208 positives plus one broken-renderer control:
  141 from #191, 27 from #286, 35 from #287, and 5 from #288. #254 adds 18
  Northwind and #255 adds 12 observation-stress cases; no new syntax. This
  census is separate from v1.5.2's build validator, which checks one target's
  manifest against one schema snapshot instead.

## Validate repository changes

Run commands from the repository root. Keep the committed dependency graph for
ordinary validation; use clean resolution only when dependency behavior is the
subject of the task.

```sh
swift build
swift test --filter SQLSkillDocumentationTests
swift test --filter SQLDocumentationCatalogTests
swift test
python3 scripts/ci/sqlite-conformance-inventory.py check
scripts/ci/check-downstream-swift5-client.sh committed
./make-docs.sh docs
scripts/ci/check-first-party-warnings.sh
scripts/ci/check-strict-concurrency.sh
```

Every Swift snippet above is embedded verbatim from the maintained downstream
consumer fixture and checked by `SQLSkillDocumentationTests`; edit the fixture
first, never the fence. Run the warnings and strict-concurrency gates with a
supported Xcode, and use the required GitHub compatibility matrix for exact
Swift 5.9 and Swift 6.0-6.3 evidence rather than substituting a local compiler.

The live-query async suites -- `XLAsyncStreamPublisherTests`,
`XLObservableLiveQueryTests`, `GRDBLiveQueryAsyncStreamTests`, and
`LiveQueryBufferingSemanticsTests` -- were unreliable for a long time, and the
standing advice was to treat any failure in them as flaky until proven
otherwise. That advice is retired. Waits there are awaits on named events,
through `Tests/SQLTests/XLLiveQueryWaitSupport.swift`, so load delays these
tests rather than changing their verdict. The one time-bounded helper,
`xlWaitUntil(describing:)`, covers the only condition nothing can signal -- an
object being deallocated -- and names that condition when it times out.
Investigate a failure there as a regression rather than re-running it away.
