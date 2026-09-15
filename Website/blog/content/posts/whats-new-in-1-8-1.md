---
title: "What's new in v1.8.1"
date: 2026-09-15
description: "SwiftQL v1.8.1 is a correctness and safety patch. Crashes become typed errors, silently wrong results are fixed or refused, REGEXP bounds its input, and a few queries that ran on 1.8.0 now need a one-line change."
---

SwiftQL v1.8.1 is a patch, but not a quiet one. Nineteen issues went into it,
and almost all of them share one shape: something that stopped the process,
returned a wrong answer without saying so, or ran for an unbounded time. Each
one now either works or throws a typed error.

That has a cost. A query that relied on one of the wrong answers ran on 1.8.0
and throws on 1.8.1, and a few rendered statements change. This post walks
through what changed, with before and after code where your source is affected,
and ends with a checklist for upgrading.

## Crashes that are now errors, or just work

**Functions inside a result set inside a transaction.** SwiftQL used to install
every custom and bundled SQLite function before every execution. SQLite treats a
second install of the same name and argument count as a change to the function,
and refuses it while a statement is active. GRDB turns that refusal into
`fatalError`, so this crashed:

```swift
try database.withTransaction { transaction in
    try transaction.makeRequest(with: allNotes).withResultSet { notes in
        while let note = try notes.next() {
            // A REGEXP query while the outer cursor is open.
            let links = try transaction.makeRequest(with: linksMatching(note)).fetchAll()
        }
    }
}
```

v1.8.1 installs each function once per physical connection and records the
install on the connection itself, with a zero-argument marker function. The
query above runs. As side effects, executions stop expiring the connection's
prepared statements, a `REGEXP` pattern compiles once per connection instead of
once per execution, and two `GRDBDatabase` values over one `DatabasePool` no
longer fail with `no such function: regexp` on a shared reader.

**Static row layouts.** A statement built from `staticRowLayout(using:)` crashed
at `select(_:)`, `with(...).select(_:)`, `insert(...).select(_:)`,
`QueryBuilder(select:)`, `Returning(_:)`, and `returning(_:)`: those entry points
replayed `readRow` against a reader that cannot supply dialect values. New
overloads read the column aliases from the layout's metadata, and the dynamic
initializers detect a layout at run time:

```swift
// 1.8.0: preconditionFailure. 1.8.1: returns the inserted row.
let statement = insert(t).values(row).returning(layout)
let inserted: [TestTable] = try database.makeRequest(with: statement).fetchAll()
```

**Contextual-only columns in legacy writes.** A `@SQLTable` column whose type has
no `XLLiteral` conformance, such as a `Date` read through a contextual codec,
crashed on its first `Values(row)` insert. It now throws
`XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(valueType:)` before
SQLite sees the statement, and no row changes. Write such a row through its
static row layout.

## Wrong answers that are now refused

### A compound branch cannot carry its own LIMIT

SQLite applies `ORDER BY`, `LIMIT`, and `OFFSET` to a whole compound select,
never to one branch. SwiftQL rendered a branch's clauses anyway, so a limit you
wrote on the recursive step silently limited everything:

```swift
// 1.8.0: ran, with LIMIT applied to the whole compound.
// 1.8.1: throws XLSQLValueEncodingError.unsupportedCompoundBranchClause.
select(seed).unionAll { select(step).from(this).limit(10) }

// Both versions: the same SQL, written where it applies.
select(seed).unionAll { select(step).from(this) }.limit(10)
```

The same rule rejects a right-hand branch with `WITH`, which SQLite never
accepted, and a right-hand branch that is itself a compound, which SQLite
regrouped from the left. Chain the operators instead:
`a.except { b }.union { c }`. The check runs when the statement renders, before
SQLite prepares it, on every request path. The result-builder spelling,
`Union()` followed by `Select`, is not affected.

### QueryBuilder combines conditions in the order you wrote them

`QueryBuilder` kept `and` terms and `or` terms in separate lists and folded
every `and` first:

```swift
let query = QueryBuilder(select: company)
    .from(company)
    .and(company.name == "A")
    .or(company.name == "B")
    .and(company.name == "C")

// 1.8.0 renders the equivalent of: WHERE ((name == 'A' AND name == 'C') OR name == 'B')
// 1.8.1 renders the equivalent of: WHERE ((name == 'A' OR name == 'B') AND name == 'C')
```

A query that uses only `and`, only `or`, or every `and` before every `or` renders
exactly as before. A mixed chain can now return different rows, so read each
one against the condition you meant.

### Text with a NUL character

GRDB binds text with a length of -1, so SQLite reads a bound value only up to its
first NUL. `"a\0b"` was stored as `"a"`. An inline literal was cut short the
same way. Both now fail with `XLSQLValueEncodingError.nulCharacterInText`.
Because U+0000 is the only code point that encodes to a zero byte in UTF-8,
rejecting it means every value SwiftQL accepts is bound in full. Store data that
can contain NUL as a blob.

### Nested scopes keep their own names

A subquery or common table body gets its own schema. When that schema started
from nothing, it handed out names the enclosing statement already used: an
inner `WITH cte0` shadowed the outer one, and an inner automatic binding
rendered the same `:p0` as an outer one, so setting one value replaced the
other.

v1.8.1 adds `XLSchema(parent:)` and schema subquery methods that continue the
enclosing sequence:

```swift
let schema = XLSchema()
let outer = schema.binding(of: Int.self)
var inner: XLNamedBindingReference<Int>!
let statement = select(
    schema.subquery { nested -> any XLQueryStatement<Int> in
        let innerBinding = nested.binding(of: Int.self)
        inner = innerBinding
        return select(outer - innerBinding)
    }
)
var request = database.makeRequest(with: statement)
request.set(outer, 7)
request.set(inner, 5)
try request.fetchOne() // 2: two parameters, :p0 and :p1
```

The free `subquery { schema in ... }` form cannot see the enclosing schema. When
it produces the same collision, rendering now throws
`XLInvocationBindingError.conflictingParameterKey` instead of silently merging
the two values. The common tables built from a schema (`commonTable`, `from`,
`fromExpression`, and the scalar and recursive forms) use the nested schema
already, so an inner automatic binding there now has its own name, and a caller
that set only the outer reference must set the inner one too. Explicitly named
sources and bindings render as before.

### Everything else in this group

- A request nested inside `withResultSet` with the same SQL as the outer request
  reused GRDB's cached statement and reset the outer cursor, which repeated or
  skipped rows. It now prepares its own statement while the cached one is busy.
- `fetchAtMost(_:bindings:)` on a `RETURNING` request ran on a read-only pool
  reader and failed. That is the fetch `@SQLQuery` generates for a bare-row
  return. It now runs on the writer, as `fetchAll` and `fetchOne` do.
- A statement matching an `XLRegexPattern` built as a local lost its
  registration before it ran, and failed with `unregisteredPattern`. The
  statement now keeps its pattern alive.

## REGEXP bounds its input

A `REGEXP` match runs inside a SQLite function callback, where SQLite does not
check for interruption, so a statement cannot be cancelled in the middle of one
match. The pattern often comes straight from a search field. v1.8.1 refuses an
oversized operand before it compiles or matches anything:

| Operand | Limit | Error |
| --- | ---: | --- |
| Pattern string | 1,024 UTF-8 bytes | `XLRegexpLengthLimitError` |
| Subject text, including a registered `XLRegexPattern`'s subject | 16,384 UTF-8 bytes | `XLRegexpLengthLimitError` |

Nothing is truncated. A statement that searched longer column text now fails
when it reaches such a row, so search that text with full-text search or match
it in Swift. A length bound reduces catastrophic backtracking; it cannot remove
it, because an exponential pattern needs only a few dozen characters. Validate a
pattern that comes from untrusted input.

## Live queries without the main thread

`stream()` and `streamOne()` on a GRDB-backed request now observe a constant
database region. A refetch after a commit runs on a pool reader rather than
inline on the writer, and GRDB coalesces a burst of commits. Values arrive on a
private serial queue, and the default retry backoff waits on the same queue, so
a thread that blocks while it waits, the main thread included, cannot deadlock.

If your code read stream values as if they arrived on the main thread, move to
the main actor yourself. Combine's `publish()` and `publishOne()` still deliver
on the main queue by default, and `XLQueryObserver` and `XLQueryRowObserver`
still change their state on the main thread.

## The build validator and the index advisor

- v1.8.0 said that index verification fails closed when the pinned snapshot
  changes. It did not: the verifier caught the error for each candidate and the
  run exited 0. From 1.8.1 the run fails, including when the change happens
  while a candidate's verification throws or between two candidates. The 1.8.0
  changelog entry now carries a dated correction.
- A scratch copy that cannot be set up gives a readable reason and a
  `plan.scratch-setup-failed` build warning, and the new `warnings` field on the
  run results carries it.
- The scratch connection registers the bundled functions, so a statement that
  uses `REGEXP` can get a verified recommendation on a SQLite build that
  rejects unknown functions under `EXPLAIN`.
- `swiftql-index-advisor --apply` refuses to replace a file whose first line is
  not its generated header, and refuses an `--output` that is the same file as
  `--plan-report`. Adopting the advisor for an existing hand-written file takes
  one explicit run:

```
$ swiftql-index-advisor --plan-report plans.json --apply --output Sources/App/Indexes.sql --force
```

The new "Query plan advice" guide in the documentation covers all of it: the
opt-in file, the options, the suppression grammar, the improvement rule, and
the limits of the advice.

## The conformance inventory

The inventory records the behavior this patch changed, with new evidence rather
than new features:

| | 1.8.0 | 1.8.1 |
| --- | ---: | ---: |
| Inventory version | 1.7.0 | 1.8.1 |
| Feature records | 117 | 117 |
| Supported | 113 | 113 |
| Evidence records | 197 | 207 |
| Evidence that exercises real SQLite | 121 | 126 |

## One known gap

A custom `XLRowReadable` projection that is not a static row layout, and whose
own `readRow` throws against the definition reader, still stops the process in
`Select.init(_:)` and `Returning.init(_:)`. Reporting it as an error needs those
initializers to throw, which breaks source, so it waits for v2.0 as
[#744](https://github.com/lukevanin/swiftql/issues/744).

## Upgrading

```swift
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.8.1")
```

Before you upgrade, look for:

- a `switch` with no `default` over `XLSQLValueEncodingError` or
  `SQLiteIndexAdvisorError`;
- `REGEXP` with a pattern that can exceed 1,024 bytes, or over text that can
  exceed 16,384 bytes;
- a `QueryBuilder` chain that mixes `and` and `or`;
- a compound branch with `ORDER BY`, `LIMIT`, `OFFSET`, or `WITH`, especially a
  recursive common table limited inside its `unionAll` closure;
- text that can contain U+0000;
- tests that pin the SQL of unnamed nested sources, or code that sets only an
  outer automatic binding;
- two `XLCustomFunction` types that share a name and argument count;
- code that expects `stream()` values on the main thread;
- an application function that replaces `regexp` or a SQLite built-in while a
  statement is active, which now throws `XLDatabaseContractError.prepareFailure`;
- a build or script that relies on the validator passing when the snapshot
  changes during verification, or on `swiftql-index-advisor --apply`
  overwriting a file without its generated header.

The [changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md) has
a migration step for each one.
