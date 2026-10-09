//
//  SwiftUISupport.swift
//
//
//  Created by Luke Van In on 2026/07/26.
//

import Dispatch
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


///
/// Observes a live query and republishes its rows as a SwiftUI-friendly
/// `ObservableObject`.
///
/// Wraps `XLRequest.publish()` so a view model or view can adopt a query
/// directly with `@StateObject`/`@ObservedObject` instead of managing a
/// `Cancellable` by hand:
///
/// ```swift
/// final class PeopleViewModel: ObservableObject {
///     let people: XLQueryObserver<Person>
///
///     init(database: some XLDatabase) {
///         people = XLQueryObserver(database.makeRequest(with: peopleQuery))
///     }
/// }
/// ```
///
/// A view reads `observer.rows` and `observer.error` in its `body`; SwiftUI
/// re-renders whenever either `@Published` property changes. Observation
/// starts immediately on initialization and stops when the observer is
/// deallocated. Every delivered value is applied on the main thread.
/// ``XLRequest/publish()`` delivers on the main queue for every request
/// (issue #684), so each value is applied at once, with no second hop
/// (issue #652). The underlying fetch runs wherever the request's driver runs
/// it: on a database reader, for the GRDB driver.
///
public final class XLQueryObserver<Row>: ObservableObject {

    @Published public private(set) var rows: [Row] = []

    @Published public private(set) var error: Error?

    private var cancellable: AnyCancellable?

    private let delivery = XLMainThreadDelivery()

    public convenience init(_ request: any XLRequest<Row>) {
        self.init(publisher: request.publish())
    }

    public convenience init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        self.init(publisher: request.publish(bindings: bindings))
    }

    /// Observes `publisher`, which is what a request's ``XLRequest/publish()`` returns. Internal,
    /// so tests can deliver values on a thread of their choosing.
    init(publisher: AnyPublisher<[Row], Error>) {
        let delivery = delivery
        cancellable = publisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        delivery.deliver { self?.error = error }
                    }
                },
                receiveValue: { [weak self] rows in
                    delivery.deliver { self?.rows = rows }
                }
            )
    }
}


///
/// Observes a live single-row query and republishes it as a SwiftUI-friendly
/// `ObservableObject`.
///
/// Wraps `XLRequest.publishOne()`, mirroring ``XLQueryObserver`` for queries
/// that return at most one row.
///
public final class XLQueryRowObserver<Row>: ObservableObject {

    @Published public private(set) var row: Row?

    @Published public private(set) var error: Error?

    private var cancellable: AnyCancellable?

    private let delivery = XLMainThreadDelivery()

    public convenience init(_ request: any XLRequest<Row>) {
        self.init(publisher: request.publishOne())
    }

    public convenience init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        self.init(publisher: request.publishOne(bindings: bindings))
    }

    /// Observes `publisher`, which is what a request's ``XLRequest/publishOne()`` returns.
    /// Internal, so tests can deliver values on a thread of their choosing.
    init(publisher: AnyPublisher<Row?, Error>) {
        let delivery = delivery
        cancellable = publisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        delivery.deliver { self?.error = error }
                    }
                },
                receiveValue: { [weak self] row in
                    delivery.deliver { self?.row = row }
                }
            )
    }
}


/// Applies one subscription's deliveries on the main thread, in the order they arrive.
///
/// This replaces an unconditional `.receive(on: DispatchQueue.main)` (issue #652). `publish()`
/// already delivers on the main queue, so that operator only added a second hop. Before issue #684
/// an external ``XLRequest`` conformer scheduled its own publisher; every request's publisher is
/// now SwiftQL's own, but a value that does arrive off the main thread is still moved there before
/// it touches `@Published` state.
///
/// A delivery on the main thread runs at once only when no earlier delivery is still queued.
/// Otherwise it queues behind that delivery. So a publisher that changes threads cannot have an
/// older off-main value overwrite a newer main-thread value.
///
/// The count update and the main-queue enqueue happen under one lock, so the enqueue order is the
/// order of the `deliver(_:)` calls. Combine already sends a subscriber one event at a time; the
/// lock keeps the order correct without relying on that.
private final class XLMainThreadDelivery: @unchecked Sendable {

    private let lock = NSLock()

    private var queuedCount = 0

    func deliver(_ body: @escaping () -> Void) {
        lock.lock()
        guard Thread.isMainThread && queuedCount == 0 else {
            queuedCount += 1
            let work = XLMainThreadWork(body: body)
            DispatchQueue.main.async { [self] in
                work.body()
                lock.lock()
                queuedCount -= 1
                lock.unlock()
            }
            lock.unlock()
            return
        }
        lock.unlock()
        body()
    }
}


/// Carries one delivery closure across `DispatchQueue.main.async`, whose closure is `@Sendable`.
///
/// `@unchecked Sendable` because the closure captures the observer's non-`Sendable` `Row` values.
/// The crossing is safe: ``XLMainThreadDelivery`` hands each closure to the main queue exactly once
/// and keeps no other reference, so only the main thread ever runs it. A struct, not a
/// `nonisolated(unsafe)` shadow, so it parses on every supported compiler, Swift 5.9 included.
private struct XLMainThreadWork: @unchecked Sendable {
    let body: () -> Void
}
