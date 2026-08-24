//
//  GRDBRequest+ResultSet.swift
//  SwiftQL
//
//  Scoped result sets: hand the caller a cursor over the rows for the duration
//  of one closure, rather than an array of all of them.
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

    func withResultSet<Result>(
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        try withResultSet(bindings: try legacyBindings.packet(), operation)
    }

    ///
    /// True-streaming override of the ``XLRequest`` default: lends an
    /// `XLResultSet` backed directly by `GRDBInvocationExecutor`'s
    /// value-level cursor stepper, so `next()` performs one real SQLite step
    /// and one real typed decode -- nothing is prefetched, and nothing is
    /// buffered beyond the one row currently being decoded.
    ///
    /// A `RETURNING` request (`requiresWriteConnection`) is the one
    /// exception: `RETURNING` rows are produced as SQLite steps through the
    /// data-changing statement itself, so stepping only part of the cursor
    /// would commit a write that only partially ran. Decoding lazily could
    /// silently apply an incomplete `UPDATE`/`DELETE`/`INSERT` if the caller
    /// stopped calling `next()` early. To keep that impossible, a
    /// `RETURNING` request decodes every row eagerly inside its transaction
    /// -- exactly like `fetchAll(bindings:)` -- before handing the
    /// already-decoded rows to the caller through the same lazy `next()`
    /// surface. Non-`RETURNING` requests are unaffected and stream lazily.
    ///
    func withResultSet<Result>(
        bindings: any XLInvocationBindingPacket,
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "withResultSet: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")

        if requiresWriteConnection {
            var driver = executor.driver
            var items: [Row] = []
            try driver.withTransaction { connection in
                items = try decodeRows(packet: packet, in: &connection)
            }
            return try withEagerResultSet(items, operation)
        }

        let rowDecoder = GRDBRowDecoder(reader: reader)
        return try executor.withValuesStepper(
            packet: packet,
            requiresWriteConnection: false
        ) { valuesStepper in
            let resultSet = XLResultSet<Row>(stepper: {
                guard let values = try valuesStepper() else {
                    return nil
                }
                return try rowDecoder.decode(values: values)
            })
            defer { resultSet.close() }
            return try operation(resultSet)
        }
    }

    /// Mirrors `XLRequest`'s eager compatibility fallback (see
    /// `SQLDatabase.swift`), used only for the `RETURNING` path above where
    /// rows must already be fully decoded before `operation` runs.


    // `publish()`/`publish(bindings:)`/`publishOne()`/`publishOne(bindings:)` are Combine convenience
    // adapters over `stream()`/`streamOne()` (issue #309): they never call `ValueObservation
    // .publisher(in:)` or own a Combine-side retry pipeline. Observation, immutable-packet capture,
    // retry, decoding, and buffering all come from the async stream; `xlLiveQueryPublisher(makeStream:)`
    // only adapts Combine subscription/demand/cancellation and applies the documented main-queue
    // delivery default.
    //
    // Two guard checks below stay eager (a synchronous `Fail`) instead of folding into the lazy stream
    // adapter: `requiresWriteConnection` (a `RETURNING` statement is never observable) and a `nil`
    // `databasePool` (a transaction-scoped driver, issue #284, has no pool to track). Both are pure,
    // already-computed structural checks -- not observation, retry, or decoding logic -- and keeping
    // them synchronous preserves a real regression contract: `SQLTransactionScopeTests
    // .testPublishInsideATransactionFailsPredictablyInsteadOfObservingAnInvalidatedConnection` calls
    // `.publish()` and synchronously waits on the *same* thread `withTransaction(_:)`'s body is running
    // on. `databasePool.write(_:)` blocks the calling thread for that body's duration, so if this fast-
    // fail error were instead delivered lazily through a `Task` plus `.receive(on: DispatchQueue.main)`
    // (as `stream()`/`streamOne()` do), it could never be delivered while that same thread is the one
    // blocked waiting for it -- a deadlock. `Fail` needs no dispatch queue and delivers synchronously,
    // exactly like the pre-#309 implementation did for these two cases.
}
