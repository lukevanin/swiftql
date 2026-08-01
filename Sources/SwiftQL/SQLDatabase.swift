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
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlEntitiesChangedPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLEntitiesChanged)
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlEntitiesChangedObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLEntitiesChanged,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Observe with XLRequest.publish() or GRDB ValueObservation.")
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
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlCommitPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLCommit)
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlCommitObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLCommit,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Observe with XLRequest.publish() or GRDB ValueObservation.")
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
public struct XLRequestBuilder<Row> {
    
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
/// to invocation packets. Use the fetch methods to execute the query, or the publish methods to create
/// an adapter-backed Combine publisher that observes the query's database region.
///
public protocol XLRequest<Row> {
    associatedtype Row

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
    /// under the hood, and `GRDBRequest`'s `RETURNING` exception) -- both
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
    /// Creates a Combine Publisher that observes and emits all rows from the query.
    ///
    /// Observation starts when a subscriber first requests positive demand. Each subscriber receives a
    /// fresh initial value and owns an independent observation. Subscribing with zero demand performs no
    /// database work. Adapter-specific scheduling, write visibility, and connection boundaries apply.
    ///
    /// The publisher fails with the original query-execution or row-decoding error instead of emitting a
    /// partial result. An adapter may expose an explicit retry policy; GRDB-backed requests remain terminal
    /// by default and retry only when their database is configured to do so.
    ///
    func publish() -> AnyPublisher<[Row], Error>

    /// Observes all rows using one immutable packet for every retry and refresh.
    func publish(bindings: any XLInvocationBindingPacket) -> AnyPublisher<[Row], Error>
    
    ///
    /// Creates a Combine Publisher that observes and emits the first row from the query.
    ///
    /// Observation starts when a subscriber first requests positive demand. Each subscriber receives a
    /// fresh initial value and owns an independent observation. Subscribing with zero demand performs no
    /// database work. Adapter-specific scheduling, write visibility, and connection boundaries apply.
    ///
    /// The publisher fails with the original query-execution or row-decoding error. An adapter may expose
    /// an explicit retry policy; GRDB-backed requests remain terminal by default and retry only when their
    /// database is configured to do so.
    ///
    func publishOne() -> AnyPublisher<Row?, Error>

    /// Observes the first row using one immutable packet for every retry and refresh.
    func publishOne(bindings: any XLInvocationBindingPacket) -> AnyPublisher<Row?, Error>

    ///
    /// Returns SwiftQL's canonical async live-query source (issue #308): a complete snapshot of every
    /// row returned by the query, delivered through Swift structured concurrency instead of Combine.
    ///
    /// Observation begins with iteration, not merely by constructing the returned stream: only the
    /// first `next()` call (directly, or via `for try await`) starts the underlying observation. Each
    /// call to `stream()` creates one independent, single-consumer observation — exactly like each
    /// `publish()` call today creates one independent Combine subscription. Two consumers that both
    /// want live updates must call `stream()` twice; concurrently iterating one returned stream value
    /// from two places is not a supported fan-out.
    ///
    /// The stream buffers at most one undelivered snapshot: a newly produced snapshot always replaces,
    /// never queues behind, a snapshot the consumer has not yet asked for. Resuming iteration delivers
    /// whatever has already been produced — it does not itself force a fresh fetch. See
    /// <doc:LiveQueries>, "Buffering and Resumed-Demand Semantics (#291)", for the full contract
    /// this implements.
    ///
    /// Fetching is all-or-nothing, exactly like `fetchAll()`/`publish()`: if the query cannot execute
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

    /// Observes all rows using one immutable packet for every initial fetch, refresh, and retry — the
    /// async analog of ``publish(bindings:)``. The packet is captured and validated once; it is never
    /// re-read from mutable request state.
    func stream(bindings: any XLInvocationBindingPacket) -> AsyncThrowingStream<[Row], Error>

    ///
    /// Returns SwiftQL's canonical async live-query source (issue #308) for just the first row: the
    /// async analog of ``publishOne()``. See ``stream()`` for the full observation, buffering, and
    /// cancellation contract; `streamOne()` differs only in delivering `Row?` snapshots instead of
    /// `[Row]` snapshots.
    ///
    func streamOne() -> AsyncThrowingStream<Row?, Error>

    /// Observes the first row using one immutable packet for every initial fetch, refresh, and retry —
    /// the async analog of ``publishOne(bindings:)``.
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
    /// `GRDBRequest.withResultSet(bindings:_:)` for the true-streaming GRDB implementation).
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

    private func withEagerResultSet<Result>(
        _ rows: [Row],
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        var iterator = rows.makeIterator()
        let resultSet = XLResultSet<Row>(stepper: { iterator.next() })
        defer { resultSet.close() }
        return try operation(resultSet)
    }

    /// Compatibility default for adapters that do not implement early-stopping decode: fetches every
    /// row and truncates. Adapters that can decode incrementally (e.g. `GRDBRequest`) override this to
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

    /// Compatibility default for existing adapters. Invalid packets fail on
    /// subscription instead of being silently ignored.
    public func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return publish()
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    /// Compatibility default for existing adapters. Invalid packets fail on
    /// subscription instead of being silently ignored.
    public func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return publishOne()
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
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
    /// Compatibility default for request adapters that predate #308's async live-query source.
    ///
    /// Bridges this conformer's existing `publish()` Combine pipeline into the literal
    /// `AsyncThrowingStream<[Row], Error>` surface, lazily: the Combine subscription — and any
    /// database work it triggers — starts only on the returned stream's first `next()` call, so
    /// "observation begins with iteration" still holds for adapters that only ever implemented the
    /// Combine surface.
    ///
    /// `GRDBRequest` overrides this default with a true async-native GRDB observation source
    /// (``GRDBLiveQueryAsyncBridge``) that never routes through Combine. This default must never be
    /// changed to call `stream()` (directly or indirectly) itself — that would recurse indefinitely for
    /// any conformer that does not override `stream()`; it must always bridge from `publish()` instead.
    ///
    public func stream() -> AsyncThrowingStream<[Row], Error> {
        XLRequestPublisherAsyncBridge(makePublisher: { self.publish() }).stream()
    }

    /// Compatibility default mirroring ``stream()``, bridging ``publish(bindings:)`` instead. See
    /// ``stream()`` for why this must never call `stream(bindings:)` itself.
    public func stream(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<[Row], Error> {
        XLRequestPublisherAsyncBridge(makePublisher: { self.publish(bindings: bindings) }).stream()
    }

    /// Compatibility default mirroring ``stream()``, bridging ``publishOne()`` instead. See
    /// ``stream()`` for why this must never call `streamOne()` itself.
    public func streamOne() -> AsyncThrowingStream<Row?, Error> {
        XLRequestPublisherAsyncBridge(makePublisher: { self.publishOne() }).stream()
    }

    /// Compatibility default mirroring ``stream()``, bridging ``publishOne(bindings:)`` instead. See
    /// ``stream()`` for why this must never call `streamOne(bindings:)` itself.
    public func streamOne(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<Row?, Error> {
        XLRequestPublisherAsyncBridge(makePublisher: { self.publishOne(bindings: bindings) }).stream()
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


/// Lazily bridges an `XLRequest` compatibility default's `publish()`/`publishOne()` Combine pipeline
/// into a single-consumer `AsyncThrowingStream`, reusing ``XLSingleSlotAsyncBuffer`` for #291's
/// bound-1 "newest wins" policy. This is the non-GRDB-aware half of #308: it knows nothing about GRDB
/// or retry policy, only Combine, because it exists purely so third-party `XLRequest` conformers that
/// predate `stream()`/`streamOne()` keep compiling with a reasonable, still lazily-started default.
///
/// `GRDBRequest` does not use this type: its own `stream()`/`streamOne()` overrides build directly on
/// ``GRDBLiveQueryAsyncBridge`` instead, per the hard constraint that the canonical GRDB-backed source
/// must not be implemented in terms of `publish()`/`publishOne()`/`AnyPublisher.values`/any Combine
/// pipeline.
final class XLRequestPublisherAsyncBridge<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var didStart = false

    private var isCancelled = false

    private var cancellable: AnyCancellable?

    private let buffer = XLSingleSlotAsyncBuffer<Value>()

    private let makePublisher: () -> AnyPublisher<Value, Error>

    init(makePublisher: @escaping () -> AnyPublisher<Value, Error>) {
        self.makePublisher = makePublisher
    }

    private func claimStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didStart else { return false }
        didStart = true
        return true
    }

    /// Stores `newCancellable`, then reports whether `cancel()` had already
    /// run by that point. `cancel()` can run concurrently between `sink(...)`
    /// creating the subscription and this call storing it -- in that window
    /// `cancel()` finds nothing stored yet to cancel, so without this
    /// check-after-store re-verification the subscription it just missed
    /// would keep running forever, leaking whatever resources the wrapped
    /// publisher holds. Mirrors the identical pattern
    /// `GRDBLiveQueryAsyncBridge.beginAttempt()` uses for the same race.
    private func storeCancellableReportingIfAlreadyCancelled(
        _ newCancellable: AnyCancellable
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return true }
        cancellable = newCancellable
        return false
    }

    func next() async throws -> Value? {
        // The start decision lives *inside* `operation`, not before this
        // call: if the consuming `Task` is already cancelled at this point,
        // Swift guarantees `onCancel` runs before `operation` starts
        // executing, so `cancel()` completes -- and claims the start slot,
        // see below -- before `claimStart()` ever runs, so an
        // already-cancelled task subscribes to nothing.
        return try await withTaskCancellationHandler(
            operation: {
                if claimStart() {
                    let buffer = self.buffer
                    let subscription = makePublisher().sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                buffer.finish(throwing: nil)
                            case .failure(let error):
                                buffer.finish(throwing: error)
                            }
                        },
                        receiveValue: { value in
                            // See the matching note on GRDBLiveQueryAsyncStream.handleValue(_:generation:):
                            // `buffer.yield(_:)`'s parameter is `sending` (Swift 6.0+), and this `value` is
                            // a plain, non-sending Combine callback parameter.
                            #if compiler(>=6.0)
                            nonisolated(unsafe) let value = value
                            #endif
                            buffer.yield(value)
                        }
                    )
                    if storeCancellableReportingIfAlreadyCancelled(subscription) {
                        // `cancel()` ran between subscribing above and
                        // storing here, missing this subscription entirely.
                        // Cancel it ourselves so it doesn't keep running.
                        subscription.cancel()
                    }
                }
                return try await buffer.next()
            },
            onCancel: { [weak self] in self?.cancel() }
        )
    }

    /// Safe to call more than once, and safe to call whether or not `next()`
    /// was ever invoked: claims the start slot itself so a `next()` call
    /// arriving after `cancel()` (before a subscription ever began) finds the
    /// buffer already finished instead of subscribing to a publisher nothing
    /// will ever consume.
    func cancel() {
        lock.lock()
        didStart = true
        isCancelled = true
        let existing = cancellable
        cancellable = nil
        lock.unlock()
        existing?.cancel()
        buffer.cancel()
    }

    /// The `unfolding` closure captures `self` strongly, not weakly: this
    /// bridge is constructed and handed straight to `stream()` with no other
    /// owner (see the `stream()`/`streamOne()` compatibility defaults
    /// above), so a weak capture would let it deallocate immediately after
    /// this call returns, before any consumer ever iterates — silently
    /// turning every stream into one that resolves to `nil` on its very
    /// first `next()`. The returned `AsyncThrowingStream` becomes this
    /// bridge's only owner from here on, and the bridge does not hold a
    /// reference back to the stream, so this creates no retain cycle.
    func stream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(unfolding: {
            try await self.next()
        })
    }
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
    /// Executes the statement.
    ///
    func execute() throws

    /// Executes the statement with one immutable per-invocation binding packet.
    func execute(bindings: any XLInvocationBindingPacket) throws
}

extension XLWriteRequest {

    /// Compatibility default for request adapters that do not yet expose static
    /// parameter metadata.
    public var parameterLayout: XLParameterLayout {
        .empty
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        guard bindings.layout.isEmpty,
              bindings.bindingCount == 0,
              bindings.isComplete else {
            throw XLRequestBindingError.unsupportedInvocationBindings(
                requestType: String(reflecting: Self.self),
                layout: bindings.layout
            )
        }
        try execute()
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
    func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row>

    ///
    /// Constructs a prepared, row-readable request from a data-changing statement
    /// that carries a `RETURNING` clause.
    ///
    func makeRequest<Row>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row>

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
    func makeRequest<Row>(with builder: XLRequestBuilder<Row>) -> any XLRequest<Row> {
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
    public func makeRequest<Row>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row> {
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
