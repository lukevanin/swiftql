//
//  XLSingleSlotAsyncBuffer.swift
//

import Foundation


/// Bound-1, "newest wins" async handoff selected by issue #291 for every
/// SwiftQL canonical live-query stream.
///
/// At most one produced value is ever held undelivered. A value that arrives
/// while nothing is buffered either resumes a waiting `next()` call directly
/// or becomes the single buffered value; a value that arrives while an
/// earlier one is still buffered *replaces* it rather than queuing behind it.
/// This mirrors `AsyncThrowingStream.Continuation.BufferingPolicy
/// .bufferingNewest(1)` semantics without depending on that GRDB-experimental
/// buffering-policy API directly, so the exact same type backs both
/// ``GRDBLiveQueryAsyncBridge`` (the true async-native GRDB source, #308) and
/// the `XLRequest` protocol-extension compatibility default that bridges an
/// adapter's existing `publish()`/`publishOne()` Combine pipeline.
///
/// `Value` may itself be `Optional` (as `streamOne()`'s `Row?` is): a present
/// `nil` row is a real delivered snapshot and is buffered like any other
/// value, distinct from "nothing buffered yet."
final class XLSingleSlotAsyncBuffer<Value>: @unchecked Sendable {

    private let lock = NSLock()

    /// The buffering bound selected by #291: at most one snapshot is ever
    /// held. A newly yielded value replaces (not queues behind) any
    /// previously buffered, undelivered value.
    private var pendingValue: Value?

    private var pendingError: Error?

    private var isFinished = false

    private var waiter: CheckedContinuation<Value?, Error>?

    /// Buffers `value`, replacing whatever was previously buffered, or
    /// resumes an already-suspended `next()` call directly if one is
    /// waiting. Has no effect after ``finish(throwing:)``/``cancel()``.
    ///
    /// `sending` (Swift 6.0+ only -- the `#else` branch keeps this compiling under the pinned Swift
    /// 5.9 cell, which predates the `sending` parameter modifier) tells the compiler this call is
    /// `value`'s last use in the caller: it either resumes `waiter` with it directly or moves it into
    /// `pendingValue`, never both, so ownership fully transfers here rather than staying aliased with
    /// the caller's copy.
    // The whole declaration is duplicated per branch: splitting only the signature across #if/#else
    // and sharing one body does not parse -- each active branch's opening brace must be matched by a
    // closing brace within that same branch.
    #if compiler(>=6.0)
    func yield(_ value: sending Value) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: value)
            return
        }
        pendingValue = value
        lock.unlock()
    }
    #else
    func yield(_ value: Value) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: value)
            return
        }
        pendingValue = value
        lock.unlock()
    }
    #endif

    /// Ends the buffer, delivering `error` (if any) to the currently
    /// suspended or next `next()` call exactly once. Safe to call more than
    /// once; only the first call has an effect.
    func finish(throwing error: Error?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        // Deliberately does NOT clear `pendingValue`: a value legitimately
        // yielded before `finish()` is called (e.g. a one-shot compatibility
        // publisher that emits once and completes immediately, delivered
        // synchronously within the same `sink` callback chain) must still be
        // delivered by the next `next()` call before iteration ends -- values
        // then completion, in that order, exactly like the Combine pipeline
        // being bridged. `yield(_:)`'s own `isFinished` guard already
        // prevents a value that arrives *after* `finish()`/`cancel()` from
        // ever being buffered in the first place, which is the actual race
        // this type must reject.
        if let waiter {
            self.waiter = nil
            lock.unlock()
            if let error {
                waiter.resume(throwing: error)
            }
            else {
                waiter.resume(returning: nil)
            }
            return
        }
        pendingError = error
        lock.unlock()
    }

    /// Ends the buffer because the *consumer* cancelled, not because the
    /// upstream source completed: every outstanding or future `next()` call
    /// resolves to `nil`, exactly like a normal, non-erroring end of
    /// iteration, and cancellation is never surfaced as a thrown
    /// `CancellationError` or a completion failure -- mirroring how
    /// cancelling a Combine subscription today never delivers a `.failure`
    /// completion.
    ///
    /// Unlike ``finish(throwing:)``, this also discards any value already
    /// buffered but not yet delivered: once the consumer no longer wants
    /// delivery, a stale snapshot slipping through afterward would violate
    /// the cancellation contract, not represent a legitimate "last value
    /// before normal completion." This is why `cancel()` does not simply
    /// delegate to `finish(throwing: nil)`.
    func cancel() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        pendingValue = nil
        pendingError = nil
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: nil)
            return
        }
        lock.unlock()
    }

    private enum FastPathOutcome {
        case value(Value)
        case error(Error)
        case finished
        case pending
    }

    /// All plain synchronous locked mutation is kept out of `next()`'s
    /// `async` body: recent Foundation marks `NSLock.lock()`/`unlock()` as
    /// unavailable directly inside asynchronous contexts (an error under the
    /// Swift 6 language mode), so both the initial fast-path check and the
    /// re-check performed once a continuation is available live in plain,
    /// non-`async` helper methods instead.
    private func checkFastPath() -> FastPathOutcome {
        lock.lock()
        defer { lock.unlock() }
        if let value = pendingValue {
            pendingValue = nil
            return .value(value)
        }
        if isFinished {
            if let pendingError {
                self.pendingError = nil
                return .error(pendingError)
            }
            return .finished
        }
        return .pending
    }

    /// Re-checks and, if still pending, registers the continuation as the
    /// single outstanding waiter — all inside one locked critical section.
    /// This must not be split into a separate check-then-register pair of
    /// locked calls: a value or termination arriving on another thread in
    /// the gap between them would otherwise be lost (`yield`/`finish` only
    /// resume a `waiter` that is already registered; anything arriving
    /// before registration would sit in `pendingValue`/`isFinished` and
    /// never wake this continuation).
    private func resolveImmediatelyOrRegister(_ continuation: CheckedContinuation<Value?, Error>) {
        lock.lock()
        if let value = pendingValue {
            pendingValue = nil
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        if isFinished {
            let error = pendingError
            pendingError = nil
            lock.unlock()
            if let error {
                continuation.resume(throwing: error)
            }
            else {
                continuation.resume(returning: nil)
            }
            return
        }
        precondition(
            waiter == nil,
            "XLSingleSlotAsyncBuffer.next() called concurrently: a second "
                + "caller would silently overwrite and leak/hang the first "
                + "waiter. Each canonical stream is single-consumer."
        )
        waiter = continuation
        lock.unlock()
    }

    /// Returns the next buffered value, suspending if nothing is buffered
    /// yet. Resolves to `nil` once cancelled/finished without an error,
    /// or throws the original terminal error exactly once.
    ///
    /// Calling `next()` never itself triggers new upstream work — it only
    /// asks for whatever has already been produced, per #291's "resuming
    /// does not force a fresh fetch" rule.
    func next() async throws -> Value? {
        switch checkFastPath() {
        case .value(let value):
            return value
        case .error(let error):
            throw error
        case .finished:
            return nil
        case .pending:
            return try await withCheckedThrowingContinuation { continuation in
                resolveImmediatelyOrRegister(continuation)
            }
        }
    }
}
