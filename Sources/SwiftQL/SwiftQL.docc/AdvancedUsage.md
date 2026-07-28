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

## Requests, layouts, and packets

Requests retain the generated SQL and an immutable `XLParameterLayout`. The
layout is static metadata: it records each logical parameter's deterministic
index, binding key, value type, nullability, coding context, and selected codec
identity. Runtime values are separate. Put them in a fresh
`XLInvocationBindings` packet for each call, then pass that packet to
`fetchAll(bindings:)`, `fetchOne(bindings:)`, `execute(bindings:)`, or a
packet-backed publisher. Creating a request translates the SwiftQL statement
into SQL but does not prepare it immediately. On execution, GRDB obtains a
cached SQLite statement for that SQL on the connection performing the work.

## Dialect and driver responsibilities

The SQLite dialect defines how SwiftQL renders valid SQLite syntax, including
identifier quoting, placeholder spelling, value storage classes, and required
SQLite capabilities. The database driver has a separate job: it leases a
connection, prepares the rendered SQL, binds SQLite values to its transport,
executes the statement, and reads SQLite values from the result. GRDB is the
current SQLite driver, but it does not define the SQLite syntax or the logical
policy for converting application values.

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

The GRDB adapter steps result rows through a package-internal, driver-neutral
callback while the leased connection is active. It copies each row into
normalized SQLite values before advancing because GRDB reuses cursor-backed row
storage. The synchronous callback may stop without stepping later rows, and a
thrown decoding error releases the cursor and connection before it propagates.
A cursor value is never returned from the database-access closure.

The public v1 behavior remains eager: `fetchAll()` still returns a complete
typed array, while `fetchOne()` returns an optional first row. Those
compatibility APIs are layered over the same incremental primitive.
`fetchAll()` therefore retains its typed output as required but no longer
retains a complete intermediate array of GRDB rows or normalized SQLite-value
rows before typed decoding. Future package adapters should implement the same
callback lifetime rather than exposing their native cursor types.

## Transactions and bindings

Transaction-scoped work pins one connection for the duration of the
transaction. Code inside that transaction must use the pinned connection and
must not re-enter the root pool, which could lease another connection and break
the transaction boundary or deadlock while waiting for itself.

The synchronous v1 driver commits when the transaction body returns and rolls
back when it throws. `withValidatedTransaction` preserves the exact body error,
so a dedicated caller error can express explicit rollback intent. The v1
contract does not expose nested transactions, savepoints, or task-cancellation
hooks; do not attempt those by re-entering the root pool from a pinned body.
The current GRDB v1 driver is pool-backed and does not expose a separate
single-connection transaction capability.

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
`XLDatabaseContractError` categories. The existing GRDB compatibility facade
keeps raw `DatabaseError` and `XLColumnReadError` values where its retry policy
and established decoding API need to inspect them; database and dialect
mismatches are still rejected before physical preparation in both paths.

## Cross-task raw-value execution

For cross-task raw-value execution with GRDB, call
`GRDBDatabase.prepareInvocation(with:)`. Its `GRDBPreparedInvocation` result is
`Sendable` and accepts an independent packet in `fetchAllValues`,
`fetchOneValues`, or `execute`. It deliberately returns normalized SQLite
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
  uncommitted writes.
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
`makeRequest(with:)` call alongside it in the same body.
