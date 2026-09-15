//
//  XLPreparedQuery.swift
//  SwiftQL
//
//  Issue #660: the observable form of a declared query. `@SQLQuery` and
//  `@SQLQueries` generate a function that returns one of these, built from the
//  same render-once request and binding packet the generated executor fetches
//  with, so a live query can observe a declaration without the statement being
//  written a second time.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


///
/// One invocation of a declared query, ready to observe: the request the
/// declaration's render-once cache holds, and the immutable binding packet
/// built from the arguments of this invocation.
///
/// You do not construct this type yourself. `@SQLQuery` generates a
/// `PreparedQuery`-suffixed peer beside each executor, and `@SQLQueries` generates
/// the `preparedQueries` namespace on the database:
///
/// ```swift
/// // @SQLQuery
/// let query = try database.personByNamePreparedQuery(name: "John Doe")
///
/// // @SQLQueries
/// let query = try database.preparedQueries.personByName(name: "John Doe")
///
/// for try await people in query.stream() {
///     print(people)
/// }
/// ```
///
/// The generated function and the generated executor emit the same
/// preparation code: the request comes from the same cache entry, so the
/// statement renders at most once per database whichever form runs first, and
/// the packet holds the same bindings the executor would fetch with.
///
/// The observation methods mirror ``XLRequest``'s packet-backed forms. Each one
/// captures ``bindings`` once for the initial fetch, every refresh, and every
/// retry. Use ``stream()`` or ``publish()`` for a declaration that returns
/// `[Row]`, and ``streamOne()`` or ``publishOne()`` for one that returns `Row?`
/// or `Row`. An observation does not enforce the exactly-one cardinality of a
/// `Row` declaration: when the row goes away, the observation delivers `nil`
/// rather than failing.
///
/// A new set of argument values is a new invocation. Call the generated
/// function again and observe the result, exactly as a new
/// `stream(bindings:)` call is a new observation.
///
/// Prepare a query you observe on the database, not on a transaction scope.
/// A query prepared from a scope fetches on the scope's connection, but every
/// observation method fails with
/// `XLTransactionScopeError.liveQueriesUnsupportedInTransaction`.
///
/// This type is not `Sendable`, and it does not conform with
/// `@unchecked Sendable` either. It holds an `any XLRequest<Row>`, and
/// ``XLRequest`` is a public protocol whose conformers SwiftQL does not
/// control, so SwiftQL cannot promise that a request is safe to share across
/// tasks (see <doc:LiveQueries>, "Packet-backed observations"). With strict
/// concurrency checking, prepare the query in the isolation domain that
/// observes it, for example in a `@MainActor` model's initializer, and send
/// the arguments across the boundary instead.
///
public struct XLPreparedQuery<Row> {

    /// The declaration's cached, value-free request.
    public let request: any XLRequest<Row>

    /// The immutable packet that holds this invocation's argument values.
    public let bindings: XLInvocationBindings<XLSQLiteValue>

    /// Pairs a cached request with one invocation's packet. Generated code
    /// calls this initializer; application code gets a prepared query from a
    /// generated function instead.
    public init(
        request: any XLRequest<Row>,
        bindings: XLInvocationBindings<XLSQLiteValue>
    ) {
        self.request = request
        self.bindings = bindings
    }

    /// Observes all rows. Same as `request.stream(bindings: bindings)`.
    public func stream() -> AsyncThrowingStream<[Row], Error> {
        request.stream(bindings: bindings)
    }

    /// Observes the first row. Same as `request.streamOne(bindings: bindings)`.
    public func streamOne() -> AsyncThrowingStream<Row?, Error> {
        request.streamOne(bindings: bindings)
    }

    /// Publishes all rows. Same as `request.publish(bindings: bindings)`.
    public func publish() -> AnyPublisher<[Row], Error> {
        request.publish(bindings: bindings)
    }

    /// Publishes the first row. Same as `request.publishOne(bindings: bindings)`.
    public func publishOne() -> AnyPublisher<Row?, Error> {
        request.publishOne(bindings: bindings)
    }
}
