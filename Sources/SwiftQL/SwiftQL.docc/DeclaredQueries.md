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

## Named bindings for a statement value

A declared query binds its parameters for you. Some statements are not
declared queries: a write with `RETURNING`, or a read that a live query
observes through its request. Such a statement uses named bindings, and each
call needs a packet of values.

Attach `@SQLBindings` to a struct with one stored property for each named
binding. The macro generates a static typed reference for each property, which
the statement uses, and `bindings(for:)` and `bindings(in:)`, which build the
immutable `XLInvocationBindings` packet from the property values:

<!-- test: XLDocumentationTests.testDocumentationDeclaredQueries -->
```swift
@SQLBindings
struct PersonSearchBindings {
    var name: String
    var minimumAge: Int
}

let searchStatement = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(
        person.name == PersonSearchBindings.name
        && person.age >= PersonSearchBindings.minimumAge
    )
}
let searchRequest = database.makeRequest(with: searchStatement)
let adults = try searchRequest.fetchAll(
    bindings: PersonSearchBindings(name: "John Doe", minimumAge: 21)
        .bindings(for: searchRequest)
)
```

The property is the only place the binding's name and type are written:

- A misspelled reference, such as `PersonSearchBindings.nmae`, is a missing
  static member, so it does not compile.
- A missing value or a misspelled value label is a memberwise-initializer
  error, so it does not compile either.
- The packet binds each value under its property name. `nil` in an optional
  property is a present SQL `NULL`, not a missing binding.
- The packet is still checked against the request's parameter layout. If the
  statement does not use a declared binding, building the packet throws
  `XLInvocationBindingError.parameterDeclarationNotInLayout`. If the statement
  uses a binding that the struct does not declare, it throws
  `XLInvocationBindingError.missingBindings`.

Pass the packet to `fetchAll(bindings:)`, `fetchOne(bindings:)`,
`execute(bindings:)`, a packet-backed publisher, or an `XLObservableQuery`.

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
the first call's value.

The rewrite replaces every expression reference to a parameter with its
named binding, wherever the reference sits. Since v1.9
([#661](https://github.com/lukevanin/swiftql/issues/661)) that includes an
argument to a DSL method or clause, so a declared query can match text and
limit its rows with parameters:

<!-- test: XLDocumentationTests.testDocumentationDeclaredQueries -->
```swift
@SQLQueries
extension GRDBDatabase {

    private struct Query {
        func people(matching pattern: String, expression: String, limit: Int) -> [Person] {
            sqlResult { schema in
                let person = schema.table(Person.self)
                Select(person)
                From(person)
                Where(person.name.like(pattern) || person.name.regexp(expression))
                OrderBy(person.name.ascending())
                Limit(limit)
            }
        }
    }
}
```

A comparison operand (`column == name`), a method argument
(`column.like(pattern)`, `column.regexp(expression)`), a clause argument
(`Limit(limit)`, `Offset(offset)`), a local binding (`let alias = name`), and
a reference in a nested closure all become the same named placeholder. The
generated statement never holds the value, and the compiler rejects a use
that needs the Swift value instead of an expression, such as a helper that
takes a `String`.

The macro rejects, at the declaration site, every shape where the rewrite
cannot produce a correct placeholder:

- a parameter used inside a **string interpolation** (renders into the SQL
  text instead of binding a placeholder),
- a parameter accessed **through member access** (`name.uppercased()`), which
  transforms the value in Swift where no placeholder can represent it,
- a parameter whose name is also a **key-path component** (`\Person.name`) or
  the **callee** of a call (`From(person)`, `Limit(10)`). Neither position is a
  reference to the parameter, so the rewrite leaves it unchanged and the macro
  asks you to rename the parameter,
- a **hand-constructed** `XLNamedBindingReference` or `contextualBinding` (the
  macro is the sole authority for a placeholder's name and type),
- a declaration that **shadows** a parameter name,
- a **collection-typed parameter** (`[T]`, `Set`, `Dictionary`) — a
  variable-length `IN` list would change the rendered SQL text with the
  element count, breaking the stable-SQL premise the cache relies on, and
  a single named placeholder cannot bind a list anyway,
- a parameter that is **never referenced** at all.

Every one of these is a compile-time diagnostic at the declaration, not a
runtime failure. This means the encoding has **no silent-freeze path**: a
parameter value either becomes a placeholder, or the declaration fails to
compile.

A parameter passed to a call whose parameter type is `Any` or generic is **not
a binding**. For example, `String(describing: name)` receives the binding
reference, not the parameter's value, and returns the reference's description
as an ordinary Swift string. That string then renders into the SQL as a
constant literal, the same for every call, so the query silently compares
against the wrong text. The macro does not detect this shape. Pass a parameter
only to SwiftQL expression APIs — an operator, a method such as `like(_:)` or
`regexp(_:)`, or a clause such as `Limit(_:)` — never to a general Swift
function. A parenthesized member-access base (`(name).lowercased()`)
is not lexically detectable and is left to the compiler as a type error on the
generated code.

## Diagnostics point at the declaration

Every diagnostic above — and every structural one (non-function declaration,
static/class method, generic function, throwing/async function, variadic or
unnamed parameter, missing or unsupported return type, missing body) — is
reported on the specification's own source location, not on the generated
code. A malformed declaration therefore never produces a confusing error deep
inside macro-expanded output.

## v1.5 transitional syntax and the v2 migration path

The v1.5.1 prototype builds its value-free statement with the existing
`sql { }` / `XLQueryStatement` / `makeRequest(with:)` v1 path — the same
statement construction every other SwiftQL query already uses. It
deliberately does **not** build on the newer `XLStaticQueryDescriptor` /
`XLQueryCapture` catalog machinery described in <doc:StaticQueries>; that
stable-v2 catalog integration is out of scope until the catalog-facing issues
it depends on land. Existing `@SQLQuery`/`@SQLQueries` declarations are
expected to keep compiling once that integration ships — the migration is
expected to be a change to what the macro generates internally, not to how
you write a specification function.

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
