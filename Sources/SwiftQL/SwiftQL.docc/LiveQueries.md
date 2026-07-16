# Live queries

Use Combine Publishers to observe changes to the database. 

## Overview

This guide shows how to use combine publishers with SwiftQL.

### Combine

We can create a Combine Publisher from a select query, which will publish a
result whenever any of the tables referenced in the query are modified by 
SwiftQL. Use `publish` to observe the results of a query:

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

We can use `publishOne` to publish just the first result a query:

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

The Combine Publisher will continue to publish results while a reference is held to the cancellable,
until it is cancelled or reaches a terminal completion or failure.
