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
5. **Make database membership explicit.** A generated database catalog should
   register the tables available to an application, expose only those tables to
   its typed query scope, and give every table reference an identity independent
   of its rendered SQL alias.
6. **Make static queries first-class.** A query declaration should describe its
   typed parameters, result shape, cardinality, dialect, and SQL without
   handwritten parameter objects or request boilerplate.
7. **Make value coding contextual.** Paired codecs should map Swift values to
   dialect-native values under an immutable database or query configuration.
   Property, result, or parameter metadata may select a named override without
   changing the Swift value type.
8. **Make execution boundaries explicit.** Query definitions are
   database-independent, prepared handles are database-bound, and physical
   prepared statements are connection-bound.
9. **Design for concurrency and testing.** Bindings should be immutable per
   invocation, executors should define their isolation guarantees, and syntax
   should be testable separately from adapters.
10. **Use evidence for performance work.** Establish rendering, preparation,
   cache, binding, execution, and decoding baselines before adopting custom
   engine behavior.
11. **Use semantic versioning intentionally.** Preserve v1 source compatibility
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
| [v2](https://github.com/lukevanin/swiftql/milestone/10) | Generated database catalogs, Swift 6, and a stable dialect-aware API | Fluent catalog-scoped queries plus intentional naming, package, DDL, and adapter cleanup |
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
| v1.2 | [dialect/driver contracts](https://github.com/lukevanin/swiftql/issues/131), [streaming row decoding](https://github.com/lukevanin/swiftql/issues/248), [contextual value codecs](https://github.com/lukevanin/swiftql/issues/188), [static query descriptors](https://github.com/lukevanin/swiftql/issues/129), [immutable bindings](https://github.com/lukevanin/swiftql/issues/82), [source-coverage baseline](https://github.com/lukevanin/swiftql/issues/189), [SQLite value conformance](https://github.com/lukevanin/swiftql/issues/252), [transaction invariants](https://github.com/lukevanin/swiftql/issues/253) |
| v1.3 | [syntax conformance inventory](https://github.com/lukevanin/swiftql/issues/190), [combinatorial conformance cases](https://github.com/lukevanin/swiftql/issues/191), [build-time SQLite validation research](https://github.com/lukevanin/swiftql/issues/132), [Northwind correctness corpus](https://github.com/lukevanin/swiftql/issues/254), [observation stress contracts](https://github.com/lukevanin/swiftql/issues/255) |
| v1.4 | [SQLite coverage index](https://github.com/lukevanin/swiftql/issues/115), [direct scalar CTE rows](https://github.com/lukevanin/swiftql/issues/43) |
| v1.5 | [ergonomics index](https://github.com/lukevanin/swiftql/issues/116), [macro index](https://github.com/lukevanin/swiftql/issues/117), [prepared handles](https://github.com/lukevanin/swiftql/issues/18), [lazy typed result set](https://github.com/lukevanin/swiftql/issues/249), [@SQLQuery prototype](https://github.com/lukevanin/swiftql/issues/26), [Date text](https://github.com/lukevanin/swiftql/issues/61) and [numeric codecs](https://github.com/lukevanin/swiftql/issues/62), [UUID codecs](https://github.com/lukevanin/swiftql/issues/192), [interactive DocC tutorial](https://github.com/lukevanin/swiftql/issues/27), [macro regression corpus](https://github.com/lukevanin/swiftql/issues/256), [compile scalability benchmarks](https://github.com/lukevanin/swiftql/issues/257), [runtime workload research](https://github.com/lukevanin/swiftql/issues/259) |
| v2 | [generated database catalogs and fluent table references](https://github.com/lukevanin/swiftql/issues/217), [Swift 6 mode](https://github.com/lukevanin/swiftql/issues/133), [typed DDL](https://github.com/lukevanin/swiftql/issues/139), [FluentQL and DynamicQL extraction](https://github.com/lukevanin/swiftql/issues/326), [GRDB adapter boundary](https://github.com/lukevanin/swiftql/issues/113), [XL migration](https://github.com/lukevanin/swiftql/issues/33), [catalog stress fixtures](https://github.com/lukevanin/swiftql/issues/258) |
| v2.1 | [native SQLite adapter](https://github.com/lukevanin/swiftql/issues/136), [Linux CI](https://github.com/lukevanin/swiftql/issues/135), [VDBE research](https://github.com/lukevanin/swiftql/issues/138), [shared-corpus adapter parity](https://github.com/lukevanin/swiftql/issues/260) |
| v2.2 | [PostgreSQL vertical slice](https://github.com/lukevanin/swiftql/issues/137) |
| v2.3 | [MySQL vertical slice](https://github.com/lukevanin/swiftql/issues/130) |
| v2.4 | [SQL Server vertical slice](https://github.com/lukevanin/swiftql/issues/134) |

## Generated Database Catalogs and Fluent Table References

Generated database catalogs are a headline v2 feature. A catalog is the typed
definition of the tables available to an application; it remains distinct from
a runtime database, connection, pool, or executor. The live task graph is
maintained in the
[v2 database-catalog tracking issue](https://github.com/lukevanin/swiftql/issues/217).
Its declaration may resemble:

```swift
@SQLDatabase
struct AppDatabase {
    private static let person = Person.self
    private static let company = Company.self
}
```

Exact registration spelling remains subject to macro prototyping. Registration
declarations are inputs to the catalog macro, not public table references.

The macro generates catalog-owned table factories and a database-specific query
scope. Only registered tables are exposed, so `AppDatabase.sql` can reject a
reference from another catalog or an unregistered table. The intended query
surface is:

```swift
let query = AppDatabase.sql { schema in
    let person = schema.person
    let manager = schema.person(as: "manager")
    let company = schema.company.nullable

    Select(person, manager, company)
    From(person)
    Join(manager, on: person.managerID == manager.id)
    Join.Left(company, on: person.companyID == company.id)
}
```

The reference model has deliberately visible rules:

- `AppDatabase.person()` and `schema.person()` each create a new table
  reference;
- `schema.person` is a lazily created default reference, stable only within one
  query scope;
- `person(as: "manager")` still creates a new reference; `as:` supplies only a
  preferred rendered alias and never defines identity;
- `.nullable` is an identity-preserving typed view whose columns reflect outer
  join nullability;
- insert, update, and delete statements should infer their write role from a
  normal registered table reference; an explicit identity-preserving
  `.writeTarget` view remains available only where a generic API needs it.

Internally, a factory creates an unbound reference with an opaque identity. The
query binding pass assigns deterministic SQL aliases and preserves the identity
through copies and typed views. It must not depend on process-global or
task-local "current schema" state.

Database-scoped query construction performs structural reference validation.
Every table identity used by a select, predicate, grouping, ordering, or write
must be bound in the appropriate query scope by a `FROM` or `JOIN` source, the
statement's write target, or a permitted correlated outer scope. Common-table
and derived-table references are still introduced through `FROM` or `JOIN`.
For example, separate factory calls in `Select(AppDatabase.person())` and
`From(AppDatabase.person())` produce distinct identities and therefore an
unbound-reference error. Explicit alias collisions, incorrect nullable views,
and cross-catalog references are also diagnosed.

A catalog generates a typed bootstrap operation that creates missing registered
tables when explicitly requested. Bootstrap is not a migration system: changing
an existing table still requires an explicit, versioned migration strategy.

## Companion Packages: FluentQL and DynamicQL

SwiftQL currently ships three ways to construct a statement: the result-builder
syntax, a functional/fluent spelling of the same statically known statements,
and imperative runtime builders (`QueryBuilder`, `InsertBuilder`). v2 reduces
SwiftQL itself to the result builder as the single query-construction spelling
and moves the other two surfaces into companion packages, each in its own
repository with its own release cadence. The live task graph is the
[extraction tracking issue](https://github.com/lukevanin/swiftql/issues/326).

- **FluentQL** hosts the functional and fluent spelling — `select(p).from(p)`
  as an alternative way to write a statement whose structure is known at
  compile time. It is a supported spelling preference, not a deprecation shim.
- **DynamicQL** hosts the runtime query builders for statements whose structure
  is decided by data rather than source code — user-driven filters, optional
  joins, configurable ordering. It uses SwiftQL, but it fulfills a
  fundamentally different purpose than a spelling layer, so it versions as its
  own product instead of riding along with FluentQL.

The split is motivated inside SwiftQL as well: carrying the functional
overloads next to the result builder makes overload sets collide, which blocks
completing the result-builder surface for nullable operands. Nothing leaves
SwiftQL before its result-builder equivalent provably compiles.

The packaging rules are deliberate:

- Each companion depends on SwiftQL; SwiftQL and its tests never depend on a
  companion, and the companions do not depend on each other.
- Companions build on an intentional, documented statement-construction seam,
  not on access-level accidents. A hook both companions need belongs in the
  seam.
- Each companion documents which of its versions track which SwiftQL major.

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
        AppDatabase.sql { schema in
            let person = schema.person

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

### Streaming rows and lazy result sets

v1.2 adds a source-compatible, package-scoped streaming row-decoding seam and
implements it with GRDB's connection-scoped cursor APIs. GRDB rows are normalized
and decoded before the cursor advances, so many-row execution does not first
materialize both every GRDB row and a complete `[[XLSQLiteValue]]` matrix. The
existing eager `fetchAll()` and `fetchOne()` APIs remain compatible and should
share the streaming execution path where practical. This work is tracked by
[incremental GRDB row decoding](https://github.com/lukevanin/swiftql/issues/248)
and does not depend on the native SQLite adapter.

v1.5 previews a typed, single-pass `XLResultSet<Row>` final reference type for
callers that want to process only the rows they request. Its synchronous
`withResultSet` API is scoped to one database access, uses throwing `next()`
iteration, and closes retained references when the scope ends. It is neither
`Sendable` nor a replayable `Collection`; an ordinary copyable struct cannot
honestly represent its live connection-bound cursor state on Swift 5.9. A future
struct may instead represent an immutable deferred query recipe. Demand-driven
asynchronous iteration remains separate work because it needs an explicit
backpressure, cancellation, and connection-lifetime contract. The v1.5 preview
is tracked by the
[lazy typed result-set issue](https://github.com/lukevanin/swiftql/issues/249).

## Scalar Rows and Contextual Value Codecs

### Direct scalar rows

Scalar SELECTs already have enough information to decode a direct Swift value.
The remaining wrapper requirement comes from compound-query and common-table
metadata that assumes every row is a macro-generated `XLResult`.

v1.4 should let ordinary and recursive CTEs return `T` or `T?` directly. The
implementation should preserve the existing row reader across compound branches
and expose an adapter-neutral scalar CTE reference with a stable typed value
column. `SQLScalarResult` remains source-compatible during v1; it becomes a
legacy shim rather than a requirement. Scalar-subquery conversion and nested
optional flattening remain separate concerns.

The alias-first, value-semantic lifecycle recommendation for recursive
definitions is documented in [Value-Semantic Recursive CTE Construction](Documentation/Architecture/RecursiveCTEConstruction.md).

### Contextual value codecs

One Swift type may have multiple valid database representations. `Date` may be
stored as canonical text, Unix time, or Julian day; `UUID` may be text, a
16-byte SQLite BLOB, or a native PostgreSQL/SQL Server value. A global type
conformance or property wrapper alone cannot model this consistently for table
properties, query parameters, and computed results.

The intended model is:

```text
Swift value
    -> named typed codec selected by immutable query/database configuration
        -> dialect-native value and storage metadata
            -> driver transport binding
```

Encoding and decoding are a paired, throwing operation with a stable codec
identity and version. Selection order is explicit property/result/parameter
metadata, query override, database default, then the v1 legacy custom-literal
compatibility path. Missing or ambiguous selection is an error. There is no
process-global mutable registry.

A property annotation may eventually resemble `@SQLCodec(...)`, but it carries
metadata only: it must not wrap the property or change its initializer,
mutability, equality, or `Codable` behavior. Codec or representation changes are
data migrations and must affect schema fingerprints and query identity whenever
they alter SQL, storage, or capability requirements.

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

## Conformance and Documentation Strategy

### Grammar-informed conformance tests

SQLite's official syntax diagrams are an excellent reviewed source of legal
branches and interactions, but they are not consumed as an executable grammar.
SwiftQL will maintain a checked-in, versioned inventory that records each public
syntax family and adopted upstream behavior case, its support status, SQLite
documentation and version provenance, upstream repository/commit/path/license
provenance where applicable, capability requirements, blocking issue and target
milestone when deferred, and rendering/prepare/execution/compile-fail evidence.

Tests generated from that inventory use deterministic, constraint-aware pairwise
coverage plus targeted higher-order cases for risky interactions. They construct
typed SwiftQL statements rather than concatenating SQL, prepare every positive
case with a version-identified real SQLite engine, and execute representative
semantic cases against seeded schemas. The suite remains bounded and does not
claim complete SQLite grammar coverage.

### Open-source behavioral test adoption

SwiftQL will adapt behavior matrices from mature MIT-licensed SQLite libraries
instead of copying their APIs or test harnesses literally. The initial reviewed
sources are pinned snapshots of
[GRDB.swift](https://github.com/groue/GRDB.swift/tree/b83108d10f42680d78f23fe4d4d80fc88dab3212),
[SQLite.swift](https://github.com/stephencelis/SQLite.swift/tree/ccaae3d01fd655be40f20665f1f61dc6deecec27),
[Lighter](https://github.com/Lighter-swift/Lighter/tree/3486fc08d580aa3a87cd29ede023ba291a90de8b),
[Blackbird](https://github.com/MarcoArment/Blackbird/tree/0960ffc7649e9c35cfdb5f6b0b98216a34e8c09a),
and
[FluentBenchmark](https://github.com/vapor/fluent-kit/tree/6f8844284df4f797d2a81721511d053357d97b56/Sources/FluentBenchmark/Tests).
An upstream attribution manifest records the repository, commit, path, original
test or workload, adaptation, and license notice for every adopted family.
Substantial copied material retains its upstream copyright and permission
notice; otherwise tests are rewritten around SwiftQL's public contracts.

The adoption inventory classifies each surveyed case as already covered,
adoptable now, syntax-gated, adapter/API-gated, or intentionally out of scope.
Every gated case names its blocking issue and target milestone once planned.
Deferred cases remain visible in the conformance inventory and move into the
executable suite only when the required typed surface exists; they do not become
permanently skipped tests. ORM associations, persistence callbacks, eager
loading, soft deletes, and other record-lifecycle behavior remain out of scope
unless SwiftQL deliberately adopts an equivalent abstraction.

The first adoptable families are:

- SQLite storage-class, affinity, numeric-boundary, optional, Unicode, BLOB,
  enum, and contextual-codec behavior;
- literal, identifier, positional/named binding, repeated-parameter, empty
  sequence, and injection-shaped input behavior;
- `IN` edge cases, nullable comparison symmetry, precedence, collation,
  aggregates, clause composition, subqueries, compounds, and CTEs already
  represented by the public DSL;
- CRUD, structured failures, transaction-contract, observation, cancellation,
  and bounded concurrency behavior exposed by current adapters;
- macro diagnostics, awkward identifiers and schema shapes, high-arity
  generation, and downstream compile-only compatibility.

Each positive case asserts the strongest applicable evidence layers: Swift
type-checking, deterministic rendering and bindings, successful preparation by
the real SQLite parser, and semantic execution. Negative cases use compile-fail,
diagnostic, preparation-failure, or structured runtime-error assertions at the
boundary that owns the rule. Exact SQL copied from another library is not an
oracle when aliases or binding syntax intentionally differ; raw SQL and SQLite
results provide the semantic oracle.

### Northwind real-database corpus

Current-surface integration tests use the MIT-licensed
[Northwind SQLite fixture](https://github.com/Northwind-swift/NorthwindSQLite.swift/blob/865de0872e61692a49cd6069cd2df8f9ac04541e/dist/northwind.db)
at commit `865de0872e61692a49cd6069cd2df8f9ac04541e`, initially pinned by SHA-256
`cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8`.
The canonical fixture is immutable and read-only. Mutation, transaction,
rollback, and observation tests use unique, parallel-safe temporary copies and
never modify the checked-in artifact.

Fixture validation records the upstream revision and license, verifies the
checksum and `PRAGMA integrity_check`, and asserts the expected 13 application
tables, 17 views, 93 customers, 830 orders, 2,155 order-detail rows, and 77
products. The first semantic corpus covers quoted names such as `Order Details`,
nullable shipping fields, Unicode and BLOB values, compound keys, stable
pagination, customer/order/employee/product joins, left joins, grouped
aggregates and `HAVING`, packaged views, subqueries, compounds, and CTEs. Typed
SwiftQL results are compared with raw SQL or the fixture's views, including
fixed sentinels such as order `10248` having three details totalling `440.0`.

The small pinned fixture is a correctness corpus, not evidence of production
scale or concurrent throughput. Large-read, write, and concurrency benchmarks
use separate deterministic databases with recorded checksums, schemas,
generator revisions, seeds, and fixed clocks. The upstream unseeded,
current-date population script is not a reproducible baseline.

### Comparative runtime and compile-time evidence

Cross-library runtime comparisons use current pinned dependency versions,
identical selected columns and value representations, equivalent statement and
connection lifecycles, correctness checksums, and explicit setup boundaries.
Unavoidable representation or API differences are recorded with the result.
Reports separate construction/rendering, cold preparation, cached lookup,
binding, execution, and decoding where the compared APIs expose those seams.
Correctness checks and fixture setup remain outside timed intervals. Reports
record raw samples, median, p95, cross-process spread, rows or operations per
second, and peak resident memory alongside exact hardware, toolchain, library,
SQLite build/configuration, and pragma provenance. Read throughput, point
lookup, joins/aggregates, writes in a transaction, observation, concurrency,
and cold startup remain distinct workload-specific API comparisons rather than
one universal library ranking.

Compile-time comparisons use isolated consumer packages with equivalent raw
SQL, GRDB, SQLite.swift, Lighter, and SwiftQL workloads. The matrix scales table
and representative query declarations independently through 1, 10, 100, and
500 cases and measures dependency-warm clean builds, no-op incremental builds,
and an incremental rebuild after changing one query. Reports include wall,
user, and system time, peak memory, build-timing summaries, generated-source
size, and binary size under an exact toolchain and dependency lock. Results
describe whole consumer builds unless separate compiler traces isolate macro
expansion, and no hard regression threshold is set until repeatable baselines
exist.

Lighter's separate `PerformanceTestSuite` provides a useful Northwind workload
idea but has no repository license. SwiftQL independently implements the
scenario and does not copy that harness without permission.

### Progressive documentation

v1.5 will add native DocC interactive tutorials with scrollable steps and
highlighted code evolution. Complete code snapshots for every step must
type-check, final scenarios must execute against real SQLite, and the generated
HTML/JSON routes and assets must be verified through the existing Pages pipeline.
This is a guided documentation experience, not a custom JavaScript application
or an in-browser SQLite playground.

## Milestone Outcomes

### v1.1 — Reliability, Test Coverage, Bug Fixes, and Swift 6 Readiness

Establish a trustworthy baseline before broadening the API:

- reproduce and fix known correctness bugs;
- expand macro, rendering, binding, execution, decoding, and regression tests;
- establish the pinned upstream-behavior inventory and attribution manifest,
  then adopt immediately supported value, binding, expression, CRUD,
  transaction, observation, macro, and compile-only regression families;
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
- define a dialect-owned value boundary plus immutable contextual codec registry
  and coding configuration;
- carry stable codec and storage metadata through descriptors, bindings, and
  decoding without requiring wrapper value types;
- define logical prepared-handle and executor contracts;
- keep the core free of GRDB-specific public types;
- add reusable adapter contract tests;
- run shared storage-class, affinity, numeric-boundary, structured-error, and
  contextual-codec fixtures through the core and GRDB adapter boundaries;
- add a package-scoped streaming row-decoding seam and decode GRDB results with
  bounded intermediate storage while preserving the eager public APIs;
- capture reproducible first-party source-coverage reports before broad internal
  refactors;
- make dialect selection explicit in new infrastructure.

This milestone introduces multi-dialect architecture; it does not promise a
non-SQLite public syntax module.

### v1.3 — Existing SQLite-Surface Conformance

Verify that SwiftQL's existing public syntax renders and behaves correctly under
supported SQLite versions:

- maintain a versioned, machine-readable syntax and conformance inventory;
- test rendered SQL with SQLite's real prepare and execution paths;
- generate deterministic, constrained pairwise and targeted higher-order cases
  using SQLite's syntax diagrams as reviewed provenance rather than an
  executable grammar;
- cover precedence, nullability, quoting, aliases, joins, subqueries, compound
  queries, common table expressions, values, functions, and statement clauses
  already exposed by SwiftQL;
- execute the pinned Northwind corpus through typed SwiftQL queries and raw-SQL
  or packaged-view oracles, using temporary copies for mutation tests;
- record each adopted behavior as implemented, feature-gated, or intentionally
  out of scope, with every planned deferral linked to its blocking issue and
  target milestone;
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

Feature-gated cases discovered in the upstream survey are promoted from the
conformance inventory as their typed Swift surfaces land. A feature is not
accepted by merely enabling or unskipping an upstream-shaped test: it must meet
the same rendering, real-parser, semantic, version, and documentation gates.

This milestone also removes the one-column result wrapper requirement from
ordinary and recursive scalar CTEs while preserving v1 compatibility.

The supported subset is documented explicitly instead of implying complete
SQLite grammar coverage.

### v1.5 — Query Declarations, Ergonomics, and v2 Preview

Prototype and validate the future query-declaration model:

- prototype `@SQLQuery` using function signatures as parameter and result
  schemas;
- eliminate explicit parameter-reference and mutable request boilerplate;
- generate database-bound callable handles with labeled `callAsFunction` APIs;
- support direct cached execution and explicit handle retention;
- preview a connection-scoped, typed, single-pass result set that decodes only
  requested rows while preserving eager `fetchAll()` compatibility;
- produce declaration-site diagnostics for unsupported signatures and forms;
- prototype build-time validation against a schema snapshot;
- preview metadata-only property/result/parameter codec selection;
- provide explicit SQLite Date and UUID codec presets plus JSON/user-defined
  codec ergonomics without changing existing persisted formats;
- publish a native DocC interactive tutorial whose displayed snapshots compile
  and whose final scenario executes;
- benchmark macro expansion, generated code, clean and incremental consumer
  compilation, cold preparation, cache hits, binding, execution, decoding,
  memory, and representative cross-library workloads;
- publish the proposed v2 migration surface.

Swift 6-only functionality remains a preview if it cannot be packaged without
silently raising the v1.x compiler minimum.

### v2 — Generated Database Catalogs, Swift 6, and Stable API

Use the major-version boundary for intentional API and package cleanup:

- require the selected Swift 6 toolchain and enable Swift 6 language mode;
- ship generated database catalogs and their fluent, catalog-scoped table
  reference API as the primary v2 query entry point;
- enforce reference identity, binding, alias, nullability, write-role, and
  catalog-membership invariants with actionable diagnostics;
- validate catalog generation and compilation against pinned awkward and
  high-arity schema shapes, including quoted names, compound keys, BLOBs,
  optionals, self-references, alias collisions, and large table sets;
- provide an explicit typed bootstrap path for creating missing registered
  tables without presenting bootstrap as schema migration;
- ship the stable query-declaration API;
- remove the legacy `XL` public prefix and publish a migration guide;
- separate core abstractions, SQLite syntax, macros, and driver adapters;
- make the result builder the single query-construction spelling: extract the
  functional/fluent spelling to the companion FluentQL package and the runtime
  `QueryBuilder`/`InsertBuilder` surface to the companion DynamicQL package,
  each in its own repository with a one-way dependency on SwiftQL;
- make GRDB an adapter rather than an implementation detail of the core module;
- introduce typed, dialect-aware DDL;
- stabilize contextual codec naming, storage metadata, and the migration path
  from legacy `XLLiteral`/`XLCustomType` behavior;
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
- codec and dialect-value parity with the GRDB adapter;
- schema/version invalidation and safe reprepare behavior;
- execute the shared adopted correctness and workload corpus against both the
  GRDB and native SQLite adapters;
- preparation warm-up and metrics;
- no GRDB dependency for clients selecting the native adapter.

### v2.2 — PostgreSQL Dialect and Adapter

Add an explicitly scoped PostgreSQL syntax module and driver adapter. Model
PostgreSQL semantics directly, publish a supported-feature matrix, use
database-bound prepared handles, and validate against supported live PostgreSQL
server versions. Native UUID, JSONB, timestamp, and other characteristic values
use PostgreSQL mappings instead of SQLite storage conventions.

### v2.3 — MySQL Dialect and Adapter

Add an explicitly scoped MySQL syntax module and driver adapter. Model MySQL
semantics directly, publish a supported-feature matrix, use database-bound
prepared handles, and validate against supported live MySQL server versions.
Date/time, UUID/binary, JSON, text/collation, and numeric mappings are explicit.

### v2.4 — SQL Server Dialect and Adapter

Add an explicitly scoped SQL Server syntax module and driver adapter. Model
T-SQL semantics directly, publish a supported-feature matrix, use
database-bound prepared handles, and validate against supported live SQL Server
versions. Native `uniqueidentifier`, `datetime2`, and string mappings remain
distinct from SQLite and PostgreSQL representations.

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
- supported syntax claims appear in the versioned conformance inventory with
  deterministic evidence;
- adopted third-party behavior has pinned source and license provenance, and
  any substantial copied material retains the required notice;
- real-database fixtures have pinned upstream identity, license, checksum,
  integrity and row-count assertions, plus an immutable-source/temp-copy policy;
- feature-gated and intentionally out-of-scope surveyed cases remain explicit
  inventory entries, and each planned deferral names a blocking issue and target
  milestone rather than becoming a silent exclusion or permanent skip;
- adapters pass the shared contract suite and applicable live-engine tests;
- adapters do not own logical codec policy and pass the shared value-codec
  fixtures for their dialect;
- macro changes have expansion, diagnostic, runtime, and downstream-package
  tests;
- the README, DocC catalog, changelog, compatibility guidance, and examples
  match the shipped API;
- the repository's agent `SKILL.md` is updated and validated against the
  shipped API;
- the milestone release-readiness audit is complete, with every unresolved
  gap recorded as an atomic follow-up issue;
- performance-sensitive changes include comparable baseline and post-change
  measurements;
- comparative runtime and compile-time reports use equivalent workloads,
  correctness checksums, explicit timing boundaries, pinned toolchains and
  dependencies, and machine-readable raw samples;
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
- [SQLite SQL language and syntax diagrams](https://www.sqlite.org/lang.html)
- [SQLite syntax-diagram index](https://www.sqlite.org/syntax.html)
- [SQLite database serialization](https://www.sqlite.org/c3ref/serialize.html)
- [SQLite virtual machine opcodes](https://www.sqlite.org/opcode.html)
- [SQLite query-planner stability](https://www.sqlite.org/queryplanner-ng.html)
- [Swift DocC](https://www.swift.org/documentation/docc/)
- [Swift DocC code steps](https://www.swift.org/documentation/docc/code)
