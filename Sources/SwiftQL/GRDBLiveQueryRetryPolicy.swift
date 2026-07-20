#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif
import Dispatch
import Foundation
import GRDB


/// Controls recovery after a GRDB-backed live query fails.
///
/// The default ``terminal`` policy preserves the behavior of SwiftQL 1.0: the
/// observation terminates with its original error. ``retryBusy`` is an
/// explicit opt-in for transient SQLite contention. It retries only
/// `DatabaseError` values whose primary result code is `SQLITE_BUSY`.
public enum GRDBLiveQueryRetryPolicy: Hashable, Sendable {

    /// Terminates the observation with its original error without retrying.
    case terminal

    /// Retries transient `SQLITE_BUSY` failures after 0.1, 0.2, and 0.4 seconds.
    ///
    /// These are three additional attempts, with no jitter and a maximum delay
    /// below the one-second v1.1 cap. A delivered value resets the consecutive
    /// retry budget. All non-BUSY errors, including `SQLITE_LOCKED`, remain
    /// terminal.
    case retryBusy

    private static let retryBusyDelays: [TimeInterval] = [0.1, 0.2, 0.4]

    func retryDelay(after error: Error, retryNumber: Int) -> TimeInterval? {
        guard self == .retryBusy,
              retryNumber >= 0,
              retryNumber < Self.retryBusyDelays.count,
              let databaseError = error as? DatabaseError,
              databaseError.resultCode == .SQLITE_BUSY
        else {
            return nil
        }
        return Self.retryBusyDelays[retryNumber]
    }
}


/// Type-erased scheduling seam for deterministic retry tests.
struct GRDBLiveQueryRetryScheduler: @unchecked Sendable {

    private let scheduleImpl: @Sendable (TimeInterval) -> AnyPublisher<Void, Never>

    init(schedule: @escaping @Sendable (TimeInterval) -> AnyPublisher<Void, Never>) {
        self.scheduleImpl = schedule
    }

    func publisher(after delay: TimeInterval) -> AnyPublisher<Void, Never> {
        scheduleImpl(delay)
    }

    static let mainQueue = GRDBLiveQueryRetryScheduler { delay in
        Just(())
            .delay(
                for: .nanoseconds(Int(delay * 1_000_000_000)),
                scheduler: DispatchQueue.main
            )
            .eraseToAnyPublisher()
    }
}


/// Subscriber-local state for a retrying observation.
private final class GRDBLiveQueryRetryState: @unchecked Sendable {

    private let lock = NSLock()

    private let policy: GRDBLiveQueryRetryPolicy

    private var currentGeneration = 0

    private var consecutiveRetryCount = 0

    private var isCancelled = false

    init(policy: GRDBLiveQueryRetryPolicy) {
        self.policy = policy
    }

    func beginAttempt() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return nil }
        currentGeneration += 1
        return currentGeneration
    }

    func shouldDeliver(generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled && generation == currentGeneration
    }

    func didDeliver(generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled && generation == currentGeneration else { return }
        consecutiveRetryCount = 0
    }

    func retryDelay(after error: Error, generation: Int) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled && generation == currentGeneration,
              let delay = policy.retryDelay(
                  after: error,
                  retryNumber: consecutiveRetryCount
              )
        else {
            return nil
        }
        consecutiveRetryCount += 1
        return delay
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        currentGeneration += 1
        lock.unlock()
    }
}


/// Creates one independent retry coordinator for every downstream subscriber.
func makeGRDBLiveQueryRetryPublisher<Output>(
    policy: GRDBLiveQueryRetryPolicy,
    scheduler: GRDBLiveQueryRetryScheduler,
    makeSource: @escaping () -> AnyPublisher<Output, Error>
) -> AnyPublisher<Output, Error> {
    Deferred {
        let state = GRDBLiveQueryRetryState(policy: policy)
        return makeGRDBLiveQueryRetryAttempt(
            state: state,
            scheduler: scheduler,
            makeSource: makeSource
        )
        .handleEvents(receiveCancel: state.cancel)
        .eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}


private func makeGRDBLiveQueryRetryAttempt<Output>(
    state: GRDBLiveQueryRetryState,
    scheduler: GRDBLiveQueryRetryScheduler,
    makeSource: @escaping () -> AnyPublisher<Output, Error>
) -> AnyPublisher<Output, Error> {
    guard let generation = state.beginAttempt() else {
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    return makeSource()
        .filter { _ in
            state.shouldDeliver(generation: generation)
        }
        .handleEvents(receiveOutput: { _ in
            state.didDeliver(generation: generation)
        })
        .catch { error -> AnyPublisher<Output, Error> in
            guard let delay = state.retryDelay(
                after: error,
                generation: generation
            ) else {
                return Fail(error: error).eraseToAnyPublisher()
            }

            return scheduler.publisher(after: delay)
                .setFailureType(to: Error.self)
                .flatMap(maxPublishers: .max(1)) {
                    makeGRDBLiveQueryRetryAttempt(
                        state: state,
                        scheduler: scheduler,
                        makeSource: makeSource
                    )
                }
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
}
