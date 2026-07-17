# Live Queries

Use Combine publishers to observe query results as a database changes.

## Overview

SwiftQL requests expose `publish()` and `publishOne()` alongside their synchronous fetch methods.
With the GRDB adapter, each subscription starts a GRDB value observation and begins a fresh database
fetch. The observation then tracks the database region that the query actually reads.

### Combine

Use `publish()` to observe all rows returned by a request:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
let cancellable = request.publish().sink(
    receiveCompletion: { completion in
        if case .failure(let error) = completion {
            print("Query failed: \(error)")
        }
    },
    receiveValue: { results in
        print("Fetched results: \(results)")
    }
)
```

Use `publishOne()` to observe just the first result:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
let cancellable = request.publishOne().sink(
    receiveCompletion: { completion in
        if case .failure(let error) = completion {
            print("Query failed: \(error)")
        }
    },
    receiveValue: { result in
        print("Fetched result: \(String(describing: result))")
    }
)
```

Fetching is all-or-nothing. If the query cannot execute or any row cannot be decoded, the publisher
finishes with the original error and does not emit a truncated result.

### Packet-backed observations

A parameterized request exposes a static `parameterLayout`; its values belong
to an immutable packet supplied to `publish(bindings:)` or
`publishOne(bindings:)`. This observation selects one `Person` by its text ID:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
let idParameter = XLNamedBindingReference<String>(name: "id")
let personByID = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == idParameter)
}
let request = database.makeRequest(with: personByID)
let layout = request.parameterLayout
let idBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: layout,
    bindings: [
        try XLInvocationBinding(
            slot: layout.slot(for: .named("id"))!,
            value: .text("per-1")
        )
    ]
).validatingComplete()

let cancellable = request.publish(bindings: idBindings).sink(
    receiveCompletion: { completion in
        if case .failure(let error) = completion {
            print("Query failed: \(error)")
        }
    },
    receiveValue: { results in
        print("Fetched results: \(results)")
    }
)
```

SwiftQL validates and captures the packet when it constructs the GRDB
observation. Every initial fetch, database refresh, and BUSY retry for that
publisher uses the same values; the request is never mutated. A separately
constructed packet-backed publisher captures its own values without
cross-triggering or leaking values. A missing binding fails the publisher,
whereas `.null` is a present value and is accepted only for a nullable slot.
This packet isolation does not make the current request facade `Sendable` or
promise that one request can be shared directly across tasks.

### Retry Policy

Live queries are terminal by default. Configure a GRDB database or builder with
``GRDBLiveQueryRetryPolicy/retryBusy`` when an application should recover from transient SQLite
contention:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
let database = try GRDBDatabase(
    url: databaseURL,
    logger: nil,
    liveQueryRetryPolicy: .retryBusy
)
```

The retry preset starts a fresh GRDB value observation after delays of 0.1, 0.2, and 0.4 seconds,
for at most three additional attempts. The delays are deterministic, capped below one second, and
have no jitter. A successfully delivered value resets this consecutive retry budget.

Only a GRDB `DatabaseError` whose primary result code is `SQLITE_BUSY` is retried, including extended
BUSY result codes. `SQLITE_LOCKED`, query-decoding, schema, corruption, authorization, I/O,
interruption, and custom errors terminate immediately with the original error. Intermediate BUSY
errors are hidden; if the retry budget is exhausted, the publisher terminates once with the last
BUSY error.

Each subscriber owns its retry state. Retrying starts a new observation against the same configured
database pool, so GRDB discovers and tracks the query's database region again. Attempts do not
overlap. Cancelling during backoff cancels the pending delay and starts no new fetch; cancelling an
active observation suppresses later values even though SQLite work already executing internally may
finish. Writes committed during backoff may coalesce into the next snapshot because live queries are
state streams, not commit logs. For a packet-backed observation, starting that
new GRDB observation reuses the publisher's captured packet rather than reading
mutable values from the request or connection.

### Observation Semantics

GRDB-backed observations have these behaviors:

- Observation starts on subscription, not when `publish()` or `publishOne()` creates the publisher.
- Each subscriber owns an independent observation and receives a fresh initial value. A publisher does
  not replay a snapshot captured for an earlier subscriber.
- Parameterized publishers retain the immutable packet passed at construction;
  all refreshes and retries use that packet.
- Relevant writes performed through the same `DatabasePool` are observed, including direct GRDB writes
  and migrations. Writes from another process or an unrelated connection pool are not observed.
- Initial and updated values are delivered asynchronously on the main dispatch queue by default. Apply
  Combine's `receive(on:)` operator when a consumer needs another serial queue.
- GRDB may coalesce transactions or emit consecutive equal values. Treat the stream as fresh database
  states, not as a log containing one event for every commit.
- Cancelling the subscription stops its observation. With the default terminal policy, execution or
  decoding errors terminate the stream with the original error and no retry is performed.
- Writes from another process remain outside SwiftQL's live-query observation and retry guarantees.

Keep the returned cancellable alive for as long as results are needed, and cancel it when the consumer
no longer needs updates.
