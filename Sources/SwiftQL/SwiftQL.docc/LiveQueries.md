# Live Queries

Observe query results as a database changes, through Swift structured concurrency or Combine.

## Overview

`stream()`/`streamOne()` (issue #308) are SwiftQL's canonical live-query API: a `for try await` loop
over the async stream they return is the single source of truth for observation, immutable-packet
capture, retry, decoding, and buffering. `publish()`/`publishOne()` (issue #309) are Combine
convenience adapters over that same canonical source — they exist to keep existing Combine clients
working, not as a second, independently-implemented observation engine. Both, along with their
synchronous fetch-method siblings, are exposed alongside each other on every `XLRequest`.

With the GRDB adapter, each subscriber's first positive demand — or each stream's first `next()`
call — starts a GRDB value observation and begins a fresh database fetch. The observation then
tracks the database region that the query actually reads.

Apple platforms use Combine. Linux uses OpenCombine 0.14.0 and preserves the
same demand-driven GRDB observation, error, and cancellation contracts. Import
`Combine` or `OpenCombine` for the platform where the client is built.

### Async live-query streams

`stream()` and `streamOne()` are the canonical live-query API: Swift structured concurrency is the
single source of truth for SwiftQL live-query snapshots, so a `for try await` loop observes the same
GRDB lifecycle, retry policy, and immutable-packet-capture contract that `publish()`/`publishOne()`
adapt below, without routing through Combine. Framework adapters — Combine's own demand-mapped
adapter (issue #309, below) and `@Observable` (issue #97) — build on this canonical source rather
than maintaining a parallel observation engine.

Use `stream()` to observe all rows returned by a request:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
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

Use `streamOne()` to observe just the first result:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
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

`stream(bindings:)` and `streamOne(bindings:)` accept the same immutable `XLInvocationBindingPacket`
as `publish(bindings:)`/`publishOne(bindings:)`: the packet is captured and validated once, and every
initial fetch, refresh, and retry reuses it. See "Packet-backed observations" below for a full
worked example.

Fetching remains all-or-nothing: if the query cannot execute or any row cannot be decoded, iteration
throws the original error and does not yield a truncated result — exactly like `publish()`/
`publishOne()` finishing with the original error instead of a partial result. Constructing a stream
performs no database work; only its first `next()` call (directly, or the first loop iteration of a
`for try await`) starts the underlying GRDB observation. Each `stream()`/`streamOne()` call creates
one independent, single-consumer observation, exactly like each `publish()` call creates one
independent Combine subscription — two consumers that both want live updates must call `stream()`
twice.

Cancellation is owned by `Task` cancellation reaching a suspended `next()` call: cancelling the
consuming `Task` ends iteration — `next()` resolves to `nil`, never a thrown `CancellationError` —
and tears down the underlying GRDB observation and any pending retry backoff. This mirrors how
cancelling a Combine subscription never delivers a `.failure` completion. Breaking out of a
`for await` loop while another strong reference to the stream survives does not, by itself, cancel
anything.

The stream buffers at most one undelivered snapshot: a newly produced snapshot always replaces,
never queues behind, a snapshot the consumer has not yet asked for, and resuming iteration delivers
whatever has already been produced rather than forcing a fresh fetch. See "Buffering and
Resumed-Demand Semantics (#291)" below for the full contract `stream()`/`streamOne()` implement.

Async consumers resume per ordinary Swift concurrency scheduling — there is no async analog of
Combine's main-queue delivery default. A framework adapter that needs a specific delivery guarantee
(e.g. main-thread delivery for SwiftUI) implements that guarantee itself on top of this canonical
source; it is not a property of `stream()`/`streamOne()`.

``XLRequest`` is a public protocol with external conformers. `stream()`/`streamOne()` (and their
bindings variants) have a source-compatible default implemented in terms of `publish()`/
`publishOne()`, so an existing third-party conformer that only implements the Combine surface keeps
compiling and still starts its underlying work lazily. `GRDBRequest` overrides this default with a
true async-native GRDB observation source that never routes through Combine.

`stream()`/`streamOne()` observe complete live-query snapshots — the entire matching row set (or its
first row) as of one committed transaction — and are distinct from `XLResultSet`'s row-by-row lazy
cursor (issue #249): a result set decodes one already-fetched, static result page lazily and once,
while a live-query stream re-observes the database and can yield many snapshots over its lifetime.

### Packet-backed observations

A parameterized request exposes a static `parameterLayout`; its values belong
to an immutable packet supplied to `stream(bindings:)`/`streamOne(bindings:)` or their Combine
analogs, `publish(bindings:)`/`publishOne(bindings:)`. This observation selects one `Person` by its
text ID:

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
```

The async call site:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
for try await results in request.stream(bindings: idBindings) {
    print("Fetched results: \(results)")
}
```

The Combine call site:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
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
stream or publisher uses the same values; the request is never mutated. A separately
constructed packet-backed stream or publisher captures its own values without
cross-triggering or leaking values. A missing binding fails the observation,
whereas `.null` is a present value and is accepted only for a nullable slot.
This packet isolation does not make the current request facade `Sendable` or
promise that one request can be shared directly across tasks.

### Combine-compatible publishers (a convenience adapter over streams, issue #309)

`publish()`/`publishOne()` are Combine convenience adapters over `stream()`/`streamOne()`: Combine
owns only subscription, demand accounting, delivery, completion, and cancellation adaptation.
Database observation, immutable-packet capture, retry, decoding, and buffering all come from the
canonical async stream above — a fresh stream is constructed and iterated by an internal
demand-gated pull loop for every subscriber, so two subscriptions never share one stream, iterator,
retry budget, or buffered snapshot. Values are delivered on the main dispatch queue by default (see
"Observation Semantics" below), matching the pre-#309 behavior exactly.

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

### SwiftUI (`ObservableObject`, Combine-backed)

``XLQueryObserver`` and ``XLQueryRowObserver`` wrap `publish()`/`publishOne()`
as `ObservableObject`s, so a view model can adopt a live query directly with
`@StateObject`/`@ObservedObject` instead of managing a `Cancellable` by hand:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
final class PeopleListModel: ObservableObject {
    let people: XLQueryObserver<Person>

    init(database: some XLDatabase, query: some XLQueryStatement<Person>) {
        people = XLQueryObserver(database.makeRequest(with: query))
    }
}
```

A SwiftUI view reads `people.rows` and `people.error` in its `body`; both are
`@Published`, so the view re-renders whenever either changes. Observation
starts immediately on initialization and stops when the observer is
deallocated — the same demand, transaction, and cancellation semantics
described below apply, since both types subscribe through the same
`publish()`/`publishOne()` publishers.

### SwiftUI (`@Observable`, issue #97)

``XLObservableQuery`` and ``XLObservableQueryRow`` are a third, independent live-query consumption
surface, for platforms that ship Swift's `Observation` framework. They are availability-gated with
`@available(iOS 17, macOS 14, *)` — verified empirically against this package's pinned toolchains,
not guessed — while every other SwiftQL API, including ``XLQueryObserver``/``XLQueryRowObserver``
above, keeps compiling and working unchanged down to the package's iOS 16 / macOS 13 floor.

Like ``XLQueryObserver``/``XLQueryRowObserver``, these types own only model/task lifecycle and
main-actor state updates — they are a thin adapter, not a third observation engine. Unlike those
Combine-backed wrappers, they consume `stream()`/`streamOne()` (issue #308) directly through one
owned `for try await` `Task` per instance; they never call `publish()`/`publishOne()` and never
observe GRDB, `DatabasePool`, or `NotificationCenter` directly:

<!-- test: XLDocumentationTests.testDocumentationLiveQueryPublishers -->
```swift
@available(iOS 17, macOS 14, *)
@Observable
final class PeopleListModel {
    let people: XLObservableQuery<Person>

    init(database: some XLDatabase, query: some XLQueryStatement<Person>) {
        people = XLObservableQuery(database.makeRequest(with: query))
    }
}
```

A SwiftUI view reads `people.rows`, `people.isLoading`, and `people.error` directly in its `body`; the
`@Observable` macro tracks each property access, so the view re-renders whenever any of them changes —
no `@Published`/`@ObservedObject`/`@StateObject` annotations are needed. Observation starts immediately
on initialization, exactly like ``XLQueryObserver``, and stops deterministically when the instance is
released (`deinit` cancels the owned `Task`, tearing down the underlying observation) or when
``XLObservableQuery/stop()``/``XLObservableQueryRow/stop()`` is called explicitly, whichever happens
first. Every snapshot and terminal error is applied to `rows`/`row`/`isLoading`/`error` on the main
actor, so view code needs no additional synchronization to read them. `rows`/`row` reflect the latest
known state, not a commit log: a terminal error leaves the last successfully observed value in place
and sets `error`, mirroring `stream()`/`streamOne()`'s own "fetching is all-or-nothing" contract — no
partial or truncated snapshot is ever applied. Binding replacement (a new immutable
`XLInvocationBindingPacket`) is a new model instance, exactly as a new `stream(bindings:)` call is a new
independent observation: neither type mutates its packet after construction.

Choosing among the three live-query consumption surfaces — structured concurrency, `@Observable`, and
Combine — is a matter of what already structures the call site, not different database semantics: all
three are adapters over the same `stream()`/`streamOne()` source and share identical buffering (#291),
retry, binding-capture, and cancellation contracts.

| Surface | Use when |
| --- | --- |
| `for try await` over `stream()`/`streamOne()` | Already inside `async` code (a `Task`, an `actor`, a background pipeline) with no UI framework to satisfy. |
| ``XLQueryObserver``/``XLQueryRowObserver`` (`ObservableObject`) | SwiftUI (or UIKit/AppKit via Combine) targeting iOS 16 / macOS 13, or a codebase already standardized on Combine. |
| ``XLObservableQuery``/``XLObservableQueryRow`` (`@Observable`) | SwiftUI targeting iOS 17 / macOS 14 or later, wanting Observation-native property tracking instead of `@Published`. |

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

- Observation starts when a subscriber first requests positive demand, not when `publish()` or
  `publishOne()` creates the publisher. Subscribing with zero demand does not start SQLite work.
- Each subscriber owns an independent observation and receives a fresh initial value. A publisher does
  not replay a snapshot captured for an earlier subscriber.
- Combine demand is a delivery bound. Finite demand limits the number of snapshots delivered, and
  values received by the publisher with no outstanding demand are dropped. Fetching and main-queue
  delivery are asynchronous, however, so a snapshot already in flight can consume demand requested
  later. Do not treat a new demand request as a "fetch latest" operation; keep demand outstanding for
  a later relevant commit when the consumer needs a current durable snapshot.
- Parameterized publishers retain the immutable packet passed at construction;
  all refreshes and retries use that packet.
- Relevant writes performed through the same `DatabasePool` are observed, including direct GRDB
  writes and migrations. A transaction with multiple relevant writes exposes a committed state, not
  each intermediate write. A rolled-back transaction never appears as durable observed state, and a
  write outside the query's tracked region does not expose a changed snapshot.
- Every delivered value is a complete committed snapshot. GRDB may coalesce multiple transactions or
  emit consecutive equal snapshots, so do not interpret one delivery as one commit.
- A write through another process or another `DatabasePool` does not trigger this observation, even
  when it targets the same SQLite file. Once that external write is durable, a later relevant commit
  through the observed pool can trigger a fetch whose snapshot includes the externally committed
  state.
- Initial and updated values are delivered asynchronously on the main dispatch queue by default. Apply
  Combine's `receive(on:)` operator when a consumer needs another serial queue.
- Cancelling the subscription stops future delivery. Cancellation cannot synchronously interrupt an
  SQLite call already in flight, but the value or completion from that work is suppressed after
  cancellation.
- The demand, transaction, and cancellation rules do not change the configured retry policy. With the
  default terminal policy, execution or decoding errors terminate the stream with the original error
  and no retry is performed; ``GRDBLiveQueryRetryPolicy/retryBusy`` still retries only qualifying BUSY
  errors with the delays and limit described above.

Keep the returned cancellable alive for as long as results are needed, and cancel it when the consumer
no longer needs updates.

## Buffering and Resumed-Demand Semantics (#291)

This section records the decision required by
[issue #291](https://github.com/lukevanin/swiftql/issues/291): the buffering, cancellation, and
snapshot-ownership contract that #308's canonical `AsyncThrowingStream` live-query source and #309's
demand-aware Combine adapter must both implement. It originated as a design record, not new public
API; #308's `stream()`/`streamOne()` above have since implemented it, and #309 will adapt Combine to
the same policy.

### Why this needed a decision

[Issue #255](https://github.com/lukevanin/swiftql/issues/255)'s repeated-stress contract
(`Tests/SQLTests/SQLPublisherTests.swift`, `testIncrementalDemandBoundsDeliveryUntilLaterCommitReachesCurrentState`)
demonstrated that an observed-table refresh can already be in flight after Combine demand is exhausted.
If demand is replenished before that refresh reaches the subscription, the intermediate durable snapshot
consumes the new demand, and a later commit then needs another unit of demand. That is not a bug in the
current Combine publisher; it is the documented, deliberate behavior described above under "Observation
Semantics" ("Do not treat a new demand request as a 'fetch latest' operation"). But it also means the
current Combine publisher retains **zero** buffered state: a value that cannot be delivered because
demand is exhausted is simply dropped, not held. The pinned GRDB dependency's own async observation API
(`ValueObservation.values(in:bufferingPolicy:)`) defaults `bufferingPolicy` to `.unbounded` — an
unreviewed default SwiftQL must not silently inherit for its own canonical stream.

### Decision

**SwiftQL's canonical live-query stream buffers at most one snapshot, and a newly produced snapshot
always replaces (never queues behind) a snapshot that has not yet been delivered.** This is GRDB's own
`AsyncThrowingStream.Continuation.BufferingPolicy.bufferingNewest(1)` semantics, applied consistently
whether the eventual consumer is a `for try await` loop or a Combine subscriber pulling through #309's
adapter. Concretely:

- A stream never holds more than one undelivered snapshot in memory, regardless of write rate or how
  long a consumer pauses.
- A snapshot the consumer has not yet asked for is never lost while there is still a chance to deliver
  a more current one: if two relevant commits happen while the consumer is paused, the second snapshot
  replaces the first, and the consumer sees the newer one when it resumes.
- Resuming iteration (or resuming Combine demand) delivers whatever the bridge has already produced — it
  does not itself force a brand-new fetch of "the literal latest row," and it does not guarantee the
  single freshest possible state if a write races the delivery. This preserves, rather than changes, the
  existing Combine contract's warning against treating "new demand" as "fetch latest."
- The database-state semantics are identical for async and Combine consumers: both are fed by the same
  bounded, newest-wins buffer. Only how each adapter turns "a value is available" into delivery (await
  vs. Combine demand accounting) differs.

#### Alternatives considered and rejected

| Policy | Verdict | Why |
| --- | --- | --- |
| Unbounded buffer (GRDB's own `.values` default) | Rejected | Memory grows without bound under a slow/paused consumer plus rapid writes — exactly the risk flagged by the #290 evidence. Turns the stream into a de facto commit log, which the issue explicitly forbids. |
| No buffering at all (current Combine behavior: drop when no demand, hold nothing) | Rejected as the *sole* policy, kept as an accurate description of today's Combine publisher | Correct and bounded, but wasteful: GRDB already did the fetch work, and a resumed consumer must wait for the *next* write to see state it could have had immediately. Does not optimize for "current-state usefulness" the way the issue asks. |
| A larger fixed bound (e.g. `bufferingNewest(4)`) | Rejected | Buffered live-query snapshots are *state*, not *events*; delivering several stale intermediate snapshots to a resumed consumer misrepresents a state stream as a commit log and does not serve any consumer need "current-state usefulness" doesn't already cover. Memory scales with the bound for no compensating benefit. |
| Explicit drop-at-fetch-boundary (only one fetch in flight; further relevant-write notifications while a fetch is running are coalesced independent of consumer demand) | Subsumed | This describes GRDB's *own* internal change-coalescing (verified empirically below — it is not exactly one-fetch-per-write), which SwiftQL does not control and should not try to redefine. `bufferingNewest(1)` is the correctly-scoped SwiftQL-owned policy that sits on top of whatever coalescing granularity GRDB's tracking layer already provides. |
| `bufferingNewest(1)` (selected) | **Accepted** | Bounded to O(1) regardless of write rate or pause duration; always exposes the newest known state on resume; verified implementable and correctly bounded against real GRDB (see Evidence, below); does not change database-state semantics between async and Combine consumers. |

### Snapshot lifecycle state machine

```text
                     first next() / first iteration
                                  |
                                  v
  [not started] --------------------------------------> [observing]
       |                                                    |  |
       | (stream constructed, never iterated)               |  | onChange(value)
       | -> deinit, no GRDB work ever performed              |  v
       |                                                     |  [fetched] --yield--> mailbox holds
       |                                                     |                        exactly 0 or 1
       |                                                     |                        undelivered
       |                                                     |                        snapshot
       |                                                     |
       | cancel() / consuming Task cancelled                 | onError(error)
       v                                                      v
  [terminated: cancelled]                             [terminated: failed]
       |                                                      |
       +--------------------- next() resolves to ----------- +
                  nil (cancelled)     |      throws original error (failed)
                                      v
                           no further onChange/onError is delivered;
                           the GRDB observation and any pending retry
                           backoff are torn down exactly once.
```

Lifecycle points, precisely:

- **Fetched**: GRDB's `ValueObservation` computed a value from a relevant commit (or the initial
  current-state fetch). This always happens, on every relevant write, independent of consumer demand —
  SwiftQL does not and cannot pause GRDB's own tracking short of cancelling the whole observation.
- **Yielded**: the fetched value is handed to the buffer. If nothing is waiting, it becomes the single
  buffered snapshot, replacing whatever was buffered before.
- **Buffered**: at most one snapshot, held only until either a consumer takes it or a newer one replaces
  it.
- **Requested**: a consumer calls `next()` (directly, via `for try await`, or via #309's demand-mapped
  pull). This never itself triggers a new GRDB fetch; it only asks for whatever the buffer already has,
  suspending if nothing is buffered yet.
- **Delivered**: the buffered snapshot (or a value produced synchronously enough to skip buffering) is
  returned from `next()`.
- **Superseded**: a buffered-but-undelivered snapshot is discarded because a newer one replaced it. This
  is the only form of "dropping" in the new policy, and it only ever discards a snapshot that was never
  delivered to any consumer.
- **Cancelled**: the consuming `Task` is cancelled, or the bridge's cancellation is invoked explicitly.
  `next()` resolves to `nil` (a normal end of iteration), never a thrown `CancellationError` and never a
  completion failure — this matches how cancelling a Combine subscription today never delivers a
  `.failure` completion.

### Does resuming trigger a fresh fetch?

**No.** Requesting demand again (Combine) or calling `next()` again (async) only asks for whatever GRDB
has already produced. It does not force GRDB to re-run the query. The only work that unconditionally
happens on every relevant commit is GRDB's own tracking/fetch, which runs independent of whether any
consumer is currently asking for values. This is unchanged from today's Combine contract and is
deliberately **not** strengthened into "resuming fetches the latest state," per the issue's explicit
hard constraint.

### Single-consumer behavior and an unused stream

Each `stream()` (and `streamOne()`) call creates one independent observation with its own single-slot
buffer — exactly like each `publish()` call today creates one independent Combine subscription. Two
consumers that both want live updates must call `stream()` twice; iterating the same `AsyncThrowingStream`
value with two concurrent loops is not a supported fan-out (Swift's `AsyncThrowingStream` itself does not
guarantee fan-out semantics — concurrent iterators race over one shared buffer). Constructing a stream
value and never iterating it must perform no SQLite work: the GRDB observation starts only inside the
first `next()` call, mirroring "subscribing with zero demand does not start SQLite work" for Combine.

### Cancellation ownership

Cancellation is owned by **`Task` cancellation reaching the suspended `next()` call**, not by merely
breaking out of a `for await` loop while other strong references to the stream remain alive (breaking a
loop, by itself, does not cancel anything — the underlying resources stay live until nothing references
them). Concretely, for #308's implementation:

- `AsyncThrowingStream<Element, Error>`'s `unfolding:` initializer (the one that produces the literal
  return type #308's methods must expose) has **no separate `onCancel` parameter** — that parameter only
  exists on `AsyncStream`. Cancellation-awareness must live inside the `produce` closure itself, by
  wrapping its suspension point in `withTaskCancellationHandler(operation:onCancel:)`.
- A plain `withCheckedThrowingContinuation` is **not** automatically cancellation-aware; without an
  explicit `withTaskCancellationHandler`, a suspended `next()` call would simply never resume, and the
  underlying GRDB observation would keep running indefinitely.
- #308's retry integration must reuse `GRDBLiveQueryRetryPolicy.swift`'s existing generation-counter
  cancellation-ownership design (`GRDBLiveQueryRetryState`), retargeted to feed the stream's buffer
  instead of a Combine `AnyPublisher`. Cancelling the bridge must both end the buffer (so a suspended or
  future `next()` resolves to `nil`) and cancel the underlying GRDB `AnyDatabaseCancellable`, so no further
  fetch, retry backoff, or delivery occurs after cancellation.

### Async-to-Combine demand mapping (issue #309)

`publish()`/`publishOne()` map Combine demand onto stream iteration through a small pull loop, not a
second buffer. This is implemented by `XLAsyncStreamPublisher`/`XLAsyncStreamSubscription`
(`Sources/SwiftQL/XLAsyncStreamPublisher.swift`), which `xlLiveQueryPublisher(makeStream:)` wraps with
the main-queue delivery default:

- **Zero demand**: the adapter's internal consumer `Task` is not started at all. It does not start
  until the first unit of demand arrives — this preserves "subscribing with zero demand does not start
  SQLite work."
- **Incremental demand** (`request(.max(n))`): the consumer task calls `next()` exactly `n` times,
  delivering each result downstream and decrementing remaining demand by one per delivery, exactly like
  GRDB's own `ValueSubscription.request(_:)` accounting. It never calls `next()` ahead of outstanding
  demand.
- **Unlimited demand**: the consumer task loops calling `next()` as fast as values become available,
  which in practice means it is rate-limited by the stream's own bounded buffer and GRDB's write-driven
  fetch cadence — not by an unbounded read-ahead queue on top.
- **Demand added from `receive(_:)`**: additional demand returned from the downstream subscriber's
  `receive(_:)` simply increases the remaining-demand counter, which may resume a stalled pull loop; it
  has no separate mechanism.
- **Cancellation**: cancelling the Combine subscription cancels the adapter's consumer `Task`, which —
  via the cancellation-ownership rule above — tears down the underlying observation. The subscription
  never emits after cancellation and never turns cancellation into a `.failure` completion: it tracks
  whether its own `cancel()` caused the stream to end and suppresses exactly that self-inflicted
  completion, without suppressing or delaying delivery of a value the stream legitimately produced and
  buffered before cancellation happened (that value is still simply never forwarded once `cancel()` has
  been called, per Combine's own "nothing after cancel()" contract — a different, simpler rule than the
  stream's own buffering guarantee above).

This reproduces the existing Combine demand contract's shape (a value that arrives with no demand
outstanding is effectively not delivered) while changing *what "not delivered" means*: today it means
"permanently dropped, gone"; under the new policy it means "held as the one buffered snapshot, and
delivered without needing to wait for one more relevant write, once demand resumes." That is the one
intentional behavior change from the pre-#309 publisher contract — see Migration, below.

### Evidence

`Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift` contains a throwaway, test-scoped prototype
(`LazyBufferedGRDBBridge`, `SingleSlotMailbox`, `DemandDrivenPuller` — none of this is production API)
built directly on GRDB's own `ValueObservation.start(in:scheduling:onError:onChange:)` -- at the time
this prototype was written, the same primitive `GRDBSQLDatabase.swift`'s pre-#309 `publisher(fetch:)`
helper called for the OpenCombine path, with retry supplied by `GRDBLiveQueryRetryPolicy.swift`'s
`makeGRDBLiveQueryRetryPublisher` wrapping that source. Both were removed once #309 rebuilt
`publish()`/`publishOne()` as adapters over `stream()`/`streamOne()`, which reuse the same
`ValueObservation.start` primitive through `GRDBLiveQueryAsyncBridge` instead. The prototype exists
only to produce deterministic, real-GRDB evidence that this policy is implementable on the pinned
Swift 5.9 / GRDB 6.29.3 toolchain, using bounded polling (not sleeps) for synchronization, matching the
existing test suite's style. Two properties of `AsyncThrowingStream<Element, Error>(unfolding:)` were
verified empirically against the pinned Swift toolchain (not assumed) before this design was
finalized: constructing it performs no work until the first `next()` call, and its `produce` closure is
invoked exactly once per consumer pull with no internal read-ahead — both required for the literal
`AsyncThrowingStream` return type to satisfy "observation begins with iteration."

| Edge case | Test oracle |
| --- | --- |
| Unused stream | `LiveQueryBufferingSemanticsTests.testUnusedStreamPerformsNoFetch` |
| Slow/paused async consumer, rapid commits, in-flight fetch, buffer replacement | `LiveQueryBufferingSemanticsTests.testPausedConsumerWithRapidCommitsSeesOnlyTheNewestBoundedSnapshot` |
| Resumed iteration does not itself trigger a fetch | `LiveQueryBufferingSemanticsTests.testResumingIterationDoesNotItselfStartASecondObservationOrForceAFetch` |
| Cancellation (explicit) | `LiveQueryBufferingSemanticsTests.testExplicitCancelStopsDeliveryAndTearsDownTheUnderlyingObservation` |
| Cancellation (consuming `Task`, via the literal `AsyncThrowingStream` type) | `LiveQueryBufferingSemanticsTests.testCancellingTheConsumingTaskCancelsTheUnderlyingObservation` |
| Terminal error, delivered exactly once | `LiveQueryBufferingSemanticsTests.testTerminalErrorIsForwardedExactlyOnceThroughTheBridge` |
| Two consumers from separate calls; independent databases/streams | `LiveQueryBufferingSemanticsTests.testTwoIndependentBridgesDoNotShareBufferedStateOrCrossTrigger` |
| Zero demand, incremental demand | `LiveQueryBufferingSemanticsTests.testDemandDrivenPullerConsumesExactlyDemandedCountWithoutEagerDraining` |
| Unlimited demand | `LiveQueryBufferingSemanticsTests.testUnlimitedDemandDeliversAsValuesBecomeAvailableWithoutSpinningOrDoubleDelivery` |
| Cancellation during fetch/backoff, retry, consecutive-equal-snapshot, transaction coalescing, rollback exclusion, immutable-binding capture, cross-database isolation | Already covered by the existing #255 stress contract and are **unchanged** by this decision: `Tests/SQLTests/GRDBLiveQueryRetryTests.swift` (`testCancellationDuringBackoffStartsNoLaterAttemptOrCallback`, `testEachSubscriberOwnsAnIndependentRetryBudget`, `testRealGRDBObservationRecoversFromInjectedBusyAndKeepsObserving`) and `Tests/SQLTests/SQLPublisherTests.swift` (`testMultipleWritesInOneTransactionPublishOnlyDurableState`, `testRolledBackWriteNeverAppearsBeforeCommittedLiveness`, `testDistinctDatabasePoolsDoNotCrossTrigger`, `testIrrelevantTableWriteDoesNotChangeObservedSnapshot`) |

### Migration guidance

Nothing about `publish()`/`publishOne()`'s public signatures, subscription-time behavior, fresh-initial-
value guarantee, main-queue delivery default, retry policy, transaction coalescing, or cross-database
isolation changed when #309 rebuilt them as adapters over `stream()`/`streamOne()`. The one intentional
behavior change:

- **Before**: a value computed while a Combine subscriber had zero outstanding demand was dropped
  permanently. The subscriber would not see that state until another *relevant write* happened after
  demand was replenished.
- **After**: that value is retained as the single buffered snapshot. Once demand is replenished, the
  subscriber sees it immediately — without needing to wait for a further write.
- **Who is affected**: only consumers that relied on the old drop-everything behavior to mean "resuming
  demand never reveals state that existed before I requested more" — that was never a documented
  guarantee, and the existing documentation already warns against depending on demand timing to infer
  freshness. No source changes are required; no client can newly observe *stale* data it could not see
  before, only *current* data slightly sooner.

### Remaining limitations

- The evidence above validates the bridge design against a raw GRDB `ValueObservation`, not against
  #308's actual production request/retry/binding-capture pipeline. `Tests/SQLTests/GRDBLiveQueryAsyncStreamTests.swift`
  is that follow-up suite: it drives the real `stream()`/`streamOne()` methods against temporary GRDB
  databases, using the same bounded-polling style, and covers every edge case in the table above plus
  the immutable-packet-capture and cross-database-isolation contracts specific to the production
  request pipeline. `Tests/SQLTests/XLAsyncStreamPublisherTests.swift` is the equivalent follow-up
  suite for #309's Combine adapter: it drives `XLAsyncStreamPublisher` against hand-controlled,
  GRDB-independent streams to prove the demand-mapping and cancellation-vs-completion contract
  deterministically, while `Tests/SQLTests/SQLPublisherTests.swift` and
  `Tests/SQLTests/GRDBLiveQueryRetryTests.swift` prove the same `publish()`/`publishOne()` contract
  end-to-end against a real GRDB database.
- GRDB's own change-notification coalescing granularity (how many rapid writes collapse into one
  `ValueObservation` re-fetch) is not something SwiftQL controls or has committed to a specific number
  for; `testPausedConsumerWithRapidCommitsSeesOnlyTheNewestBoundedSnapshot` deliberately asserts only that
  resuming needs *far fewer* `next()` calls than there were writes, not an exact coalescing ratio, since
  that ratio can vary with scheduling and is not part of this contract.
- This decision does not address `XLResultSet` row-by-row cursors (#249) or the query-plan/index-advice
  work (#396) — it is scoped exclusively to whole-snapshot live-query streams.
- `Tests/SQLTests/XLObservableLiveQueryTests.swift` is #97's follow-up suite: it drives
  ``XLObservableQuery``/``XLObservableQueryRow`` against real, temporary GRDB databases to prove
  initial delivery, refresh, a terminal error leaving `rows`/`row` untouched, main-actor state
  application, cancellation before the first value, a released instance's owned `Task` performing no
  further work (via a probe independent of the deallocated instance), binding replacement by
  constructing a new instance, and two instances observing independent databases without
  cross-triggering. The `@available(iOS 17, macOS 14, *)` gate was verified empirically — compiling
  `@Observable` against a pre-macOS-14 deployment target fails with "'Observable()' is only available
  in macOS 14.0 or newer" — rather than assumed from documentation alone.
