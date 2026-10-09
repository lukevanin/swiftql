//
//  SQLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineFoundation
#endif


extension Notification.Name {
    static let XLEntitiesChanged = Notification.Name("swiftql.entitiesChanged")
}

extension String {
    static let XLEntities = "swiftql.entities"
}

extension NotificationCenter {
    
    @available(*, deprecated, message: "Live queries no longer consume global entity notifications. Use XLRequest.stream() or XLRequest.publish().")
    public func sqlEntitiesChangedPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLEntitiesChanged)
    }
    
    @available(*, deprecated, message: "Live queries no longer consume global entity notifications. Use XLRequest.stream() or XLRequest.publish().")
    public func sqlEntitiesChangedObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLEntitiesChanged,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "Live queries no longer consume global entity notifications. Observe with XLRequest.stream() or XLRequest.publish().")
    public func postSQLEntitiesChangedNotification(entities: Set<String>) {
        post(
            name: .XLEntitiesChanged,
            object: nil,
            userInfo: [
                String.XLEntities: entities
            ]
        )
    }
}


extension Notification.Name {
    static let XLCommit = Notification.Name("swiftql.commit")
}

extension NotificationCenter {
    
    @available(*, deprecated, message: "Live queries no longer consume global commit notifications. Use XLRequest.stream() or XLRequest.publish().")
    public func sqlCommitPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLCommit)
    }
    
    @available(*, deprecated, message: "Live queries no longer consume global commit notifications. Use XLRequest.stream() or XLRequest.publish().")
    public func sqlCommitObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLCommit,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "Live queries no longer consume global commit notifications. Observe with XLRequest.stream() or XLRequest.publish().")
    public func postSQLCommitNotification() {
        post(
            name: .XLCommit,
            object: nil,
            userInfo: [:]
        )
    }
}


///
/// Constructs a prepared select query statement with parameters.
///
public struct XLRequestBuilder<Row: Sendable> {
    
    public typealias Parameterize = (inout any XLRequest<Row>) -> Void
    
    private let statement: any XLQueryStatement<Row>
    
    private let parameterize: Parameterize
    
    public init(with statement: any XLQueryStatement<Row>, parameterize: @escaping Parameterize) {
        self.statement = statement
        self.parameterize = parameterize
    }
    
    public func build(with database: XLDatabase) -> any XLRequest<Row> {
        var request = database.makeRequest(with: statement)
        parameterize(&request)
        return request
    }
}


///
/// A prepared select query statement.
///
/// Read ``parameterLayout`` to construct an immutable `XLInvocationBindings` packet, then pass
/// that packet to the binding-aware fetch or publish method for each execution. This keeps the
/// prepared request's static SQL separate from its per-invocation values.
///
/// The mutating `set` methods remain available as v1 source-compatibility shims while callers migrate
/// to invocation packets. Use the fetch methods to execute the query, and the stream methods to
/// observe it as a live query.
///
/// ## Live queries
///
/// The four stream members are the live-query requirements (issue #684): ``stream()``,
/// ``stream(bindings:)``, ``streamOne()``, and ``streamOne(bindings:)``. An adapter implements them
/// with `AsyncThrowingStream` and needs neither Combine nor OpenCombine to conform. The `bindings:`
/// variants have compatibility defaults for an adapter without invocation packets, as the fetch
/// members do.
///
/// The Combine members, ``publish()``, ``publish(bindings:)``, ``publishOne()``, and
/// ``publishOne(bindings:)``, are not requirements. SwiftQL implements them for every request,
/// over the stream members, through ``XLAsyncStreamPublisher``. An adapter that only has a Combine
/// publisher implements each stream member in one line with ``XLPublisherAsyncBridge``.
///
public protocol XLRequest<Row> {

    ///
    /// The decoded row type.
    ///
    /// `Sendable` because a row crosses an isolation boundary on every
    /// observation path: `stream()` hands a snapshot to an iterating task, and
    /// `publish()` hands one to a subscriber.
    ///
    /// The constraint sits here, on the associated type, rather than on the
    /// observation members, because Swift can express it nowhere else. A
    /// constraint on an individual protocol requirement is rejected outright,
    /// and a refinement that adds it cannot be conformed to conditionally,
    /// because `Sendable` is a marker protocol with no runtime representation.
    /// Both were tried; see issue #685.
    ///
    associatedtype Row: Sendable

    /// Immutable static parameter metadata captured when the request was prepared.
    var parameterLayout: XLParameterLayout { get }
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable
    
    ///
    /// Assigns a literal value to a variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Fetches all rows returned by the query.
    ///
    /// The fetch is atomic: if executing the query or decoding any row fails, no partial result is returned.
    ///
    /// - Throws: The original query-execution or row-decoding error.
    ///
    func fetchAll() throws -> [Row]

    /// Fetches all rows with one immutable per-invocation binding packet.
    func fetchAll(bindings: any XLInvocationBindingPacket) throws -> [Row]

    ///
    /// Fetches at most `limit` rows with one immutable per-invocation binding packet, stopping as soon
    /// as `limit` rows have been decoded rather than materializing every matching row.
    ///
    /// Use this to check a query's cardinality (e.g. "zero, one, or more than one row?") without paying
    /// to decode and retain every row when many might match.
    ///
    /// - Precondition: `limit >= 0`.
    /// - Throws: The original query-execution or row-decoding error.
    ///
    func fetchAtMost(_ limit: Int, bindings: any XLInvocationBindingPacket) throws -> [Row]

    ///
    /// Fetches the first row returned by the query.
    ///
    /// - Throws: The original query-execution or row-decoding error.
    ///
    func fetchOne() throws -> Row?

    /// Fetches the first row with one immutable per-invocation binding packet.
    func fetchOne(bindings: any XLInvocationBindingPacket) throws -> Row?

    ///
    /// Executes `operation` with a single-pass ``XLResultSet`` built from
    /// zero bindings, exposing at most one additional row per `next()` call
    /// instead of every matching row up front.
    ///
    /// This protocol requirement does not itself guarantee lazy stepping --
    /// see ``XLResultSet`` for which implementations are truly streaming
    /// (decoding at most one row per `next()`, with no row fetched or decoded
    /// before `operation` calls `next()` for it) versus eager (this
    /// protocol's own compatibility default, which calls ``fetchAll()``
    /// under the hood, and `XLDriverRequest`'s `RETURNING` exception) -- both
    /// still honor `XLResultSet`'s single-pass reference semantics, throwing
    /// iteration, non-`Sendable` isolation, scope lifetime, and
    /// partial-progress behavior, just not the streaming cost profile.
    ///
    /// - Throws: The original query-execution error, or whatever `operation` throws.
    ///
    func withResultSet<Result>(
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result

    ///
    /// Executes `operation` with a lazy, single-pass ``XLResultSet`` for one
    /// immutable per-invocation binding packet. See ``withResultSet(_:)``.
    ///
    func withResultSet<Result>(
        bindings: any XLInvocationBindingPacket,
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result

    ///
    /// The asynchronous fetches of this request (issue #681).
    ///
    /// `try await request.async.fetchAll()` runs the same SQL with the same
    /// bindings as `try request.fetchAll()`, but suspends the calling task
    /// instead of blocking its thread while it waits for a connection. A view
    /// taken from a request that is a value, as SwiftQL's own requests are, carries the
    /// bindings set through `set(parameter:value:)` when it is taken; one
    /// taken from a class reads them when it fetches. See ``XLAsyncRequest``.
    ///
    var async: any XLAsyncRequest<Row> { get }

    ///
    /// Returns SwiftQL's canonical async live-query source (issue #308): a complete snapshot of every
    /// row returned by the query, delivered through Swift structured concurrency.
    ///
    /// This is a live-query requirement (issue #684). ``publish()`` is built on it, so an adapter
    /// implements this member, never the publisher. An adapter that only has a Combine publisher
    /// implements it in one line with ``XLPublisherAsyncBridge``. An adapter whose driver conforms
    /// to `XLObservingDatabaseDriver` can build it on that driver's `observe(_:fetch:)`.
    ///
    /// Observation begins with iteration, not merely by constructing the returned stream: only the
    /// first `next()` call (directly, or via `for try await`) starts the underlying observation. Each
    /// call to `stream()` creates one independent, single-consumer observation, and each subscriber
    /// to ``publish()`` gets its own call. Two consumers that both want live updates must call
    /// `stream()` twice; concurrently iterating one returned stream value from two places is not a
    /// supported fan-out.
    ///
    /// The stream buffers at most one undelivered snapshot: a newly produced snapshot always replaces,
    /// never queues behind, a snapshot the consumer has not yet asked for. Resuming iteration delivers
    /// whatever has already been produced — it does not itself force a fresh fetch. See
    /// <doc:LiveQueries>, "Buffering and Resumed-Demand Semantics (#291)", for the full contract
    /// this implements.
    ///
    /// Fetching is all-or-nothing, exactly like `fetchAll()`: if the query cannot execute
    /// or any row cannot be decoded, iteration throws the original error and does not yield a truncated
    /// result. Cancelling the consuming `Task` ends iteration — `next()` resolves to `nil`, never a
    /// thrown `CancellationError` — and tears down the underlying observation; it never surfaces as a
    /// completion failure.
    ///
    /// This is a complete live-query snapshot, distinct from ``XLRequest``'s `RETURNING`-based readback
    /// and from a lazy, single-pass, row-by-row result cursor (issue #249): every delivery here is the
    /// full matching row set as of one committed transaction, and the same query can deliver many
    /// snapshots over the stream's lifetime.
    ///
    func stream() -> AsyncThrowingStream<[Row], Error>

    /// Observes all rows using one immutable packet for every initial fetch, refresh, and retry.
    /// ``publish(bindings:)`` is built on it. The packet is captured and validated once; it is never
    /// re-read from mutable request state.
    ///
    /// A default implementation serves an adapter without invocation packets: an empty packet
    /// observes through ``stream()``, and any other packet fails on the first `next()` call.
    func stream(bindings: any XLInvocationBindingPacket) -> AsyncThrowingStream<[Row], Error>

    ///
    /// Returns SwiftQL's canonical async live-query source (issue #308) for just the first row.
    /// ``publishOne()`` is built on it. See ``stream()`` for the full observation, buffering, and
    /// cancellation contract; `streamOne()` differs only in delivering `Row?` snapshots instead of
    /// `[Row]` snapshots.
    ///
    func streamOne() -> AsyncThrowingStream<Row?, Error>

    /// Observes the first row using one immutable packet for every initial fetch, refresh, and retry.
    /// ``publishOne(bindings:)`` is built on it.
    func streamOne(bindings: any XLInvocationBindingPacket) -> AsyncThrowingStream<Row?, Error>
}

extension XLRequest {

    /// Compatibility default for request adapters that do not yet expose static
    /// parameter metadata.
    public var parameterLayout: XLParameterLayout {
        .empty
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        try validateCompatibilityBindings(bindings)
        return try fetchAll()
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        try validateCompatibilityBindings(bindings)
        return try fetchOne()
    }

    /// Compatibility default for adapters that predate ``XLResultSet``: eagerly fetches every row
    /// with ``fetchAll()``, then serves the already-decoded rows one at a time through the same
    /// `next()` surface a true streaming adapter exposes. External conformers written before this
    /// requirement existed keep compiling and behaving correctly; only the memory and latency
    /// benefit of true row-at-a-time streaming requires an adapter override (see
    /// `XLDriverRequest.withResultSet(bindings:_:)` for SwiftQL's own true-streaming implementation).
    public func withResultSet<Result>(
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        try withEagerResultSet(fetchAll(), operation)
    }

    /// Compatibility default for adapters that predate ``XLResultSet``. See ``withResultSet(_:)``.
    public func withResultSet<Result>(
        bindings: any XLInvocationBindingPacket,
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        try withEagerResultSet(fetchAll(bindings: bindings), operation)
    }

    /// Presents rows already in memory as a result set.
    ///
    /// Internal rather than private so `XLDriverRequest` can use it for the case
    /// where it has already decoded every row -- it carried a verbatim copy
    /// (issue #561), which `private` being file-scoped had forced.
    package func withEagerResultSet<Result>(
        _ rows: [Row],
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        var iterator = rows.makeIterator()
        let resultSet = XLResultSet<Row>(stepper: { iterator.next() })
        defer { resultSet.close() }
        return try operation(resultSet)
    }

    /// Compatibility default for adapters that do not implement early-stopping decode: fetches every
    /// row and truncates. Adapters that can decode incrementally (e.g. `XLDriverRequest`) override this to
    /// actually stop after `limit` rows.
    public func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        precondition(limit >= 0, "fetchAtMost(_:bindings:) requires limit >= 0, got \(limit).")
        guard limit > 0 else {
            return []
        }
        return Array(try fetchAll(bindings: bindings).prefix(limit))
    }

    private func validateCompatibilityBindings(
        _ bindings: any XLInvocationBindingPacket
    ) throws {
        guard bindings.layout.isEmpty,
              bindings.bindingCount == 0,
              bindings.isComplete else {
            throw XLRequestBindingError.unsupportedInvocationBindings(
                requestType: String(reflecting: Self.self),
                layout: bindings.layout
            )
        }
    }

    ///
    /// Compatibility default for request adapters without invocation packets, as
    /// ``fetchAll(bindings:)`` is: an empty packet observes through ``stream()``, and any other
    /// packet fails instead of being silently ignored.
    ///
    /// The failure is lazy, like every other live-query failure. Calling this does no work, and
    /// the first `next()` call throws ``XLRequestBindingError/unsupportedInvocationBindings(requestType:layout:)``,
    /// unless the consuming task is already cancelled, when it returns `nil`.
    ///
    /// This default never calls a publish member: since issue #684 those are built on the stream
    /// members, so a default bridging them would call itself.
    ///
    public func stream(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<[Row], Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    /// Compatibility default mirroring ``stream(bindings:)``: an empty packet observes through
    /// ``streamOne()``, and any other packet fails on the first `next()` call.
    public func streamOne(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<Row?, Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return streamOne()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }

    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }

    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


/// Returns an `AsyncThrowingStream` that performs no work until its first
/// `next()` call, at which point it immediately throws `error` and finishes
/// -- unless the consuming `Task` is already cancelled, in which case it
/// resolves to `nil` instead, per the same cancellation contract every other
/// canonical stream honors: cancellation ends iteration with `nil`, never a
/// thrown error, `CancellationError` included. Used when a stream cannot be
/// constructed at all: an invalid invocation packet, including one the
/// `XLRequest` compatibility defaults reject, a `RETURNING` request, or a
/// transaction-scoped driver with no pool to observe. The construction error
/// must still be reported lazily, on first iteration, to preserve
/// "observation begins with iteration, not merely by constructing an unused
/// stream" for every code path, not only the successful one.
///
/// It lives beside those adapter-neutral defaults rather than with the GRDB
/// bridge, which also uses it (issue #684).
package func xlFailingAsyncThrowingStream<Value>(_ error: Error) -> AsyncThrowingStream<Value, Error> {
    AsyncThrowingStream(unfolding: {
        guard !Task.isCancelled else {
            return nil
        }
        throw error
    })
}


///
/// A prepared statement that modifies the database, such as a create, update, insert, or delete statement.
///
/// `XLWriteRequest` differs from `XLRequest` in that it does not provide methods to return results
/// from executing the request.
///
public protocol XLWriteRequest {

    /// Immutable static parameter metadata captured when the request was prepared.
    var parameterLayout: XLParameterLayout { get }
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable

    ///
    /// Assigns a literal value to a named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Executes the statement, and reports what it did: the rows it changed,
    /// and whether it could write (issue #679).
    ///
    @discardableResult
    func execute() throws -> XLExecutionResult

    /// Executes the statement with one immutable per-invocation binding
    /// packet, and reports what it did.
    @discardableResult
    func execute(bindings: any XLInvocationBindingPacket) throws -> XLExecutionResult

    ///
    /// The asynchronous execution of this statement (issue #681).
    ///
    /// `try await request.async.execute()` runs the same SQL with the same
    /// bindings as `try request.execute()`, but suspends the calling task
    /// instead of blocking its thread. It reads the bindings set through
    /// `set(parameter:value:)` as ``XLRequest/async`` describes. See
    /// ``XLAsyncWriteRequest``.
    ///
    var async: any XLAsyncWriteRequest { get }
}

extension XLWriteRequest {

    /// Compatibility default for request adapters that do not yet expose static
    /// parameter metadata.
    public var parameterLayout: XLParameterLayout {
        .empty
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    @discardableResult
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws -> XLExecutionResult {
        guard bindings.layout.isEmpty,
              bindings.bindingCount == 0,
              bindings.isComplete else {
            throw XLRequestBindingError.unsupportedInvocationBindings(
                requestType: String(reflecting: Self.self),
                layout: bindings.layout
            )
        }
        return try execute()
    }
    
    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


///
/// A database that can execute select, update, insert, create, and delete statements.
///
public protocol XLDatabase {
    
    ///
    /// Constructs a prepared query request from a query statement.
    ///
    func makeRequest<Row: Sendable>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row>

    ///
    /// Constructs a prepared, row-readable request from a data-changing statement
    /// that carries a `RETURNING` clause.
    ///
    func makeRequest<Row: Sendable>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row>

    ///
    /// Constructs a prepared update request from an update statement.
    ///
    func makeRequest(with statement: any XLUpdateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared insert request from an insert statement.
    ///
    func makeRequest(with statement: any XLInsertStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared create request from a create statement.
    ///
    func makeRequest(with statement: any XLCreateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared delete request from a delete statement.
    ///
    func makeRequest(with statement: any XLDeleteStatement) -> any XLWriteRequest

    ///
    /// The identity a render-once cache keys on, or `nil` to opt out.
    ///
    /// A macro-generated `@SQLQuery`/`@SQLQueries` executor (issues #18/#26)
    /// renders its statement once per declaration and reuses the request; this
    /// key scopes that reuse. Returning `nil` (the default) renders on every
    /// call. See ``XLPreparedQueryCacheKey``.
    ///
    var preparedQueryCacheKey: XLPreparedQueryCacheKey? { get }
}

extension XLDatabase {

    ///
    /// Convenience method used to make a request for the database using a request builder.
    ///
    func makeRequest<Row: Sendable>(with builder: XLRequestBuilder<Row>) -> any XLRequest<Row> {
        builder.build(with: self)
    }

    ///
    /// Default `RETURNING` support for adapters that predate the clause.
    ///
    /// `makeRequest(with:)` for a returning statement is a protocol requirement;
    /// adding it *without* a default would source-break existing third-party
    /// `XLDatabase` conformers. This default keeps them compiling. An adapter
    /// that can execute a data-changing statement and read its returned rows
    /// overrides this method; until then, constructing a `RETURNING` request
    /// traps with a clear message rather than silently dropping the clause.
    ///
    public func makeRequest<Row: Sendable>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row> {
        preconditionFailure(
            "\(type(of: self)) does not support RETURNING statements. Override "
            + "XLDatabase.makeRequest(with: any XLReturningStatement) to add support."
        )
    }

    ///
    /// Default render-once opt-out for adapters that do not render SQL
    /// deterministically per dialect, or that predate ``XLPreparedQueryCacheKey``.
    /// A macro-generated executor renders on every call exactly as before.
    ///
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        nil
    }
}
