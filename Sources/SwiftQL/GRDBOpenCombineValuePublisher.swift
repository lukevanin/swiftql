#if !canImport(Combine)
import Foundation
import GRDB
import OpenCombine


/// OpenCombine bridge for GRDB value observations on non-Apple platforms.
///
/// GRDB's native publisher is compiled only when Apple's Combine module is
/// available. This bridge preserves the same demand-driven lifecycle: the
/// SQLite observation does not start until positive demand arrives, and every
/// subscriber owns an independent observation and cancellation token.
struct GRDBOpenCombineValuePublisher<Output>: Publisher {

    typealias Failure = Error

    typealias Start = (
        @escaping (Error) -> Void,
        @escaping (Output) -> Void
    ) -> AnyDatabaseCancellable

    private let start: Start

    init(start: @escaping Start) {
        self.start = start
    }

    func receive<S>(subscriber: S)
    where S: Subscriber, S.Input == Output, S.Failure == Error {
        let subscription = GRDBOpenCombineValueSubscription(
            start: start,
            downstream: subscriber
        )
        subscriber.receive(subscription: subscription)
    }
}


private final class GRDBOpenCombineValueSubscription<Downstream>: Subscription
where Downstream: Subscriber, Downstream.Failure == Error {

    fileprivate typealias Start = (
        @escaping (Error) -> Void,
        @escaping (Downstream.Input) -> Void
    ) -> AnyDatabaseCancellable

    private enum State {
        case waiting(start: Start, downstream: Downstream)
        case observing(
            downstream: Downstream,
            remainingDemand: Subscribers.Demand
        )
        case finished
    }

    private let lock = NSRecursiveLock()
    private var cancellable: AnyDatabaseCancellable?
    private var state: State

    fileprivate init(start: @escaping Start, downstream: Downstream) {
        state = .waiting(start: start, downstream: downstream)
    }

    func request(_ demand: Subscribers.Demand) {
        var cancellableToCancel: AnyDatabaseCancellable?

        lock.lock()
        switch state {
        case let .waiting(start, downstream):
            guard demand > .none else {
                lock.unlock()
                return
            }

            state = .observing(
                downstream: downstream,
                remainingDemand: demand
            )
            let startedCancellable = start(
                { [weak self] error in
                    self?.receiveCompletion(.failure(error))
                },
                { [weak self] value in
                    self?.receive(value)
                }
            )

            switch state {
            case .observing:
                cancellable = startedCancellable
            case .finished:
                cancellableToCancel = startedCancellable
            case .waiting:
                preconditionFailure("observation returned to waiting state")
            }

        case let .observing(downstream, remainingDemand):
            state = .observing(
                downstream: downstream,
                remainingDemand: remainingDemand + demand
            )

        case .finished:
            break
        }
        lock.unlock()

        cancellableToCancel?.cancel()
    }

    func cancel() {
        lock.lock()
        let cancellableToCancel = cancellable
        cancellable = nil
        state = .finished
        lock.unlock()

        cancellableToCancel?.cancel()
    }

    private func receive(_ value: Downstream.Input) {
        lock.lock()
        guard case let .observing(downstream, remainingDemand) = state,
              remainingDemand > .none else {
            lock.unlock()
            return
        }

        let additionalDemand = downstream.receive(value)
        if case let .observing(currentDownstream, currentDemand) = state {
            state = .observing(
                downstream: currentDownstream,
                remainingDemand: currentDemand + additionalDemand - 1
            )
        }
        lock.unlock()
    }

    private func receiveCompletion(
        _ completion: Subscribers.Completion<Error>
    ) {
        lock.lock()
        guard case let .observing(downstream, _) = state else {
            lock.unlock()
            return
        }
        cancellable = nil
        state = .finished
        lock.unlock()

        downstream.receive(completion: completion)
    }
}
#endif
