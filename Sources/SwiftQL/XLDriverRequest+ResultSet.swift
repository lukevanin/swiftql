//
//  XLDriverRequest+ResultSet.swift
//  SwiftQL
//
//  Scoped result sets: hand the caller a cursor over the rows for the duration
//  of one closure, rather than an array of all of them.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation


extension XLDriverRequest {

    func withResultSet<Result>(
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        try withResultSet(bindings: try legacyBindings.packet(), operation)
    }

    ///
    /// True-streaming override of the ``XLRequest`` default: lends an
    /// `XLResultSet` backed directly by `XLInvocationExecutor<Driver>`'s
    /// row-handle stepper, so `next()` performs one real SQLite step and one
    /// real typed decode, reading each column from the cursor's row (issue
    /// #678) -- nothing is prefetched, and nothing is buffered beyond the one
    /// row currently being decoded.
    ///
    /// A `RETURNING` request (`requiresWriteConnection`) is the one
    /// exception. It changes the database, and a pooled reader connection is
    /// read-only, so it must run in a transaction on the writer connection.
    /// Streaming it lazily would hold that writer, and the transaction, open
    /// across every `next()` call in the caller's code. So a `RETURNING`
    /// request decodes every row eagerly inside its transaction -- exactly
    /// like `fetchAll(bindings:)` -- before handing the already-decoded rows
    /// to the caller through the same lazy `next()` surface. Stopping early
    /// would not leave a partial write in any case: SQLite applies every
    /// change of the statement during its first step, and the later steps only
    /// return the `RETURNING` rows (issue #643). Non-`RETURNING` requests are
    /// unaffected and stream lazily.
    ///
    func withResultSet<Result>(
        bindings: any XLInvocationBindingPacket,
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        let packet = try executor.validatedPacket(bindings, for: "withResultSet", logger: logger)

        if requiresWriteConnection {
            let items = try executor.driver.withBlockingTransaction { connection in
                try decodeRows(packet: packet, in: &connection)
            }
            // The shared eager fallback from `XLRequest` (see
            // `SQLDatabase.swift`). A `RETURNING` statement changes the
            // database, so its rows are decoded inside the transaction above,
            // on the writer, and are already in memory by the time `operation`
            // runs -- there is no cursor left to stream from.
            return try withEagerResultSet(items, operation)
        }

        let rowDecoder = XLRowDecoder(reader: reader)
        return try executor.withRowHandleStepper(
            packet: packet,
            requiresWriteConnection: false
        ) { rowStepper in
            let resultSet = XLResultSet<Row>(stepper: {
                guard let row = try rowStepper() else {
                    return nil
                }
                return try rowDecoder.decode(row: row)
            })
            defer { resultSet.close() }
            return try operation(resultSet)
        }
    }
}
