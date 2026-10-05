//
//  XLDriverRequest+Fetch.swift
//  SwiftQL
//
//  Eager fetching: run the statement, decode every row, return an array.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation


extension XLDriverRequest {

    func fetchAll() throws -> [Row] {
        try fetchAll(bindings: legacyBindings.packet())
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        let packet = try executor.validatedPacket(bindings, for: "fetchAll", logger: logger)
        return try withBlockingConnection { connection in
            try decodeRows(packet: packet, in: &connection)
        }
    }

    ///
    /// Runs `operation` on the connection this request reads from: a pooled
    /// reader for a query, or the writer inside a transaction for a
    /// `RETURNING` statement (issue #643), because a pooled reader is
    /// read-only.
    ///
    /// Every fetch decodes inside `operation`, so a `RETURNING` row that fails
    /// to decode rolls the statement back instead of reporting an error for a
    /// committed change. ``withConnection(_:)`` makes the same choice with the
    /// driver's asynchronous scopes (issue #681).
    ///
    func withBlockingConnection<Result>(
        _ operation: (inout Driver.Connection) throws -> Result
    ) throws -> Result {
        if requiresWriteConnection {
            return try executor.driver.withBlockingTransaction(operation)
        }
        return try executor.driver.withBlockingReadConnection(operation)
    }

    ///
    /// The asynchronous form of ``withBlockingConnection(_:)``, for
    /// `XLDriverAsyncRequest` (issue #681): the same reader-or-writer choice, made
    /// with the driver's asynchronous scopes.
    ///
    func withConnection<Result: Sendable>(
        _ operation: @Sendable (inout Driver.Connection) throws -> Result
    ) async throws -> Result {
        if requiresWriteConnection {
            return try await executor.driver.withTransaction(operation)
        }
        return try await executor.driver.withReadConnection(operation)
    }

    func decodeRows(
        packet: XLValidatedSQLitePacket,
        in connection: inout Driver.Connection
    ) throws -> [Row] {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRowHandle(packet: packet, in: &connection) { row in
            do {
                let item = try rowDecoder.decode(row: row)
                items.append(item)
                return .advance
            }
            catch {
                logger?.error("fetchAll : Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }

    ///
    /// Fetches at most `limit` rows. On a `RETURNING` statement this is still
    /// safe to stop early: SQLite applies every change of the statement during
    /// its first step, so the rows left unread are only output, never
    /// unapplied work. The commit needs the statement to be reset first,
    /// because SQLite refuses to commit while a statement is still in
    /// progress. The connection contract releases the cursor behind
    /// `forEachRowHandle` when it returns (issues #682 and #678), which
    /// resets the statement before the transaction commits.
    ///
    func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        let packet = try executor.validatedPacket(bindings, for: "fetchAtMost(\(limit))", logger: logger)
        return try withBlockingConnection { connection in
            try decodeRows(packet: packet, limit: limit, in: &connection)
        }
    }

    func decodeRows(
        packet: XLValidatedSQLitePacket,
        limit: Int,
        in connection: inout Driver.Connection
    ) throws -> [Row] {
        precondition(limit >= 0, "fetchAtMost(_:bindings:) requires limit >= 0, got \(limit).")
        guard limit > 0 else {
            return []
        }
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRowHandle(packet: packet, in: &connection) { row in
            do {
                let item = try rowDecoder.decode(row: row)
                items.append(item)
                return items.count < limit ? .advance : .stop
            }
            catch {
                logger?.error("fetchAtMost(\(limit)): Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }

    func fetchOne() throws -> Row? {
        try fetchOne(bindings: legacyBindings.packet())
    }

    ///
    /// Fetches the first row. A `RETURNING` statement decodes it inside its
    /// transaction, so a row that fails to decode rolls the statement back. A
    /// query decodes it after the reader is released, as it always has, so
    /// the decode holds no connection.
    ///
    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        let packet = try executor.validatedPacket(bindings, for: "fetchOne", logger: logger)
        if requiresWriteConnection {
            return try executor.driver.withBlockingTransaction { connection in
                try decode(executor.fetchOne(packet: packet, in: &connection))
            }
        }
        let values = try executor.driver.withBlockingReadConnection { connection in
            try executor.fetchOne(packet: packet, in: &connection)
        }
        return try decode(values)
    }

    ///
    /// The asynchronous form of ``fetchOne(bindings:)`` after validation, for
    /// `XLDriverAsyncRequest` (issue #681). It decodes where the synchronous form
    /// does: a `RETURNING` row inside its transaction, a query's row after the
    /// reader is released.
    ///
    func fetchOne(packet: XLValidatedSQLitePacket) async throws -> Row? {
        let executor = executor
        if requiresWriteConnection {
            // The decode runs in the driver's `@Sendable` operation, so the
            // request travels in its `Sendable` view.
            let view = XLDriverAsyncRequest(request: self)
            return try await executor.driver.withTransaction { connection in
                try view.request.decode(executor.fetchOne(packet: packet, in: &connection))
            }
        }
        let values = try await executor.driver.withReadConnection { connection in
            try executor.fetchOne(packet: packet, in: &connection)
        }
        return try decode(values)
    }

    /// Decodes the values of one row, or returns `nil` when there is none.
    func decode(_ values: [XLSQLiteValue]?) throws -> Row? {
        guard let values else {
            return nil
        }
        return try GRDBRowDecoder(reader: reader).decode(values: values)
    }
}
