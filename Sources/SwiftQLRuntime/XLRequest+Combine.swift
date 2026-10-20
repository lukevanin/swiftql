//
//  XLRequest+Combine.swift
//
//  The Combine surface of a request: a leaf adapter over its live-query
//  stream members (issue #684). This is the one file that gives every request
//  its publishers, so an adapter conforming to `XLRequest` never imports
//  Combine itself.
//

import Dispatch
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif


extension XLRequest {

    ///
    /// Creates a Combine publisher that observes and emits all rows from the query.
    ///
    /// The publisher is built on ``stream()`` through ``XLAsyncStreamPublisher``, so every adapter
    /// gets the same Combine behaviour (issue #684):
    ///
    /// - Observation starts when a subscriber first requests positive demand. Subscribing with zero
    ///   demand performs no database work.
    /// - Each subscriber receives a fresh initial value and owns an independent observation: one
    ///   call to ``stream()`` per subscriber.
    /// - Values are delivered asynchronously on the main dispatch queue.
    /// - The publisher fails with the original query-execution or row-decoding error instead of
    ///   emitting a partial result. An adapter may expose an explicit retry policy; GRDB-backed
    ///   requests remain terminal by default and retry only when their database is configured to do
    ///   so.
    /// - Cancelling the subscription cancels the observation.
    ///
    /// Adapter-specific write visibility and connection boundaries apply.
    ///
    public func publish() -> AnyPublisher<[Row], Error> {
        if let failure = livePublishPreflightFailure(bindings: nil) {
            return Fail(error: failure).eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.stream() })
    }

    /// Observes all rows using one immutable packet for every retry and refresh. Built on
    /// ``stream(bindings:)`` exactly as ``publish()`` is built on ``stream()``, so a packet the
    /// request rejects fails the publisher instead of being silently ignored.
    public func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        if let failure = livePublishPreflightFailure(bindings: bindings) {
            return Fail(error: failure).eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.stream(bindings: bindings) })
    }

    ///
    /// Creates a Combine publisher that observes and emits the first row from the query.
    ///
    /// Built on ``streamOne()`` with the same subscription, demand, delivery, failure, and
    /// cancellation behaviour as ``publish()``.
    ///
    public func publishOne() -> AnyPublisher<Row?, Error> {
        if let failure = livePublishPreflightFailure(bindings: nil) {
            return Fail(error: failure).eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.streamOne() })
    }

    /// Observes the first row using one immutable packet for every retry and refresh. Built on
    /// ``streamOne(bindings:)`` exactly as ``publishOne()`` is built on ``streamOne()``.
    public func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        if let failure = livePublishPreflightFailure(bindings: bindings) {
            return Fail(error: failure).eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.streamOne(bindings: bindings) })
    }

    /// The failure a SwiftQL adapter knows its live query will end with before it starts, which the
    /// publisher reports at once rather than on first demand. `nil` for any other conformer.
    private func livePublishPreflightFailure(
        bindings: (any XLInvocationBindingPacket)?
    ) -> Error? {
        (self as? any XLLivePublishPreflight)?.livePublishPreflightFailure(bindings: bindings)
    }
}


///
/// A SwiftQL request adapter that can tell, before observing, that its live query cannot start.
///
/// The publish members were requirements before issue #684, and the GRDB adapter's publishers
/// failed at subscription, even with zero demand, when the query could never be observed: a
/// `RETURNING` statement, a request made inside a transaction scope, or invalid bindings set
/// through `set(parameter:value:)`. The stream members report the same failures on first
/// iteration. This keeps the publishers failing as they did, so the Combine surface behaves
/// identically for existing callers.
///
/// Internal: a conformer outside SwiftQL gets its failures from its stream on first demand.
///
package protocol XLLivePublishPreflight {

    /// The error the live query is known to end with, or `nil` when it may start. `bindings` is
    /// the packet a `bindings:` publish member was given, or `nil` for a member without one.
    func livePublishPreflightFailure(bindings: (any XLInvocationBindingPacket)?) -> Error?
}


/// Wraps `makeStream` as an `AnyPublisher` with SwiftQL's documented main-queue delivery default
/// (`Sources/SwiftQL/SwiftQL.docc/LiveQueries.md`, "Observation Semantics"): "Initial and updated
/// values are delivered asynchronously on the main dispatch queue by default."
///
/// Composing the stock `.receive(on:)` operator on top of ``XLAsyncStreamPublisher`` is deliberate --
/// it reuses Combine's own, already-correct demand-preserving scheduling instead of reimplementing
/// queue-hopping inside the subscription itself, which would need to duplicate `.receive(on:)`'s
/// backpressure bookkeeping for no benefit. `XLAsyncStreamSubscription` therefore stays thread-
/// agnostic: it delivers on whatever thread its consumer `Task` runs on, and `.receive(on:)` is the
/// only thing that reschedules delivery onto the main queue.
func xlLiveQueryPublisher<Value: Sendable>(
    makeStream: @escaping () -> AsyncThrowingStream<Value, Error>
) -> AnyPublisher<Value, Error> {
    XLAsyncStreamPublisher(makeStream: makeStream)
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}
