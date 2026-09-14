//
//  SwiftUISupport.swift
//
//
//  Created by Luke Van In on 2026/07/26.
//

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

    public init(_ request: any XLRequest<Row>) {
        subscribe(to: request.publish())
    }

    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        subscribe(to: request.publish(bindings: bindings))
    }

    private func subscribe(to publisher: AnyPublisher<[Row], Error>) {
        cancellable = publisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        xlOnMainThread { self?.error = error }
                    }
                },
                receiveValue: { [weak self] rows in
                    xlOnMainThread { self?.rows = rows }
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

    public init(_ request: any XLRequest<Row>) {
        subscribe(to: request.publishOne())
    }

    public init(_ request: any XLRequest<Row>, bindings: any XLInvocationBindingPacket) {
        subscribe(to: request.publishOne(bindings: bindings))
    }

    private func subscribe(to publisher: AnyPublisher<Row?, Error>) {
        cancellable = publisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        xlOnMainThread { self?.error = error }
                    }
                },
                receiveValue: { [weak self] row in
                    xlOnMainThread { self?.row = row }
                }
            )
    }
}


/// Runs `body` on the main thread: at once when the caller is already there, otherwise
/// asynchronously on the main queue.
///
/// This replaces an unconditional `.receive(on: DispatchQueue.main)` (issue #652). A GRDB-backed
/// `publish()` already delivers on the main queue, so that operator only added a second hop. An
/// external ``XLRequest`` conformer schedules its own publisher, so an off-main value still has to
/// be moved to the main queue before it touches `@Published` state. A conformer that delivers on the
/// main thread for some values and off it for others can see those two groups interleave; one that
/// keeps to a single thread keeps its order.
private func xlOnMainThread(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
        body()
    }
    else {
        DispatchQueue.main.async(execute: body)
    }
}
