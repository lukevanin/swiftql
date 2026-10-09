//
//  XLPublisherAsyncBridge.swift
//
//  The publisher-to-stream bridge: how a request adapter that only has a
//  Combine publisher implements the live-query stream members (issue #684).
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


///
/// Bridges a Combine publisher into a lazily started, single-consumer
/// `AsyncThrowingStream`, so an ``XLRequest`` adapter that only has a
/// publisher can implement each live-query stream member in one line
/// (issue #684):
///
/// ```swift
/// func stream() -> AsyncThrowingStream<[Row], Error> {
///     XLPublisherAsyncBridge(makePublisher: { self.makeRowsPublisher() }).stream()
/// }
/// ```
///
/// The returned stream follows the live-query stream contract that
/// ``XLRequest/stream()`` states:
///
/// - Observation begins with iteration. Neither creating the bridge nor
///   calling ``stream()`` calls `makePublisher`. The first `next()` call
///   calls it once and subscribes, with unlimited demand.
/// - The stream buffers at most one undelivered value. A newer value replaces
///   one the consumer has not yet asked for. See "Live Queries" in SwiftQL's documentation,
///   "Buffering and Resumed-Demand Semantics (#291)".
/// - A failure completion throws its error from `next()`, and a finished
///   completion ends iteration.
/// - Cancelling the consuming task ends iteration with `nil` and cancels the
///   subscription.
///
/// Each bridge makes one stream with one subscription. Make a new bridge for
/// each call to a stream member, as the example does.
///
/// `Value` is `Sendable` because each value crosses from the thread the
/// publisher delivers on to the task that iterates the stream. A request's
/// rows already are.
///
/// Do not bridge ``XLRequest/publish()`` or any other publish member of the
/// same request: since issue #684 those are built on the stream members, so
/// a stream built from them would call itself. Bridge the adapter's own
/// publisher.
///
public final class XLPublisherAsyncBridge<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var didStart = false

    private var isCancelled = false

    private var cancellable: AnyCancellable?

    private let buffer = XLSingleSlotAsyncBuffer<Value>()

    private let makePublisher: () -> AnyPublisher<Value, Error>

    /// Creates a bridge that calls `makePublisher` when its stream is first
    /// iterated.
    ///
    /// - Parameter makePublisher: Makes the publisher the stream subscribes
    ///   to. It is called at most once, on the stream's first `next()` call.
    public init<Upstream: Publisher>(
        makePublisher: @escaping () -> Upstream
    ) where Upstream.Output == Value, Upstream.Failure == Error {
        self.makePublisher = { makePublisher().eraseToAnyPublisher() }
    }

    private func claimStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didStart else { return false }
        didStart = true
        return true
    }

    /// Stores `newCancellable`, then reports whether `cancel()` had already
    /// run by that point. `cancel()` can run concurrently between `sink(...)`
    /// creating the subscription and this call storing it -- in that window
    /// `cancel()` finds nothing stored yet to cancel, so without this
    /// check-after-store re-verification the subscription it just missed
    /// would keep running forever, leaking whatever resources the wrapped
    /// publisher holds. Mirrors the identical pattern
    /// `GRDBLiveQueryAsyncBridge.beginAttempt()` uses for the same race.
    private func storeCancellableReportingIfAlreadyCancelled(
        _ newCancellable: AnyCancellable
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return true }
        cancellable = newCancellable
        return false
    }

    func next() async throws -> Value? {
        // The start decision lives *inside* `operation`, not before this
        // call: if the consuming `Task` is already cancelled at this point,
        // Swift guarantees `onCancel` runs before `operation` starts
        // executing, so `cancel()` completes -- and claims the start slot,
        // see below -- before `claimStart()` ever runs, so an
        // already-cancelled task subscribes to nothing.
        return try await withTaskCancellationHandler(
            operation: {
                if claimStart() {
                    let buffer = self.buffer
                    let subscription = makePublisher().sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                buffer.finish(throwing: nil)
                            case .failure(let error):
                                buffer.finish(throwing: error)
                            }
                        },
                        receiveValue: { value in
                            // `Value` is `Sendable`, so `buffer.yield(_:)` accepts it as a `sending`
                            // argument directly, as `GRDBLiveQueryAsyncBridge.handleValue` does.
                            buffer.yield(value)
                        }
                    )
                    if storeCancellableReportingIfAlreadyCancelled(subscription) {
                        // `cancel()` ran between subscribing above and
                        // storing here, missing this subscription entirely.
                        // Cancel it ourselves so it doesn't keep running.
                        subscription.cancel()
                    }
                }
                return try await buffer.next()
            },
            onCancel: { [weak self] in self?.cancel() }
        )
    }

    /// Safe to call more than once, and safe to call whether or not `next()`
    /// was ever invoked: claims the start slot itself so a `next()` call
    /// arriving after `cancel()` (before a subscription ever began) finds the
    /// buffer already finished instead of subscribing to a publisher nothing
    /// will ever consume.
    func cancel() {
        lock.lock()
        didStart = true
        isCancelled = true
        let existing = cancellable
        cancellable = nil
        lock.unlock()
        existing?.cancel()
        buffer.cancel()
    }

    /// The stream this bridge feeds. Calling it does no work: the publisher
    /// is made and subscribed to on the stream's first `next()` call.
    ///
    /// The `unfolding` closure captures `self` strongly, not weakly: a
    /// bridge is usually constructed and handed straight to `stream()` with
    /// no other owner, so a weak capture would let it deallocate immediately
    /// after this call returns, before any consumer ever iterates — silently
    /// turning every stream into one that resolves to `nil` on its very
    /// first `next()`. The returned `AsyncThrowingStream` becomes this
    /// bridge's only owner from here on, and the bridge does not hold a
    /// reference back to the stream, so this creates no retain cycle.
    public func stream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(unfolding: {
            try await self.next()
        })
    }
}
