//
//  GRDBRequest+Async.swift
//  SwiftQL
//
//  Issue #681: the GRDB adapter's asynchronous request surface. Each fetch
//  validates its packet as the synchronous fetch does, then runs the same
//  per-connection work inside the driver's asynchronous scope (#676), so the
//  calling task suspends on GRDB's queue instead of blocking its thread.
//

import Foundation
import GRDB


extension GRDBRequest {

    var async: any XLAsyncRequest<Row> {
        GRDBAsyncRequest(request: self)
    }
}


extension GRDBWriteRequest {

    var async: any XLAsyncWriteRequest {
        GRDBAsyncWriteRequest(request: self)
    }
}


///
/// The asynchronous fetches of a ``GRDBRequest``.
///
/// A plain query reads on a pooled reader. A `RETURNING` query runs in a
/// transaction on the writer, as its synchronous fetches do (issue #643).
///
/// `@unchecked Sendable` because the request's row reader is not `Sendable`.
/// The request is an immutable copy here, and a GRDB request is already
/// called from many threads: `GRDBDatabase` supplies a render-once cache key,
/// so a declared query's cache hands one `GRDBRequest` to callers on any
/// thread. The reader runs only inside the driver's operation, while the
/// calling task waits for it.
///
struct GRDBAsyncRequest<Row: Sendable>: XLAsyncRequest, @unchecked Sendable {

    let request: GRDBRequest<Row>

    func fetchAll() async throws -> [Row] {
        try await fetchAll(bindings: request.legacyBindings.packet())
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) async throws -> [Row] {
        let packet = try request.executor.sqlitePacket(bindings)
        request.logger?.debug(
            "fetchAll: <<<\(request.executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        return try await withConnection { request, connection in
            try request.decodeRows(packet: packet, in: &connection)
        }
    }

    func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) async throws -> [Row] {
        let packet = try request.executor.sqlitePacket(bindings)
        request.logger?.debug(
            "fetchAtMost(\(limit)): <<<\(request.executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        return try await withConnection { request, connection in
            try request.decodeRows(packet: packet, limit: limit, in: &connection)
        }
    }

    func fetchOne() async throws -> Row? {
        try await fetchOne(bindings: request.legacyBindings.packet())
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) async throws -> Row? {
        let packet = try request.executor.sqlitePacket(bindings)
        request.logger?.debug(
            "fetchOne: <<<\(request.executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        let values = try await withConnection { request, connection in
            try request.executor.fetchOne(packet: packet, in: &connection)
        }
        guard let values else {
            return nil
        }
        return try GRDBRowDecoder(reader: request.reader).decode(values: values)
    }

    ///
    /// Runs `operation` on the connection this request reads from: a reader,
    /// or, for a `RETURNING` statement, the writer inside a transaction.
    ///
    private func withConnection<Result: Sendable>(
        _ operation: @escaping @Sendable (GRDBRequest<Row>, inout GRDBDatabaseDriverConnection) throws -> Result
    ) async throws -> Result {
        let driver = request.executor.driver
        let view = self
        if request.requiresWriteConnection {
            return try await driver.withTransaction { connection in
                try operation(view.request, &connection)
            }
        }
        return try await driver.withReadConnection { connection in
            try operation(view.request, &connection)
        }
    }
}


///
/// The asynchronous execution of a ``GRDBWriteRequest``, in a transaction on
/// the writer as its synchronous ``GRDBWriteRequest/execute()`` runs.
///
struct GRDBAsyncWriteRequest: XLAsyncWriteRequest {

    let request: GRDBWriteRequest

    func execute() async throws {
        try await execute(bindings: request.legacyBindings.packet())
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) async throws {
        let executor = request.executor
        let packet = try executor.sqlitePacket(bindings)
        request.logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        try await executor.driver.withTransaction { connection in
            try executor.execute(packet: packet, in: &connection)
        }
    }
}
