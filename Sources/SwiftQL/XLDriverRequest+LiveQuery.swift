//
//  XLDriverRequest+LiveQuery.swift
//  SwiftQL
//
//  Observation: re-running the statement whenever the database changes, as an
//  async stream. The driver observes through `XLObservingDatabaseDriver`
//  (issue #682), and the Combine publishers are SwiftQL's own, built on these
//  streams (`XLRequest+Combine.swift`, issue #684).
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation


extension XLDriverRequest {

    /// Why this request cannot be observed, or `nil` when it can be.
    ///
    /// A `RETURNING` statement writes as it reads, so re-running it on every
    /// database change would perform the write again -- once per change, for as
    /// long as anyone is watching. That is never what a caller asking for a
    /// live query meant, so it is refused rather than obeyed.
    ///
    /// Checked by every observation entry point: the stream members and the
    /// publish preflight. It was written out at each of them (issue #560); one
    /// of them drifting is a silent write-amplification bug rather than a
    /// compile error.
    var observationUnavailableError: Error? {
        guard requiresWriteConnection else {
            return nil
        }
        return XLReturningRequestError.observationUnsupported
    }

    func stream() -> AsyncThrowingStream<[Row], Error> {
        do {
            return try stream(bindings: legacyBindings.packet())
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func stream(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<[Row], Error> {
        if let error = observationUnavailableError {
            return xlFailingAsyncThrowingStream(error)
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            // Only `Sendable` values cross into the observation: the executor
            // and the logger. The row reader stays on this side of the
            // boundary, and the rows it decodes are built after the
            // observation delivers them.
            let executor = executor
            let logger = logger
            let values = XLObservedValues(
                executor.driver.observe(executor.logicalStatement) { connection -> [[XLSQLiteValue]] in
                    logger?.debug(
                        "stream: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                    return try executor.fetchAll(packet: packet, in: &connection)
                }
            )
            let decodeRow = sendableRowDecode()
            return AsyncThrowingStream(unfolding: { () async throws -> [Row]? in
                guard let rows = try await values.next() else {
                    return nil
                }
                do {
                    return try rows.map(decodeRow)
                }
                catch {
                    logger?.error("stream: Cannot decode entity: \(error)")
                    // A decode failure ends the stream, which is the contract
                    // <doc:LiveQueries> states. Decoding runs here rather than
                    // inside the observation, so this closure ends the stream
                    // itself. `AsyncThrowingStream`'s `unfolding` wrapper calls
                    // this closure again after a throw; stopping the
                    // observation makes that next call resolve to `nil`,
                    // exactly as the observation's own terminal error path does.
                    values.stop()
                    throw error
                }
            })
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func streamOne() -> AsyncThrowingStream<Row?, Error> {
        do {
            return try streamOne(bindings: legacyBindings.packet())
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func streamOne(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<Row?, Error> {
        if let error = observationUnavailableError {
            return xlFailingAsyncThrowingStream(error)
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            // Same boundary as `stream(bindings:)` above: the observation
            // carries raw dialect values, and the row reader decodes them
            // after delivery.
            let executor = executor
            let logger = logger
            let values = XLObservedValues(
                executor.driver.observe(executor.logicalStatement) { connection -> [XLSQLiteValue]? in
                    logger?.debug(
                        "streamOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                    return try executor.fetchOne(packet: packet, in: &connection)
                }
            )
            let decodeRow = sendableRowDecode()
            return AsyncThrowingStream(unfolding: { () async throws -> Row?? in
                guard let row = try await values.next() else {
                    return nil
                }
                guard let row else {
                    return Row??.some(nil)
                }
                do {
                    return Row??.some(try decodeRow(row))
                }
                catch {
                    logger?.error("streamOne: Cannot decode entity: \(error)")
                    // Same terminal rule as `stream(bindings:)` above.
                    values.stop()
                    throw error
                }
            })
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }
}


/// One observation's values, which the request decodes before delivering,
/// and can stop when a decode fails.
///
/// Holds only the observation's iterator, never the stream, so stopping
/// releases the observation: a stream ends, and its driver stops observing,
/// once the stream and its iterators are released. A single consumer iterates
/// it, as every live-query stream has one consumer, which is why it is
/// `@unchecked Sendable`: nothing calls it concurrently.
final class XLObservedValues<Value: Sendable>: @unchecked Sendable {

    private var iterator: AsyncThrowingStream<Value, Error>.AsyncIterator?

    init(_ values: AsyncThrowingStream<Value, Error>) {
        iterator = values.makeAsyncIterator()
    }

    /// The next value, or `nil` once the observation has ended or stopped.
    /// An error the observation throws is terminal: later calls return `nil`.
    func next() async throws -> Value? {
        guard var current = takeIterator() else {
            return nil
        }
        let value = try await current.next()
        restore(current)
        return value
    }

    /// Releases the observation. Later calls to ``next()`` return `nil`.
    func stop() {
        iterator = nil
    }

    private func takeIterator() -> AsyncThrowingStream<Value, Error>.AsyncIterator? {
        defer { iterator = nil }
        return iterator
    }

    private func restore(_ current: AsyncThrowingStream<Value, Error>.AsyncIterator) {
        iterator = current
    }
}


/// A driver that can tell, before observing, that it cannot observe at all (issue #682).
///
/// Internal. The GRDB driver conforms: a driver pinned to a transaction scope has no pool to
/// observe. ``XLDriverRequest``'s publish preflight asks it, so the check stays with the driver
/// while the preflight serves every request.
protocol XLLiveQueryAvailability {

    /// Why this driver cannot observe, or `nil` when it can.
    var liveQueryUnavailableError: Error? { get }
}


extension GRDBDatabaseDriver: XLLiveQueryAvailability {

    var liveQueryUnavailableError: Error? {
        databasePool == nil ? XLTransactionScopeError.liveQueriesUnsupportedInTransaction : nil
    }
}


extension XLDriverRequest: XLLivePublishPreflight {

    /// The failures the publishers have always reported at subscription rather than on first
    /// demand (issue #684): a `RETURNING` statement, and, for a member without a packet, bindings
    /// set through `set(parameter:value:)` that do not form a valid packet, on every driver; and a
    /// driver that reports, through `XLLiveQueryAvailability`, that it cannot observe at all, such
    /// as a GRDB driver pinned to a transaction scope. The stream members report each of these on
    /// first iteration.
    ///
    /// These are pure, already-computed structural checks, not observation, retry, or decoding
    /// logic, and keeping them synchronous preserves a real regression contract:
    /// `SQLTransactionScopeTests.testPublishInsideATransactionFailsPredictablyInsteadOfObservingAnInvalidatedConnection`
    /// calls `publish()` and synchronously waits on the same thread the `withTransaction(_:)` body
    /// runs on. The pool's write access blocks that thread for the body's duration, so an error
    /// delivered lazily, through a task and `.receive(on: DispatchQueue.main)`, could never arrive
    /// while that thread is the one waiting for it. `Fail` needs no dispatch queue and delivers
    /// synchronously.
    func livePublishPreflightFailure(
        bindings: (any XLInvocationBindingPacket)?
    ) -> Error? {
        if let error = observationUnavailableError {
            return error
        }
        if bindings == nil {
            do {
                _ = try legacyBindings.packet()
            }
            catch {
                return error
            }
        }
        return (executor.driver as? any XLLiveQueryAvailability)?.liveQueryUnavailableError
    }
}
