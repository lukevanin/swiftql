import Foundation
import Observation
import XCTest

/// A one-shot signal that an awaiting task is resumed by, rather than polls.
///
/// `fire()` may run on whichever thread mutated the observed state, on the
/// deadline task, or on a cancellation handler, so the state is
/// lock-protected. A `fire()` that lands before `wait()` is recorded, and the
/// later `wait()` returns at once: a change that happens between subscribing
/// and suspending cannot be missed.
private final class ObservationChangeSignal: @unchecked Sendable {

    private let lock = NSLock()

    private var fired = false

    private var continuation: CheckedContinuation<Void, Never>?

    func fire() {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        fired = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}


@available(iOS 17, macOS 14, *)
extension XCTestCase {

    /// Suspends until `isSatisfied` holds for main-actor `@Observable` state,
    /// resumed by Observation's own change notification instead of a poll.
    ///
    /// Each round evaluates `isSatisfied` inside `withObservationTracking`, so
    /// the properties it reads are exactly the ones whose next mutation resumes
    /// the wait, and no change can slip in between checking and subscribing.
    /// `onChange` fires just before the new value is visible, so the loop yields
    /// the main actor once and evaluates again. Under load the loop takes more
    /// turns; it never concludes early.
    ///
    /// The wait is event-driven, but it is not unbounded. A state that never
    /// arrives would otherwise hang the job until its timeout with nothing in
    /// the log. `timeout` is a generous backstop, far above how long any of
    /// these states takes on a loaded runner, and its failure names the state.
    /// The wait also ends, with a failure naming the state, when the test task
    /// is cancelled.
    ///
    /// - Parameters:
    ///   - description: The state being awaited, used in every failure message.
    ///   - timeout: The backstop, in seconds, for the whole wait.
    ///   - isSatisfied: The condition, read on the main actor.
    @MainActor
    func waitForObservedState(
        _ description: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        until isSatisfied: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1_000))
        while true {
            let changed = ObservationChangeSignal()
            let isSatisfiedNow = withObservationTracking {
                isSatisfied()
            } onChange: {
                changed.fire()
            }
            if isSatisfiedNow {
                return
            }

            // Whichever comes first resumes the wait: the observed change, the
            // deadline, or cancellation of the test task.
            let backstop = Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                changed.fire()
            }
            await withTaskCancellationHandler {
                await changed.wait()
            } onCancel: {
                changed.fire()
            }
            backstop.cancel()

            if Task.isCancelled {
                XCTFail(
                    "Cancelled while waiting for \(description)",
                    file: file,
                    line: line
                )
                return
            }
            if ContinuousClock.now >= deadline {
                if !isSatisfied() {
                    XCTFail(
                        "Timed out after \(timeout)s waiting for \(description)",
                        file: file,
                        line: line
                    )
                }
                return
            }
            await Task.yield()
        }
    }
}
