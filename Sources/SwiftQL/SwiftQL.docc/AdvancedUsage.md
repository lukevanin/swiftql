# Advanced usage

Understand how a SwiftQL statement reaches SQLite: preparation, connection
ownership, row lifetime, binding packets, and transaction boundaries.

## Overview

<doc:GettingStarted> shows what to write. This guide explains what happens
underneath, and it is where the exact contracts live: which values are bound
to which connection, when SQLite prepares a statement, how long a result row
survives, what is safe to share between tasks, and which mistakes are rejected
rather than tolerated.

None of this is required to write a working query. Read it when you are
tuning execution, running work across tasks, writing your own database
adapter, or diagnosing something that only fails under a connection pool.

## Package layout and version boundaries

Adapter packages can depend directly on the `SwiftQLCore` library product. It
exports the dialect, dialect-value, logical-statement, and driver contracts
without linking GRDB; the `SwiftQL` product remains the compatibility facade
that includes the current GRDB-backed SQLite adapter.

SwiftQL v1.3 validates the existing SQLite surface against recorded real-engine,
Northwind, and stress evidence; it does not introduce a new public syntax or
validation API. In particular, issue
[#132](https://github.com/lukevanin/swiftql/issues/132) is a
research-only schema-snapshot preparation prototype. Applications still own
their schema lifecycle and perform physical preparation on the runtime
connection that executes each statement.

The build-time validator v1.5.2 shipped from that research does not change
either point. It prepares a manifest of declared queries against a checked-in
schema snapshot during the build and finalizes each statement immediately, so
runtime preparation on the executing connection still happens exactly as
described here. See <doc:StaticQueries> for what a successful validation does
and does not prove.

## Requests, layouts, and packets

Requests retain the generated SQL and an immutable `XLParameterLayout`. The
layout is static metadata: it records each logical parameter's deterministic
index, binding key, value type, nullability, coding context, and selected codec
identity. Runtime values are separate. Put them in a fresh
`XLInvocationBindings` packet for each call, then pass that packet to
`fetchAll(bindings:)`, `fetchOne(bindings:)`, `execute(bindings:)`, or a
packet-backed publisher. `execute()` and `execute(bindings:)` return an
`XLExecutionResult`: the rows the statement changed, and whether it could
write. To learn an inserted row's id, add a `RETURNING` clause and fetch it.
Creating a request translates the SwiftQL statement
into SQL but does not prepare it immediately. On execution, GRDB obtains a
cached SQLite statement for that SQL on the connection performing the work.

Every request can also be awaited through its `async` view:
`try await request.async.fetchAll(bindings:)`, `fetchOne(bindings:)`, and
`fetchAtMost(_:bindings:)`, and `try await request.async.execute(bindings:)`
for a write. The view runs the same SQL with the same packet, but the calling
task suspends while the driver's asynchronous scope lends a connection, instead
of blocking its thread. It is a separate view rather than `async` overloads, so
a synchronous `try request.fetchAll()` inside an asynchronous function keeps
compiling. With GRDB, a request made in a `withTransaction(_:)` scope has no
asynchronous form: its connection belongs to the synchronous body, and
awaiting it throws `XLTransactionScopeError.scopeEscaped`.

For a statement with named bindings, `@SQLBindings` generates both the typed
references the statement uses and the packet for each call, so a binding name
is checked at compile time. See "Named bindings for a statement value" in
<doc:DeclaredQueries>.

## Dialect and driver responsibilities

The SQLite dialect defines how SwiftQL renders valid SQLite syntax, including
identifier quoting, placeholder spelling, value storage classes, and required
SQLite capabilities. The database driver has a separate job: it leases a
connection, prepares the rendered SQL, binds SQLite values to its transport,
executes the statement, and reads SQLite values from the result. GRDB is the
current SQLite driver, but it does not define the SQLite syntax or the logical
policy for converting application values.

``GRDBDatabase`` runs its requests on the GRDB driver. ``XLDriverDatabase``
runs the same requests on any driver that implements SwiftQL's driver contract
(issue #682), so a driver from outside SwiftQL needs no GRDB types. Such a
driver conforms to three SwiftQLCore protocols:

- `XLDatabaseDriver`, whose asynchronous scopes serve each request's `async`
  view;
- `XLBlockingDatabaseDriver`, whose blocking scopes serve the synchronous
  members, such as `fetchAll()` and `execute()`;
- `XLObservingDatabaseDriver`, whose `observe(_:fetch:)` serves `stream()` and
  the publish members.

Its dialect must be `XLSQLiteDialect`. ``XLDriverDatabase`` conforms to
``XLDatabase`` but not yet to ``XLTransactionalDatabase``: a portable way for a
driver to pin one connection for a transaction scope is issue #808.

## Logical and physical preparation

Logical requests and prepared handles are database- or pool-bound. They retain
the rendered SQL and request metadata, but they do not own one physical
statement. Physical GRDB statements are connection-bound and must not be shared
between connections or concurrent executions.

With a connection pool, each execution leases a connection and resolves or
caches the physical statement separately on that leased connection. Another
execution may lease a different connection and therefore prepare the same SQL
again. A single-connection database may reuse its own statement cache, but its
physical statements still belong only to that connection.

Preparation is therefore an execution-time operation. Successful preparation
on one connection does not guarantee every later preparation: preparation can
still fail later on a newly leased connection, for example when its schema,
registered functions, or available capabilities differ.

## Incremental row lifetime

Every request steps result rows through the connection contract's
`forEachRow(_:_:)` callback, or lends a row stepper through
`withValuesStepper(_:_:)`, while the leased connection is active. Both are
public `XLDatabaseDriverConnection` requirements since issue #682. Their
defaults fetch every row with `fetchAll(_:)` first, and a driver that can step
a cursor overrides them. The GRDB connection overrides both, and copies each
row into normalized SQLite values before advancing because GRDB reuses
cursor-backed row storage. The synchronous callback may stop without stepping later rows, and a
thrown decoding error releases the cursor and connection before it propagates.
A cursor value is never returned from the database-access closure.

The public v1 behavior remains eager: `fetchAll()` still returns a complete
typed array, while `fetchOne()` returns an optional first row. Those
compatibility APIs are layered over the same incremental primitive.
`fetchAll()` therefore retains its typed output as required but no longer
retains a complete intermediate array of GRDB rows or normalized SQLite-value
rows before typed decoding. A driver that overrides the callback must keep the
same lifetime rather than exposing its native cursor type.

## Transactions and bindings

Transaction-scoped work pins one connection for the duration of the
transaction. Code inside that transaction must use the pinned connection and
must not re-enter the root pool, which could lease another connection and break
the transaction boundary or deadlock while waiting for itself.

A driver transaction commits when its operation returns and rolls back when it
throws. The driver scopes are asynchronous: `withTransaction(_:_:)` suspends
until the writer is free, then runs the operation synchronously on it, in the
`XLTransactionKind` the caller names. `withValidatedTransaction` preserves the
exact operation error, so a dedicated caller error can express explicit
rollback intent. A driver scope checks for cancellation before it lends a
connection, and the GRDB driver's asynchronous scopes also interrupt a running
operation when its task is cancelled, which rolls the transaction back.
`withTransaction(_:)` on a database is different: its body is synchronous, so
it checks for cancellation once, before the transaction begins, and then runs
the body to completion. The contract does not
expose nested transactions or savepoints; do not attempt those by re-entering
the root pool from a pinned body. The current GRDB driver is pool-backed and
does not expose a separate single-connection transaction capability.

Each invocation packet carries normalized dialect values in logical-index
order, so every call has fresh bindings. Packet-backed execution does not move
those values into the logical request or connection-wide statement cache.
Packets and layouts are value-semantic and `Sendable` when their dialect values
are. The current `XLRequest` facade itself is not `Sendable` and does not yet
promise that one request can be shared across tasks; use packets to separate
values across repeated calls in the request's supported isolation context.

Driver integrations can use the `prepareValidated`, `bindValidated`,
`fetchAllValidated`, `fetchOneValidated`, `executeValidated`, and
`withValidatedTransaction` helpers to normalize transport failures into
`XLDatabaseContractError` categories. A failure the database itself reports
reaches the caller as an `XLDatabaseError`, whose portable `code`, such as
`.busy` or `.constraint`, does not depend on the driver, and the helpers pass
it through unchanged. The GRDB driver reports every GRDB `DatabaseError` this
way, including a `BEGIN` or `COMMIT` that fails, and keeps GRDB's error as the
`underlying` value; `nativeCode` is SQLite's extended result code. An
`XLColumnReadError` still reaches the caller unchanged for the established
decoding API. Database and dialect mismatches are still rejected before
physical preparation in both paths.

## Cross-task raw-value execution

For cross-task raw-value execution, call `GRDBDatabase.prepareInvocation(with:)`
or `XLDriverDatabase.prepareInvocation(with:)`.
Its ``XLPreparedInvocation`` result is `Sendable`, is also still named
`GRDBPreparedInvocation`, and accepts an independent packet in
`fetchAllValues`, `fetchOneValues`, or `execute`. It deliberately returns normalized SQLite
values instead of retaining the legacy typed row-reader graph.

<!-- test: XLDocumentationTests.testDocumentationAdvancedUsage -->
```swift
let minimumAgeParameter = XLNamedBindingReference<Int>(name: "minimumAge")
let namedAdultsQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age >= minimumAgeParameter)
}
let preparedInvocation = database.prepareInvocation(with: namedAdultsQuery)

let minimumAgeSlot = preparedInvocation.parameterLayout
    .slot(for: .named("minimumAge"))!
let invocationBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: preparedInvocation.parameterLayout,
    bindings: [
        try XLInvocationBinding(slot: minimumAgeSlot, value: .integer(21))
    ]
).validatingComplete()

let rows: [[XLSQLiteValue]] = try preparedInvocation.fetchAllValues(
    bindings: invocationBindings
)
```

Each row arrives as normalized `XLSQLiteValue` columns in the statement's own
result order; decoding them into application types is the caller's
responsibility. For a durable, database-independent SQL and value-layout
contract, create an `XLStaticQueryDescriptor` and prepare it through the
overload described in <doc:StaticQueries>.

## Legacy mutable bindings

The mutating `set` methods remain as a migration shim for v1 literal bindings.
They immediately normalize each value into a compatibility packet stored in
that request copy. Existing code can continue to copy, set, and execute a
request, but new code should keep the prepared request immutable and pass an
explicit packet for each call. The shim cannot override a contextual
parameter's selected codec. Static descriptors use the same immutable packet
contract while adding stable identity, result metadata, cardinality, and a
cross-task prepared handle; see <doc:StaticQueries>.

## Typed multi-statement transaction scopes

`GRDBDatabase.withTransaction(_:)` (issue #284, `XLTransactionalDatabase`) runs
an ordered sequence of typed requests — reads and writes alike — as one atomic
unit on a single pinned connection, without ever naming a GRDB type. It is the
typed counterpart to the driver-level `withTransaction` described above: where
the driver hands an adapter integration a raw connection, this hands ordinary
application code another `GRDBDatabase`, so the body is just more
`makeRequest(with:)` calls (and, inside a `@SQLQueries` extension, more
`Context` calls — `execute(_:)` is sugar over this same primitive).
<doc:GettingStarted> shows the everyday spelling; this section states the
guarantees it rests on.

Ordering, atomicity, and lifetime work exactly as the driver-level contract
above describes, plus the guarantees a typed, adapter-neutral surface adds:

- **Order and results.** Every request the body issues runs in source order
  on the one connection `withTransaction(_:)` pinned for this call; an
  ordinary local variable carries one operation's result to a later one or to
  the transaction's own return value.
- **Commit and rollback.** The whole body is one commit unit: it commits only
  after the body returns normally, and rolls back every write the body
  performed — on a preparation, binding, execution, decoding, or user-thrown
  failure alike — before rethrowing the original, unmodified error.
- **Read-your-writes.** A read issued from the scope observes an earlier,
  still-uncommitted write from the same body, because both run on the same
  pinned connection.
- **No GRDB type in the contract.** The scope handed to the body is another
  `GRDBDatabase` — the exact same type <doc:GettingStarted> uses — never a
  GRDB `Database`, `DatabasePool`, or statement handle.

Three cases are rejected before any transaction work happens, each with a
predictable, catchable `XLTransactionScopeError` rather than a crash or silent
wrong answer:

- **Nested transactions and savepoints are not supported.** Calling
  `withTransaction(_:)` again from inside an active body — on the scope it was
  given, *or* on the original database captured from the enclosing scope —
  throws `.nestedTransactionUnsupported`. The v1 driver has no savepoint hook,
  so a nested call cannot prove it would only commit or roll back its own
  writes; re-entering the connection pool from inside an open transaction can
  also deadlock or silently lease a different connection that only sees the
  database's last *committed* state, missing the transaction's own
  uncommitted writes. A task created inside the body is separate work, not
  part of the body: it may use the original database, where its writes wait
  for the transaction to finish and its reads see committed data. Do not make
  the body wait for such a task's write: the write waits for the transaction,
  and the transaction waits for the body, so neither finishes.
- **The scope must not escape the body.** A request, write request, or scope
  value used after `withTransaction(_:)` returns throws `.scopeEscaped`: the
  pinned connection is invalidated the instant the body returns, so
  continuing would silently touch a connection GRDB may already be reusing
  for unrelated work.
- **Live queries are not supported inside a transaction.** `publish()` /
  `publishOne()` on a transaction-scoped request throws
  `.liveQueriesUnsupportedInTransaction`: `ValueObservation` tracks a
  connection pool across commits over time, and a transaction-scoped
  connection is invalidated before there is anything to observe.

The nested case is worth seeing written out, because the rejection is a
catchable error and the outer body's own writes still roll back:

<!-- test: XLDocumentationTests.testDocumentationAdvancedUsage -->
```swift
do {
    try database.withTransaction { scope in
        let candidate = Person(id: "nested", occupationId: nil, name: "Ida", age: 33)
        try scope.makeRequest(with: sqlInsert(candidate)).execute()
        try scope.withTransaction { _ in }
    }
} catch let error as XLTransactionScopeError {
    // .nestedTransactionUnsupported — and the insert above rolled back.
    print(error)
}
```

Cancellation is checked once, at the very start of `withTransaction(_:)`: a
task that is already cancelled throws `CancellationError` before opening the
transaction. The body itself runs synchronously to completion once started —
there is no later cooperative cancellation point, so mid-transaction
cancellation is not a supported capability of this v1 surface, not a silently
ignored one.

`withTransaction(_:)` is a non-macro v1 compatibility API: a plain closure
over `XLTransactionalDatabase`, available on the same Swift 5.9 floor as the
rest of this article, independent of the `@SQLQuery`/`@SQLQueries` macros
described in <doc:DeclaredQueries>. Composing with those macros needs no
separate transaction-aware spelling — a `@SQLQueries` extension's generated
`execute(_:)` already calls `withTransaction(_:)` internally, so every
declared query it runs shares the same pinned connection as any
`makeRequest(with:)` call alongside it in the same body. Since v1.9
([#662](https://github.com/lukevanin/swiftql/issues/662)) a declared query
called on the scope itself also runs on that pinned connection, instead of
opening a nested transaction; see <doc:DeclaredQueries>.

## Inserting many rows through one statement

`sqlInsert(_:)` renders a row's values into the SQL text as literals. A loop of
`makeRequest(with: sqlInsert(row)).execute()` therefore renders a new
statement for every row, and every distinct row is a distinct SQL string that
SQLite prepares again. `GRDBDatabase.insert(contentsOf:)` (issue #668) renders
the insert once, with a bound parameter in place of each literal, and binds
each row's values through an invocation packet:

<!-- test: XLDocumentationTests.testDocumentationAdvancedUsage -->
```swift
let newPeople = [
    Person(id: "batch-1", occupationId: nil, name: "Kim", age: 41),
    Person(id: "batch-2", occupationId: nil, name: "Lee", age: 37),
]
try database.withTransaction { scope in
    try scope.insert(contentsOf: newPeople)
}
```

The guarantees:

- **One render, one preparation.** The call renders the statement once and
  prepares it once, on the connection that runs the rows. A 100-row batch
  renders once and prepares once.
- **One connection, one unit.** On a transaction scope the rows run inside a
  savepoint in that scope's transaction. When a row fails, the savepoint rolls
  back every row of the call and the error is thrown. Writes the body made
  before or after the call stay, so a body that catches the error and returns
  commits without any row of the batch. On any other database the call opens
  one write transaction for all rows, so either every row commits or none does.
- **The sequence is read inside the connection access.** Elements are produced
  one at a time after the scope is checked. An escaped scope throws before a
  lazy sequence produces anything, and it throws for an empty sequence too.
- **No statement outlives its connection.** The prepared statement is a local
  value of the call. It is used only inside the call's connection access, on
  the connection that prepared it, and it is dropped before the call returns.
  A batch on an escaped scope throws `.scopeEscaped`, and a batch on the root
  database from inside an active body throws `.nestedTransactionUnsupported`,
  as every other request does.
- **The same stored values and errors as `sqlInsert(_:)`.** A row whose values
  cannot be bound to the shared statement renders on its own as
  `sqlInsert(_:)` does, inside the same transaction. That covers a value that
  renders as SQL other than one literal, such as a custom literal type that
  wraps its value in a function call, and a value that fails to render, such as
  a non-finite `Double`. Such a row fails with the error the single-row path
  reports. The SQL that `sqlInsert(_:)` renders for one row does not change.
