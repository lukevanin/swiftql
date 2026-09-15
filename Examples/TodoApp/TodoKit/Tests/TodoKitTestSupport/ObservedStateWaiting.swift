import Foundation
import Observation
import XCTest

/// A one-shot signal that an awaiting task is resumed by, rather than polls.
///
/// `fire()` may run on whichever thread mutated the observed state, so the
/// state is lock-protected. A `fire()` that lands before `wait()` is recorded,
/// and the later `wait()` returns at once: a change that happens between
/// subscribing and suspending cannot be missed.
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
    /// the main actor once and evaluates again. That is an await on a scheduling
    /// hop, not on a duration: under load the loop takes more turns, and it
    /// never concludes early.
    ///
    /// This is the demo's copy of `xlWaitForObservedState` in SwiftQL's own
    /// live-query suites. Like that helper, it has no deadline, because a
    /// deadline is what turns a slow runner into a failed test. A state that
    /// never arrives is left to the test runner's own timeout.
    ///
    /// - Parameters:
    ///   - description: The state being awaited. It names the wait at the call
    ///     site, and it is the failure message if the waiting task is
    ///     cancelled before the state arrives.
    ///   - isSatisfied: The condition, read on the main actor.
    @MainActor
    public func waitForObservedState(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        until isSatisfied: @escaping @MainActor () -> Bool
    ) async {
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
            await changed.wait()
            if Task.isCancelled {
                XCTFail(
                    "Cancelled while waiting for \(description)",
                    file: file,
                    line: line
                )
                return
            }
            await Task.yield()
        }
    }
}
