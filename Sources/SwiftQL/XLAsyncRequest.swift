//
//  XLAsyncRequest.swift
//  SwiftQL
//
//  Issue #681: the asynchronous request surface. A request's fetches and a
//  write request's execution can be awaited through its `async` view, which
//  suspends the calling task while the driver's asynchronous scope (#676)
//  lends a connection, instead of blocking the calling thread.
//
//  The view is a separate value rather than `async` overloads of the existing
//  methods. Swift prefers an `async` overload inside an asynchronous function,
//  so overloading `fetchAll()` would make every existing
//  `try request.fetchAll()` in asynchronous code fail to compile until it
//  gained an `await`. The synchronous methods keep their meaning everywhere.
//

import Foundation


///
/// The asynchronous fetches of a prepared query, reached through
/// ``XLRequest/async``.
///
/// Each method runs the same rendered SQL with the same invocation packet as
/// the synchronous method of the same name, and decodes rows the same way. The
/// only difference is how the caller waits for a connection: the calling task
/// suspends instead of blocking its thread.
///
/// A task that is already cancelled gets `CancellationError` before a
/// connection is lent. An adapter may also interrupt a running statement when
/// its task is cancelled; the GRDB adapter does, and a fetch that reads the
/// rows of a `RETURNING` statement then rolls the statement back.
///
/// With the GRDB adapter, a request made from a
/// ``XLTransactionalDatabase/withTransaction(_:)`` scope has no asynchronous
/// form: its connection belongs to the synchronous body, and awaiting it throws
/// ``XLTransactionScopeError/scopeEscaped``. Another adapter's view decides for
/// itself; the ``XLRequest/async`` default calls the synchronous fetch, which
/// is only as safe outside the scope as the adapter's request is.
///
public protocol XLAsyncRequest<Row>: Sendable {

    /// The decoded row type.
    associatedtype Row: Sendable

    ///
    /// Fetches all rows, with the bindings set through the request's
    /// `set(parameter:value:)` methods, read as ``XLRequest/async`` describes.
    ///
    /// The fetch is atomic: if executing the query or decoding any row fails,
    /// no partial result is returned.
    ///
    func fetchAll() async throws -> [Row]

    /// Fetches all rows with one immutable per-invocation binding packet.
    func fetchAll(bindings: any XLInvocationBindingPacket) async throws -> [Row]

    ///
    /// Fetches at most `limit` rows with one immutable per-invocation binding
    /// packet, stopping as soon as `limit` rows have been decoded.
    ///
    /// - Precondition: `limit >= 0`.
    ///
    func fetchAtMost(_ limit: Int, bindings: any XLInvocationBindingPacket) async throws -> [Row]

    ///
    /// Fetches the first row, with the bindings set through the request's
    /// `set(parameter:value:)` methods, read as ``XLRequest/async`` describes.
    ///
    func fetchOne() async throws -> Row?

    /// Fetches the first row with one immutable per-invocation binding packet.
    func fetchOne(bindings: any XLInvocationBindingPacket) async throws -> Row?
}


///
/// The asynchronous execution of a prepared write statement, reached through
/// ``XLWriteRequest/async``.
///
/// It executes the same rendered SQL with the same invocation packet as the
/// synchronous ``XLWriteRequest/execute()``. See ``XLAsyncRequest`` for
/// cancellation and transaction scopes.
///
public protocol XLAsyncWriteRequest: Sendable {

    ///
    /// Executes the statement, with the bindings set through the request's
    /// `set(parameter:value:)` methods, read as ``XLRequest/async`` describes.
    ///
    func execute() async throws

    /// Executes the statement with one immutable per-invocation binding packet.
    func execute(bindings: any XLInvocationBindingPacket) async throws
}


extension XLRequest {

    ///
    /// Compatibility default for request adapters that predate
    /// ``XLAsyncRequest``: each asynchronous fetch checks for cancellation,
    /// then calls the synchronous fetch of the same name on a Dispatch global
    /// queue, and suspends the awaiting task until it returns.
    ///
    /// It keeps an existing adapter compiling without blocking a thread of
    /// Swift's cooperative pool. A running fetch cannot be interrupted, and it
    /// runs on a thread other than the one that made the request. The view is
    /// `Sendable`, so code on an actor can await it. The default therefore
    /// assumes the adapter's request can be called from another thread. An
    /// adapter that can suspend on its own connection, or whose request cannot
    /// be called from another thread, overrides this property.
    ///
    public var async: any XLAsyncRequest<Row> {
        XLBlockingAsyncRequest(request: self)
    }
}


extension XLWriteRequest {

    ///
    /// Compatibility default for request adapters that predate
    /// ``XLAsyncWriteRequest``: asynchronous execution checks for
    /// cancellation, then calls the synchronous ``execute()`` on a Dispatch
    /// global queue. It makes the same assumption about the adapter's request
    /// as ``XLRequest/async``.
    ///
    public var async: any XLAsyncWriteRequest {
        XLBlockingAsyncWriteRequest(request: self)
    }
}


///
/// The ``XLRequest/async`` default: the synchronous fetches, run on a Dispatch
/// global queue while the awaiting task suspends.
///
/// `@unchecked Sendable` because the view must be `Sendable`, so code on an
/// actor can await it, while the wrapped request need not be. That is the
/// assumption ``XLRequest/async`` documents: the adapter's request can be
/// called from a thread other than the one that made it. An adapter for which
/// that is false overrides `async`.
///
struct XLBlockingAsyncRequest<Request: XLRequest>: XLAsyncRequest, @unchecked Sendable {

    let request: Request

    func fetchAll() async throws -> [Request.Row] {
        try await xlRunOffCooperativePool { try request.fetchAll() }
    }

    func fetchAll(bindings: any XLInvocationBindingPacket) async throws -> [Request.Row] {
        try await xlRunOffCooperativePool { try request.fetchAll(bindings: bindings) }
    }

    func fetchAtMost(_ limit: Int, bindings: any XLInvocationBindingPacket) async throws -> [Request.Row] {
        try await xlRunOffCooperativePool { try request.fetchAtMost(limit, bindings: bindings) }
    }

    func fetchOne() async throws -> Request.Row? {
        try await xlRunOffCooperativePool { try request.fetchOne() }
    }

    func fetchOne(bindings: any XLInvocationBindingPacket) async throws -> Request.Row? {
        try await xlRunOffCooperativePool { try request.fetchOne(bindings: bindings) }
    }
}


///
/// The ``XLWriteRequest/async`` default. `@unchecked Sendable` for the reason
/// given on ``XLBlockingAsyncRequest``.
///
struct XLBlockingAsyncWriteRequest<Request: XLWriteRequest>: XLAsyncWriteRequest, @unchecked Sendable {

    let request: Request

    func execute() async throws {
        try await xlRunOffCooperativePool { try request.execute() }
    }

    func execute(bindings: any XLInvocationBindingPacket) async throws {
        try await xlRunOffCooperativePool { try request.execute(bindings: bindings) }
    }
}


///
/// Runs a blocking synchronous call for an asynchronous caller: checks for
/// cancellation, then runs `body` on a Dispatch global queue and suspends the
/// caller until it returns, so the wait holds a Dispatch thread rather than one
/// of Swift's cooperative pool.
///
private func xlRunOffCooperativePool<Value: Sendable>(
    _ body: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(with: Result { try body() })
        }
    }
}
