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
/// deallocated. Every delivered value is applied on the main thread. A value
/// that already arrives on the main thread -- as it does from a GRDB-backed
/// request, whose `publish()` delivers on the main queue by default -- is
/// applied at once, with no second hop (issue #652). A value from another
/// ``XLRequest`` conformer, whose scheduling is adapter-specific, that arrives
/// on another thread is dispatched to the main queue first.
/// For a GRDB-backed request, the underlying fetch runs on a database reader.
///
public final class XLQueryObserver<Row>: ObservableObject {

    @Published public private(set) var rows: [Row] = []

    @Published public private(set) var error: Error?

    private var cancellable: AnyCancellable?

    private let delivery = XLMainThreadDelivery()

    public init(_ request: any XLRequest<Row>) {
        subscribe(to: request.publish())
    }

    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        subscribe(to: request.publish(bindings: bindings))
    }

    private func subscribe(to publisher: AnyPublisher<[Row], Error>) {
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

    public init(_ request: any XLRequest<Row>) {
        subscribe(to: request.publishOne())
    }

    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        subscribe(to: request.publishOne(bindings: bindings))
    }

    private func subscribe(to publisher: AnyPublisher<Row?, Error>) {
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
/// This replaces an unconditional `.receive(on: DispatchQueue.main)` (issue #652). A GRDB-backed
/// `publish()` already delivers on the main queue, so that operator only added a second hop. An
/// external ``XLRequest`` conformer schedules its own publisher, so an off-main value still has to
/// be moved to the main queue before it touches `@Published` state.
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
            DispatchQueue.main.async { [self] in
                body()
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
