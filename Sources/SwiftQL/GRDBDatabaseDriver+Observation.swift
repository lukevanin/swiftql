//
//  GRDBDatabaseDriver+Observation.swift
//  SwiftQL
//
//  The GRDB driver observes a statement with `ValueObservation` (issue #684).
//

import Dispatch
import Foundation
internal import GRDB


extension GRDBDatabaseDriver: XLObservingDatabaseDriver {

    /// Observes `statement` with GRDB's `ValueObservation`, re-running `fetch` on a pool connection
    /// after each committed change to what the statement reads.
    ///
    /// The observation recovers from a failure as the driver's
    /// ``liveQueryRetryPolicy`` says, which is terminal unless the database
    /// that owns the driver is configured to retry.
    func observe<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        fetch: @escaping @Sendable (inout GRDBDatabaseDriverConnection) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        do {
            return try observationBridge(
                statement,
                retryPolicy: liveQueryRetryPolicy,
                retryScheduler: liveQueryRetryScheduler,
                fetch: fetch
            ).stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    /// Builds the async-native GRDB observation bridge behind ``observe(_:fetch:)``.
    ///
    /// The observation tracks a constant region (issue #652). `fetch` runs one statement, prepared
    /// from the immutable `statement`, bound to a packet fixed when the stream was made. GRDB
    /// records a statement's region from SQLite's authorizer when the statement is prepared, not
    /// from the rows a step visits, so every fetch selects the same region. That region is every
    /// table the statement reads, so it covers `statement.entities`, and also the base tables of a
    /// view the statement selects from. With a constant region, GRDB refetches after a commit on a
    /// pool reader and coalesces a burst of commits; `tracking(_:)` would refetch inline on the
    /// writer, once per commit.
    ///
    /// Each bridge also gets its own serial queue. GRDB delivers snapshots on it, and it is the
    /// default retry scheduler, so nothing in a stream needs the main thread. The Combine adapter
    /// adds its main-queue hop itself (`xlLiveQueryPublisher(makeStream:)`).
    ///
    /// `fetch` is `@Sendable` because GRDB 7 runs it on a pool reader, and `Value` is `Sendable`
    /// because GRDB 7 constrains a reducer's value. A request therefore fetches raw dialect values
    /// and decodes its typed rows afterwards: `GRDBInvocationExecutor` is `Sendable`, while the row
    /// reader graph behind `XLRowReadable` is not.
    ///
    /// - Throws: ``XLDatabaseContractError/driverMismatch(expectedDatabase:actualDatabase:driver:)``
    ///   when `statement` belongs to another database, and
    ///   ``XLTransactionScopeError/liveQueriesUnsupportedInTransaction`` for a driver pinned to a
    ///   transaction scope (issue #284), which has no pool to track.
    func observationBridge<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        retryPolicy: GRDBLiveQueryRetryPolicy,
        retryScheduler: GRDBLiveQueryRetryScheduler?,
        fetch: @escaping @Sendable (inout GRDBDatabaseDriverConnection) throws -> Value
    ) throws -> GRDBLiveQueryAsyncBridge<Value> {
        guard statement.databaseIdentifier == databaseIdentifier else {
            throw XLDatabaseContractError.driverMismatch(
                expectedDatabase: statement.databaseIdentifier,
                actualDatabase: databaseIdentifier,
                driver: driverIdentifier
            )
        }
        guard let databasePool else {
            throw XLTransactionScopeError.liveQueriesUnsupportedInTransaction
        }
        let driver = self
        let queue = DispatchQueue(label: "SwiftQL.GRDBLiveQuery")
        return GRDBLiveQueryAsyncBridge(
            policy: retryPolicy,
            scheduler: retryScheduler ?? .queue(queue),
            makeSource: { onError, onChange in
                ValueObservation
                    .trackingConstantRegion { database in
                        var connection = driver.makeConnection(database)
                        return try fetch(&connection)
                    }
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
