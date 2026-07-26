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
import OpenCombineDispatch
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
/// deallocated; every delivered value is received on the main queue, though
/// the underlying fetch may begin on whatever thread triggers it.
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
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error
                    }
                },
                receiveValue: { [weak self] rows in
                    self?.rows = rows
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
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error
                    }
                },
                receiveValue: { [weak self] row in
                    self?.row = row
                }
            )
    }
}
