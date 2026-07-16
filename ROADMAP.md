# SwiftQL Roadmap

SwiftQL aims to make database-specific SQL feel native in Swift while preserving
the semantics and capabilities of each database.

This document records product direction and release boundaries. GitHub
[milestones](https://github.com/lukevanin/swiftql/milestones) and their linked
issues are the source of truth for current scope, dependencies, and status.
Version numbers express the intended order of work, not release dates.

## Direction

1. **Stay close to the target database.** SQLite, PostgreSQL, MySQL, and SQL
   Server should expose dialect-specific Swift syntax instead of translating
   SQLite syntax into every backend.
2. **Keep dialect and driver independent.** A dialect defines valid SQL syntax
   and rendering. A driver prepares, binds, executes, observes, and decodes
   queries for a database engine.
3. **Prefer correctness over permissive rendering.** Represent invalid states
   in the type system where practical, and validate generated SQL against the
   real database parser.
4. **Share semantics, not a lowest common denominator.** Common expression,
   rendering, binding, and codec infrastructure should be reused internally,
   while backend-specific features remain available through dialect modules.
5. **Make static queries first-class.** A query declaration should describe its
   typed parameters, result shape, cardinality, dialect, and SQL without
   handwritten parameter objects or request boilerplate.
6. **Make execution boundaries explicit.** Query definitions are
   database-independent, prepared handles are database-bound, and physical
   prepared statements are connection-bound.
7. **Design for concurrency and testing.** Bindings should be immutable per
   invocation, executors should define their isolation guarantees, and syntax
   should be testable separately from adapters.
8. **Use evidence for performance work.** Establish rendering, preparation,
   cache, binding, execution, and decoding baselines before adopting custom
   engine behavior.
9. **Use semantic versioning intentionally.** Preserve v1 source compatibility
   where practical. Reserve broad naming, package, concurrency, and adapter
   changes for v2.

## Release Sequence

| Milestone | Theme | Release boundary |
| --- | --- | --- |
| [v1.1](https://github.com/lukevanin/swiftql/milestone/7) | Reliability, tests, bug fixes, Swift 6 readiness | A trustworthy baseline on Swift 5.9 and Swift 6 toolchains |
| [v1.2](https://github.com/lukevanin/swiftql/milestone/6) | Dialect-aware core and binding foundation | Internal seams needed by query declarations and future backends |
| [v1.3](https://github.com/lukevanin/swiftql/milestone/8) | Existing SQLite-surface conformance | Current public syntax proven against real SQLite |
| [v1.4](https://github.com/lukevanin/swiftql/milestone/9) | Common SQLite feature coverage | A documented, useful SQLite subset |
| [v1.5](https://github.com/lukevanin/swiftql/milestone/1) | Query declarations, ergonomics, and v2 preview | The future API validated without silently raising the v1 toolchain floor |
| [v2](https://github.com/lukevanin/swiftql/milestone/10) | Swift 6 and stable dialect-aware API | Intentional naming, package, DDL, and adapter cleanup |
| [v2.1](https://github.com/lukevanin/swiftql/milestone/2) | Native SQLite adapter | Direct SQLite C execution as an alternative to GRDB |
| [v2.2](https://github.com/lukevanin/swiftql/milestone/5) | PostgreSQL | Native PostgreSQL syntax and adapter |
| [v2.3](https://github.com/lukevanin/swiftql/milestone/4) | MySQL | Native MySQL syntax and adapter |
| [v2.4](https://github.com/lukevanin/swiftql/milestone/3) | SQL Server | Native T-SQL syntax and adapter |

The v1 milestones are sequential quality and architecture layers. Work on a
small PostgreSQL proof may start before v2 is frozen so the shared core is
tested by a genuinely different dialect instead of being generalized from
SQLite alone. That proof does not change the public release order.

Key planning and foundation issues:

| Milestone | Live issue index or foundation |
| --- | --- |
| v1.1 | [test and reliability index](https://github.com/lukevanin/swiftql/issues/118), [Swift 6 readiness](https://github.com/lukevanin/swiftql/issues/127), [performance baselines](https://github.com/lukevanin/swiftql/issues/128) |
| v1.2 | [dialect/driver contracts](https://github.com/lukevanin/swiftql/issues/131), [static query descriptors](https://github.com/lukevanin/swiftql/issues/129), [immutable bindings](https://github.com/lukevanin/swiftql/issues/82) |
| v1.3 | [build-time SQLite validation research](https://github.com/lukevanin/swiftql/issues/132) |
| v1.4 | [SQLite coverage index](https://github.com/lukevanin/swiftql/issues/115) |
| v1.5 | [ergonomics index](https://github.com/lukevanin/swiftql/issues/116), [macro index](https://github.com/lukevanin/swiftql/issues/117), [prepared handles](https://github.com/lukevanin/swiftql/issues/18), [@SQLQuery prototype](https://github.com/lukevanin/swiftql/issues/26) |
| v2 | [Swift 6 mode](https://github.com/lukevanin/swiftql/issues/133), [typed DDL](https://github.com/lukevanin/swiftql/issues/139), [GRDB adapter boundary](https://github.com/lukevanin/swiftql/issues/113), [XL migration](https://github.com/lukevanin/swiftql/issues/33) |
| v2.1 | [native SQLite adapter](https://github.com/lukevanin/swiftql/issues/136), [Linux CI](https://github.com/lukevanin/swiftql/issues/135), [VDBE research](https://github.com/lukevanin/swiftql/issues/138) |
| v2.2 | [PostgreSQL vertical slice](https://github.com/lukevanin/swiftql/issues/137) |
| v2.3 | [MySQL vertical slice](https://github.com/lukevanin/swiftql/issues/130) |
| v2.4 | [SQL Server vertical slice](https://github.com/lukevanin/swiftql/issues/134) |

## Query Declarations and Prepared Handles

The intended model is:

```text
query declaration
    -> database-bound logical prepared handle
        -> immutable bound invocation
            -> connection-bound physical prepared statement
                -> result
```

These are distinct concepts:

- A **query declaration** is a static, typed, dialect-specific description of a
  query.
- A **prepared query handle** is a logical executable bound to a database or
  pool.
- A **physical prepared statement** belongs to one database connection and is
  cached or prepared separately for each connection.

The target developer experience is illustrated below. Exact generated names
and macro spelling remain subject to the v1.5 prototype.

```swift
extension SomeSQLiteDatabase {
    @SQLQuery(dialect: SQLite.self)
    func personByID(id: UUID) async throws -> Person? {
        SQLite.sql { schema in
            let person = schema.table(Person.self)

            Select(person)
            From(person)
            Where(person.id == id)
        }
    }
}
```

The function signature supplies the binding and result schema. The macro lowers
`id` to an internal typed binding, so callers do not declare or mutate an
explicit `SQLParameter`.

The database method may provide a cached one-shot execution path:

```swift
let person = try await database.personByID(id: id)
```

It should also be possible to retain an explicit prepared handle:

```swift
let personByID = try await database.preparePersonByID()
let person = try await personByID(id: id)
```

A generated nominal handle with `callAsFunction(id:)` is preferred over a bare
closure. Swift function values do not preserve argument labels, while a nominal
handle can preserve labels, carry query metadata, define `Sendable` and
isolation behavior, and support future execution options.

For a connection pool, a prepared handle must not claim ownership of one global
`sqlite3_stmt`. It should retain a `Sendable` executor and stable query identity,
then use the physical connection's statement cache. Bindings must be fresh for
every invocation and must not be shared mutable state.

The design must cover:

- zero, one, and multiple parameters, including nullable parameters;
- zero-or-one, exactly-one, many-row, scalar, and command results;
- reads and writes;
- synchronous and asynchronous drivers;
- cancellation, transactions, and database isolation;
- direct cached execution and explicitly retained handles;
- useful macro diagnostics at the declaration site.

## Swift 6 Compatibility

Swift 6 is an immediate compatibility priority, but compiler compatibility and
language-mode compatibility are different promises.

The intended policy is:

- v1.x continues to support an actual Swift 5.9 compiler where practical.
- v1.x also builds with the supported Swift 6 compiler in Swift 5 language
  mode.
- First-party code becomes warning-free under complete strict-concurrency
  checking during v1.x.
- v2 may require a Swift 6 toolchain and enable Swift 6 language mode.
- A Swift 5-language-mode application built with a Swift 6 compiler can call
  the v2 library.
- An application restricted to an actual Swift 5.x compiler remains on the
  maintained v1.x line.

Function-body macros require a Swift 6-era toolchain. The v1.5 `@SQLQuery` work
is therefore a prototype or separately gated preview while v1.x retains its
Swift 5.9 minimum. If it cannot be isolated without weakening package
compatibility, it becomes stable in v2 rather than raising the v1.x toolchain
requirement.

The compatibility matrix should include:

- Swift 5.9 compiler with v1.x in Swift 5 language mode;
- supported Swift 6 compiler with v1.x in Swift 5 language mode;
- supported Swift 6 compiler with complete strict-concurrency checking;
- v2 in Swift 6 language mode;
- a downstream fixture whose application target remains in Swift 5 language
  mode while importing v2 with a Swift 6 compiler.

## Build-Time SQLite Validation

Build-time query validation is practical and valuable. Given a deterministic
schema produced from typed DDL or migrations, a build tool can use the real
SQLite engine to prepare every declared query and verify:

- SQL syntax;
- required tables and columns;
- parameter count and layout;
- result column count and available metadata;
- read/write classification;
- required SQLite version, compile options, functions, collations, and
  extensions.

Generated descriptors may record stable query identity, SQL, typed parameter
and result layouts, a schema fingerprint, SQLite source identity, and capability
requirements. Runtime code can then prepare once per physical connection, cache
the statement, and optionally warm selected queries after opening or migrating
a database.

This removes runtime SwiftQL construction work and repeated SQL parsing on cache
hits. It does not eliminate the first supported SQLite preparation on each
physical connection.

### Persisted SQLite Bytecode

Stock SQLite does not provide a public API for serializing and restoring an
`sqlite3_stmt`. Database serialization stores a database image, not prepared
statements. SQLite VDBE bytecode is an internal implementation detail and may
depend on:

- the exact SQLite source revision and compile options;
- schema identity and B-tree root pages;
- query-planner statistics and configuration;
- registered functions, collations, virtual tables, and extensions;
- engine-owned pointers and process state;
- parameter-sensitive replanning.

A zero-runtime-parser implementation would therefore require a modified SQLite
engine with a versioned, relocatable bytecode format and a safe loader. It
remains a research track until benchmarks show material value and a prototype
demonstrates correctness, portability, invalidation, and a safe fallback.
SwiftQL must not claim persisted or zero-parse preparation until that evidence
exists.

## Milestone Outcomes

### v1.1 — Reliability, Test Coverage, Bug Fixes, and Swift 6 Readiness

Establish a trustworthy baseline before broadening the API:

- reproduce and fix known correctness bugs;
- expand macro, rendering, binding, execution, decoding, and regression tests;
- replace warning markers and unverified behavior with tests or tracked issues;
- improve naming, visibility, documentation, diagnostics, and code hygiene
  without unnecessary source breaks;
- make first-party code warning-free under complete strict-concurrency checking;
- add the v1 compiler compatibility matrix;
- establish preparation and execution performance baselines.

### v1.2 — Dialect-Aware SQL Core and Binding Foundation

Create source-compatible seams required for query declarations and future
backends:

- separate dialect, rendering, binding, decoding, and execution
  responsibilities;
- introduce stable query descriptors and query identities;
- define immutable typed invocation bindings;
- define logical prepared-handle and executor contracts;
- keep the core free of GRDB-specific public types;
- add reusable adapter contract tests;
- make dialect selection explicit in new infrastructure.

This milestone introduces multi-dialect architecture; it does not promise a
non-SQLite public syntax module.

### v1.3 — Existing SQLite-Surface Conformance

Verify that SwiftQL's existing public syntax renders and behaves correctly under
supported SQLite versions:

- maintain a documented syntax and conformance matrix;
- test rendered SQL with SQLite's real prepare and execution paths;
- cover precedence, nullability, quoting, aliases, joins, subqueries, compound
  queries, common table expressions, values, functions, and statement clauses
  already exposed by SwiftQL;
- add version and capability expectations;
- establish a representative schema-snapshot validation harness;
- track every known deviation explicitly.

### v1.4 — Common SQLite Feature Coverage

Add commonly needed SQLite syntax that is not represented correctly or at all.
Every feature issue must include:

- a typed Swift surface;
- correct SQLite rendering;
- prepare and execution coverage against supported SQLite versions;
- capability or version behavior where applicable;
- documentation and representative examples.

The supported subset is documented explicitly instead of implying complete
SQLite grammar coverage.

### v1.5 — Query Declarations, Ergonomics, and v2 Preview

Prototype and validate the future query-declaration model:

- prototype `@SQLQuery` using function signatures as parameter and result
  schemas;
- eliminate explicit parameter-reference and mutable request boilerplate;
- generate database-bound callable handles with labeled `callAsFunction` APIs;
- support direct cached execution and explicit handle retention;
- produce declaration-site diagnostics for unsupported signatures and forms;
- prototype build-time validation against a schema snapshot;
- benchmark macro expansion, generated code, cold preparation, cache hits,
  binding, execution, and decoding;
- publish the proposed v2 migration surface.

Swift 6-only functionality remains a preview if it cannot be packaged without
silently raising the v1.x compiler minimum.

### v2 — Swift 6 and Stable Dialect-Aware API

Use the major-version boundary for intentional API and package cleanup:

- require the selected Swift 6 toolchain and enable Swift 6 language mode;
- ship the stable query-declaration API;
- remove the legacy `XL` public prefix and publish a migration guide;
- separate core abstractions, SQLite syntax, macros, and driver adapters;
- make GRDB an adapter rather than an implementation detail of the core module;
- introduce typed, dialect-aware DDL;
- make dialect and driver capabilities explicit;
- preserve Swift 5-language-mode client callability when using a Swift 6
  compiler;
- document source migration, concurrency behavior, and compatibility
  boundaries.

### v2.1 — Native SQLite Adapter

Provide a direct SQLite C adapter that can replace the GRDB adapter:

- adapter-contract parity with the GRDB implementation;
- per-connection statement preparation and caching;
- binding, decoding, transactions, errors, cancellation, functions,
  collations, and observation behavior;
- schema/version invalidation and safe reprepare behavior;
- preparation warm-up and metrics;
- no GRDB dependency for clients selecting the native adapter.

### v2.2 — PostgreSQL Dialect and Adapter

Add an explicitly scoped PostgreSQL syntax module and driver adapter. Model
PostgreSQL semantics directly, publish a supported-feature matrix, use
database-bound prepared handles, and validate against supported live PostgreSQL
server versions.

### v2.3 — MySQL Dialect and Adapter

Add an explicitly scoped MySQL syntax module and driver adapter. Model MySQL
semantics directly, publish a supported-feature matrix, use database-bound
prepared handles, and validate against supported live MySQL server versions.

### v2.4 — SQL Server Dialect and Adapter

Add an explicitly scoped SQL Server syntax module and driver adapter. Model
T-SQL semantics directly, publish a supported-feature matrix, use
database-bound prepared handles, and validate against supported live SQL Server
versions.

Post-v2 adapter ordering may change if research, maintainership, or driver
maturity changes, but backend-specific public syntax remains the architectural
direction.

## Release Gates

Every release must satisfy these gates:

- milestone implementation and research issues are closed or explicitly
  deferred to a named later milestone;
- no known high-priority correctness regression remains open without an
  explicit release decision;
- supported compiler, platform, database, dialect, and adapter matrices are
  documented and passing;
- syntax changes have rendering plus real parser or execution validation;
- adapters pass the shared contract suite and applicable live-engine tests;
- macro changes have expansion, diagnostic, runtime, and downstream-package
  tests;
- documentation and examples match the shipped API;
- performance-sensitive changes include comparable baseline and post-change
  measurements;
- compatibility and migration impact is documented;
- limitations and unsupported syntax are explicit.

v2 additionally requires a public API review, migration guide, Swift
5-language-mode client fixture, and a clean replacement path for v1 `XL` APIs.

No release may claim compile-time preparation, zero runtime parsing, or
persisted SQLite bytecode beyond what its real validation evidence demonstrates.

## GitHub Issue Policy

GitHub issues and milestones are the live planning system. This file records
direction and release boundaries, not task status.

- Assign every implementation, test, documentation, refactor, or research issue
  to its intended milestone.
- Use one issue per independently researchable, implementable, testable, and
  reviewable outcome.
- Tracking issues are index-only and link to atomic issues. They are not
  implementation tasks.
- Give correctness and security bugs the highest applicable priority unless a
  prerequisite blocks them.
- State dependencies explicitly with `Depends on #...` and `Blocks #...`.
- State intent, scope, non-goals, compatibility constraints, observable
  acceptance criteria, and validation evidence.
- Research issues must document findings, make a recommendation, and create
  linked atomic follow-up issues for accepted work.
- Discoveries outside an active issue's scope become follow-up issues instead of
  unreviewed scope expansion.
- Move work between milestones in GitHub first. Update this document when
  product direction or a release boundary changes.

## Technical References

- [Swift function-body macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0415-function-body-macros.md)
- [Swift function type argument labels](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0111-remove-arg-label-type-significance.md)
- [Incremental concurrency migration](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md)
- [SQLite statement preparation](https://www.sqlite.org/c3ref/prepare.html)
- [SQLite database serialization](https://www.sqlite.org/c3ref/serialize.html)
- [SQLite virtual machine opcodes](https://www.sqlite.org/opcode.html)
- [SQLite query-planner stability](https://www.sqlite.org/queryplanner-ng.html)
