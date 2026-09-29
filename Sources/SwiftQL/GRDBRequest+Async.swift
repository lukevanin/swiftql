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
        let packet = try request.validatedPacket(bindings, for: "fetchAll")
        return try await withConnection { connection in
            try request.decodeRows(packet: packet, in: &connection)
        }
    }

    func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) async throws -> [Row] {
        let packet = try request.validatedPacket(bindings, for: "fetchAtMost(\(limit))")
        return try await withConnection { connection in
            try request.decodeRows(packet: packet, limit: limit, in: &connection)
        }
    }

    func fetchOne() async throws -> Row? {
        try await fetchOne(bindings: request.legacyBindings.packet())
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) async throws -> Row? {
        let packet = try request.validatedPacket(bindings, for: "fetchOne")
        return try await withConnection { connection in
            try request.decodeOne(packet: packet, in: &connection)
        }
    }

    ///
    /// Runs `operation` on the connection this request reads from: a reader,
    /// or, for a `RETURNING` statement, the writer inside a transaction. Each
    /// fetch decodes inside `operation`, so a `RETURNING` row that fails to
    /// decode rolls the statement back.
    ///
    private func withConnection<Result: Sendable>(
        _ operation: @Sendable (inout GRDBDatabaseDriverConnection) throws -> Result
    ) async throws -> Result {
        let driver = request.executor.driver
        if request.requiresWriteConnection {
            return try await driver.withTransaction(operation)
        }
        return try await driver.withReadConnection(operation)
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
        let packet = try request.validatedPacket(bindings)
        try await executor.driver.withTransaction { connection in
            try executor.execute(packet: packet, in: &connection)
        }
    }
}
