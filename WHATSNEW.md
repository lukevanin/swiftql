# What's new in SwiftQL

A plain-language summary of what changed in each release, newest first. It
answers two questions: *what can I do now that I could not do before*, and
*does this affect code I already wrote?*

For the exact, evidence-backed detail — every API name, constraint, and SQLite
version requirement — read [CHANGELOG.md](CHANGELOG.md). That file is the
canonical record; this one is a reading aid.

Almost every 1.x release has been purely additive. The one exception so far is
1.4.3, where `unixEpoch(_:)` changed its return type from `Int` to
`TimeInterval`. Each entry below ends with whether it affects code you already
wrote.

## 1.5.5 — async live queries, by default

*Released 30 July 2026.*

A `for try await` loop is now the one canonical way to observe a live query:

- `stream()`/`stream(bindings:)` and `streamOne()`/`streamOne(bindings:)` on
  `XLRequest` hand you an `AsyncThrowingStream` built directly on GRDB's own
  observation — no separate Combine-side observation engine underneath
  anymore.
- `publish()`/`publishOne()` (and their `bindings:` variants) still work with
  the same public signatures, but are now a thin Combine adapter layered over
  the async streams, rather than an independent implementation. A real
  demand-accounting over-delivery bug found while unifying the two is fixed
  as part of the rebuild.
- `XLObservableQuery`/`XLObservableQueryRow` wrap the async streams as
  `@Observable` (iOS 17/macOS 14+) SwiftUI state — `rows`/`row`, `isLoading`,
  `error` — for apps that can take the newer floor. The package's own iOS
  16/macOS 13 minimum is unchanged.
- `withResultSet(_:)`/`withResultSet(bindings:_:)` give you a connection-
  scoped, lazy, single-pass result set (`next() throws -> Row?`) that decodes
  one row at a time, for callers who want pull-based streaming without an
  async stream.

**Affects existing code?** No. `publish()`/`publishOne()` keep their existing
signatures and behavior; everything else here is additive.

## 1.5.4 — method-style functions and a smoother `Setting`

*Released 28 July 2026.*

- Scalar functions gained method-style spellings matching the majority style
  already in use — `a.min(b, ...)`, `condition.iif(then:else:)`,
  `"...".printf(...)`, `all().count()`. The older free functions
  (`min(_:)`/`max(_:)`, `iif(_:then:else:)`, `printf(format:_:)`, `count(_:)`)
  are deprecated, not removed.
- `Setting(_:_:)` now infers its row type from the `Update(_:)` right before
  it, so `Update(person); Setting(person) { $0.age = 42 }` no longer needs an
  explicit generic parameter.
- The `#row` ad hoc row-projection macro is back after being reverted for a
  Swift 5.9.2 compiler crash. The single-column shape works everywhere; the
  two-to-six column shapes need Swift 6.1+ — the first place SwiftQL's public
  surface differs by compiler version (see COMPATIBILITY.md).
- `XLQueryObserver`/`XLQueryRowObserver` wrap `publish()`/`publishOne()` as
  `ObservableObject`s, for a SwiftUI view model that wants `@Published rows`
  without hand-writing a Combine sink.

Also closed out two investigations with no code changes needed: chained
`coalesce`/`??` fallbacks already compose correctly into SQL's `COALESCE`,
and an already-optional scalar subquery result was already flattening to a
single `T?` rather than `T??`.

**Affects existing code?** No. Every change is additive or a
source-compatible deprecation; `#row`'s two-to-six column shapes are the
first surface unavailable on Swift 5.9, not a removal from it.

## 1.5.3 — value codecs for dates, JSON, and UUIDs

*Released 28 July 2026.*

Named, versioned codec presets for the value types almost every app needs to
persist, all built on the v1.2 contextual codec registry:

- `XLDateTextCodec` stores `Date` as a fixed-format, SQLite-comparable `TEXT`
  string usable directly by `date`/`time`/`datetime`/`julianday`/`strftime`.
- Three numeric `Date` presets — `UnixMilliseconds`, `UnixSeconds`,
  `JulianDay` — for apps that prefer `INTEGER`/`REAL` storage.
- `XLJSONValueCodec` stores any `Codable` value as `TEXT` or `BLOB` JSON, with
  an immutable, captured encoder/decoder configuration rather than a shared
  global one.
- `XLUUIDValueCodec.text`/`.blob` store `UUID` as canonical lowercase text or
  16-byte binary, without a wrapper type.
- `@SQLCodec(key)` selects one of these (or your own) per property on an
  `@SQLTable`/`@SQLResult`, so two properties of the same Swift type can use
  two different storage conventions.

None of these is an implicit default — encoding without an explicit selector
or a registered database default still throws a catchable error, exactly like
the v1.2 registry it builds on.

**Affects existing code?** No. Every preset and `@SQLCodec` are new, additive
surfaces; applying one to an existing property is a migration for that
property alone, the same as changing any codec's key or version already was.

## 1.5.2 — build-time query validation

*Released 27 July 2026.*

Your queries can now be checked while you build, not when your app runs. Three
pieces fit together:

- A **manifest** describes the static queries in a target — the SQL, its
  parameters, its result columns, and a snapshot of the schema they expect.
- A **validator** (`swiftql-build-validate`) opens that schema snapshot, hands
  every query to the real SQLite parser, and reports whether the SQL parses,
  the tables and columns exist, and the parameter and result shapes match.
- A **SwiftPM plugin** runs the validator as part of `swift build`, so a query
  that no longer matches your schema fails the build with a diagnostic instead
  of failing in front of a user.

What it does *not* do: it checks that a query is well-formed against the
schema, not that it returns the right answers. Behavior is still your tests'
job. Manifests are currently written by hand or generated externally.

**Affects existing code?** No. Everything here is new and opt-in.

## 1.5.1 — declare queries as Swift functions

*Released 26 July 2026.*

The headline is `@SQLQuery` and `@SQLQueries`. Instead of building a statement,
holding a request, and assembling a bindings packet by hand, you write a
function that describes the query and let the macro generate the rest:

- Parameters come from the function's own signature.
- The return type decides how many rows you get — `[Row]` fetches all, `Row?`
  fetches zero or one, and a bare `Row` insists on exactly one.
- Each call gets a fresh, immutable set of bindings. You never mutate a shared
  request, and a value can never be baked into cached SQL by accident — the
  macro rejects, at compile time, every parameter spelling it cannot safely
  turn into a placeholder.
- The SQL for a declaration is rendered once and reused, so repeated calls
  reuse one prepared SQLite statement.

Also in this release:

- **Typed transactions.** `withTransaction { scope in ... }` runs several
  typed requests as one atomic unit on one connection, with no GRDB type
  anywhere in your code. Nesting a transaction, using the scope after it ends,
  or observing a live query inside one are rejected with catchable errors
  instead of crashing.
- **Nested result types.** A property of an `@SQLTable` or `@SQLResult` type
  can now be another such type, so a joined row can decode into a structured
  Swift value instead of a flat one.

The `#row` macro was cut from this release: it crashed the pinned Swift 5.9.2
compiler. It is deferred rather than abandoned.

**Affects existing code?** No. The macros are an addition; hand-built requests
keep working.

## 1.4.6 — faster construction and decoding

*Released 25 July 2026.*

Internal performance work with no visible API change. Building and rendering a
query allocates noticeably less memory, and decoding no longer allocates a
fresh buffer per row. The generated SQL is byte-for-byte identical to before.

**Affects existing code?** No — nothing public changed.

## 1.4.5 — more join shapes and better CTEs

*Released 24 July 2026.*

- `NATURAL JOIN` and `JOIN ... USING (columns)`.
- `RIGHT JOIN` and `FULL OUTER JOIN` (both need SQLite 3.39 or later), plus
  complete `CROSS JOIN` coverage in the query builder.
- `MATERIALIZED` / `NOT MATERIALIZED` hints on common table expressions.
- A common table expression that produces a single scalar column no longer
  needs a one-property wrapper type just to carry it.
- Compound queries (`UNION`, `INTERSECT`, `EXCEPT`) work over plain values like
  `Int` and `String` without a result wrapper.

**Affects existing code?** No. The one previously broken API, `Join.Outer`,
stays removed in favor of `Join.Left` and `Join.FullOuter`.

## 1.4.4 — writes that handle conflicts and return rows

*Released 23 July 2026.*

- Conflict handling on inserts: `INSERT OR IGNORE`, `OR REPLACE`, `OR ABORT`,
  and friends, plus `REPLACE INTO`.
- Upserts through `INSERT ... ON CONFLICT`, in both the `DO NOTHING` and
  `DO UPDATE SET ...` forms.
- `RETURNING` on inserts, updates, and deletes — the changed rows come back as
  typed results from the same statement (needs SQLite 3.35 or later).
- Updates driven by a common table expression.

**Affects existing code?** No. The existing insert API is unchanged.

## 1.4.3 — dates and times

*Released 23 July 2026.*

Full SQLite date-and-time support: `date`, `time`, `datetime`, `julianDay`,
`unixEpoch`, and `strftime`, each taking ordered modifiers that apply in the
order you write them — `moment.datetime(.months(1), .startOfMonth)` reads the
way it evaluates. Component accessors (`year`, `month`, `day`, `hour`,
`dayOfWeek`, …) return `Int`, and optional inputs stay optional throughout.

**Affects existing code?** One narrow change: `unixEpoch(_:)` now returns
`TimeInterval` instead of `Int`, because a subsecond modifier makes SQLite
return a fractional value. `toUnixTimestamp()` still returns `Int`.

## 1.4.2 — text matching and nullable predicates

*Released 22 July 2026.*

- `LIKE` with an `ESCAPE` character, so a literal `%` or `_` can be matched.
- `notIn` in every shape `in` already supported — value lists, subqueries, and
  common table expressions — with the negation carried by the `IN` node itself
  so composing a predicate cannot accidentally move it.
- `in` and `notIn` now accept optional operands and `NULL` candidates.
- Collations, `REGEXP`, and `MATCH`.

**Affects existing code?** No; all additive.

## 1.4.1 — casts, counts, and ranges

*Released 22 July 2026.*

- A complete, type-checked `cast(to:)` matrix. Unsupported conversions simply
  do not compile, and optionality is preserved.
- `all()` for an unqualified `*`, and `count(all())` for an exact `COUNT(*)`.
- `isBetween(_:_:)` and `isNotBetween(_:_:)`, grouped so SQLite precedence is
  unambiguous.
- `total()` and a broader `averageOrNull(distinct:)`.

**Affects existing code?** No; all additive.

## 1.3.0 — evidence, not new syntax

*Released 20 July 2026.*

This release added no syntax. It added proof that the existing syntax works: a
versioned inventory of what SwiftQL supports, a generated conformance report,
a bounded corpus of generated query combinations, a realistic Northwind
correctness suite, and a stress suite for live queries. Each claim is tied to a
recorded SQLite version and its captured environment, so "supported" means
something specific rather than aspirational.

**Affects existing code?** No.

## 1.2.0 — separating definitions from execution

*Released 19 July 2026.*

The structural release. A query definition, the values for one call, and the
database that runs it became three separate things:

- `SwiftQLCore` is a new product holding the dialect, statement, and driver
  contracts with no GRDB dependency, for anyone writing an adapter.
- `XLStaticQueryDescriptor` describes a query — SQL, parameters, results,
  identity, cardinality — before any database exists, and can be prepared
  against one later.
- Bindings live in fresh immutable packets per call, so runtime values never
  leak into a cached statement or a query's identity.
- Contextual value codecs let one Swift type have more than one SQLite
  representation, chosen per database, with no process-global registry.

Rows are also decoded incrementally now, so a large fetch no longer builds an
intermediate copy of every row before decoding.

**Affects existing code?** No. Existing requests, named bindings, custom
types, and result models all keep compiling. The new contracts are there when
you need durable identity or cross-task execution — not a required migration.

One boundary worth knowing: values SQLite cannot represent, such as a
non-finite `Double`, now fail with a clear encoding error rather than emitting
invalid SQL.

## 1.1.0 — reliability and release infrastructure

*Released 17 July 2026.*

Aggregates gained optional-returning forms (`minOrNull`, `sumOrNull`,
`groupConcatOrNull`, …) that can express an empty or all-`NULL` result as Swift
`nil`. The non-optional spellings still work for the rest of 1.x, but the
canonical APIs will return optionals in SwiftQL 2.

Most of the release went into things you do not call directly: a verified
tag-release pipeline, documentation that is built and validated in CI, a
downstream consumer fixture that proves the macros work from another package,
a reproducible benchmark executable, and warnings-as-errors across every
supported compiler.

**Affects existing code?** The non-optional `min`, `max`, `sum`, `average`, and
`groupConcat` APIs are deprecated but retained for all of 1.x.
