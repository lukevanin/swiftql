---
title: "What's new in v1.9"
date: 2026-09-16
description: "SwiftQL v1.9 makes a declared query the whole read path. A declaration can now be observed by a live query, called inside a transaction, and written with LIKE or REGEXP over a parameter. A new macro gives named bindings a typed packet, and a batch insert runs one prepared statement for a whole transaction."
---

SwiftQL has had declared queries since v1.5. You write a Swift method, you give
its body a statement builder, and the macro generates an executor. The SQL
renders once for each database. The parameters bind through a fresh packet on
every call. Nothing a user typed reaches the SQL text.

That was true only while the declaration did one thing: fetch rows and return
them. Three common jobs fell outside it. A view that observed the same read
needed a second copy of the statement. A read inside a transaction opened a
transaction of its own and failed. A search that matched text with `LIKE` or
`REGEXP` could not be declared at all.

v1.9 closes all three. This post walks through each one with the code that the
to-do demo actually deleted.

## 1. A view can observe a declaration

A live query observes an `XLRequest`. Until v1.9, a declaration gave you no
request — only an executor that rendered, bound, and fetched in one call. So a
demo that both fetched and observed the same read wrote the read twice.

Here is what the to-do demo carried. `TodoLiveReads.swift` existed only to
mirror three declarations in `TodoReads.swift`:

```swift
/// The duplication is real: `TodoReads.swift` declares the same three, and a
/// change to one has to be made in both.
enum TodoLiveReads {

    static let todoID = XLNamedBindingReference<TodoUUID>(name: "id")

    /// Mirrors `Query.todoLists()`.
    static var lists: any XLQueryStatement<TodoList> {
        sql { schema in
            let list = schema.table(TodoList.self)
            Select(list)
            From(list)
            OrderBy(list.position.ascending(), list.name.ascending())
        }
    }

    /// Mirrors `Query.todo(id:)`.
    static var todoByID: any XLQueryStatement<Todo> {
        sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            Where(todo.id == todoID)
        }
    }
}
```

Binding a value into one of those observations meant finding the slot by its
string name:

```swift
public static func todoIDBindings(
    _ id: TodoUUID,
    layout: XLParameterLayout
) throws -> XLInvocationBindings<XLSQLiteValue> {
    guard let slot = layout.slot(for: .named("id")) else {
        throw TodoStoreError.unknownParameter(
            statement: "to-do by identifier",
            name: "id"
        )
    }
    return try XLInvocationBindings<XLSQLiteValue>(
        layout: layout,
        bindings: [try XLInvocationBinding(slot: slot, value: id.sqlValue)]
    ).validatingComplete()
}
```

Every declaration now has a **prepared form**. It takes the arguments the
executor takes, and it returns an `XLPreparedQuery`: the request from the
declaration's render-once cache, and the binding packet for those arguments.
The whole file above is gone, and the demo's view models read this way:

```swift
listsQuery = try database.preparedQueries.todoLists()
listCountsQuery = try database.preparedQueries.listCounts()

todo = XLObservableQueryRow(
    try database.database.preparedQueries.todo(id: todoID)
)
```

The name depends on which macro declared the query:

| Form | Executor | Prepared form |
| --- | --- | --- |
| `@SQLQuery` | `try database.fetchPersonByName(name:)` | `try database.personByNamePreparedQuery(name:)` |
| `@SQLQueries` | `try database.personByName(name:)` | `try database.preparedQueries.personByName(name:)` |

An `XLPreparedQuery` accepts `stream()`, `streamOne()`, `publish()`, and
`publishOne()`, and it goes straight into `XLObservableQuery` and
`XLObservableQueryRow`.

Two properties make this more than a convenience. The prepared form and the
executor read the **same cache entry**, so the statement still renders at most
once for each database, whichever form runs first. And the packet holds exactly
the values the executor would bind, so the observed statement and the fetched
statement cannot drift apart. That was the real cost of the duplicated file:
not the extra lines, but the chance that a change reached one copy only.

Two limits are worth knowing. `XLPreparedQuery` is not `Sendable`, because it
holds an `any XLRequest`, so prepare it in the isolation domain that observes
it. And new argument values need a new prepared query, because the packet is
captured once for the initial fetch and for every refresh.

## 2. A declaration can run inside a transaction

Before v1.9 the `@SQLQueries` database-level executor always opened a
transaction of its own. Called inside a `withTransaction(_:)` body, it threw
`nestedTransactionUnsupported`. So a body that wrote something and then wanted
to read it back had to build the read again with `makeRequest(with:)`.

Now call the executor on the scope:

```swift
let matches = try database.withTransaction { scope in
    try scope.makeRequest(with: sqlInsert(candidate)).execute()
    return try scope.personByName(name: candidate.name)
}
```

The call runs on the transaction's connection. It reads the write the body made
a line earlier, and it commits or rolls back with it. It uses the database's
render-once cache entry and the binding packet a call on the database builds, so
a scope adds no cache entry and no render.

The demo's own start-up sequence is the clearest case. It creates the schema and
reads it back inside one transaction:

```swift
didSeed = try database.withTransaction { scope in
    try Self.createSchema(in: scope)
    // The declared read, called on the scope, runs on the
    // transaction's connection, so it sees the schema just created.
    guard try scope.todoLists().isEmpty else {
        return false
    }
    try Self.insert(TodoSeed(referenceDate: referenceDate), in: scope)
    return true
}
```

The scope rules do not change. An ended scope throws `scopeEscaped`. The
original database used inside a body still throws
`nestedTransactionUnsupported`, and so does `execute(_:)` called on a scope. A
query prepared from a scope fetches, but it cannot be observed: observation
needs the connection pool, so it throws
`liveQueriesUnsupportedInTransaction`.

## 3. A parameter can go into a method call

A declared query's body may not freeze a parameter into the rendered SQL. That
rule is what makes one render serve every call. Until v1.9 the frozen-literal
guard enforced it bluntly: a parameter passed to any call was rejected. That
ruled out `column.like(pattern)`, `column.regexp(pattern)`, and `Limit(count)`,
which are exactly how an application searches and pages.

The macros now rewrite a parameter passed to a DSL method or clause into its
named binding. The demo's list view read was a hand-built statement for this
reason alone; it is a declaration again:

```swift
func filteredTodos(
    listID: TodoUUID,
    includesCompleted: Bool,
    includesActive: Bool,
    overdueOnly: Bool,
    referenceDate: TodoDate,
    searchPattern: String,
    sortOrder: Int
) -> [Todo] {
    sqlResult { schema in
        let todo = schema.table(Todo.self)
        Select(todo)
        From(todo)
        Where(
            todo.listID == listID
            && (todo.isCompleted == includesCompleted
                || todo.isCompleted != includesActive)
            && (overdueOnly == false
                || (todo.dueAt < referenceDate
                    && todo.isCompleted == false))
            && (todo.title.regexp(searchPattern)
                || todo.notes.regexp(searchPattern))
        )
        // …ordering terms omitted…
    }
}
```

One statement serves every filter, sort, and search the app offers, and the view
observes it through `database.preparedQueries.filteredTodos(...)`.

The guard still rejects the two shapes that really would freeze a value: string
interpolation, and member access on a parameter. One gap is worth stating
plainly. A parameter passed to a call whose parameter type is `Any` or generic,
such as `String(describing:)`, is **not** turned into a binding, and the macro
cannot detect it. Pass parameters to SwiftQL expression APIs only.

The rewrite also gained a diagnostic it needed. A parameter named `name`, in a
body that also wrote `\Person.name`, used to produce invalid code. A parameter
named `From` rewrote the `From(…)` clause. The rewrite now leaves key-path
components and callees alone, and the macro reports the shared name at your
declaration.

## The manifest writes itself

Build-time validation has prepared every query in a manifest against a
checked-in schema snapshot since v1.5.2. Writing that manifest was the
unpleasant part: you typed each entry by hand, or you built
`XLStaticQueryDescriptor` values yourself.

In v1.9 the macros lower each declaration to a static descriptor, a new
build-tool plugin reads every declaration in a target and generates a
`<Target>DeclaredQueries` registry, and
`SQLiteBuildValidationDeclaredQueryManifest.makeManifest(...)` turns that
registry into a manifest. A hand-written manifest is now the fallback, not the
main path. The build-validation plugin also gained an `XcodeBuildToolPlugin`
conformance, so an Xcode application target can run it, not only a SwiftPM
target.

That story has its own post, written against the shipped behaviour with every
command and every diagnostic captured from a real run:
[**SwiftQL now validates your declared queries against your real database at
build time**](https://lukevanin.github.io/swiftql/blog/posts/build-time-sqlite-validation/).

## Named bindings get a typed packet

Some statements are not declared queries. A write is the usual one, with or
without `RETURNING`. Such a statement uses named bindings, and every call needs
a packet of values. Before v1.9 you wrote each binding's name twice — once in
the statement, once in the packet — as a string:

```swift
let idParameter = XLNamedBindingReference<TodoUUID>(name: "id")
let titleParameter = XLNamedBindingReference<String>(name: "title")
// …

let bindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: request.parameterLayout,
    bindings: [
        try Self.binding(layout, "id", id.sqlValue),
        try Self.binding(layout, "title", .text(title)),
        try Self.binding(layout, "notes", .text(notes)),
        try Self.binding(layout, "dueAt", dueAt?.sqlValue ?? .null),
        try Self.binding(layout, "priority", .integer(Int64(priority.rawValue))),
    ]
).validatingComplete()
```

A typo in any of those strings compiled, and then failed at run time. The demo
carried a `binding(_:_:_:)` helper whose only job was to turn a missing slot
into a readable error.

`@SQLBindings` removes the strings. Write one stored property for each binding.
The macro generates a typed static reference for each property, and the packet
builder:

```swift
@SQLBindings
private struct UpdateTodoBindings {
    var id: TodoUUID
    var title: String
    var notes: String
    var dueAt: TodoDate?
    var priority: TodoPriority
}

let statement = update(table)
    .set { row in
        row.title = UpdateTodoBindings.title
        row.notes = UpdateTodoBindings.notes
        row.dueAt = UpdateTodoBindings.dueAt
        row.priority = UpdateTodoBindings.priority
    }
    .where(table.id == UpdateTodoBindings.id)
    .returning(schema.table(Todo.self))

let request = database.makeRequest(with: statement)
let bindings = try UpdateTodoBindings(
    id: id, title: title, notes: notes, dueAt: dueAt, priority: priority
).bindings(for: request)
```

The property is now the only place the binding's name and type appear:

| Mistake | Before v1.9 | With `@SQLBindings` |
| --- | --- | --- |
| Misspelled reference in the statement | Runtime error | Missing static member; does not compile |
| Misspelled value label | Runtime error | Initializer error; does not compile |
| Forgotten value | Runtime error | Initializer error; does not compile |
| Statement does not use a declared binding | Runtime error | Runtime error |
| Statement uses an undeclared binding | Runtime error | Runtime error |

The last two rows stay at run time on purpose, and they are why you declare one
struct for each statement shape. A statement you build conditionally has a
different parameter layout for each shape, so give each shape its own struct.
The macro also refuses a property with an initial value and an initializer
inside the struct, because either one would let a call leave a value out.
`scripts/ci/check-named-binding-packet-type-safety.sh` proves each compile error
in CI.

## One prepared statement for a batch insert

`sqlInsert(_:)` renders a row's values into the SQL text as literals. That is
correct and it is safe, but it means a loop inserts N distinct SQL strings, and
SQLite prepares every distinct string again:

```swift
// Before: renders 100 statements, prepares 100 statements.
try database.withTransaction { scope in
    for person in newPeople {
        try scope.makeRequest(with: sqlInsert(person)).execute()
    }
}
```

`GRDBDatabase.insert(contentsOf:)` renders the insert once, with a bound
parameter in place of each literal, prepares it once for the call, and binds
each row through an invocation packet:

```swift
// After: renders once, prepares once.
try database.withTransaction { scope in
    try scope.insert(contentsOf: newPeople)
}
```

On a scope, the rows run inside a savepoint in that transaction: when one row
fails, every row of the call rolls back, and the writes the body made before it
stay. On any other database the call opens one write transaction, so either
every row commits or none does. A row whose values cannot be bound — a value
that renders as SQL other than one literal, or a value that fails to render,
such as a non-finite `Double` — falls back to rendering on its own, in the same
transaction, and fails with the same error `sqlInsert(_:)` gives. The SQL that
`sqlInsert(_:)` renders for one row does not change.

### What it measured

The cross-library `transactional_write` contract inserts a 100-row batch in one
transaction, against the committed Northwind fixture. It was recorded on one
Mac16,8 (Apple M4 Pro, 14 cores, 24 GiB), macOS 26.6.2, Xcode 27.0, Swift 6.4.
Two "before" runs and two "after" runs alternated between two clean revisions,
each with five independent processes, 10 warmups, and 100 timed samples:

| Recording | SwiftQL write path | SwiftQL median | SwiftQL spread | GRDB median | GRDB spread |
| --- | --- | ---: | ---: | ---: | ---: |
| 2026-08-02 (`f1202ce9`) | per-row `sqlInsert(_:)` | 995.94 us | 1.8% | 431.54 us | 8.7% |
| 2026-09-15 before, round 1 (`35e78e53`) | per-row `sqlInsert(_:)` | 993.42 us | 5.1% | 393.31 us | 8.0% |
| 2026-09-15 before, round 2 (`35e78e53`) | per-row `sqlInsert(_:)` | 1.00 ms | 4.0% | 394.23 us | 1.8% |
| 2026-09-15 after, round 1 (`54abf673`) | `insert(contentsOf:)` | 363.98 us | 5.3% | 394.08 us | 15.9% |
| 2026-09-15 after, round 2 (`54abf673`) | `insert(contentsOf:)` | 358.17 us | 4.5% | 387.06 us | 5.0% |

The batch path is about **2.8x faster** than the per-row path, against process
spreads of 4.0% to 5.3%. The two "before" runs also agree with the older
2026-08-02 figure within 1%.

Two things the table does **not** support. It establishes no ordering between
SwiftQL and GRDB: SwiftQL's median is 7.6% and 7.5% below GRDB's, and in round 1
that gap is smaller than GRDB's own 15.9% spread. And the per-row figure
measures rendering rather than preparation, because the workload inserts the
same batch every iteration, so GRDB's statement cache already holds all 100
literal statements after warmup. A workload with different values every
iteration would add 100 preparations per transaction to the per-row path only.
That workload was not measured.

Other agents were building software on the host throughout these runs; the
one-minute load average stayed between 3.6 and 11.9 on 14 cores. Every raw
sample log is kept beside its report under
`Benchmarks/Comparison/Issue259/Issue668/`.

## Three JSON corrections

v1.6 made SQLite's JSON support a typed SwiftQL surface. Three of its behaviours
were wrong, and this release changes them. Each one can change what your code
reads or how it compiles.

**A `Bool` is a JSON boolean.** `jsonObject(("done", todo.isCompleted))` wrote
`1` or `0`. It now writes `true` or `false`. A literal renders as
`json('true')`; any other `Bool` expression renders as a `CASE`, so SQL `NULL`
stays JSON `null`. A `Codable` reader of a `Bool` field now reads the stored
document. Code that read such a member as a number must change.

**A `Data` value fails before SQLite prepares.** Passing `Data` to a JSON
function produced one of two bad outcomes: SQLite reported
`JSON cannot hold BLOB values`, or it silently read the bytes as a document when
they happened to be valid JSONB. The statement now fails when it renders, with
`XLSQLValueEncodingError.blobInJSONValue(valueType:function:)`. To nest JSONB
held in a `Data` column, pass it through `minifiedJSONB()` first. The check
reads the static type, so a `Data?` value is rejected even when the row holds
SQL `NULL`.

**A mutation on a `NOT NULL` document is non-optional.**

```swift
// Before: the result is String?, so the assignment needs coalesce.
row.checklist = todo.checklist.jsonSetting(path, to: value) ?? "{}"

// After: the result is String, and assigns straight back.
row.checklist = todo.checklist.jsonSetting(path, to: value)
```

`jsonRemoving` and `jsonbRemoving` on a non-optional document report the root
path `$` with the new case `jsonRootRemoval(function:)`, because SQLite returns
`NULL` when it removes the root. `jsonPatched(with:)` stays optional, because a
`NULL` patch also gives `NULL`.

## Smaller things

- **A `@SQLTable` or `@SQLResult` property default now applies.** A `var`
  property with an initial value gives the generated initializer a default for
  its parameter, so a call can leave that property out. Before, the initializer
  ignored the initial value and demanded the argument. It is a Swift default
  only; it adds no SQL `DEFAULT` clause.
- **SwiftQL 1.x supports GRDB 6 only.** An application on GRDB 7 cannot resolve
  SwiftQL 1.x. `Research/GRDB7Evaluation.md` records the build against GRDB
  7.11.1 and the break list, and the `Sendable` findings feed the v2.0 `Row`
  decision.
- **OpenCombine is a Linux-only dependency.** An Apple-platform build now
  compiles and links no OpenCombine module. The version requirement relaxes
  from `exact: "0.14.0"` to `from: "0.14.0"`, so a consumer graph that needs a
  later compatible release resolves. `Package.resolved` keeps the tested pin.
- **New benchmark baselines.** All three reports — phase harness, cross-library
  comparison, and consumer compile time — were re-recorded at one revision on
  one host, and `BENCHMARKS.md` now names the current baseline. The compile-time
  summarizer also rejects a sample whose wall time disagrees with SwiftPM's own
  build duration in the same log.

## Upgrading

```swift
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.9.0")
```

This release is not purely additive. Check for these five things:

1. **A name collision with a generated member.** The macros now generate
   `preparedQueries` and `declaredQueries` on a `@SQLQueries` type, and a
   `<name>PreparedQuery` and `<name>DeclaredQuery` peer beside each `@SQLQuery`
   declaration. A member of yours with one of those names stops compiling.
   Rename your member or your specification. `@SQLQueries` reports the
   collisions it can see at your declaration; a peer macro on Swift 5.9's
   swift-syntax cannot see other members, so a `@SQLQuery` collision arrives as
   an "invalid redeclaration" error in generated code.
2. **A `Data` value in a JSON function.** It now throws `blobInJSONValue`. Pass
   it through `minifiedJSONB()`, or leave it out of the document.
3. **A JSON mutation result you unwrap twice.** On a `NOT NULL` document the
   result is non-optional now, so unwrap it once.
4. **A `switch` over `XLSQLValueEncodingError` with no `default` clause.** It
   must handle `blobInJSONValue` and `jsonRootRemoval`.
5. **A build-validation manifest.** New manifests are format version 2, which
   makes the provenance fields and `value_type_name` optional, allows an empty
   `queries` list, and rejects an unknown key at every level. The reader still
   accepts version 1 and re-encodes it to the same bytes. Several report
   properties are now `String?`, and both `SQLiteBuildValidationManifestError`
   and `SQLiteBuildValidationPlanSuppressionError` gain `unknownKey(path:)`.

The [changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md) has
the exhaustive detail, and its Migration section covers each break above.
