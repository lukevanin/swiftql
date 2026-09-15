# Declared queries

Generate a nominal, database-bound prepared-query handle from a function
signature: labeled parameters, result cardinality, statement caching, and a
frozen-literal guard, all derived by a macro instead of hand-written.

## Overview

Introduced in v1.5.1 (issues [#18](https://github.com/lukevanin/swiftql/issues/18)
and [#26](https://github.com/lukevanin/swiftql/issues/26)), `@SQLQuery` and
`@SQLQueries` are attached macros that turn a **query-specification
function** — an ordinary Swift function whose body builds a `sql { }`
statement from its own parameters — into a callable, cached, database-bound
query. Both macros lower to the same generated shape; they differ only in
where the specification lives and what the generated executor is named:

| Form | Specification lives | Executor name | Call site |
| --- | --- | --- | --- |
| `@SQLQuery` | a database extension, one function per query | `fetch` + capitalized spec name | `try database.fetchPersonByName(name:)` |
| `@SQLQueries` | a nested `private struct Query` inside a `@SQLQueries`-attached extension | the spec's own name | `try database.personByName(name:)` |

`@SQLQueries` is the recommended form for product code: because the
specification lives in a `private` container that generated code never
references, the container's own (trapping) functions never appear in the
public API. `@SQLQuery` is retained as a smaller, independently useful
building block and as the encoding both forms share underneath.

Both macros need only the stable Swift 5.9 attached-macro roles (`@attached(peer)`
and `@attached(member)`) — no experimental function-body macro and no Swift 6
compiler floor. The vestigial specification function that a peer or member
macro cannot remove is unreachable in the `@SQLQueries` form because of its
container's access control, and it traps loudly if called directly in the
`@SQLQuery` form (see [Why a trapping entry point](#why-a-trapping-entry-point)
below).

## Declare a query

Write an instance method on a database extension whose body is a `sql { }`
statement builder over the method's own parameters, and attach `@SQLQuery`.
The **return type**, not the body, tells the macro what to generate: a bare
row type fetches exactly one row, an optional row type fetches zero-or-one,
and an array fetches every match.

<!-- test: XLDocumentationTests.testDocumentationDeclaredQueries -->
```swift
extension GRDBDatabase {

    @SQLQuery
    func personByExactName(name: String) -> Person? {
        sqlResult { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == name)
        }
    }
}

let match = try database.fetchPersonByExactName(name: "John Doe")
```

The macro derives everything from the signature:

- **Labeled parameters** come straight from the function's own parameter list
  — `fetchPersonByExactName(name:)` keeps the argument label, so callers get
  the same compiler-checked labels and useful type errors a normal Swift
  function would give. This is why the encoding must be a macro: a bare
  closure loses argument labels entirely.
- **Result cardinality** comes from the return annotation:

  | Return annotation | Fetch | Executor result |
  | --- | --- | --- |
  | `[Row]` | fetch all | `[Row]` |
  | `Row?` | fetch first-or-none | `Row?` |
  | `Row` (bare, non-optional, non-array) | fetch exactly one | `Row`, throws `XLQueryCardinalityError.noRowsMatched` on zero rows or `.moreThanOneRowMatched` on more than one |
  | legacy `any/some XLQueryStatement<Row>` | fetch all | `[Row]` |

  The legacy `XLQueryStatement<Row>` spelling from the encoding's original
  form is still accepted and dispatches like `[Row]`; new declarations should
  prefer the direct result shapes.
- A **fresh, immutable binding packet** is constructed on every call from the
  arguments you pass — callers never construct or mutate an `XLParameter` or
  `XLNamedBindingReference` themselves, and never bind by textual SQL
  substitution. Two invocations with different arguments are two independent
  packets built against the one cached request; a bound value is never part
  of the query's static identity.

Container form (`@SQLQueries`) generates the same executor shape, but reads
every specification out of a nested container in one expansion and gives the
executor its own name instead of a `fetch`-prefixed one:

<!-- test: XLDocumentationTests.testDocumentationDeclaredQueries -->
```swift
@SQLQueries
extension GRDBDatabase {

    private struct Query {
        func personByName(name: String) -> [Person] {
            sqlResult { schema in
                let person = schema.table(Person.self)
                Select(person)
                From(person)
                Where(person.name == name)
            }
        }
    }
}

let matches = try database.personByName(name: "John Doe")
// Equivalent explicit form:
let sameMatches = try database.execute { context in
    try context.personByName(name: "John Doe")
}
```

`execute(_:)` and the generated `Context` type let you run more than one
declared query in the same scope without repeating a database lookup per
call. Since issue #284, `execute(_:)` is sugar over the adapter-neutral typed
transaction scope described in <doc:AdvancedUsage>'s "Typed multi-statement
transaction scopes": it commits only after the whole closure returns and
rolls back everything the closure did on any failure, so
`context.database.makeRequest(with:)` calls interleaved with declared-query
calls in the same closure commit or roll back together. `Context.database` is
the pinned scope, not the original database — pass it to `makeRequest(with:)`
for any operation the closure needs beyond the container's own declared
queries.

## Render-once caching

The generated executor does not render SQL on every call. Each declaration
gets one `XLRenderOnceCache`, and the **first** call for a given database
renders the value-free statement (parameters are named placeholders, never
inline literals) and caches the resulting request; every later call —
including concurrent first calls racing on an empty cache — reuses that
cached request and only builds a fresh invocation packet. Because the
rendered SQL text never changes between calls, the underlying GRDB
connection's own statement cache reuses one physical prepared statement too.

The cache key is `(databaseIdentifier, dialectIdentifier)`
(``XLPreparedQueryCacheKey``): rendering depends only on the dialect, so a
second dialect would render into its own entry, and the database identifier
keeps one static cache from ever handing one database's prepared request to
another. `GRDBDatabase.preparedQueryCacheKey` supplies a fresh identifier per
instance — two `GRDBDatabase` values wrapping the same connection pool render
independently. An adapter that has not opted into render-once caching
returns `nil` from `preparedQueryCacheKey` (the `XLDatabase` default), and the
executor simply renders on every call, exactly as it would without the cache.

### Inside a transaction

A transaction scope shares the cache entry of the database it was opened on.
`GRDBDatabase.preparedQueryCacheKey` returns the same key for the scope that
`withTransaction(_:)` hands you as for the database itself, so calling a
declared query inside any number of transactions renders the statement at most
once and adds no entry beyond the database's own. The cache stores that entry
bound to the database's pool, even when a transaction renders it first. A
request is bound to one connection, so the cache binds the entry to the calling
scope's connection at call time. A declared
query called on the scope runs on the transaction's connection and sees the
transaction's uncommitted writes. The same declaration called on the database
afterward runs on the pool, as before.

### Concurrency and `Sendable`

`XLRenderOnceCache` is `Sendable`; its single lock only ever guards the
render-once population of one dictionary, so many threads can safely race to
call a declared query for the first time — the statement renders exactly
once, and every caller (including the ones that arrived first) gets a request
built from that one render. Each call still builds its own invocation packet and
executes independently, so concurrent invocations with different argument
values never share mutable state and never share a physical `sqlite3_stmt`
across connections: the existing `XLRequest`/connection-pool contracts still
apply per call.

## Why a trapping entry point

A specification function is still a real, callable Swift function — a peer
or member macro cannot delete or rewrite the declaration it is attached to.
To keep that vestigial function from silently doing the wrong thing if it is
ever called directly (which would execute the query with inline value
literals baked in, defeating the cached request's whole purpose), a
direct-result specification calls `sqlResult { }` instead of `sql { }`.
`sqlResult` type-checks identically to `sql` but **traps** if actually
invoked; the macro rewrites the call back to the real `sql { }` builder only
inside the generated statement peer. In the `@SQLQueries` container form this
residual function is additionally unreachable from outside the file, because
generated code never references the container and you are free to mark it
`private`.

## The frozen-literal guard

The render-once cache's central hazard is a parameter value that escapes the
signature-driven rewrite: if the macro cannot turn every reference to a
parameter into a named placeholder, that value could freeze into the cached
SQL text on the very first call, and every later call would silently reuse
the first call's value. The macro closes this by rejecting, at the
declaration site, every reference shape it cannot rewrite:

- a parameter used inside a **string interpolation** (renders into the SQL
  text instead of binding a placeholder),
- a parameter **captured by a nested closure** (outside the rewrite's reach),
- a parameter passed as a **direct argument to a function call** (the
  rewrite cannot see through the call — `matches(name)` is rejected; write
  `column == name` instead),
- a parameter used to **initialize a local binding** (`let alias = name`;
  the binding's later uses are unreachable),
- a **hand-constructed** `XLNamedBindingReference` or `contextualBinding` (the
  macro is the sole authority for a placeholder's name and type),
- a declaration that **shadows** a parameter name, or accesses a parameter
  **through member access** (`name.uppercased()`),
- a **collection-typed parameter** (`[T]`, `Set`, `Dictionary`) — a
  variable-length `IN` list would change the rendered SQL text with the
  element count, breaking the stable-SQL premise the cache relies on, and
  a single named placeholder cannot bind a list anyway,
- a parameter that is **never referenced** at all.

Every one of these is a compile-time diagnostic at the declaration, not a
runtime failure, and every remaining reference shape the guard accepts — a
comparison operand such as `column == name` — is the one shape the rewrite
can always turn into a named placeholder. This means the encoding has **no
silent-freeze path**: a parameter value either becomes a placeholder, or the
declaration fails to compile.

Two shapes are not lexically detectable and are intentionally left to the
compiler as loud type errors on the generated code rather than silently
accepted: a parameter used as the *callee* of a call (`predicate(x)`), and a
parenthesized member-access base (`(name).lowercased()`). Neither produces a
silently wrong result.

## Diagnostics point at the declaration

Every diagnostic above — and every structural one (non-function declaration,
static/class method, generic function, throwing/async function, variadic or
unnamed parameter, missing or unsupported return type, missing body) — is
reported on the specification's own source location, not on the generated
code. A malformed declaration therefore never produces a confusing error deep
inside macro-expanded output.

## Static descriptors and build validation

Since v1.9 (issue [#659](https://github.com/lukevanin/swiftql/issues/659)),
every declaration also describes itself, so it can become an
`XLStaticQueryDescriptor` (see <doc:StaticQueries>) and an entry in a
build-validation manifest without a hand-written list.

The macro has no type information, so it emits data rather than a
descriptor. For each specification it emits an `XLDeclaredQuery` value: the
specification's name, the cardinality its return type selects, each
parameter's name and Swift type, the row type, and the value-free statement
the executor renders. Every generated member is an instance member, and none
copies a specification body into a new context, so a declaration that
compiles for its executor compiles for its descriptor too:

- `@SQLQueries` generates a `declaredQueries` property on its `Context`,
  which evaluates each body exactly where the `Context` executor evaluates
  it, and a `declaredQueries` property on the extended type that reads it
  through a `Context`.
- `@SQLQuery` generates a `<name>DeclaredQuery()` method beside each
  declaration. It calls the existing `<name>Statement()` peer, and keeps the
  declaration's access level and `mutating` modifier.

`XLDeclaredQuery.makeDescriptor()` assembles the descriptor at run time:

- It renders the statement with the encoder of the database the value was
  read from, so the descriptor's SQL is the SQL that database runs, whatever
  identifier formatting it was built with. A `GRDBDatabase` supplies its
  encoder. For another database type, build the value with the initializer
  that takes an encoder.
- It takes the parameter layout from the rendered statement, and checks it
  against the declared parameter names, value types, and nullability.
- A row selected through a static row layout takes its result slots, codecs
  included, from the layout's metadata. Any other row is replayed against a
  reader that records each column's alias and Swift type.
- It names the definition `<DatabaseType>/<specification>@1`. The type name
  keeps its enclosing types (`Outer.Database`) and drops its module. Nothing
  in the identity depends on the build, so an unchanged declaration has the
  same descriptor identity in every build.

### Discover every declaration in a target

Apply the `SwiftQLDeclaredQueryRegistryPlugin` build-tool plugin to the target
that declares the queries. On every build it scans the target's own Swift
sources with SwiftSyntax and compiles a generated `<Target>DeclaredQueries`
enum into that target. Its `queries(for:)` method takes database instances
and returns the declared queries of every `@SQLQueries` extension and every
`@SQLQuery` function it found. It throws
`XLDeclaredQueryError.missingDatabaseInstance` when no instance of a type
that declares queries is passed, so a database type cannot be left out
silently.

The registry is generated into the declaring target, not into a generator,
because the generated members keep their declaration's access level. A
declaration the registry cannot reach from another file -- one that is
`private` or `fileprivate`, one on a generic or constrained type or in an
extension of one, or one outside a type -- is reported as a build warning
rather than left out silently. To leave one declaration out without the
warning, write `// swiftql-registry: ignore` on the line before its
attribute.

The scan reads every Swift file of the target, so a database type declared in
one file and extended with declarations in another is handled. Everything the
registry names compiles under the source's own `#if` conditions: an import
keeps its condition and its attributes, a database type's whole block keeps
the condition the type is declared under, and each declaration keeps its own.

### Generate the manifest

The `SwiftQLSQLiteBuildValidationDeclaredQueries` library projects declared
queries into a format version 2 manifest.
`SQLiteBuildValidationDeclaredQueryManifest.makeManifest(queries:snapshotIdentifier:snapshotURL:)`
takes the queries and a checked-in schema snapshot, and returns the manifest,
with one entry per query and no fixture provenance, and the queries it had to
skip. A query whose rows cannot be described statically is skipped by name
with the reason, not guessed at.

A package runs a small generator that opens a database the way the
application does, passes it to the generated registry, calls `makeManifest`,
and writes the canonical JSON beside the snapshot. The generator names no
query, so a query added to the target is in the next regenerated manifest.
The manifest is not validated when it is generated: the
`swiftql-build-validate` validator and the
`SwiftQLSQLiteBuildValidationPlugin` build plugin stay the validation step.
<doc:TodoDemo> generates its manifest this way.

None of this changes the executor. Existing `@SQLQuery` and `@SQLQueries`
declarations keep compiling, render the same SQL, and run the same way. The
catalog-scoped lowering that v2 plans (issue
[#494](https://github.com/lukevanin/swiftql/issues/494)) is expected to change
what the macro generates internally, not how you write a specification
function.

## Current limitations

- **Read-only.** Only `SELECT`-shaped specifications are supported. A
  write statement (`INSERT`/`UPDATE`/`DELETE`, with or without `RETURNING`)
  is not yet an accepted return shape; write declarations remain a possible
  future cardinality (a `.command` shape dispatching to
  `XLWriteRequest.execute`), not implemented in v1.5.1.
- **No collection parameters.** A fixed set of scalar parameters or the
  `in(_:)` expression forms are today's alternative to a variable-length
  `IN` list.
- **No async executor yet.** The generated executor is synchronous and
  throwing; an `async` variant is additive future work, not a breaking
  change to what exists today.
- **Same-name overloads collide.** Generated peer and member names are
  derived from the specification's base name only, so two `@SQLQuery`
  functions that share a base name but differ only in parameter list
  generate colliding peer declarations. This fails loudly as a
  duplicate-declaration compile error, not silently.
- **One `@SQLQueries` extension per database type.** A second
  `@SQLQueries`-attached extension of the same database type would
  redeclare `Context` and `execute(_:)`. Declare every specification for one
  database type in a single `@SQLQueries` extension's `Query` container.
- **The registry's name belongs to the plugin.** The plugin generates a type
  and a file named `<Target>DeclaredQueries` in the target it is applied to.
  A target that already declares a type or holds a file with that name gets a
  redeclaration error or a duplicate build output. Rename your own type or
  file.
- **Discovery needs the plugin in a SwiftPM target.** The registry is
  generated by `SwiftQLDeclaredQueryRegistryPlugin`, which runs in a SwiftPM
  target. Xcode asks you to trust the plugin the first time it builds a
  project that uses it. Only declarations the registry can reach are found;
  every other one is reported as a build warning.
- **Lowering reads placeholders.** Recording the result columns of a row
  that is not a static row layout calls each result type's `sqlDefault()`,
  as rendering a legacy `Select` projection already does. A parameter of a
  custom type that is not an `XLEnum` also binds its `sqlDefault()` once, to
  learn its SQLite storage class. A query whose columns cannot be recorded, or
  whose placeholder binds `NULL`, is skipped from the manifest by name.
- **Only a `GRDBDatabase` supplies its encoder.** A declared query read from
  another database type throws `XLDeclaredQueryError.encoderUnavailable` when
  it is lowered. Describe such a query with the `XLDeclaredQuery` initializer
  that takes an encoder.
