# Live queries with SwiftQL

## Overview

This guide shows how to use combine publishers with SwiftQL.

### Combine

We can create a Combine Publisher from a select query, which will publish a
result whenever any of the tables referenced in the query are modified by 
SwiftQL. Use `publish` to observe the results of a query:

```swift
let cancellable = request.publish().sink { [weak self] results in
    print("Fetched results: \(results")
}
```

We can use `publishOne` to publish just the first result a query:

```swift
let cancellable = request.publishOne().sink { [weak self] result in
    print("Fetched result: \(result")
}
```
 
The Combine Publisher will continue to publish results as long as a reference is
held to the cancellable.
