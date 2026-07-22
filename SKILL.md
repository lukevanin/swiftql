---
name: swiftql
description: Use when Codex works in a Swift package or Apple application that uses SwiftQL to define typed tables or results, build or modify SQLite queries, pass immutable bindings, add contextual codecs, prepare reusable static queries, integrate a database adapter, or diagnose SwiftQL execution boundaries. Use the checked-out public v1 contract; 1.3.0 is the latest published package and adds conformance evidence rather than new public syntax or validation APIs. Do not use this skill to teach SQL generally or claim unshipped features.
---

# SwiftQL

Use SwiftQL as a typed, SQL-shaped SQLite DSL. Keep schema objects, query
structure, and invocation values separate, and verify every API against the
checked-out package version before editing consumer code.

## Establish the package boundary

- Add `https://github.com/lukevanin/swiftql.git` with Swift Package Manager and
  attach the `SwiftQL` library product to each application target that imports
  it.
- Depend on the application-facing `SwiftQL` product for macros, the DSL,
  contextual codecs, and the GRDB-backed SQLite driver.
- Depend directly on `SwiftQLCore` only when implementing a dialect or database
  adapter. It deliberately contains no usable GRDB connection.
- Require Swift tools 5.9, Swift 5 language mode, iOS 16 or later, or macOS 13
  or later. Supported Swift 6 compilers still use Swift 5 mode; Swift 6 mode,
  non-Apple platforms, non-SQLite dialects, and non-GRDB drivers are unsupported.
- Read [the changelog](CHANGELOG.md) before choosing a package requirement.
  `1.3.0` is the latest published package. Pin a source revision only when
  intentionally testing later changes from `main`.

## Prefer the high-level application workflow

1. Declare stored rows with `@SQLTable` and projections with `@SQLResult`.
2. Build a statement with `sql { schema in ... }`; obtain table references from
   that closure instead of constructing column names as strings.
3. Create one logical request with `GRDBDatabase.makeRequest(with:)`.
4. For parameters, retain the request and construct a fresh immutable
   `XLInvocationBindings<XLSQLiteValue>` packet for every call. Treat a missing
   binding differently from a present SQL `NULL`.
5. Call `fetchAll(bindings:)`, `fetchOne(bindings:)`, or `execute(bindings:)`.
   Let preparation, binding, driver, and decoding errors propagate unless the
   application has an explicit error policy.

The following complete example is compiled and executed by the maintained
Swift 5 consumer fixture.

<!-- compile-test: IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift -->
```swift
import SwiftQL

@SQLTable(name: "SkillPerson")
struct SkillPerson: Equatable {
    let id: String
    let name: String
}

enum SkillQueryError: Error {
    case missingNameParameter
}

func fetchSkillPeople(
    named name: String,
    from database: GRDBDatabase
) throws -> [SkillPerson] {
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let query = sql { schema in
        let person = schema.table(SkillPerson.self)
        Select(person)
        From(person)
        Where(person.name == nameParameter)
    }
    let request = database.makeRequest(with: query)
    guard let nameSlot = request.parameterLayout.slot(for: .named("name")) else {
        throw SkillQueryError.missingNameParameter
    }
    let bindings = try XLInvocationBindings<XLSQLiteValue>(
        layout: request.parameterLayout,
        bindings: [
            try XLInvocationBinding(slot: nameSlot, value: .text(name)),
        ]
    ).validatingComplete()
    return try request.fetchAll(bindings: bindings)
}
```

Lower-level boundaries include `SwiftQLCore`, validated driver helpers, raw-value
prepared handles, and direct GRDB; use them only for the specialized needs below.

Use `sqlCreate` only for basic table creation. It does not add declared SQLite
type names, primary keys, uniqueness, foreign keys, indexes, or migrations, and
it never upgrades an existing table. Keep production schema evolution in an
explicit application-owned migration system.

## Use the v1.2 reusable-query boundary retained in v1.3

Choose a static query when the definition needs durable identity, explicit
parameter and result metadata, cardinality, registration before a database is
opened, or a raw-value handle that can cross tasks.

- Declare invocation inputs with `XLQueryCapture`; runtime Swift values are not
  inferred from bare variables in the runtime DSL.
- Render and validate the statement, then construct an immutable
  `XLStaticQueryDescriptor`. Never store a database, connection, prepared
  statement, or invocation value in the descriptor.
- Give each definition a stable `XLQueryDefinitionIdentity`; persist its
  canonical bytes or hex, never Swift `hashValue`. Increment the version when
  the canonical contract intentionally changes.
- Prepare the descriptor through `GRDBDatabase.prepareInvocation(with:)`, then
  make a fresh packet for each call. Match the prepared operation to the
  descriptor cardinality.
- Use macro-generated static row layouts for contextual-only properties or
  typed static decoding. The raw `GRDBPreparedStaticQuery` is `Sendable`; the
  closure-backed typed layout wrapper remains task-local in v1.3.

Read the canonical [static-query guide](https://lukevanin.github.io/swiftql/documentation/swiftql/staticqueries/)
for descriptor construction, captures, cardinality, preparation, and typed
layouts rather than reproducing those contracts in consumer comments.

## Respect dialect, driver, and codec ownership

- Let `XLSQLiteDialect` own SQLite grammar, placeholder spelling, identifiers,
  storage classes, and required capabilities. Let the driver own connections,
  physical statements, transport binding, execution, and row reads.
- Keep physical statements on the connection that prepared them. A logical
  request or prepared handle is database-bound but does not own one physical
  statement across a pool.
- Prefer immutable contextual `XLValueCodec` registrations when one Swift type
  has one or more database representations. Select codecs deterministically,
  snapshot the configuration in the database or prepared handle, and treat a
  codec key or version change as a schema/data compatibility decision.
- Use intrinsic `Bool`, `Int`, finite `Double`, `String`, and `Data` storage
  directly. Use prepared contextual parameters and result codecs for other
  application values. Reject missing, duplicate, wrong-layout, wrong-storage,
  and nullability-mismatched bindings before execution.
- Decode ordinary queries into their selected `@SQLTable` or `@SQLResult` row.
  For a raw static handle, validate result layout and cardinality before using
  `resultCodec(_:identifiedBy:)` to decode contextual values.
- Treat `XLInvocationBindingError` and `XLRequestBindingError` as caller
  contract failures. Adapter authors should preserve structured
  `XLDatabaseContractError` categories; the established GRDB facade can still
  expose `DatabaseError` or `XLColumnReadError` where its compatibility policy
  requires those concrete errors.

Read [contextual codecs](https://lukevanin.github.io/swiftql/documentation/swiftql/customtypes/)
and [prepared execution boundaries](https://lukevanin.github.io/swiftql/documentation/swiftql/gettingstarted/)
for the exact selection order, structured errors, row lifetime, and driver
contracts.

## Report v1.3 support from canonical evidence

- Treat the versioned [inventory](Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json) as
  the source of truth and its [report](Conformance/SQLite/REPORT.md) as a generated
  view; use the [compatibility guide](COMPATIBILITY.md#sqlite-conformance-inventory)
  to interpret it. It records 104 feature records: 95 supported, 1 partial,
  2 capability-gated, 1 intentionally unsupported, and 5 unimplemented.
- Keep those five statuses distinct. Bind every claim to the feature's recorded
  SQLite version, source ID, compile options, capabilities, evidence, and
  rationale before claiming support.
- Of the 134 evidence records, 85 exercise real SQLite against one captured
  environment, SQLite 3.51.0. Evidence is reusable, so evidence and feature
  counts do not map one to one; never turn this into an exhaustive-SQL claim.
- The generated corpus holds 208 positives plus one broken-renderer control:
  141 from #191, 27 from #286, 35 from #287, and 5 from #288. #254 adds 18
  Northwind and #255 adds 12 observation-stress cases; no new syntax.
- #132 remains package-private research. It ships no public validator, build
  plugin, query macro, schema system, or new v1.3 API. It neither persists
  prepared statements nor removes runtime preparation on a physical connection.

## Keep transactions and migrations explicit

- Do not invent a high-level `GRDBDatabase.transaction` API. The shipped v1
  transaction contract is the lower-level driver's synchronous
  `withValidatedTransaction` helper.
- Use only the pinned connection inside its transaction body. Do not re-enter
  the root pool. A returned body commits; a thrown body rolls back and preserves
  the body error.
- Do not claim nested transactions, savepoints, task-cancellation hooks, or a
  separate single-connection GRDB capability in v1.3.
- Treat migrations as application or driver work. `sqlCreate` is not a
  migration engine.

## Avoid compatibility and escape-hatch traps

- Keep existing `makeRequest(with:)`, mutating `set`, `XLCustomType`, legacy
  literal readers, and raw `XLSQLiteValue` code working when maintaining v1
  clients. For new code, prefer explicit invocation packets, `XLFieldReader`,
  contextual codecs, and static descriptors where their added guarantees are
  needed.
- Do not share `XLRequest` across tasks; it is not `Sendable`. Use the raw
  prepared invocation/static handles for supported cross-task raw-value work.
- Do not turn runtime values into identifiers, ordering choices, placeholder
  counts, or SQL grammar. Bind values; keep grammar and identifiers in the
  Swift expression graph.
- SwiftQL exposes no general raw-fragment API. When unsupported SQL genuinely
  requires a direct GRDB escape hatch, isolate it at the application boundary,
  allowlist any dynamic grammar or identifiers, and bind all data values.
- Do not use deprecated pre-XL names such as `SQLNamedBindingReference`, or
  represent NaN/non-finite `Double` values as inline SQLite numeric tokens.

Check [the README](README.md) and [compatibility matrix](COMPATIBILITY.md) before
changing product, platform, dependency, or concurrency claims.

## Validate repository changes

Run commands from the repository root. Keep the committed dependency graph for
ordinary validation; use clean resolution only when dependency behavior is the
subject of the task.

```sh
swift test --filter SQLSkillDocumentationTests
python3 scripts/ci/sqlite-conformance-inventory.py check
scripts/ci/check-downstream-swift5-client.sh committed
swift test
./make-docs.sh docs
scripts/ci/check-first-party-warnings.sh
scripts/ci/check-strict-concurrency.sh
```

Run the warnings and strict-concurrency gates with a supported Xcode. Use the
required GitHub compatibility matrix for exact Swift 5.9 and Swift 6.0-6.3
evidence; do not silently substitute another local compiler.
