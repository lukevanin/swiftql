---
title: "What's new in v1.5.5"
date: 2026-07-30
description: "SwiftQL v1.5.5 adds async live-query streams, an @Observable wrapper for SwiftUI, and a lazy single-pass result set, and rebuilds Combine's publish() as an adapter over the new streams."
---

SwiftQL v1.5.5 is the current latest release. It adds a `for try await`-based live-query API alongside the existing Combine one, an `@Observable` wrapper built on top of it for SwiftUI, and a lazy result set for stepping through large reads one row at a time. Combine's `publish()`/`publishOne()` keep their signatures but now run on top of the new streams instead of their own separate observation engine.

## Live queries through `for try await`

Earlier versions observed a changing query through Combine's `publish()`/`publishOne()` only. This release adds `stream()`/`stream(bindings:)` and `streamOne()`/`streamOne(bindings:)` to `XLRequest`, so the same observation is available as an `AsyncThrowingStream`:

```swift
let task = Task {
    do {
        for try await results in request.stream() {
            print("Fetched results: \(results)")
        }
    }
    catch {
        print("Query failed: \(error)")
    }
}
// Later, when results are no longer needed:
task.cancel()
```

`streamOne()` is the same shape for just the first row:

```swift
let task = Task {
    do {
        for try await result in request.streamOne() {
            print("Fetched result: \(String(describing: result))")
        }
    }
    catch {
        print("Query failed: \(error)")
    }
}
task.cancel()
```

Constructing a stream does no database work; only the first `next()` call — directly, or the first loop iteration of a `for try await` — starts the underlying GRDB observation. Cancelling the consuming `Task` ends iteration cleanly (`next()` resolves to `nil`, never a thrown `CancellationError`) and tears down the observation and any pending retry.

Both `stream()`/`streamOne()` and `publish()`/`publishOne()` now come from one shared source, `GRDBLiveQueryAsyncBridge`, built directly on GRDB's `ValueObservation.start`. Immutable-packet capture, retry, decoding, and buffering live there once, rather than being duplicated per adapter — `stream(bindings:)` and `publish(bindings:)` accept the same immutable `XLInvocationBindingPacket`.

The stream buffers at most one undelivered snapshot: a newly produced snapshot always replaces, never queues behind, one the consumer hasn't asked for yet, and resuming iteration delivers whatever GRDB already produced rather than forcing a fresh fetch. That "bound-1, newest wins" contract, and the alternatives considered and rejected, are written up in `<doc:LiveQueries>`, "Buffering and Resumed-Demand Semantics."

## `@Observable` live queries for SwiftUI

`XLObservableQuery`/`XLObservableQueryRow` wrap `stream()`/`streamOne()` as `@Observable` state, for SwiftUI clients on platforms that ship the `Observation` framework (`iOS 17`/`macOS 14`+):

```swift
@available(iOS 17, macOS 14, *)
struct PeopleListView: View {
    let people: XLObservableQuery<Person>

    var body: some View {
        List(people.rows, id: \.id) { person in
            Text(person.name)
        }
    }
}
```

Observation starts on initialization and stops when the instance is deallocated or `stop()` is called, whichever comes first. `rows`, `isLoading`, and `error` are applied on the main actor, so a view reads them directly with no extra synchronization. A terminal error leaves the last successfully observed `rows` in place and sets `error`, rather than clearing what's already on screen. This is additive: the package's existing iOS 16/macOS 13 floor is unchanged, and the type is compiled out entirely where `Observation` isn't available.

## A lazy, single-pass result set

`fetchAll()` decodes every matching row up front; `fetchOne()` decodes at most one. Between those, `withResultSet(_:)` now hands the callback an `XLResultSet<Row>` whose `next() throws -> Row?` steps and decodes exactly one row at a time:

```swift
try database.makeRequest(with: peopleNamedFredQuery).withResultSet { results in
    while let person = try results.next() {
        print(person.name)
    }
}
```

For a true streaming implementation (the ordinary, non-`RETURNING` case), no row is fetched or decoded before `operation` calls `next()` for it, so stopping early — an early `return`, `break`, or thrown error — means later rows are never stepped or decoded at all. `XLResultSet` is a reference type, not a `Sequence` or `Collection`: it's valid only for the duration of the `withResultSet(_:)` callback, and a reference retained past that point throws `XLResultSetError.closed` on every later `next()` instead of continuing to return rows. Unlike `fetchAll()`, a decode or SQLite error only ends iteration from that point forward — rows already returned by earlier `next()` calls stay valid.

Reach for `withResultSet(_:)` when a result may be large, the caller may stop before consuming every row, or decoding cost should scale with rows actually requested rather than total query cardinality. Reach for `fetchAll()` when every row is needed as a complete, retained array.

## Combine rebuilt on top of the new streams

`publish()`/`publishOne()`/`publishOne(bindings:)`/`publish(bindings:)` keep their existing public signatures, so no call site needs to change. Underneath, they're now a leaf adapter — `XLAsyncStreamPublisher` — that maps a subscriber's `Subscribers.Demand` onto a pull loop over a fresh `stream()`/`streamOne()` per subscription, instead of an independently implemented `ValueObservation`-backed engine. A real demand-accounting over-delivery bug found during that rebuild is fixed as part of this change.

## Migration

None required. `stream()`/`streamOne()`/`withResultSet(_:)`/`XLObservableQuery` are additive, and `publish()`/`publishOne()` keep their existing signatures and behavior.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.5.5 release](https://github.com/lukevanin/swiftql/releases/tag/v1.5.5)
