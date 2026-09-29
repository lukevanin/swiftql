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
        try Task.checkCancellation()
        return try await fetchAll(bindings: request.legacyBindings.packet())
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) async throws -> [Row] {
        try Task.checkCancellation()
        let packet = try request.executor.validatedPacket(bindings, for: "fetchAll", logger: request.logger)
        return try await request.withConnection { connection in
            try request.decodeRows(packet: packet, in: &connection)
        }
    }

    func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) async throws -> [Row] {
        try Task.checkCancellation()
        let packet = try request.executor.validatedPacket(bindings, for: "fetchAtMost(\(limit))", logger: request.logger)
        return try await request.withConnection { connection in
            try request.decodeRows(packet: packet, limit: limit, in: &connection)
        }
    }

    func fetchOne() async throws -> Row? {
        try Task.checkCancellation()
        return try await fetchOne(bindings: request.legacyBindings.packet())
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) async throws -> Row? {
        try Task.checkCancellation()
        let packet = try request.executor.validatedPacket(bindings, for: "fetchOne", logger: request.logger)
        return try await request.fetchOne(packet: packet)
    }
}


///
/// The asynchronous execution of a ``GRDBWriteRequest``, in a transaction on
/// the writer as its synchronous ``GRDBWriteRequest/execute()`` runs.
///
struct GRDBAsyncWriteRequest: XLAsyncWriteRequest {

    let request: GRDBWriteRequest

    func execute() async throws -> XLExecutionResult {
        try Task.checkCancellation()
        return try await execute(bindings: request.legacyBindings.packet())
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) async throws -> XLExecutionResult {
        let executor = request.executor
        try Task.checkCancellation()
        let packet = try executor.validatedPacket(bindings, for: "execute", logger: request.logger)
        return try await executor.driver.withTransaction { connection in
            try executor.execute(packet: packet, in: &connection)
        }
    }
}
