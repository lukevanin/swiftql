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

## 1.7.0 — REGEXP that just works

*Unreleased. Dated when the version is tagged.*

- The `REGEXP` operator no longer needs the application to register anything.
  SQLite ships no `regexp` function, so every query that used the operator
  failed to prepare until now. SwiftQL supplies one, backed by Swift `Regex`.
- A pattern matches anywhere in the subject, which is what the widely used
  `regexp` extensions for SQLite and PostgreSQL's `~` operator do. Anchor with
  `^` and `$` for a whole-subject match. A `NULL` on either side yields `NULL`,
  and an invalid pattern is reported rather than silently matching nothing.
- A pattern is compiled once per statement execution rather than once per row,
  so a scan over a large table pays one compile and then only matches.
- `XLRegexPattern` matches a `Regex` written with `RegexBuilder`, so a pattern
  can be composed and checked at compile time instead of spelled as a string.
- A statement using `REGEXP` with a string pattern runs as a static query
  descriptor and passes the SQLite build validator. One using an
  `XLRegexPattern` does not, because its key means something only in the process
  that rendered it.

**Affects existing code?** Only if you already registered your own `regexp`. If
you did, it still wins: SwiftQL never replaces a `regexp` already on the
connection, so the operator keeps meaning exactly what it meant.

## 1.6.0 — JSON, and a much faster decode

*Released 3 September 2026.*

SQLite's JSON support is now a typed SwiftQL surface. A query can reach inside a
JSON document — read one value, build a document, change it, or collect rows
into one — without loading the text, decoding it in Swift, and writing the whole
thing back. Separately, decoding a large result set is about 56% faster than in
1.5.7, and you get that with no source change at all.

- **Read a value out of a document.** `jsonElement(at:)` renders `->` and gives
  you the element as JSON text. `jsonValue(at:as:)` renders `->>` and gives you
  it as the SQL type you name. `jsonExtract(at:as:)` is the function form.
  All three are optional results, because a path that matches nothing is SQL
  `NULL`.
- **Name a value without writing a path string.** `XLJSONPath.root.key("tags")
  .index(0)` builds `$.tags[0]`. It quotes a key only where SQLite's grammar
  needs one, so `key("a.b")` names the single key `a.b` rather than reading as
  "b inside a". A path renders as a text operand, so it is never a raw-SQL
  escape hatch.
- **Build, inspect, and change documents.** `jsonArray` and `jsonObject`
  construct them. `minifiedJSON()`, `prettyJSON()`, `jsonQuoted()`,
  `jsonType()`, `validJSONOrNull()`, `jsonArrayLength()`, and
  `jsonErrorPosition()` inspect them. `jsonInserting`, `jsonReplacing`,
  `jsonSetting`, `jsonRemoving`, and `jsonPatched` write back into them.
- **Collect rows into a document.** `jsonGroupArray()` and
  `jsonGroupObject(name:value:)` are the two SQLite JSON aggregates. Neither
  result is optional: an empty group gives `[]` and `{}`, not SQL `NULL`.
- **JSONB, when the binary form is worth it.** Every function that returns JSON
  has a `jsonb`-prefixed twin returning SQLite's binary representation. The
  functions whose result is a SQL value rather than JSON have no twin, because
  SQLite defines none.
- **Decoding is 56% faster on a large fetch.** Two changes to how generated row
  readers work: a literal column now selects a statically-constrained read
  instead of finding its conformance at run time, and the generated row closure
  builds each column's expression once rather than once per row. Each was
  measured on its own against the state before it, on a 16,143-row, 14-column
  fetch: 39.4% and then a further 28.3%, which compose to about 56%.
- **`sql { ... }` works as a subquery**, on Swift 6.1 and later, inferring a
  table row, a nullable table row, or a scalar from the surrounding
  expression. On Swift 5.9 and 6.0 the overloads are not compiled, because they
  crash those compilers, and `subqueryExpression { ... }` remains the spelling
  there.

Some of this needs a newer SQLite than the oldest one SwiftQL supports. The
`->` and `->>` operators need 3.38.0, JSONB needs 3.45.0, `json_pretty` needs
3.46.0, and `json_valid` with flags needs 3.45.0. SwiftQL renders the SQL
either way; it is the engine that refuses.

**Affects existing code?** Almost none of it. Everything above is additive, and
the decode speed-up needs no source change — existing `@SQLTable` and
`@SQLResult` models reach the faster path as they are. Two narrow cases change.
`validJSON()` is deprecated in favour of `validJSONOrNull()`, because
`json_valid(NULL)` returns SQL `NULL` rather than false and a non-optional
`Bool` cannot represent that; the old spelling still compiles and renders the
same SQL. And an `XLRowReader` conformance outside this package that overrides
the unconstrained `staticColumn(_:alias:)` to give literal columns special
behaviour will no longer see literal columns arrive there; implement the new
constrained requirement as well to keep it. A reader that implements only
`column(_:alias:)`, which is the documented shape, is unaffected.

## 1.5.7 — internal cleanup, and two fixes

*Released 27 August 2026.*

This release is almost all internal. It carries the refactoring from the August
2026 audit: dead code removed, oversized files decomposed, duplicated macro,
driver, and codec code collapsed, test scaffolding consolidated, and the
build-validation research prototype retired. Two real bugs are fixed along the
way.

- A `RETURNING` request now registers the custom functions that opt into
  implicit registration. A predicate that called such a function worked in a
  plain `SELECT`, but failed with SQLite's "no such function" error once you
  wrote the same statement as `UPDATE ... RETURNING` or
  `DELETE ... RETURNING`. Functions added upfront with
  `GRDBDatabaseBuilder.addFunction(_:)` were never affected.
- A NaN `Double` bound through a `@SQLQuery` parameter now throws where the
  value is captured, instead of further down at the driver boundary. Nothing
  was ever stored as SQL `NULL`: the driver already rejected the value, so such
  a query already threw. Every capture path now agrees on where the throw
  happens and which error it carries.
- Four public types that nothing referenced are gone: `XLDatabaseMetadata`,
  `XLDatabaseMetadataObject`, `XLTableName`, and `XLUnionDependency`. Six
  unreferenced members of `SQLiteBuildValidationRuntimeMetadata` are gone too,
  and `hasFunction(named:argumentCount:)` loses its `argumentCount` parameter.

**Affects existing code?** Almost none of it. The two fixes only turn a failure
into the correct behaviour. Three narrow cases do change. Code that names one of
the four removed types no longer compiles, although nothing referenced them
anywhere in this repository. Code that calls
`hasFunction(named:argumentCount:)` must drop the `argumentCount` argument.
Code that calls `_xlQueryParameterBinding` directly and inspects its result,
rather than executing the query, now sees a throw for a NaN `Double` where it
saw `.real(nan)` before.

## 1.5.6 — nullable columns in `Setting` closures

*Released 4 August 2026.*

- A nullable column can now be assigned in a `Setting` closure the way any
  Swift optional is. `row.occupationId = "occ-1"` sets the column,
  `row.occupationId = nil` sets it to SQL `NULL`, and an optional-typed
  expression such as a binding reference or another nullable column assigns
  with that same spelling. None of those compiled before, because the generated
  setter's outer `Optional` meant "leave this column out of the `SET` clause"
  and collided with the column's own optionality. A column the closure never
  assigns still stays out of the statement.
- `@SQLTable` and `@SQLResult` now generate a `Sendable` conformance for
  `public` and `package` models, so a model built entirely from column values
  crosses isolation domains without a `nonisolated(unsafe)` at the call site.
  Swift already infers the conformance for an internal struct, so nothing is
  generated below `package`, and a model that states its own `Sendable` or
  `@unchecked Sendable` keeps that declaration. This needs Swift 6.0 or later;
  the Swift 5.9 support point behaves as it did.
- The build-validation plugin builds under Xcode again. On the published 1.5.2
  through 1.5.5 packages, a plugin-adopting target failed with `Build input
  file cannot be found` before validation ran, because the executable target
  and the product it ships under had different names.
- `SQLiteBuildValidator` reports the schema checks it could not run as
  `.unsupported` diagnostics instead of dropping them from the report, so a
  check that failed to run is distinguishable from one that was never asked
  for.

**Affects existing code?** Almost none of it: the new `Setting` spelling is
additive, and `.toNullable()` still compiles wherever you already use it. One
narrow case does change. A `public` or `package` model holding a stored
property that is not itself `Sendable` is now diagnosed on the generated
conformance, where it used to compile silently; declaring `@unchecked
Sendable` on that model turns the generation off and takes responsibility for
it.

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
- Collations, `REGEXP`, and `MATCH`. (`REGEXP` needed a function you
  registered yourself until 1.7.0, which ships one.)

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
