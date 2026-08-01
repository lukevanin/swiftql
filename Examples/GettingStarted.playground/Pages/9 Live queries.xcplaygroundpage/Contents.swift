/*:
 # Live queries

 [Previous: Transactions](@previous)

 Every query so far has answered a question once. A live query keeps answering
 it: `stream()` returns an async sequence that yields the current result set and
 then yields a fresh one whenever a relevant write commits.
 */

import Foundation
import SwiftQL
import SwiftQLExamples

let database = try ExampleDatabase.makeSeeded()

let engineersQuery = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.occupationId == "eng")
    OrderBy(person.id.ascending())
}
let engineersRequest = database.makeRequest(with: engineersQuery)

/*:
 ## Waiting for a stream on a page

 A playground page runs its top-level code to the end and then finishes, so a
 page that starts an observation and stops has nothing to show. It has to wait.

 How it waits matters. The GRDB adapter starts its observation with GRDB's
 default scheduling, which delivers on the main queue, so a page that blocks
 the main thread waiting for a snapshot deadlocks: the snapshot it is waiting
 for needs the thread it is holding. `runMainLoop(until:)` below drives the
 main run loop instead of blocking it, which lets those deliveries through.

 None of this is needed in an application, where an observation lives in a
 `Task` owned by a view model and nothing waits on the main thread.
 */
func runMainLoop(until finished: DispatchSemaphore, timeout: TimeInterval = 10) {
    let deadline = Date().addingTimeInterval(timeout)
    while finished.wait(timeout: .now()) == .timedOut, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

/*:
 ## Observing a result set

 A `for try await` loop over `stream()` is the whole API. Each iteration hands
 you a complete snapshot: the entire matching row set as of one committed
 transaction, never a partial one.

 The loop below takes two snapshots and stops. The first is the database as it
 stands. It then inserts a new engineer, and that commit is what produces the
 second.
 */
let finished = DispatchSemaphore(value: 0)

let observer = Task {
    var snapshots = 0
    do {
        for try await engineers in engineersRequest.stream() {
            snapshots += 1
            print("snapshot \(snapshots):", engineers.map(\.exampleSummary))

            if snapshots == 1 {
                let newHire = Person(id: "kit", occupationId: "eng", name: "Kit", age: 27)
                try database.makeRequest(with: sqlInsert(newHire)).execute()
            }
            else {
                break
            }
        }
    }
    catch {
        print("live query failed:", error)
    }
    finished.signal()
}

runMainLoop(until: finished)
observer.cancel()
/*:
 Prints:

 ```
 snapshot 1: ["Fred (31)", "Grace (29)"]
 snapshot 2: ["Fred (31)", "Grace (29)", "Kit (27)"]
 ```

 ## What the stream guarantees

 Constructing a stream performs no database work. The first `next()` call, which
 is what the first loop iteration does, starts the underlying GRDB observation
 and the first fetch. A stream that is never iterated never touches SQLite.

 Each `stream()` call creates one independent single-consumer observation, so
 two consumers that both want live updates call `stream()` twice.

 Fetching is all or nothing. If the query cannot execute, or any row cannot be
 decoded, iteration throws the original error rather than yielding a truncated
 result.

 The stream buffers at most one undelivered snapshot, and a newly produced
 snapshot replaces rather than queues behind one the consumer has not taken yet.
 A paused consumer therefore sees the newest state when it resumes rather than a
 backlog, and memory stays bounded however fast the writes arrive.

 Cancellation belongs to the consuming `Task`. Cancelling it ends iteration,
 with `next()` resolving to `nil` rather than throwing `CancellationError`, and
 tears down the observation and any pending retry backoff. Breaking out of the
 loop while another strong reference to the stream survives does not by itself
 cancel anything, which is why the page calls `observer.cancel()` above.

 Every delivered value is a complete committed snapshot. GRDB may coalesce
 several transactions into one, so do not read one delivery as one commit, and a
 rolled-back transaction never appears at all.
 */

/*:
 ## Observing a single row

 `streamOne()` is the same thing for a query that identifies at most one row. It
 yields `Person?`, so a row that stops matching shows up as `nil` rather than
 ending the stream.
 */
let fredRequest = database.makeRequest(with: sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred")
})

let oneFinished = DispatchSemaphore(value: 0)

let rowObserver = Task {
    var snapshots = 0
    do {
        for try await fred in fredRequest.streamOne() {
            snapshots += 1
            print("row \(snapshots):", fred?.exampleSummary ?? "no match")

            if snapshots == 1 {
                try database.makeRequest(with: sql { schema in
                    let person = schema.into(Person.self)
                    Update(person)
                    Setting(person) { row in
                        row.age = 32
                    }
                    Where(person.id == "fred")
                }).execute()
            }
            else {
                break
            }
        }
    }
    catch {
        print("live query failed:", error)
    }
    oneFinished.signal()
}

runMainLoop(until: oneFinished)
rowObserver.cancel()
/*:
 Prints:

 ```
 row 1: Fred (31)
 row 2: Fred (32)
 ```

 ## Where to go next

 `stream()` and `streamOne()` are the canonical live-query API. SwiftUI has two
 adapters over them: `XLQueryObserver` and `XLQueryRowObserver` for
 `ObservableObject` on iOS 16 and macOS 13, and `XLObservableQuery` and
 `XLObservableQueryRow` for `@Observable` on iOS 17 and macOS 14. Combine's
 `publish()` and `publishOne()` adapt the same source for existing Combine code.
 All of them share the buffering, retry, binding-capture, and cancellation
 contracts described above, so the choice is about what already structures the
 call site.

 The `LiveQueries` article covers the retry policy, observation semantics, and
 the full buffering contract. `Queries` covers joins, grouping, ordering,
 subqueries, and CTEs, and `AdvancedUsage` covers connections, statement
 preparation, row lifetime, and the full transaction contract.
 */
