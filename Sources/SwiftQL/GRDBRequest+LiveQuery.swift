//
//  GRDBRequest+LiveQuery.swift
//  SwiftQL
//
//  Observation: re-running the statement whenever the database changes, as a
//  Combine publisher or an async stream.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
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
            return publish(bindings: try compatibilityPacket())
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
            return publishOne(bindings: try compatibilityPacket())
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
            return try stream(bindings: compatibilityPacket())
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
            guard let bridge = liveQueryStreamBridge(fetch: { database -> [Row] in
                logger?.debug(
                    "stream: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                return try decodeRows(packet: packet, in: &connection)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            return bridge.stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func streamOne() -> AsyncThrowingStream<Row?, Error> {
        do {
            return try streamOne(bindings: compatibilityPacket())
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
            guard let bridge = liveQueryStreamBridge(fetch: { database -> Row? in
                logger?.debug(
                    "streamOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                guard let values = try executor.fetchOne(packet: packet, in: &connection) else {
                    return nil
                }
                return try GRDBRowDecoder(reader: reader).decode(values: values)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            return bridge.stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    /// Builds the async-native GRDB observation bridge shared by `stream()`/`streamOne()`. Returns `nil`
    /// for a transaction-scoped driver (issue #284), which has no pool to track — the same guard
    /// `publish(bindings:)`/`publishOne(bindings:)` check eagerly for the Combine path (issue #309).
    func liveQueryStreamBridge<Value>(
        fetch: @escaping (Database) throws -> Value
    ) -> GRDBLiveQueryAsyncBridge<Value>? {
        guard let databasePool = executor.driver.databasePool else {
            return nil
        }
        return GRDBLiveQueryAsyncBridge(
            policy: liveQueryRetryPolicy,
            scheduler: liveQueryRetryScheduler,
            makeSource: { onError, onChange in
                ValueObservation
                    .tracking(fetch)
                    .start(in: databasePool, onError: onError, onChange: onChange)
            }
        )
    }

    func compatibilityPacket() throws -> XLInvocationBindings<XLSQLiteValue> {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        return compatibilityBindings
    }
}
