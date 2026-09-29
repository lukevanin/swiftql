//
//  GRDBRequest+Fetch.swift
//  SwiftQL
//
//  Eager fetching: run the statement, decode every row, return an array.
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
    /// committed change. `GRDBAsyncRequest` makes the same choice with the
    /// driver's asynchronous scopes (issue #681).
    ///
    func withBlockingConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        if requiresWriteConnection {
            return try executor.driver.withBlockingTransaction(operation)
        }
        return try executor.driver.withBlockingReadConnection(operation)
    }

    func decodeRows(
        packet: XLValidatedSQLitePacket,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRow(packet: packet, in: &connection) { values in
            do {
                let item = try rowDecoder.decode(values: values)
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
    /// progress; the GRDB row cursor behind `forEachRow` resets it when it is
    /// released, before the transaction returns.
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
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        precondition(limit >= 0, "fetchAtMost(_:bindings:) requires limit >= 0, got \(limit).")
        guard limit > 0 else {
            return []
        }
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRow(packet: packet, in: &connection) { values in
            do {
                let item = try rowDecoder.decode(values: values)
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

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        let packet = try executor.validatedPacket(bindings, for: "fetchOne", logger: logger)
        return try withBlockingConnection { connection in
            try decodeOne(packet: packet, in: &connection)
        }
    }

    func decodeOne(
        packet: XLValidatedSQLitePacket,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> Row? {
        guard let values = try executor.fetchOne(packet: packet, in: &connection) else {
            return nil
        }
        return try GRDBRowDecoder(reader: reader).decode(values: values)
    }
}
