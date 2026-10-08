//
//  XLDriverRequest+Async.swift
//  SwiftQL
//
//  Issue #681: the asynchronous request surface, generic over the driver
//  since issue #682. Each fetch
//  validates its packet as the synchronous fetch does, then runs the same
//  per-connection work inside the driver's asynchronous scope (#676), so the
//  calling task suspends on the driver's executor (on GRDB's queue, for the
//  GRDB driver) instead of blocking its thread.
//

import Foundation


extension XLDriverRequest {

    var async: any XLAsyncRequest<Row> {
        XLDriverAsyncRequest(request: self)
    }
}


extension XLDriverWriteRequest {

    var async: any XLAsyncWriteRequest {
        XLDriverAsyncWriteRequest(request: self)
    }
}


///
/// The asynchronous fetches of an `XLDriverRequest`.
///
/// A plain query reads on a pooled reader. A `RETURNING` query runs in a
/// transaction on the writer, as its synchronous fetches do (issue #643).
///
/// `@unchecked Sendable` because the request's row reader is not `Sendable`.
/// The request is an immutable copy here, and a request is already called
/// from many threads: a database that supplies a render-once cache key, as
/// `GRDBDatabase` does, has a declared query's cache hand one request to
/// callers on any thread. The reader runs only inside the driver's operation, while the
/// calling task waits for it.
///
struct XLDriverAsyncRequest<Driver, Row: Sendable>: XLAsyncRequest, @unchecked Sendable
    where Driver: XLBlockingDatabaseDriver,
          Driver: XLObservingDatabaseDriver,
          Driver.Dialect == XLSQLiteDialect
{

    let request: XLDriverRequest<Driver, Row>

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
/// The asynchronous execution of an `XLDriverWriteRequest`, in a
/// transaction on the writer as its synchronous `execute()` runs.
///
struct XLDriverAsyncWriteRequest<Driver: XLBlockingDatabaseDriver>: XLAsyncWriteRequest
    where Driver.Dialect == XLSQLiteDialect
{

    let request: XLDriverWriteRequest<Driver>

    @discardableResult
    func execute() async throws -> XLExecutionResult {
        try Task.checkCancellation()
        return try await execute(bindings: request.legacyBindings.packet())
    }

    @discardableResult
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
