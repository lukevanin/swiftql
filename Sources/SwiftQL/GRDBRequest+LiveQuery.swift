//
//  GRDBRequest+LiveQuery.swift
//  SwiftQL
//
//  Observation: re-running the statement whenever the database changes, as a
//  Combine publisher or an async stream.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Dispatch
import Foundation
import GRDB
import SwiftQLCore
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


extension GRDBRequest {

    /// Why this request cannot be observed, or `nil` when it can be.
    ///
    /// A `RETURNING` statement writes as it reads, so re-running it on every
    /// database change would perform the write again -- once per change, for as
    /// long as anyone is watching. That is never what a caller asking for a
    /// live query meant, so it is refused rather than obeyed.
    ///
    /// Checked by all six observation entry points. It was written out at each
    /// of them (issue #560); one of the six drifting is a silent
    /// write-amplification bug rather than a compile error.
    var observationUnavailableError: Error? {
        guard requiresWriteConnection else {
            return nil
        }
        return XLReturningRequestError.observationUnsupported
    }

    func publish() -> AnyPublisher<[Row], Error> {
        if let error = observationUnavailableError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        do {
            return publish(bindings: try legacyBindings.packet())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        if let error = observationUnavailableError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        guard executor.driver.databasePool != nil else {
            return Fail(error: XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
                .eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.stream(bindings: bindings) })
    }

    func publishOne() -> AnyPublisher<Row?, Error> {
        if let error = observationUnavailableError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        do {
            return publishOne(bindings: try legacyBindings.packet())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        if let error = observationUnavailableError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        guard executor.driver.databasePool != nil else {
            return Fail(error: XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
                .eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.streamOne(bindings: bindings) })
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
            // observation delivers them. See `liveQueryStreamBridge(fetch:)`.
            let executor = executor
            let logger = logger
            guard let bridge = liveQueryStreamBridge(fetch: { database -> [[XLSQLiteValue]] in
                logger?.debug(
                    "stream: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                return try executor.fetchAll(packet: packet, in: &connection)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            let decodeRow = sendableRowDecode()
            return AsyncThrowingStream(unfolding: { () async throws -> [Row]? in
                guard let values = try await bridge.next() else {
                    return nil
                }
                do {
                    return try values.map(decodeRow)
                }
                catch {
                    logger?.error("stream: Cannot decode entity: \(error)")
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
            guard let bridge = liveQueryStreamBridge(fetch: { database -> [XLSQLiteValue]? in
                logger?.debug(
                    "streamOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                return try executor.fetchOne(packet: packet, in: &connection)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            let decodeRow = sendableRowDecode()
            return AsyncThrowingStream(unfolding: { () async throws -> Row?? in
                guard let values = try await bridge.next() else {
                    return nil
                }
                guard let values else {
                    return Row??.some(nil)
                }
                do {
                    return Row??.some(try decodeRow(values))
                }
                catch {
                    logger?.error("streamOne: Cannot decode entity: \(error)")
                    throw error
                }
            })
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    /// Builds the async-native GRDB observation bridge shared by `stream()`/`streamOne()`. Returns `nil`
    /// for a transaction-scoped driver (issue #284), which has no pool to track — the same guard
    /// `publish(bindings:)`/`publishOne(bindings:)` check eagerly for the Combine path (issue #309).
    ///
    /// The observation tracks a constant region (issue #652). `fetch` runs one statement, prepared
    /// from this request's immutable `logicalStatement`, bound to a packet fixed when the stream was
    /// made. GRDB records a statement's region from SQLite's authorizer when the statement is
    /// prepared, not from the rows a step visits, so every fetch selects the same region. With a
    /// constant region, GRDB refetches after a commit on a pool reader and coalesces a burst of
    /// commits; `tracking(_:)` would refetch inline on the writer, once per commit.
    ///
    /// Each bridge also gets its own serial queue. GRDB delivers snapshots on it, and it is the
    /// default retry scheduler, so nothing in `stream()` needs the main thread. The Combine adapter
    /// adds its main-queue hop itself (`xlLiveQueryPublisher(makeStream:)`).
    ///
    /// `fetch` is `@Sendable` because GRDB 7 runs it on a pool reader, and
    /// `Value` is `Sendable` because GRDB 7 constrains a reducer's value. The
    /// callers therefore fetch raw dialect values and decode the typed row
    /// afterwards: `GRDBInvocationExecutor` is `Sendable`, while the row
    /// reader graph behind `XLRowReadable` is not.
    func liveQueryStreamBridge<Value: Sendable>(
        fetch: @escaping @Sendable (Database) throws -> Value
    ) -> GRDBLiveQueryAsyncBridge<Value>? {
        guard let databasePool = executor.driver.databasePool else {
            return nil
        }
        let queue = DispatchQueue(label: "SwiftQL.GRDBLiveQuery")
        return GRDBLiveQueryAsyncBridge(
            policy: liveQueryRetryPolicy,
            scheduler: liveQueryRetryScheduler ?? .queue(queue),
            makeSource: { onError, onChange in
                ValueObservation
                    .trackingConstantRegion(fetch)
                    .start(
                        in: databasePool,
                        scheduling: .async(onQueue: queue),
                        onError: onError,
                        onChange: onChange
                    )
            }
        )
    }


}
