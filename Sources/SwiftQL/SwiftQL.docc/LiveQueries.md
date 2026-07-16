# Live Queries

Use Combine publishers to observe query results as a database changes.

## Overview

SwiftQL requests expose `publish()` and `publishOne()` alongside their synchronous fetch methods.
With the GRDB adapter, each subscription starts a GRDB value observation and begins a fresh database
fetch. The observation then tracks the database region that the query actually reads.

### Combine

Use `publish()` to observe all rows returned by a request:

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

### Observation Semantics

GRDB-backed observations have these behaviors:

- Observation starts on subscription, not when `publish()` or `publishOne()` creates the publisher.
- Each subscriber owns an independent observation and receives a fresh initial value. A publisher does
  not replay a snapshot captured for an earlier subscriber.
- Relevant writes performed through the same `DatabasePool` are observed, including direct GRDB writes
  and migrations. Writes from another process or an unrelated connection pool are not observed.
- Initial and updated values are delivered asynchronously on the main dispatch queue by default. Apply
  Combine's `receive(on:)` operator when a consumer needs another serial queue.
- GRDB may coalesce transactions or emit consecutive equal values. Treat the stream as fresh database
  states, not as a log containing one event for every commit.
- Cancelling the subscription stops its observation. Execution or decoding errors terminate the stream
  with the original error; automatic retry or recovery is not performed.

Keep the returned cancellable alive for as long as results are needed, and cancel it when the consumer
no longer needs updates.
