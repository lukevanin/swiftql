//
//  XLObservableLiveQuery.swift
//

// `canImport(Darwin)` excludes Linux even though `canImport(Observation)` alone is true there:
// swift-corelibs' `Observation` backport on the pinned Swift 5.9.2 Ubuntu cell fails at link time
// (`undefined reference to 'swift::threading::fatal'` in `libswiftObservation.so`), and `@Observable`
// is an Apple-platform SwiftUI convenience in any case -- this feature's `iOS 17, macOS 14`
// availability floor is meaningless on Linux, where the `*` in that availability list would otherwise
// make it unconditionally compiled and linked.
#if canImport(Observation) && canImport(Darwin)
import Observation
import Foundation


///
/// Observes SwiftQL's canonical async live-query source (`stream()`, issue #308) and republishes the
/// latest snapshot as Observation-native (`@Observable`) state, for SwiftUI clients on platforms that
/// ship the `Observation` framework.
///
/// This is a thin adapter, not a third observation engine: database observation, immutable-packet
/// capture, retry, decoding, and buffering (issue #291's bound-1 "newest wins" policy) all come from
/// the `AsyncThrowingStream` `stream()`/`stream(bindings:)` returns. This type owns only one
/// consumer `Task` per instance and the main-actor state that `Task` publishes into -- it never calls
/// `publish()`, never observes GRDB/`DatabasePool`/`NotificationCenter` directly, and never
/// reimplements retry, buffering, or binding-capture logic. See <doc:LiveQueries>, "SwiftUI /
/// Observation (issue #97)", for the full picture alongside the `for try await` and Combine surfaces.
///
/// ```swift
/// @available(iOS 17, macOS 14, *)
/// struct PeopleListView: View {
///     let people: XLObservableQuery<Person>
///
///     var body: some View {
///         List(people.rows, id: \.id) { person in
///             Text(person.name)
///         }
///     }
/// }
/// ```
///
/// Observation starts immediately on initialization -- exactly like `stream()`'s first `next()` call
/// starting the underlying GRDB observation as soon as this type's own consumer `Task` begins pulling
/// from it -- and stops deterministically when this instance is deallocated or ``stop()`` is called
/// explicitly, whichever happens first. Every result and error is applied to ``rows``/``isLoading``/
/// ``error`` on the main actor, so SwiftUI can read them directly from view code without extra
/// synchronization.
///
/// ``rows`` reflects the latest known state, not a commit log: a terminal error leaves the last
/// successfully observed ``rows`` in place and sets ``error``, mirroring `stream()`'s own "fetching is
/// all-or-nothing" contract -- no partial or truncated snapshot is ever applied.
///
@available(iOS 17, macOS 14, *)
@Observable
public final class XLObservableQuery<Row>: @unchecked Sendable {

    /// The most recently observed complete row set. Empty until the first snapshot (or a terminal
    /// error) has been applied.
    @MainActor
    public private(set) var rows: [Row] = []

    /// `true` until the first snapshot or terminal error has been applied; `false` afterward for the
    /// lifetime of this instance, even across later refreshes.
    @MainActor
    public private(set) var isLoading = true

    /// The stream's terminal error, if any. `stream()` fails atomically -- once this is set, no
    /// further snapshot follows for this instance.
    @MainActor
    public private(set) var error: Error?

    private var task: Task<Void, Never>?

    ///
    /// Starts observing `request` immediately: the `@Observable` analog of `request.stream()`.
    ///
    public init(_ request: any XLRequest<Row>) {
        start(stream: request.stream())
    }

    ///
    /// Starts observing `request` immediately, using one immutable packet captured once for the
    /// initial fetch and every refresh -- the `@Observable` analog of `request.stream(bindings:)`.
    ///
    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        start(stream: request.stream(bindings: bindings))
    }

    /// Cancels the underlying observation when this instance is released, exactly like dropping a
    /// Combine `Cancellable`: cancelling the owned consumer `Task` here reaches `stream()`'s own
    /// `withTaskCancellationHandler`-based cancellation (`GRDBLiveQueryAsyncBridge`), which tears down
    /// the GRDB observation and any pending retry backoff -- no further fetch happens afterward.
    deinit {
        task?.cancel()
    }

    ///
    /// Cancels the underlying observation deterministically, without waiting for deallocation. Safe to
    /// call more than once, and idempotent with the cancellation `deinit` performs automatically;
    /// useful when a view model needs to stop observing before it happens to be released.
    ///
    public func stop() {
        task?.cancel()
        task = nil
    }

    // A `Task { @MainActor in ... for try await rows in stream ... }` shape (tried in an earlier
    // iteration of this fix) does not actually avoid crossing an isolation boundary: the stream's own
    // `next()` is a nonisolated async function regardless of the Task's isolation, so pulling `[Row]`
    // (non-Sendable, since `Row` is unconstrained) out of it and into the `@MainActor` Task body is
    // itself flagged. Keeping the Task nonisolated (matching #451's original shape) is the narrower fix
    // that actually addresses the real crossing.
    //
    // Sending `rows` into `apply(rows:)` (`@MainActor`) needs some way to cross that boundary despite
    // `Row` being unconstrained. Two Swift 6.0+-only spellings were tried and both broke the pinned
    // Swift 5.9 cell's *parser* in ways `#if compiler(>=6.0)` does not protect against: a
    // `nonisolated(unsafe)` shadow nested inside this `for` loop ("consecutive statements... must be
    // separated by ';'"), and `sending` directly on `apply(rows:)`'s `[Row]` parameter ("array types are
    // now written with the brackets around the element type" -- 5.9's parser reads `sending` as an
    // unknown type name before the following `[Row]`, not as a modifier, and produces a confusing,
    // unrelated diagnostic). Both cases show declarations and deeply-nested statements get *parsed*
    // under Swift 5.9 even inside an inactive `#if compiler(>=6.0)` branch, not just lexically skipped.
    // A plain `@unchecked Sendable` box -- ordinary Swift since well before 5.9, no new syntax at all --
    // sidesteps the whole class of problem instead of fighting the parser further.
    private func start(stream: AsyncThrowingStream<[Row], Error>) {
        // Boxing `stream` too: `Task.init`'s own operation closure needed the same treatment as
        // `apply(rows:)` above -- capturing the raw, non-Sendable-typed `AsyncThrowingStream<[Row],
        // Error>` directly (even though the stream itself is unconditionally Sendable regardless of
        // its Element) still flagged the whole closure as "task-isolated ... strongly transferred" at
        // the point `Task { ... }` is constructed, since `stream` arrives as a plain, non-sending
        // parameter of this method. Capturing the box instead, and unwrapping only once already
        // running inside the Task, avoids the crossing needing any annotation at all.
        let box = StreamBox(stream: stream)
        task = Task { [weak self, box] in
            do {
                for try await rows in box.stream {
                    // Guards against applying a value that raced ahead of a concurrent `stop()` call
                    // or deallocation: `stream()`'s own cancellation contract already discards anything
                    // buffered but undelivered once cancelled (see `XLSingleSlotAsyncBuffer.cancel()`),
                    // but this instance's own `Task.isCancelled` is the most direct, local signal that
                    // no further state update should ever reach `rows`/`isLoading`/`error`.
                    if Task.isCancelled { return }
                    await self?.apply(RowsBox(rows: rows))
                }
            }
            catch {
                if !Task.isCancelled {
                    await self?.apply(ErrorBox(error: error))
                }
            }
        }
    }

    // See the note on start(stream:) above.
    private struct StreamBox: @unchecked Sendable {
        let stream: AsyncThrowingStream<[Row], Error>
    }

    private struct RowsBox: @unchecked Sendable {
        let rows: [Row]
    }

    private struct ErrorBox: @unchecked Sendable {
        let error: Error
    }

    @MainActor
    private func apply(_ box: RowsBox) {
        self.rows = box.rows
        self.isLoading = false
    }

    @MainActor
    private func apply(_ box: ErrorBox) {
        self.error = box.error
        self.isLoading = false
    }
}


///
/// Observes SwiftQL's canonical async live-query source for just the first row (`streamOne()`, issue
/// #308) and republishes it as Observation-native (`@Observable`) state, mirroring
/// ``XLObservableQuery`` for queries that return at most one row -- the `@Observable` analog of
/// `streamOne()`/`streamOne(bindings:)`, exactly as ``XLObservableQuery`` is the analog of
/// `stream()`/`stream(bindings:)`. See ``XLObservableQuery`` for the full lifecycle, cancellation, and
/// "latest known state, not a commit log" contract this type shares.
///
@available(iOS 17, macOS 14, *)
@Observable
public final class XLObservableQueryRow<Row>: @unchecked Sendable {

    /// The most recently observed first row, or `nil` if the query currently matches no row. A
    /// present `nil` is a real delivered snapshot, distinct from "nothing observed yet" -- use
    /// ``isLoading`` to tell them apart, exactly as `streamOne()`'s own `Row?` element does.
    @MainActor
    public private(set) var row: Row?

    /// `true` until the first snapshot or terminal error has been applied; `false` afterward for the
    /// lifetime of this instance, even across later refreshes.
    @MainActor
    public private(set) var isLoading = true

    /// The stream's terminal error, if any. `streamOne()` fails atomically -- once this is set, no
    /// further snapshot follows for this instance.
    @MainActor
    public private(set) var error: Error?

    private var task: Task<Void, Never>?

    ///
    /// Starts observing `request` immediately: the `@Observable` analog of `request.streamOne()`.
    ///
    public init(_ request: any XLRequest<Row>) {
        start(stream: request.streamOne())
    }

    ///
    /// Starts observing `request` immediately, using one immutable packet captured once for the
    /// initial fetch and every refresh -- the `@Observable` analog of `request.streamOne(bindings:)`.
    ///
    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        start(stream: request.streamOne(bindings: bindings))
    }

    /// See ``XLObservableQuery``'s `deinit` -- identical cancellation-ownership contract, applied to
    /// `streamOne()` instead of `stream()`.
    deinit {
        task?.cancel()
    }

    ///
    /// Cancels the underlying observation deterministically. See ``XLObservableQuery/stop()``.
    ///
    public func stop() {
        task?.cancel()
        task = nil
    }

    // See the matching note on XLObservableQuery.start(stream:) above.
    private func start(stream: AsyncThrowingStream<Row?, Error>) {
        let box = StreamBox(stream: stream)
        task = Task { [weak self, box] in
            do {
                for try await row in box.stream {
                    if Task.isCancelled { return }
                    await self?.apply(RowBox(row: row))
                }
            }
            catch {
                if !Task.isCancelled {
                    await self?.apply(ErrorBox(error: error))
                }
            }
        }
    }

    // See the note on XLObservableQuery.start(stream:) above.
    private struct StreamBox: @unchecked Sendable {
        let stream: AsyncThrowingStream<Row?, Error>
    }

    private struct RowBox: @unchecked Sendable {
        let row: Row?
    }

    private struct ErrorBox: @unchecked Sendable {
        let error: Error
    }

    @MainActor
    private func apply(_ box: RowBox) {
        self.row = box.row
        self.isLoading = false
    }

    @MainActor
    private func apply(_ box: ErrorBox) {
        self.error = box.error
        self.isLoading = false
    }
}
#endif
