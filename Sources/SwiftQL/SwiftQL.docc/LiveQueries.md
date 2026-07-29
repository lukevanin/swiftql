# Live Queries

Use Combine-compatible publishers to observe query results as a database changes.

## Overview

SwiftQL requests expose `publish()` and `publishOne()` alongside their synchronous fetch methods.
With the GRDB adapter, each subscriber's first positive demand starts a GRDB value observation and
begins a fresh database fetch. The observation then tracks the database region that the query
actually reads.

Apple platforms use Combine. Linux uses OpenCombine 0.14.0 and preserves the
same demand-driven GRDB observation, error, and cancellation contracts. Import
`Combine` or `OpenCombine` for the platform where the client is built.

### Combine-compatible publishers

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

### SwiftUI

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
demand-aware Combine adapter must both implement. It is a design record, not new public API — #308 and
#309 implement it.

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

### Async-to-Combine demand mapping (for #309)

Combine demand maps onto stream iteration through a small pull loop, not a second buffer:

- **Zero demand**: the adapter's internal consumer task must not call `next()` at all. It must not even
  start the underlying observation until the first unit of demand arrives — this preserves "subscribing
  with zero demand does not start SQLite work."
- **Incremental demand** (`request(.max(n))`): the consumer task calls `next()` exactly `n` times,
  delivering each result downstream and decrementing remaining demand by one per delivery, exactly like
  GRDB's own `ValueSubscription.request(_:)` accounting today. It never calls `next()` ahead of
  outstanding demand.
- **Unlimited demand**: the consumer task loops calling `next()` as fast as values become available,
  which in practice means it is rate-limited by the bounded buffer and GRDB's own write-driven fetch
  cadence — not by an unbounded read-ahead queue.
- **Demand added from `receive(_:)`**: additional demand returned from the downstream subscriber's
  `receive(_:)` simply increases the remaining-demand counter, which may resume a stalled pull loop; it
  does not need its own separate mechanism.
- **Cancellation**: cancelling the Combine subscription cancels the adapter's consumer `Task`, which — via
  the cancellation-ownership rule above — tears down the GRDB observation. The subscription must never
  emit after cancellation and must never turn cancellation into a `.failure` completion.

This reproduces the existing Combine demand contract's shape (a value that arrives with no demand
outstanding is effectively not delivered) while changing *what "not delivered" means*: today it means
"permanently dropped, gone"; under the new policy it means "held as the one buffered snapshot, and
delivered without needing to wait for one more relevant write, once demand resumes." That is the one
intentional behavior change from the current publisher contract — see Migration, below.

### Evidence

`Tests/SQLTests/LiveQueryBufferingSemanticsTests.swift` contains a throwaway, test-scoped prototype
(`LazyBufferedGRDBBridge`, `SingleSlotMailbox`, `DemandDrivenPuller` — none of this is production API)
built directly on GRDB's own `ValueObservation.start(in:scheduling:onError:onChange:)`, the same
primitive `GRDBLiveQueryRetryPolicy.swift` already uses for the Combine path. It exists only to produce
deterministic, real-GRDB evidence that this policy is implementable on the pinned Swift 5.9 / GRDB 6.29.3
toolchain, using bounded polling (not sleeps) for synchronization, matching the existing test suite's
style. Two properties of `AsyncThrowingStream<Element, Error>(unfolding:)` were verified empirically
against the pinned Swift toolchain (not assumed) before this design was finalized: constructing it
performs no work until the first `next()` call, and its `produce` closure is invoked exactly once per
consumer pull with no internal read-ahead — both required for the literal `AsyncThrowingStream` return
type to satisfy "observation begins with iteration."

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
isolation changes. The one intentional behavior change, once #309 lands:

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
  #308's actual production request/retry/binding-capture pipeline; #308 must still write its own
  integration tests once the real `stream()` methods exist, following the same bounded-polling style.
  This document's edge-case coverage should be treated as a checklist for that follow-up test suite, not
  a replacement for it.
- GRDB's own change-notification coalescing granularity (how many rapid writes collapse into one
  `ValueObservation` re-fetch) is not something SwiftQL controls or has committed to a specific number
  for; `testPausedConsumerWithRapidCommitsSeesOnlyTheNewestBoundedSnapshot` deliberately asserts only that
  resuming needs *far fewer* `next()` calls than there were writes, not an exact coalescing ratio, since
  that ratio can vary with scheduling and is not part of this contract.
- This decision does not address `XLResultSet` row-by-row cursors (#249) or the query-plan/index-advice
  work (#396) — it is scoped exclusively to whole-snapshot live-query streams.
